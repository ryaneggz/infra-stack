#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/postgres/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DUMP=${1:-${INFRA_ARG_FILE:-}}
TARGET_CONTAINER=${2:-${INFRA_ARG_CONTAINER:-}}
[[ -f "$DUMP" && "$(basename "$DUMP")" == *.sql.gz ]] || {
  printf 'Usage: %s DOWNLOADED_CLUSTER.sql.gz DISPOSABLE_CONTAINER\n' "$0" >&2
  exit 2
}
valid_backup_name "$(basename "$DUMP")" || { printf 'Refusing unsafe backup filename\n' >&2; exit 2; }
validate_downloaded_artifact_path "$DUMP"
verify_artifact_checksum "$DUMP"
gzip -t "$DUMP"
[[ "$TARGET_CONTAINER" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]+$ ]] || { printf 'Invalid target container name\n' >&2; exit 2; }
docker inspect "$TARGET_CONTAINER" >/dev/null
ready_timeout=${INFRA_RESTORE_READY_TIMEOUT:-180}
if [[ ! "$ready_timeout" =~ ^[0-9]+$ ]] || ((ready_timeout < 1 || ready_timeout > 600)); then
  printf 'INFRA_RESTORE_READY_TIMEOUT must be an integer from 1 to 600 seconds.\n' >&2
  exit 2
fi
printf 'Waiting up to %ss for PostgreSQL target %s to become ready...\n' "$ready_timeout" "$TARGET_CONTAINER" >&2
ready_deadline=$((SECONDS + ready_timeout))
stable_checks=0
while ((SECONDS < ready_deadline)); do
  state=$(docker inspect --format '{{.State.Status}}' "$TARGET_CONTAINER" 2>/dev/null) || {
    printf 'PostgreSQL target disappeared while waiting: %s\n' "$TARGET_CONTAINER" >&2
    exit 1
  }
  case "$state" in
    exited|dead)
      printf 'PostgreSQL target %s entered state %s before becoming ready.\n' "$TARGET_CONTAINER" "$state" >&2
      exit 1
      ;;
  esac
  if docker exec "$TARGET_CONTAINER" pg_isready -U postgres -d postgres >/dev/null 2>&1 &&
    docker exec "$TARGET_CONTAINER" psql -X -U postgres -d postgres -Atqc 'SELECT 1' >/dev/null 2>&1; then
    ((stable_checks += 1))
    if ((stable_checks >= 3)); then
      break
    fi
  else
    stable_checks=0
  fi
  sleep 1
done
if ((stable_checks < 3)); then
  printf 'Timed out after %ss waiting for PostgreSQL target %s to become ready.\n' \
    "$ready_timeout" "$TARGET_CONTAINER" >&2
  exit 1
fi
printf 'PostgreSQL target %s is ready.\n' "$TARGET_CONTAINER" >&2
major=$(docker exec "$TARGET_CONTAINER" psql -X -U postgres -d postgres -Atqc "SHOW server_version_num")
if [[ ! "$major" =~ ^[0-9]+$ ]] || ((major / 10000 != 17)); then
  printf 'Cluster restore requires PostgreSQL 17, found %s\n' "$major" >&2
  exit 1
fi

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
