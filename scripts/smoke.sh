#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[[ -f "$ROOT/.env" ]] || { printf 'Missing .env; run make init.\n' >&2; exit 1; }
set -a
# shellcheck disable=SC1091
source "$ROOT/.env"
set +a
compose=(docker compose --project-directory "$ROOT" --env-file "$ROOT/.env" -f "$ROOT/compose.yml")
# Create bind sources as the invoking user before Docker can create root-owned paths.
minio_data_dir=${MINIO_DATA_DIR:-./data/minio}
backup_dir=${POSTGRES_BACKUP_DIR:-./backups/postgres}
[[ "$minio_data_dir" = /* ]] || minio_data_dir="$ROOT/${minio_data_dir#./}"
[[ "$backup_dir" = /* ]] || backup_dir="$ROOT/${backup_dir#./}"
mkdir -p "$backup_dir" "$minio_data_dir"
restore_container="infra-stack-restore-${RANDOM}-$$"
cleanup() {
  docker rm -fv "$restore_container" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

printf 'Waiting for the core stack...\n'
"${compose[@]}" up -d --wait --wait-timeout 240

printf 'Testing PostgreSQL and extensions...\n'
extensions=$("${compose[@]}" exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atqc \
  "SELECT string_agg(extname, ',' ORDER BY extname) FROM pg_extension WHERE extname IN ('vector','vectorscale');")
[[ "$extensions" == vector,vectorscale ]]
"${compose[@]}" exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres <<'SQL'
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'smoke_db' AND pid <> pg_backend_pid();
DROP DATABASE IF EXISTS smoke_db;
CREATE DATABASE smoke_db;
SQL
"${compose[@]}" exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d smoke_db <<'SQL'
CREATE TABLE smoke_marker (id integer PRIMARY KEY, value text NOT NULL);
INSERT INTO smoke_marker VALUES (1, 'backup-restore-ok');
SQL

printf 'Testing Redis, MinIO, and MongoDB authentication...\n'
[[ $("${compose[@]}" exec -T redis redis-cli --no-auth-warning -a "$REDIS_PASSWORD" ping) == PONG ]]
# Variables intentionally expand inside the mc utility container.
# shellcheck disable=SC2016
"${compose[@]}" --profile tools run --rm --no-deps mc -c \
  'mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null && mc mb --ignore-existing "local/$POSTGRES_BACKUP_BUCKET" >/dev/null && mc ready local'
"${compose[@]}" exec -T mongo mongosh --quiet \
  --username "$MONGO_ROOT_USERNAME" --password "$MONGO_ROOT_PASSWORD" \
  --authenticationDatabase admin --eval 'if (db.adminCommand({ping: 1}).ok !== 1) quit(2)'

printf 'Testing access from an independent container on %s...\n' "$INFRA_NETWORK"
docker run --rm --network "$INFRA_NETWORK" "$REDIS_IMAGE" \
  redis-cli -h redis --no-auth-warning -a "$REDIS_PASSWORD" ping | grep -qx PONG

printf 'Creating and remotely verifying both backup formats...\n'
"$ROOT/scripts/postgres/backup-db.sh" smoke_db
"$ROOT/scripts/postgres/backup-all.sh"
"$ROOT/scripts/postgres/verify-backups.sh"
custom_dump=$(find "$backup_dir" -maxdepth 1 -type f -name '*_smoke_db.dump' -printf '%T@ %p\n' | sort -nr | head -1 | cut -d ' ' -f 2-)
cluster_dump=$(find "$backup_dir" -maxdepth 1 -type f -name '*_cluster.sql.gz' -printf '%T@ %p\n' | sort -nr | head -1 | cut -d ' ' -f 2-)
[[ -n "$custom_dump" && -n "$cluster_dump" ]]

printf 'Restoring the custom-format dump into a disposable database...\n'
"$ROOT/scripts/postgres/restore-db.sh" "$custom_dump" restore_smoke
[[ $("${compose[@]}" exec -T postgres psql -U "$POSTGRES_USER" -d restore_smoke -Atqc "SELECT value FROM smoke_marker WHERE id=1") == backup-restore-ok ]]

printf 'Restoring the cluster dump into a disposable PostgreSQL 17 container...\n'
docker run -d --name "$restore_container" --network "$INFRA_NETWORK" \
  -e POSTGRES_PASSWORD=restore-only "$POSTGRES_IMAGE" >/dev/null
for _ in {1..60}; do
  docker exec "$restore_container" pg_isready -U postgres >/dev/null 2>&1 && break
  sleep 2
done
docker exec "$restore_container" pg_isready -U postgres >/dev/null
gzip -dc "$cluster_dump" | docker exec -i "$restore_container" psql -X -U postgres -d postgres >/tmp/infra-stack-pg_dumpall-restore.log 2>&1 || {
  cat /tmp/infra-stack-pg_dumpall-restore.log >&2
  exit 1
}
[[ $(docker exec "$restore_container" psql -X -U postgres -d smoke_db -Atqc "SELECT value FROM smoke_marker WHERE id=1") == backup-restore-ok ]]
rm -f /tmp/infra-stack-pg_dumpall-restore.log
printf 'Smoke test passed. Core services remain running; disposable restore target removed.\n'
