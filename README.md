# infra-stack

[![CI](https://github.com/ryaneggz/infra-stack/actions/workflows/ci.yml/badge.svg)](https://github.com/ryaneggz/infra-stack/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A reusable, local-first Docker Compose data stack for one MVP VM: PostgreSQL 17 with `vectorscale`/`vector`, Redis 7, MinIO, and MongoDB. It is intentionally **not a production high-availability design**. Every host port defaults to `127.0.0.1`; remote operators connect through SSH tunnels and applications connect over a shared Docker network.

```mermaid
flowchart LR
  L[Local database clients] -->|SSH tunnel| V[One MVP VM]
  A[Application Compose projects] --> N[(external network: infra)]
  subgraph V
    N --- P[postgres :5432]
    N --- R[redis :6379]
    N --- M[minio :9000/:9001]
    N --- D[mongo :27017]
    P -->|pg_dump / pg_dumpall| M
  end
```

## Quick start

Requirements: Docker Engine with Compose v2/v5, GNU Make, Bash, OpenSSL, and enough disk for the images (the Timescale all-extensions image is about 2.5 GB compressed).

```bash
git clone https://github.com/ryaneggz/infra-stack.git
cd infra-stack
make init       # creates mode-0600 .env with random 256-bit secrets; never overwrites
make config
make up         # exactly the four core databases
make smoke      # health/auth/network plus backup and restore verification
```

`make ps`, `make logs`, `make pull`, and `make down` cover normal lifecycle operations. Startup, clients, backup, download, and smoke targets automatically run `make preflight`: MinIO and PostgreSQL backup host directories are created with mode `0700`, checked for symlinks and wrong ownership, and only then passed to Compose. Long bind syntax sets `create_host_path: false`, so Docker cannot silently create an insecure root-owned MinIO path. `make down` preserves data. `INFRA_CONFIRM_RESET=destroy make reset` is the explicit, irreversible reset; it deletes database volumes, MinIO host data, and local backups.

## Services

| Service | Application hostname | Default localhost port | Persistence | Default resource limit |
|---|---|---:|---|---:|
| PostgreSQL 17 | `postgres` | 5432 | named volume | 1.5 CPU / 2 GiB |
| Redis 7 | `redis` | 6379 | named volume (AOF) | 0.5 CPU / 512 MiB |
| MinIO API / console | `minio` | 9000 / 9001 | `${MINIO_DATA_DIR:-./data/minio}` bind mount | 0.75 CPU / 1 GiB |
| MongoDB | `mongo` | 27017 | named volume | 1 CPU / 1.5 GiB |

The configured ceiling is approximately **3.75 CPUs and 5 GiB RAM**, leaving roughly 3 GiB on an 8 GiB VM for the OS, Docker, and an MVP application. Limits are real Compose `cpus`/`mem_limit` settings (not Swarm-only `deploy.resources`). Tune each `*_CPUS` and `*_MEMORY` value in `.env` based on observed workload. Limits are ceilings, not reservations.

The literal `container_name: postgres` is a deliberate single-VM compatibility constraint, so only one copy of this stack can run on a Docker host.

## Image policy and architecture support

`.example.env` pins immutable multi-platform manifest digests; changing an image is an explicit operator action. Current core pins:

- [`timescale/timescaledb-ha:pg17.6-ts2.21.3-all`](https://hub.docker.com/r/timescale/timescaledb-ha/tags?name=pg17.6-ts2.21.3-all), digest `sha256:10018c…608f`. This official Timescale PostgreSQL 17.6 / TimescaleDB 2.21.3 **all-extensions** image is the upstream-supported prebuilt route documented by [`timescale/pgvectorscale`](https://github.com/timescale/pgvectorscale/tree/0.9.0#using-a-pre-built-docker-container). It includes `vectorscale`; `CREATE EXTENSION vectorscale CASCADE` installs `vector`. Startup and health checks prove both. The image is unusually large (~2.4–2.5 GB compressed).
- [`redis:7.4.7-alpine`](https://hub.docker.com/_/redis/tags?name=7.4.7-alpine), digest `sha256:02f2cc…bfcf`. Official Redis 7 Alpine, password auth and AOF enabled.
- [`minio/minio:RELEASE.2025-09-07T16-13-09Z`](https://hub.docker.com/r/minio/minio/tags?name=RELEASE.2025-09-07), digest `sha256:14cea4…936e`, plus pinned [`minio/mc:RELEASE.2025-08-13T08-35-41Z`](https://hub.docker.com/r/minio/mc/tags?name=RELEASE.2025-08-13), digest `sha256:a7fe34…1727`.
- [`mongo:8.0.28-noble`](https://hub.docker.com/_/mongo/tags?name=8.0.28-noble), digest `sha256:346f9f…d0fe`.

All core manifests include Linux `amd64` and `arm64`. The pinned CloudBeaver, pgAdmin, RedisInsight, and Mongo Express manifests also publish both architectures. Timescale's prebuilt-container path avoids the project's unsupported native macOS Intel build. Digest pins intentionally do not float to security fixes: review upstream release notes, update tag+digest together, then run `make smoke` and CI. The repository is MIT-licensed; container images and bundled extensions retain their own upstream licenses (including MinIO's AGPLv3), which operators must review.

## Configuration and security defaults

Only `.example.env` is tracked. `make init` creates `.env` atomically with strong credentials and refuses to replace an existing file. Git and Docker ignore `.env`, every environment-file variation, `data/`, `backups/`, dumps, checksums, logs, and runtime state while explicitly retaining `.example.env`. Backup processes enforce `umask 077`: backup/download directories are `0700`, and dumps plus sidecar checksums are `0600`. This is especially important for `pg_dumpall`, which contains role password hashes.

All published mappings use `${BIND_HOST:-127.0.0.1}`. Do not set `BIND_HOST=0.0.0.0` on an Internet-facing VM. Password auth is enabled, but transport inside the Docker network and localhost mappings is plaintext. Root credentials are present in `.env`, container environments/commands, and Docker inspection metadata; access to the Docker daemon is therefore equivalent to root-secret access. Source only a trusted `.env`. This stack does not configure TLS, firewalling, secret rotation, auditing, HA, automated failover, scheduling, retention, or encryption. Use host disk encryption, restricted SSH, firewall rules, patched images, least-privilege application users, and off-host backups before production use.

## Attach an application

The stack uses an explicitly managed external network named `${INFRA_NETWORK:-infra}`. `make up` creates it when absent. Other Compose projects attach without publishing database ports:

```yaml
services:
  api:
    image: example/api
    networks: [infra]
    environment:
      DATABASE_URL: postgresql://infra:PASSWORD@postgres:5432/app
      REDIS_URL: redis://:PASSWORD@redis:6379/0
      MONGO_URL: mongodb://infra:PASSWORD@mongo:27017/app?authSource=admin
      S3_ENDPOINT: http://minio:9000
networks:
  infra:
    external: true
    name: infra
```

See [`examples/app-compose.yml`](examples/app-compose.yml). Application hostnames are exactly `postgres`, `redis`, `minio`, and `mongo`. Keep credentials in the application's untracked secret store, not its Compose file.

## SSH-first client workflow

On a workstation:

```bash
scripts/tunnel.sh --dry-run deploy@example-vm postgres redis mongo
scripts/tunnel.sh deploy@example-vm            # all five core port mappings
LOCAL_PORT_OFFSET=10000 scripts/tunnel.sh deploy@example-vm postgres
```

The helper validates `user@host`, service names, duplicate/out-of-range ports, and local collisions where Python is available. SSH uses `ExitOnForwardFailure`, a 30-second keepalive, and three missed-keepalive limit. The VM-side endpoint is `127.0.0.1:<configured-port>` because Compose publishes only to loopback.

Locally installed clients connect as follows after tunneling:

- pgAdmin, DBeaver, or `psql`: host `127.0.0.1`, port `5432`, database/user/password from `.env`, SSL disabled unless separately added.
- RedisInsight or `redis-cli`: host `127.0.0.1`, port `6379`, password from `.env`, no username.
- MongoDB Compass: `mongodb://infra:PASSWORD@127.0.0.1:27017/?authSource=admin`.
- Browser: MinIO console `http://127.0.0.1:9001`.

## Optional web clients

Web UIs never start through base `make up`:

```bash
make clients          # CloudBeaver, RedisInsight, Mongo Express; also ensures core is up
make clients-pgadmin  # same, plus pgAdmin's explicit profile
```

All UI ports are loopback-bound. Defaults: CloudBeaver `8978`, pgAdmin `5050`, RedisInsight `5540`, Mongo Express `8081`. Inside those containers use `postgres`, `redis`, and `mongo`; through an SSH tunnel use the `127.0.0.1` settings above. MinIO's built-in console makes another S3 UI unnecessary. Browser clients increase attack surface and are secondary to installed clients over SSH.

## PostgreSQL backup and restore

```bash
INFRA_ARG_DB=app make backup-db   # custom-format ..._app_<128-bit-id>.dump + .sha256
make backup-all         # gzip SQL ..._cluster_<128-bit-id>.sql.gz + .sha256 (SENSITIVE)
make verify-backups     # local pair + remote MinIO object/checksum
make list-backups
```

Publication uses a non-blocking exclusive host lock and a random 128-bit name. Existing local files or remote keys are rejected—never overwritten. Each pinned [`mc put`](https://docs.min.io/community/minio-object-store/reference/minio-mc/mc-put.html) sends the supported [S3 conditional write](https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-writes.html) header `-H 'If-None-Match:*'` with multipart disabled; MinIO atomically rejects a raced or existing key with HTTP 412. Upload-attempt metadata, checksum-before-data ordering, and guarded cleanup remove only keys proven to belong to the current attempt. Smoke covers both PUTs independently: two writers race the checksum key and prove exactly one winner, then a barrier forces an external artifact key insertion after pre-checks but before the artifact PUT. The artifact conditional write is rejected, external bytes/ownership metadata remain unchanged, and cleanup removes only the failed attempt's owned checksum. A separate retry test covers keys that pre-exist before upload starts.

**Always restore downloaded MinIO bytes, never the untested local source artifact.** Download tooling creates a new mode-`0700` staging directory, fetches both the object and sidecar, validates the sidecar filename and SHA-256, and writes both as `0600`:

```bash
name=20260810T120000Z_app_0123456789abcdef0123456789abcdef.dump
downloaded=$(scripts/postgres/download-backup.sh "$name")
scripts/postgres/restore-db.sh "$downloaded" restore_app_test
docker compose exec postgres psql -U "$POSTGRES_USER" -d restore_app_test
```

`restore-db.sh` independently requires and validates `FILE.dump.sha256` before changing the target database.

Cluster restore must use a **fresh PostgreSQL 17 target with the same Timescale all-extensions image**. It recreates databases and roles; the downloaded gzip and sidecar remain sensitive. Restrict access and never commit or casually copy them:

```bash
name=20260810T120000Z_cluster_0123456789abcdef0123456789abcdef.sql.gz
downloaded=$(scripts/postgres/download-backup.sh "$name")
docker run -d --name pg17-restore --network infra \
  -e POSTGRES_PASSWORD=temporary "$POSTGRES_IMAGE"
scripts/postgres/restore-all.sh "$downloaded" pg17-restore
# inspect/query restored data, then:
docker rm -fv pg17-restore
```

`INFRA_ARG_NAME=... make download-backup`, `INFRA_ARG_FILE=... INFRA_ARG_TARGET=restore_test make restore-db`, and `INFRA_ARG_FILE=... INFRA_ARG_CONTAINER=pg17-restore make restore-all` expose the same guarded operator tools. Values intentionally travel through the inherited process environment rather than Make recipe source. Legacy `DB=`, `NAME=`, `FILE=`, `TARGET=`, `CONTAINER=`, and `CONFIRM=` Make assignments are rejected before expansion. `make security-test` runs quote, semicolon, command-substitution, whitespace, and traversal payloads against every affected target. `make smoke` downloads both pairs into separate clean staging directories, restores only those downloaded bytes, queries known markers, tests lock/retry/conditional-race rejection, and checks restrictive modes. Read the replication path in [`docs/minio-replication-roadmap.md`](docs/minio-replication-roadmap.md).

## Troubleshooting

- **`network infra declared as external, but could not be found`**: run `make network` or `make up` rather than raw Compose.
- **Port already allocated**: edit the corresponding `*_PORT` or `BIND_HOST` in `.env`; for tunnels use `LOCAL_PORT_OFFSET`.
- **`postgres` container name conflict**: this stack permits only one instance per VM. Remove/rename the other container only after identifying its owner.
- **PostgreSQL unhealthy**: inspect `docker compose logs postgres`; extension initialization only runs on a new volume. For a preexisting volume, execute `CREATE EXTENSION IF NOT EXISTS vectorscale CASCADE;` as an owner and verify both extension rows.
- **MinIO/backup path preflight failure**: do not bypass `make preflight`. Remove symlinks, restore ownership to the invoking user, and let preflight enforce mode `0700`; Compose intentionally refuses to auto-create bind sources.
- **Digest/platform error**: use Linux amd64/arm64 and update to a verified multi-platform upstream manifest rather than deleting only the digest.
- **Slow first CI/start**: the Timescale all-extensions image is large. Subsequent pulls can use Docker layer cache.

## Scope and contributing

This repository optimizes for reproducible local development and a single MVP VM. It does not claim production HA. See [CONTRIBUTING.md](CONTRIBUTING.md), [CHANGELOG.md](CHANGELOG.md), and the [MIT license](LICENSE).
