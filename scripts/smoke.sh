#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
"$ROOT/scripts/preflight.sh" >/dev/null
# shellcheck source=scripts/postgres/common.sh
source "$ROOT/scripts/postgres/common.sh"
compose_cmd=(docker compose --project-directory "$ROOT" --env-file "$ENV_FILE" -f "$ROOT/compose.yml")
if [[ -n ${COMPOSE_OVERRIDE_FILE:-} ]]; then
  compose_cmd+=(-f "$COMPOSE_OVERRIDE_FILE")
fi
restore_container="infra-stack-restore-${RANDOM}-$$"
cleanup() {
  local rc=$?
  trap - EXIT
  if docker inspect "$restore_container" >/dev/null 2>&1; then
    if ! docker rm -fv "$restore_container" >/dev/null; then
      printf 'Failed to remove disposable restore container %s\n' "$restore_container" >&2
      ((rc == 0)) && rc=1
    fi
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

printf 'Waiting for the core stack...\n'
"${compose_cmd[@]}" up -d --wait --wait-timeout 240

printf 'Testing PostgreSQL and extensions...\n'
extensions=$("${compose_cmd[@]}" exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atqc \
  "SELECT string_agg(extname, ',' ORDER BY extname) FROM pg_extension WHERE extname IN ('vector','vectorscale');")
[[ "$extensions" == vector,vectorscale ]]
"${compose_cmd[@]}" exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres <<'SQL'
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'smoke_db' AND pid <> pg_backend_pid();
DROP DATABASE IF EXISTS smoke_db;
CREATE DATABASE smoke_db TEMPLATE template0;
SQL
"${compose_cmd[@]}" exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d smoke_db <<'SQL'
CREATE TABLE smoke_marker (id integer PRIMARY KEY, value text NOT NULL);
INSERT INTO smoke_marker VALUES (1, 'backup-restore-ok');
SQL

printf 'Testing Redis, MinIO, AWS CLI, and MongoDB authentication...\n'
[[ $("${compose_cmd[@]}" exec -T redis redis-cli --no-auth-warning -a "$REDIS_PASSWORD" ping) == PONG ]]
[[ $(s3cli_run -c 'aws --version') == aws-cli/2.36.20* ]]
# Variables intentionally expand inside the AWS CLI utility container.
# shellcheck disable=SC2016
s3cli_run -c '. /scripts/s3cli/common.sh && create_bucket_if_missing "$POSTGRES_BACKUP_BUCKET" && s3api head-bucket --bucket "$POSTGRES_BACKUP_BUCKET" >/dev/null'
"${compose_cmd[@]}" exec -T mongo mongosh --quiet \
  --username "$MONGO_ROOT_USERNAME" --password "$MONGO_ROOT_PASSWORD" \
  --authenticationDatabase admin --eval 'if (db.adminCommand({ping: 1}).ok !== 1) quit(2)'

printf 'Testing all application hostnames from an independent container on %s...\n' "$INFRA_NETWORK"
docker run --rm --network "$INFRA_NETWORK" "$MONGO_IMAGE" \
  getent hosts postgres redis minio mongo >/dev/null
docker run --rm --network "$INFRA_NETWORK" "$REDIS_IMAGE" \
  redis-cli -h redis --no-auth-warning -a "$REDIS_PASSWORD" ping | grep -qx PONG

printf 'Testing exclusive local publication lock...\n'
exec 8>"$BACKUP_DIR/.backup.lock"
chmod 0600 "$BACKUP_DIR/.backup.lock"
flock -n 8
if "$ROOT/scripts/postgres/backup-db.sh" smoke_db >/dev/null 2>&1; then
  printf 'Concurrent backup unexpectedly acquired the publication lock.\n' >&2
  exit 1
fi
flock -u 8
exec 8>&-

printf 'Creating and remotely verifying both backup formats...\n'
"$ROOT/scripts/postgres/backup-db.sh" smoke_db
"$ROOT/scripts/postgres/backup-all.sh"
"$ROOT/scripts/postgres/verify-backups.sh"
custom_dump=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*_smoke_db_*.dump' -printf '%T@ %p\n' | sort -nr | head -1 | cut -d ' ' -f 2-)
cluster_dump=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*_cluster_*.sql.gz' -printf '%T@ %p\n' | sort -nr | head -1 | cut -d ' ' -f 2-)
[[ -n "$custom_dump" && -n "$cluster_dump" ]]
"$ROOT/scripts/postgres/list-backups.sh" | grep -Fq "$(basename "$custom_dump")"
[[ $(stat -c '%a' "$BACKUP_DIR") == 700 ]]
for sensitive in "$custom_dump" "$custom_dump.sha256" "$cluster_dump" "$cluster_dump.sha256"; do
  [[ $(stat -c '%a' "$sensitive") == 600 ]]
done

printf 'Testing retry rejection without deleting published remote objects...\n'
if upload_backup "$custom_dump" >/dev/null 2>&1; then
  printf 'Retry unexpectedly overwrote a remote backup.\n' >&2
  exit 1
fi
"$ROOT/scripts/postgres/verify-backups.sh"

printf 'Testing atomic no-clobber against two concurrent remote writers...\n'
race_id=$(new_backup_id)
race_name="$(date -u +%Y%m%dT%H%M%SZ)_race_${race_id}.dump"
race_artifact="$BACKUP_DIR/$race_name"
cp "$custom_dump" "$race_artifact"
(
  cd "$BACKUP_DIR"
  sha256sum "$race_name" > "$race_name.sha256"
)
chmod 0600 "$race_artifact" "$race_artifact.sha256"
(
  # shellcheck disable=SC2030
  export S3_UPLOAD_PRE_PUT_DELAY=2
  upload_backup "$race_artifact"
) >"$BACKUP_DIR/.race-writer-1.log" 2>&1 &
writer_one=$!
(
  # shellcheck disable=SC2030,SC2031
  export S3_UPLOAD_PRE_PUT_DELAY=2
  upload_backup "$race_artifact"
) >"$BACKUP_DIR/.race-writer-2.log" 2>&1 &
writer_two=$!
set +e
wait "$writer_one"; writer_one_rc=$?
wait "$writer_two"; writer_two_rc=$?
set -e
if ! { ((writer_one_rc == 0 && writer_two_rc != 0)) || ((writer_one_rc != 0 && writer_two_rc == 0)); }; then
  cat "$BACKUP_DIR/.race-writer-1.log" "$BACKUP_DIR/.race-writer-2.log" >&2
  printf 'Expected exactly one conditional writer to succeed; got %s and %s.\n' "$writer_one_rc" "$writer_two_rc" >&2
  exit 1
fi
if ((writer_one_rc != 0)); then loser_log="$BACKUP_DIR/.race-writer-1.log"; else loser_log="$BACKUP_DIR/.race-writer-2.log"; fi
grep -Fq 'PreconditionFailed' "$loser_log"
rm -f "$BACKUP_DIR/.race-writer-1.log" "$BACKUP_DIR/.race-writer-2.log"
s3cli_run /scripts/s3cli/verify-backup.sh "$race_name" "$POSTGRES_BACKUP_BUCKET"
printf 'Atomic checksum If-None-Match race passed: one writer rejected, winner retained and verified.\n'
"$ROOT/scripts/postgres/verify-backups.sh"

printf 'Testing independent artifact PUT conflict after checksum creation...\n'
artifact_conflict_id=$(new_backup_id)
artifact_conflict_name="$(date -u +%Y%m%dT%H%M%SZ)_artifactrace_${artifact_conflict_id}.dump"
artifact_conflict="$BACKUP_DIR/$artifact_conflict_name"
artifact_barrier="$BACKUP_DIR/.artifact-put-race-ready"
artifact_log="$BACKUP_DIR/.artifact-put-race.log"
cp "$custom_dump" "$artifact_conflict"
(
  cd "$BACKUP_DIR"
  sha256sum "$artifact_conflict_name" > "$artifact_conflict_name.sha256"
)
chmod 0600 "$artifact_conflict" "$artifact_conflict.sha256"
rm -f "$artifact_barrier"
(
  # shellcheck disable=SC2030,SC2031
  export S3_UPLOAD_PRE_PUT_DELAY=5
  export S3_UPLOAD_TEST_READY_FILE=/backups/postgres/.artifact-put-race-ready
  upload_backup "$artifact_conflict"
) >"$artifact_log" 2>&1 &
artifact_uploader=$!
for _ in {1..100}; do
  [[ -f "$artifact_barrier" ]] && break
  sleep 0.1
done
[[ -f "$artifact_barrier" ]] || { printf 'Artifact race uploader never reached the post-check barrier.\n' >&2; exit 1; }
s3cli_run /scripts/s3cli/create-artifact-conflict.sh \
  "$artifact_conflict_name" "$POSTGRES_BACKUP_BUCKET" "$artifact_conflict_id"
set +e
wait "$artifact_uploader"; artifact_uploader_rc=$?
set -e
((artifact_uploader_rc != 0)) || { printf 'Artifact conditional PUT unexpectedly overwrote the external key.\n' >&2; exit 1; }
grep -Fq 'PreconditionFailed' "$artifact_log"
s3cli_run /scripts/s3cli/verify-artifact-conflict.sh \
  "$artifact_conflict_name" "$POSTGRES_BACKUP_BUCKET" "$artifact_conflict_id"
rm -f "$artifact_conflict" "$artifact_conflict.sha256" "$artifact_barrier" "$artifact_log"
printf 'Atomic artifact If-None-Match conflict passed: external bytes retained; owned checksum cleaned.\n'

printf 'Downloading clean artifact/checksum pairs from MinIO...\n'
custom_download=$("$ROOT/scripts/postgres/download-backup.sh" "$(basename "$custom_dump")")
cluster_download=$("$ROOT/scripts/postgres/download-backup.sh" "$(basename "$cluster_dump")")
[[ "$custom_download" != "$custom_dump" && "$cluster_download" != "$cluster_dump" ]]
for downloaded in "$custom_download" "$custom_download.sha256" "$cluster_download" "$cluster_download.sha256"; do
  [[ $(stat -c '%a' "$downloaded") == 600 ]]
done
[[ $(stat -c '%a' "$(dirname "$custom_download")") == 700 ]]
[[ $(stat -c '%a' "$(dirname "$cluster_download")") == 700 ]]

printf 'Restoring downloaded custom-format bytes into a disposable database...\n'
"$ROOT/scripts/postgres/restore-db.sh" "$custom_download" restore_smoke
[[ $("${compose_cmd[@]}" exec -T postgres psql -U "$POSTGRES_USER" -d restore_smoke -Atqc "SELECT value FROM smoke_marker WHERE id=1") == backup-restore-ok ]]

printf 'Restoring downloaded cluster bytes into a disposable PostgreSQL 17 container...\n'
docker run -d --name "$restore_container" --network "$INFRA_NETWORK" \
  -e POSTGRES_PASSWORD=restore-only "$POSTGRES_IMAGE" >/dev/null
stable_checks=0
for _ in {1..90}; do
  if docker exec "$restore_container" pg_isready -U postgres >/dev/null 2>&1; then
    ((stable_checks += 1))
    ((stable_checks >= 3)) && break
  else
    stable_checks=0
  fi
  sleep 2
done
((stable_checks >= 3)) || { printf 'Disposable PostgreSQL target never became stably ready.\n' >&2; exit 1; }
"$ROOT/scripts/postgres/restore-all.sh" "$cluster_download" "$restore_container"
[[ $(docker exec "$restore_container" psql -X -U postgres -d smoke_db -Atqc "SELECT value FROM smoke_marker WHERE id=1") == backup-restore-ok ]]
printf 'Smoke test passed using MinIO-downloaded bytes for both restore formats.\n'
