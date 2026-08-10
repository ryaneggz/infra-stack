#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/postgres/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

shopt -s nullglob
checksums=("$BACKUP_DIR"/*.sha256)
((${#checksums[@]} > 0)) || { printf 'No backup checksums found in %s\n' "$BACKUP_DIR" >&2; exit 1; }

for checksum in "${checksums[@]}"; do
  artifact=${checksum%.sha256}
  name=$(basename "$artifact")
  valid_backup_name "$name" || { printf 'Unsafe backup filename: %s\n' "$name" >&2; exit 1; }
  verify_artifact_checksum "$artifact"
  [[ $(stat -c '%a' "$artifact") == 600 && $(stat -c '%a' "$checksum") == 600 ]] || {
    printf 'Backup pair must have mode 0600: %s\n' "$name" >&2
    exit 1
  }
  mc_run /scripts/minio/verify-backup.sh "$name" "$POSTGRES_BACKUP_BUCKET"
done
printf 'Verified %d local and remote backup pair(s).\n' "${#checksums[@]}"
