#!/usr/bin/env bash
# Create the langfuse role + database on the shared infra-postgres.
# Reads the password written by gen-secrets.sh; never prints it.
# Run inside the infra sandbox:
#   msb exec infra -- sh /home/dev/infra-services/langfuse/bootstrap.sh
set -euo pipefail
cd "$(dirname "$0")"

[ -f .langfuse-db-pw ] || { echo "missing .langfuse-db-pw -- run gen-secrets.sh first"; exit 1; }
PW=$(cat .langfuse-db-pw)

if docker exec infra-postgres psql -U postgres -tAc \
     "select 1 from pg_roles where rolname='langfuse'" | grep -qx 1; then
  echo "role langfuse already exists; nothing to do"
  exit 0
fi

docker exec -i infra-postgres psql -U postgres -v ON_ERROR_STOP=1 \
  -v pw="'${PW}'" -f - <<'SQL'
CREATE ROLE langfuse LOGIN PASSWORD :pw;
CREATE DATABASE langfuse OWNER langfuse;
REVOKE ALL ON DATABASE langfuse FROM PUBLIC;
GRANT CONNECT ON DATABASE langfuse TO langfuse;
SQL

echo "created role + database langfuse"
