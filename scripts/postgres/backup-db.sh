#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/postgres/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DB=${1:-}
valid_identifier "$DB" || {
  printf 'Usage: %s DATABASE (SQL identifier only)\n' "$0" >&2
  exit 2
}

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
base="${timestamp}_${DB}.dump"
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

# Publish the checksum first; a visible dump therefore always has its checksum.
mv "$stage/$base.sha256" "$BACKUP_DIR/$base.sha256"
mv "$stage/$base" "$BACKUP_DIR/$base"
upload_backup "$BACKUP_DIR/$base"
printf 'Backup verified and published: %s\n' "$BACKUP_DIR/$base"
