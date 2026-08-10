#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/postgres/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DUMP=${1:-}
TARGET_CONTAINER=${2:-}
[[ -f "$DUMP" && "$(basename "$DUMP")" == *.sql.gz ]] || {
  printf 'Usage: %s DOWNLOADED_CLUSTER.sql.gz DISPOSABLE_CONTAINER\n' "$0" >&2
  exit 2
}
valid_backup_name "$(basename "$DUMP")" || { printf 'Refusing unsafe backup filename\n' >&2; exit 2; }
verify_artifact_checksum "$DUMP"
gzip -t "$DUMP"
[[ "$TARGET_CONTAINER" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]+$ ]] || { printf 'Invalid target container name\n' >&2; exit 2; }
docker inspect "$TARGET_CONTAINER" >/dev/null
major=$(docker exec "$TARGET_CONTAINER" psql -X -U postgres -d postgres -Atqc "SHOW server_version_num")
[[ ${major:0:2} == 17 ]] || { printf 'Cluster restore requires PostgreSQL 17, found %s\n' "$major" >&2; exit 1; }

log=$(mktemp "${TMPDIR:-/tmp}/infra-stack-pg_dumpall-restore.XXXXXX")
chmod 0600 "$log"
trap 'rm -f -- "$log"' EXIT
if ! gzip -dc "$DUMP" | docker exec -i "$TARGET_CONTAINER" \
  psql -X -U postgres -d postgres >"$log" 2>&1; then
  printf 'Cluster restore failed; psql diagnostics follow (dump contents are not echoed).\n' >&2
  cat "$log" >&2
  exit 1
fi
printf 'Restored sensitive cluster backup into %s; inspect it before removal.\n' "$TARGET_CONTAINER"
