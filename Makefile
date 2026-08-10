SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

COMPOSE = docker compose --env-file .env -f compose.yml
CLIENTS = $(COMPOSE) -f compose.clients.yml

.PHONY: help init network config pull up down ps logs clients clients-pgadmin backup-db backup-all verify-backups smoke reset
help: ## Show commands
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## Create .env with strong random credentials; never overwrite
	@./scripts/init.sh

network: ## Create the stable external network if absent
	@set -a; source ./.env; set +a; \
		docker network inspect "$${INFRA_NETWORK:-infra}" >/dev/null 2>&1 || \
		docker network create "$${INFRA_NETWORK:-infra}" >/dev/null

config: ## Validate the base and client Compose models
	@$(COMPOSE) config --quiet
	@$(CLIENTS) config --quiet
	@$(CLIENTS) --profile pgadmin config --quiet

pull: network ## Pull pinned service images
	@$(COMPOSE) --profile tools pull

up: network ## Start the four core databases only
	@$(COMPOSE) up -d --wait --wait-timeout 240

clients: network ## Start core services and default optional clients
	@$(CLIENTS) up -d

clients-pgadmin: network ## Start core, default clients, and pgAdmin profile
	@$(CLIENTS) --profile pgadmin up -d

down: ## Stop services; preserve database volumes and MinIO host data
	@$(CLIENTS) --profile pgadmin down --remove-orphans

ps: ## Show service status
	@$(COMPOSE) ps

logs: ## Follow core service logs
	@$(COMPOSE) logs -f --tail=100

backup-db: ## Back up one database: make backup-db DB=app
	@test -n "$(DB)" || { echo 'DB is required: make backup-db DB=app' >&2; exit 2; }
	@./scripts/postgres/backup-db.sh "$(DB)"

backup-all: ## Back up the cluster (sensitive role hashes included)
	@./scripts/postgres/backup-all.sh

verify-backups: ## Verify local checksums and downloaded MinIO objects
	@./scripts/postgres/verify-backups.sh

smoke: ## Exercise health, auth, network, backup, and both restore formats
	@./scripts/smoke.sh

reset: ## DESTROYS all local data; requires CONFIRM=destroy
	@test "$(CONFIRM)" = destroy || { echo 'Refusing. Re-run: make reset CONFIRM=destroy' >&2; exit 2; }
	@set -a; source ./.env; set +a; \
		$(CLIENTS) --profile pgadmin down --volumes --remove-orphans; \
		rm -rf -- "$${MINIO_DATA_DIR:-./data/minio}" "$${POSTGRES_BACKUP_DIR:-./backups/postgres}"
