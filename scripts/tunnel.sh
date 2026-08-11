#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/tunnel.sh [--dry-run] user@host [service...]

Core services: postgres redis minio minio-console mongo
Optional UIs: cloudbeaver pgadmin redisinsight mongo-express
Use "all" (or omit services) for all five core service ports.
Ports come from .env when present. LOCAL_PORT_OFFSET may shift local ports.
USAGE
}

dry_run=0
if [[ ${1:-} == --help || ${1:-} == -h ]]; then usage; exit 0; fi
if [[ ${1:-} == --dry-run ]]; then dry_run=1; shift; fi
target=${1:-}
[[ -n "$target" ]] || { usage >&2; exit 2; }
shift
[[ "$target" != -* && "$target" =~ ^[^@[:space:]]+@[^@[:space:]]+$ ]] || {
  printf 'Target must be user@host and may not begin with "-".\n' >&2
  exit 2
}

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi
offset=${LOCAL_PORT_OFFSET:-0}
[[ "$offset" =~ ^[0-9]+$ ]] || { printf 'LOCAL_PORT_OFFSET must be a non-negative integer.\n' >&2; exit 2; }

declare -A ports=(
  [postgres]="${POSTGRES_PORT:-5432}"
  [redis]="${REDIS_PORT:-6379}"
  [minio]="${MINIO_PORT:-9000}"
  [minio-console]="${MINIO_CONSOLE_PORT:-9001}"
  [mongo]="${MONGO_PORT:-27017}"
  [cloudbeaver]="${CLOUDBEAVER_PORT:-8978}"
  [pgadmin]="${PGADMIN_PORT:-5050}"
  [redisinsight]="${REDISINSIGHT_PORT:-5540}"
  [mongo-express]="${MONGO_EXPRESS_PORT:-8081}"
)
core=(postgres redis minio minio-console mongo)
if (($# == 0)) || [[ ${1:-} == all ]]; then
  (($# <= 1)) || { printf '"all" cannot be combined with service names.\n' >&2; exit 2; }
  selected=("${core[@]}")
else
  selected=("$@")
fi

ssh_args=(-N -T -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3)
declare -A seen=()
for service in "${selected[@]}"; do
  [[ -v "ports[$service]" ]] || { printf 'Unknown service: %s\n' "$service" >&2; usage >&2; exit 2; }
  remote_port=${ports[$service]}
  [[ "$remote_port" =~ ^[0-9]+$ ]] || { printf 'Invalid port for %s: %s\n' "$service" "$remote_port" >&2; exit 2; }
  local_port=$((remote_port + offset))
  ((local_port > 0 && local_port < 65536)) || { printf 'Local port out of range: %s\n' "$local_port" >&2; exit 2; }
  [[ ! -v "seen[$local_port]" ]] || { printf 'Duplicate local port %s.\n' "$local_port" >&2; exit 2; }
  seen[$local_port]=1
  if command -v python3 >/dev/null 2>&1 && ! python3 - "$local_port" <<'PY'
import socket, sys
sock = socket.socket()
try:
    sock.bind(("127.0.0.1", int(sys.argv[1])))
except OSError:
    raise SystemExit(1)
finally:
    sock.close()
PY
  then
    printf 'Local port %s is already in use; set LOCAL_PORT_OFFSET or change the mapped port.\n' "$local_port" >&2
    exit 1
  fi
  ssh_args+=(-L "127.0.0.1:${local_port}:127.0.0.1:${remote_port}")
done
ssh_args+=(-- "$target")

if ((dry_run)); then
  printf 'ssh'
  printf ' %q' "${ssh_args[@]}"
  printf '\n'
else
  exec ssh "${ssh_args[@]}"
fi
