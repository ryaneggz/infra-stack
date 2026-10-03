# msb infra deployment

This directory is the live configuration of the `infra` MicroSandbox VM. It is separate from the generic stack at the repository root. The VM mounts the host directory `/opt/infra-services` at `/home/dev/infra-services`.

| Path | Services |
|---|---|
| `compose.yml` | `infra-postgres` (pgvector, PostgreSQL 17), shared with production |
| `langfuse/compose.yml` | Langfuse web and worker, ClickHouse, `infra-redis`, `infra-minio`, `infra-cloudflared` (profile `tunnel`) |
| `langfuse/clickhouse-config.d/zz-limits.xml` | ClickHouse log level and size, system-log TTLs, `keep_free_space_bytes` |

Secrets are not tracked. Create the dotenv file from `env.template` in each directory, or run `langfuse/gen-secrets.sh`. First-time setup is in `langfuse/runbook-langfuse.sh`.

## Apply a change

Copy the changed files to `/opt/infra-services` on the host, then run in the sandbox:

```bash
cd /home/dev/infra-services && sudo docker compose up -d
cd /home/dev/infra-services/langfuse && sudo docker compose --profile tunnel up -d
```

Recreating `infra-postgres` interrupts production database access for several seconds.

## Disk limits

Every container rotates its log at 20 MB × 3. ClickHouse logs at `warning`, keeps system logs for 7 days, disables `trace_log` and `text_log`, and stops writing when less than 4 GiB of the shared Docker disk is free.
