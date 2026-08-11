#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/postgres/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
s3cli_run /scripts/s3cli/list-backups.sh "$POSTGRES_BACKUP_BUCKET"
