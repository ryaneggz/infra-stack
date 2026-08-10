#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
project=infra-stack
network=infra
if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
  project=${COMPOSE_PROJECT_NAME:-infra-stack}
  network=${INFRA_NETWORK:-infra}

  restore_output=$(docker ps -aq --filter 'name=^infra-stack-restore-')
  if [[ -n "$restore_output" ]]; then
    mapfile -t restore_containers <<< "$restore_output"
    docker rm -fv "${restore_containers[@]}"
  fi
  docker compose --project-directory "$ROOT" --env-file "$ROOT/.env" \
    -f "$ROOT/compose.yml" -f "$ROOT/compose.clients.yml" --profile pgadmin \
    down --volumes --remove-orphans
  if docker network inspect "$network" >/dev/null 2>&1; then
    docker network rm "$network"
  fi
fi

if command -v sudo >/dev/null 2>&1; then
  sudo rm -rf -- "$ROOT/data" "$ROOT/backups" "$ROOT/.env" \
    /tmp/compose.json /tmp/infra-stack-pg_dumpall-restore.*
else
  rm -rf -- "$ROOT/data" "$ROOT/backups" "$ROOT/.env" \
    /tmp/compose.json /tmp/infra-stack-pg_dumpall-restore.*
fi

remaining_containers=$(docker ps -aq --filter "label=com.docker.compose.project=$project")
[[ -z "$remaining_containers" ]] || { printf 'Project containers remain: %s\n' "$remaining_containers" >&2; exit 1; }
remaining_volumes=$(docker volume ls -q --filter "label=com.docker.compose.project=$project")
[[ -z "$remaining_volumes" ]] || { printf 'Project volumes remain: %s\n' "$remaining_volumes" >&2; exit 1; }
if docker network inspect "$network" >/dev/null 2>&1; then
  printf 'External network remains: %s\n' "$network" >&2
  exit 1
fi
[[ ! -e "$ROOT/data" && ! -e "$ROOT/backups" && ! -e "$ROOT/.env" ]] || {
  printf 'Runtime host paths remain after cleanup.\n' >&2
  exit 1
}
printf 'CI cleanup verified: no project containers, volumes, network, or runtime paths remain.\n'
