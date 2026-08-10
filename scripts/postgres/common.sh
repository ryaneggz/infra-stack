#!/usr/bin/env bash
set -euo pipefail
umask 077

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
POSTGRES_BACKUP_BUCKET=${POSTGRES_BACKUP_BUCKET:-postgres-backups}
[[ "$BACKUP_DIR" = /* ]] || BACKUP_DIR="$ROOT/${BACKUP_DIR#./}"
DOWNLOAD_DIR="$BACKUP_DIR/downloads"

secure_backup_directory() {
  local path=$1 owner mode
  [[ ! -L "$path" ]] || { printf 'Backup path must not be a symlink: %s\n' "$path" >&2; return 1; }
  mkdir -p -- "$path"
  chmod 0700 "$path"
  owner=$(stat -c '%u' "$path")
  mode=$(stat -c '%a' "$path")
  [[ "$owner" == "$(id -u)" && "$mode" == 700 ]] || {
    printf 'Backup path must be owned by uid %s with mode 0700: %s\n' "$(id -u)" "$path" >&2
    return 1
  }
}
secure_backup_directory "$BACKUP_DIR"
secure_backup_directory "$DOWNLOAD_DIR"

if ((${#POSTGRES_BACKUP_BUCKET} < 3 || ${#POSTGRES_BACKUP_BUCKET} > 63)) ||
  [[ ! "$POSTGRES_BACKUP_BUCKET" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]$ ]] ||
  [[ "$POSTGRES_BACKUP_BUCKET" == *..* ]]; then
  printf 'Invalid S3 bucket name: %s\n' "$POSTGRES_BACKUP_BUCKET" >&2
  exit 2
fi
export POSTGRES_BACKUP_BUCKET

compose() {
  local args=(--project-directory "$ROOT" --env-file "$ENV_FILE" -f "$ROOT/compose.yml")
  if [[ -n ${COMPOSE_OVERRIDE_FILE:-} ]]; then
    args+=(-f "$COMPOSE_OVERRIDE_FILE")
  fi
  docker compose "${args[@]}" "$@"
}

mc_run() {
  compose --profile tools run --rm --no-deps --user "$(id -u):$(id -g)" mc "$@"
}

valid_identifier() {
  [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]{0,62}$ ]]
}

valid_backup_name() {
  [[ "$1" =~ ^[0-9]{8}T[0-9]{6}Z_[a-zA-Z_][a-zA-Z0-9_]{0,62}_[a-f0-9]{32}\.dump$ ||
     "$1" =~ ^[0-9]{8}T[0-9]{6}Z_cluster_[a-f0-9]{32}\.sql\.gz$ ]]
}

new_backup_id() {
  command -v openssl >/dev/null 2>&1 || { printf 'openssl is required\n' >&2; return 1; }
  openssl rand -hex 16
}

acquire_backup_lock() {
  command -v flock >/dev/null 2>&1 || { printf 'flock is required for collision-safe publication\n' >&2; return 1; }
  exec 9>"$BACKUP_DIR/.backup.lock"
  chmod 0600 "$BACKUP_DIR/.backup.lock"
  flock -n 9 || { printf 'Another backup publication is already running.\n' >&2; return 1; }
}

verify_artifact_checksum() {
  local artifact=$1 checksum expected listed extra actual
  checksum="$artifact.sha256"
  [[ -f "$artifact" && ! -L "$artifact" && -f "$checksum" && ! -L "$checksum" ]] || {
    printf 'Artifact and sidecar checksum are required: %s\n' "$artifact" >&2
    return 1
  }
  [[ $(wc -l < "$checksum") -eq 1 ]] || { printf 'Checksum must contain exactly one line: %s\n' "$checksum" >&2; return 1; }
  read -r expected listed extra < "$checksum"
  [[ "$expected" =~ ^[a-f0-9]{64}$ && "$listed" == "$(basename "$artifact")" && -z ${extra:-} ]] || {
    printf 'Checksum sidecar has an unsafe or invalid entry: %s\n' "$checksum" >&2
    return 1
  }
  actual=$(sha256sum "$artifact")
  actual=${actual%% *}
  [[ "$actual" == "$expected" ]] || { printf 'Checksum mismatch: %s\n' "$artifact" >&2; return 1; }
}

upload_backup() {
  local artifact=$1 name attempt
  name=$(basename "$artifact")
  valid_backup_name "$name" || { printf 'Refusing unsafe backup name: %s\n' "$name" >&2; return 2; }
  attempt=${name%.*}
  [[ "$name" == *.sql.gz ]] && attempt=${name%.sql.gz}
  attempt=${attempt##*_}
  mc_run /scripts/minio/upload-backup.sh "/backups/postgres/$name" "$POSTGRES_BACKUP_BUCKET" "$attempt"
}
