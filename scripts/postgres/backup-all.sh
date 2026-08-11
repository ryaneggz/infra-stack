#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/postgres/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

acquire_backup_lock
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
backup_id=$(new_backup_id)
base="${timestamp}_cluster_${backup_id}.sql.gz"
valid_backup_name "$base"
[[ ! -e "$BACKUP_DIR/$base" && ! -e "$BACKUP_DIR/$base.sha256" ]] || {
  printf 'Refusing to overwrite existing local backup: %s\n' "$base" >&2
  exit 1
}
stage=$(mktemp -d "$BACKUP_DIR/.stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT

printf 'Creating sensitive cluster-wide backup (roles include password hashes)...\n'
compose exec -T postgres pg_dumpall --username "$POSTGRES_USER" | gzip -9 > "$stage/$base"
[[ -s "$stage/$base" ]] || { printf 'pg_dumpall produced an empty file\n' >&2; exit 1; }
gzip -t "$stage/$base"
(
  cd "$stage"
  sha256sum "$base" > "$base.sha256"
)
chmod 0600 "$stage/$base" "$stage/$base.sha256"

mv "$stage/$base.sha256" "$BACKUP_DIR/$base.sha256"
mv "$stage/$base" "$BACKUP_DIR/$base"
upload_backup "$BACKUP_DIR/$base"
printf 'Sensitive backup verified and published: %s\n' "$BACKUP_DIR/$base"
