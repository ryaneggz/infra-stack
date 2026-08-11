#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TARGET="$ROOT/.env"
TEMPLATE="$ROOT/.example.env"

if [[ -e "$TARGET" ]]; then
  printf 'Keeping existing %s; no changes made.\n' "$TARGET"
  exit 0
fi
command -v openssl >/dev/null 2>&1 || {
  printf 'openssl is required to generate credentials\n' >&2
  exit 1
}

umask 077
postgres_secret=$(openssl rand -hex 32)
redis_secret=$(openssl rand -hex 32)
minio_secret=$(openssl rand -hex 32)
pgadmin_secret=$(openssl rand -hex 32)
mongo_secret=$(openssl rand -hex 32)
mongo_express_secret=$(openssl rand -hex 32)
tmp=$(mktemp "$ROOT/.env.tmp.XXXXXX")
trap 'rm -f "$tmp"' EXIT

while IFS= read -r line || [[ -n "$line" ]]; do
  line=${line/CHANGE_ME_POSTGRES/$postgres_secret}
  line=${line/CHANGE_ME_REDIS/$redis_secret}
  line=${line/CHANGE_ME_MINIO/$minio_secret}
  line=${line/CHANGE_ME_PGADMIN/$pgadmin_secret}
  line=${line/CHANGE_ME_MONGO_EXPRESS/$mongo_express_secret}
  line=${line/CHANGE_ME_MONGO/$mongo_secret}
  printf '%s\n' "$line"
done < "$TEMPLATE" > "$tmp"

chmod 600 "$tmp"
mv "$tmp" "$TARGET"
trap - EXIT
printf 'Created %s with mode 0600 and random 256-bit credentials.\n' "$TARGET"
