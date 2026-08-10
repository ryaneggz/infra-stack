#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/postgres/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

shopt -s nullglob
checksums=("$BACKUP_DIR"/*.sha256)
((${#checksums[@]} > 0)) || { printf 'No backup checksums found in %s\n' "$BACKUP_DIR" >&2; exit 1; }

for checksum in "${checksums[@]}"; do
  artifact=${checksum%.sha256}
  [[ -s "$artifact" ]] || { printf 'Missing artifact for %s\n' "$checksum" >&2; exit 1; }
  (cd "$BACKUP_DIR" && sha256sum --check "$(basename "$checksum")")
  compose --profile tools run --rm --no-deps mc -c "
    set -eu
    mc alias set local http://minio:9000 \"\$MINIO_ROOT_USER\" \"\$MINIO_ROOT_PASSWORD\" >/dev/null
    expected=\$(cut -d ' ' -f 1 /backups/postgres/$(basename "$checksum"))
    remote_expected=\$(mc cat local/$POSTGRES_BACKUP_BUCKET/$(basename "$checksum") | cut -d ' ' -f 1)
    actual=\$(mc cat local/$POSTGRES_BACKUP_BUCKET/$(basename "$artifact") | sha256sum | cut -d ' ' -f 1)
    test \"\$expected\" = \"\$remote_expected\"
    test \"\$expected\" = \"\$actual\"
    mc stat local/$POSTGRES_BACKUP_BUCKET/$(basename "$checksum") >/dev/null
  "
done
printf 'Verified %d local and remote backup pair(s).\n' "${#checksums[@]}"
