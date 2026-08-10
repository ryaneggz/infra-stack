#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_FILE=${ENV_FILE:-$ROOT/.env}
[[ -f "$ENV_FILE" ]] || {
  printf 'Missing %s; run make init first.\n' "$ENV_FILE" >&2
  exit 1
}
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

BACKUP_DIR=${POSTGRES_BACKUP_DIR:-./backups/postgres}
[[ "$BACKUP_DIR" = /* ]] || BACKUP_DIR="$ROOT/${BACKUP_DIR#./}"
mkdir -p "$BACKUP_DIR"

compose() {
  docker compose --project-directory "$ROOT" --env-file "$ENV_FILE" -f "$ROOT/compose.yml" "$@"
}

valid_identifier() {
  [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]{0,62}$ ]]
}

upload_backup() {
  local artifact=$1
  compose --profile tools run --rm --no-deps mc \
    /scripts/minio/upload-backup.sh "/backups/postgres/$(basename "$artifact")" \
    "${POSTGRES_BACKUP_BUCKET:-postgres-backups}"
}
