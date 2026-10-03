#!/usr/bin/env bash
# Generate the Langfuse env file with fresh random secrets.
# Writes ./.env (mode 600) from ./env.template. Refuses to overwrite.
# The tunnel token is NOT generated -- paste it from the Cloudflare dashboard.
set -euo pipefail
cd "$(dirname "$0")"

OUT=.env
[ -e "$OUT" ] && { echo "refusing to overwrite existing $OUT"; exit 1; }

gen() { openssl rand -hex 32; }

DB_PW=$(gen)
umask 077
{
  echo "# Generated $(date -Is). Secrets are random; the tunnel token is a placeholder."
  echo "LANGFUSE_DATABASE_URL=postgresql://langfuse:${DB_PW}@infra-postgres:5432/langfuse"
  echo "LANGFUSE_SALT=$(gen)"
  echo "LANGFUSE_ENCRYPTION_KEY=$(gen)"
  echo "LANGFUSE_NEXTAUTH_SECRET=$(gen)"
  echo "LANGFUSE_NEXTAUTH_URL=${LANGFUSE_NEXTAUTH_URL:-https://langfuse-dev.mifune.dev}"
  echo "LANGFUSE_DISABLE_SIGNUP=false"
  echo "CLICKHOUSE_PASSWORD=$(gen)"
  echo "REDIS_PASSWORD=$(gen)"
  echo "MINIO_ROOT_USER=langfuse"
  echo "MINIO_ROOT_PASSWORD=$(gen)"
  echo "LANGFUSE_TUNNEL_TOKEN=CHANGE_ME_TUNNEL_TOKEN"
} > "$OUT"
chmod 600 "$OUT"

# Hand the same DB password to the bootstrap step without printing it.
printf '%s' "$DB_PW" > .langfuse-db-pw
chmod 600 .langfuse-db-pw
echo "wrote $OUT and .langfuse-db-pw (both 0600)"
