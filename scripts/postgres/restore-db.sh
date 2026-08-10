#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/postgres/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DUMP=${1:-}
TARGET_DB=${2:-}
[[ -f "$DUMP" ]] || { printf 'Usage: %s FILE.dump restore_TARGET\n' "$0" >&2; exit 2; }
valid_backup_name "$(basename "$DUMP")" || { printf 'Refusing unsafe backup filename\n' >&2; exit 2; }
verify_artifact_checksum "$DUMP"
valid_identifier "$TARGET_DB" || { printf 'Invalid target database name\n' >&2; exit 2; }
if [[ "$TARGET_DB" != restore_* && ${ALLOW_UNSAFE_RESTORE:-0} != 1 ]]; then
  printf 'Refusing target without restore_ prefix (set ALLOW_UNSAFE_RESTORE=1 to override).\n' >&2
  exit 2
fi

compose exec -T postgres dropdb --username "$POSTGRES_USER" --if-exists "$TARGET_DB"
# template0 avoids inheriting preloaded extensions that the dump must recreate.
compose exec -T postgres createdb --username "$POSTGRES_USER" --template template0 "$TARGET_DB"
compose exec -T postgres pg_restore --username "$POSTGRES_USER" \
  --dbname "$TARGET_DB" --clean --if-exists --no-owner < "$DUMP"
printf 'Restored %s into %s\n' "$DUMP" "$TARGET_DB"
