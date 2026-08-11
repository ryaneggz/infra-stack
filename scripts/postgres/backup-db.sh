#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/postgres/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DB=${1:-${INFRA_ARG_DB:-}}
valid_identifier "$DB" || {
  printf 'Usage: %s DATABASE (SQL identifier only)\n' "$0" >&2
  exit 2
}
acquire_backup_lock

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
backup_id=$(new_backup_id)
base="${timestamp}_${DB}_${backup_id}.dump"
valid_backup_name "$base"
[[ ! -e "$BACKUP_DIR/$base" && ! -e "$BACKUP_DIR/$base.sha256" ]] || {
  printf 'Refusing to overwrite existing local backup: %s\n' "$base" >&2
  exit 1
}
stage=$(mktemp -d "$BACKUP_DIR/.stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT

printf 'Creating PostgreSQL custom backup for %s...\n' "$DB"
compose exec -T postgres pg_dump \
  --username "$POSTGRES_USER" --dbname "$DB" --format=custom --compress=6 \
  > "$stage/$base"
[[ -s "$stage/$base" ]] || { printf 'pg_dump produced an empty file\n' >&2; exit 1; }
(
  cd "$stage"
  sha256sum "$base" > "$base.sha256"
)
chmod 0600 "$stage/$base" "$stage/$base.sha256"

# A random 128-bit suffix plus the exclusive publication lock prevents collisions.
# Checksum-first means a visible data artifact always has its sidecar.
mv "$stage/$base.sha256" "$BACKUP_DIR/$base.sha256"
mv "$stage/$base" "$BACKUP_DIR/$base"
upload_backup "$BACKUP_DIR/$base"
printf 'Backup verified and published: %s\n' "$BACKUP_DIR/$base"
