#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE=${ENV_FILE:-$ROOT/.env}
[[ -f "$ENV_FILE" ]] || { printf 'Missing %s; run make init first.\n' "$ENV_FILE" >&2; exit 1; }
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

secure_directory() {
  local path=$1 label=$2 owner mode
  [[ "$path" = /* ]] || path="$ROOT/${path#./}"
  [[ ! -L "$path" ]] || { printf '%s must not be a symlink: %s\n' "$label" "$path" >&2; return 1; }
  mkdir -p -- "$path"
  chmod 0700 "$path"
  [[ -d "$path" && ! -L "$path" ]] || { printf '%s is not a secure directory: %s\n' "$label" "$path" >&2; return 1; }
  owner=$(stat -c '%u' "$path")
  mode=$(stat -c '%a' "$path")
  [[ "$owner" == "$(id -u)" ]] || { printf '%s must be owned by uid %s, found %s\n' "$label" "$(id -u)" "$owner" >&2; return 1; }
  [[ "$mode" == 700 ]] || { printf '%s must have mode 0700, found %s\n' "$label" "$mode" >&2; return 1; }
  printf '%s ready: %s (owner %s, mode %s)\n' "$label" "$path" "$owner" "$mode"
}

secure_directory "${MINIO_DATA_DIR:-./data/minio}" 'MinIO data directory'
secure_directory "${POSTGRES_BACKUP_DIR:-./backups/postgres}" 'PostgreSQL backup directory'
