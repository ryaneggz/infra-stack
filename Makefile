SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

COMPOSE = docker compose --env-file .env -f compose.yml
CLIENTS = $(COMPOSE) -f compose.clients.yml

# Values that reach operator scripts must arrive through the process environment.
# Legacy command-line Make variables are rejected before Make can expand payloads.
ifneq ($(origin DB),undefined)
$(error DB= is unsafe; use INFRA_ARG_DB=... make backup-db)
endif
ifneq ($(origin NAME),undefined)
$(error NAME= is unsafe; use INFRA_ARG_NAME=... make download-backup)
endif
ifneq ($(origin FILE),undefined)
$(error FILE= is unsafe; use INFRA_ARG_FILE=... make restore-db/restore-all)
endif
ifneq ($(origin TARGET),undefined)
$(error TARGET= is unsafe; use INFRA_ARG_TARGET=... make restore-db)
endif
ifneq ($(origin CONTAINER),undefined)
$(error CONTAINER= is unsafe; use INFRA_ARG_CONTAINER=... make restore-all)
endif
ifneq ($(origin CONFIRM),undefined)
$(error CONFIRM= is unsafe; use INFRA_CONFIRM_RESET=destroy make reset)
endif
unexport DB NAME FILE TARGET CONTAINER CONFIRM

.PHONY: help init preflight network config pull up down ps logs clients clients-pgadmin backup-db backup-all list-backups download-backup verify-backups restore-db restore-all security-test smoke reset
help: ## Show commands
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## Create .env with strong random credentials; never overwrite
	@./scripts/init.sh

preflight: ## Secure and validate MinIO/backup host paths
	@./scripts/preflight.sh

network: ## Create the stable external network if absent
	@set -a; source ./.env; set +a; \
		docker network inspect "$${INFRA_NETWORK:-infra}" >/dev/null 2>&1 || \
		docker network create "$${INFRA_NETWORK:-infra}" >/dev/null

config: ## Validate the base and client Compose models
	@$(COMPOSE) config --quiet
	@$(CLIENTS) config --quiet
	@$(CLIENTS) --profile pgadmin config --quiet

pull: preflight network ## Pull pinned service images
	@$(COMPOSE) --profile tools pull

up: preflight network ## Start the four core databases only
	@$(COMPOSE) up -d --wait --wait-timeout 240

clients: preflight network ## Start core services and default optional clients
	@$(CLIENTS) up -d

clients-pgadmin: preflight network ## Start core, default clients, and pgAdmin profile
	@$(CLIENTS) --profile pgadmin up -d

down: ## Stop services; preserve database volumes and MinIO host data
	@$(CLIENTS) --profile pgadmin down --remove-orphans

ps: ## Show service status
	@$(COMPOSE) ps

logs: ## Follow core service logs
	@$(COMPOSE) logs -f --tail=100

backup-db: preflight ## Back up one database: INFRA_ARG_DB=app make backup-db
	@./scripts/postgres/backup-db.sh

backup-all: preflight ## Back up the cluster (sensitive role hashes included)
	@./scripts/postgres/backup-all.sh

list-backups: preflight ## List remote PostgreSQL backup objects
	@./scripts/postgres/list-backups.sh

download-backup: preflight ## Download+verify: INFRA_ARG_NAME=... make download-backup
	@./scripts/postgres/download-backup.sh

verify-backups: preflight ## Verify local and remote backup pairs
	@./scripts/postgres/verify-backups.sh

restore-db: preflight ## Restore custom backup using INFRA_ARG_FILE/INFRA_ARG_TARGET
	@./scripts/postgres/restore-db.sh

restore-all: preflight ## Restore cluster using INFRA_ARG_FILE/INFRA_ARG_CONTAINER
	@./scripts/postgres/restore-all.sh

security-test: preflight ## Prove Make arguments cannot execute shell source
	@./scripts/test-make-args.py

smoke: preflight network ## Exercise download, auth, backup, and both restore formats
	@./scripts/smoke.sh

reset: ## DESTROYS all local data; requires INFRA_CONFIRM_RESET=destroy
	@test "$${INFRA_CONFIRM_RESET:-}" = destroy || { echo 'Refusing. Re-run: INFRA_CONFIRM_RESET=destroy make reset' >&2; exit 2; }
	@set -a; source ./.env; set +a; \
		$(CLIENTS) --profile pgadmin down --volumes --remove-orphans; \
		rm -rf -- "$${MINIO_DATA_DIR:-./data/minio}" "$${POSTGRES_BACKUP_DIR:-./backups/postgres}"
