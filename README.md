# infra-stack

[![CI](https://github.com/ryaneggz/infra-stack/actions/workflows/ci.yml/badge.svg)](https://github.com/ryaneggz/infra-stack/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A reusable, local-first Docker Compose data stack for one MVP VM: PostgreSQL 17 with `vectorscale`/`vector`, Redis 7, MinIO, and MongoDB. It is not a production high-availability design. Ports bind to `127.0.0.1`; remote operators use SSH tunnels and applications use an external Docker network.

> **Upstream status:** the MinIO server source repository is archived. This stack keeps its approved fixed MinIO release for compatibility; it does not represent MinIO as actively maintained. Review [security implications](docs/security.md#archived-minio-upstream) and the [migration decision gate](docs/minio-replication-roadmap.md#decision-gate--s3-server-migration) before production use.

## Quick start

Prerequisites: Linux Docker Engine, Docker Compose v2/v5, GNU Make, Bash, OpenSSL, `flock`, Python 3, and enough disk for the images. The Timescale all-extensions image is approximately 2.5 GB compressed.

```bash
git clone https://github.com/ryaneggz/infra-stack.git
cd infra-stack
make init
make config
make up
make smoke
```

`make init` atomically creates a mode-`0600` `.env` with random 256-bit credentials and never overwrites it. `make up` starts exactly four core services. `make down` preserves data. Reset is intentionally explicit and destructive:

```bash
INFRA_CONFIRM_RESET=destroy make reset
```

## At a glance

| Service | Docker hostname | Local port | Persistence | CPU / memory ceiling |
|---|---|---:|---|---:|
| PostgreSQL 17 | `postgres` | 5432 | named volume | 1.5 / 2 GiB |
| Redis 7 | `redis` | 6379 | named volume, AOF | 0.5 / 512 MiB |
| MinIO API / console | `minio` | 9000 / 9001 | secure host bind | 0.75 / 1 GiB |
| MongoDB | `mongo` | 27017 | named volume | 1 / 1.5 GiB |

Common commands:

```bash
make ps
make logs
make pull
INFRA_ARG_DB=app make backup-db
make list-backups
make down
```

## Documentation

Start with the [documentation index](docs/README.md):

- [Architecture and application attachment](docs/architecture.md)
- [Configuration and image upgrades](docs/configuration.md)
- [Lifecycle operations and CI](docs/operations.md)
- [Backups and restore](docs/backups-and-restore.md)
- [SSH tunnels](docs/ssh-tunnels.md)
- [Optional clients](docs/clients.md)
- [Security and non-goals](docs/security.md)
- [Troubleshooting](docs/troubleshooting.md)
- [S3 replication and server-migration roadmap](docs/minio-replication-roadmap.md)

See also [`examples/app-compose.yml`](examples/app-compose.yml), [CONTRIBUTING.md](CONTRIBUTING.md), [CHANGELOG.md](CHANGELOG.md), and [LICENSE](LICENSE).
