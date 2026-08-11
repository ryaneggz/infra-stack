# Architecture

## Local-first topology

The stack targets one development/MVP VM, not high availability. Every published port defaults to `127.0.0.1`. Applications communicate over the stable external Docker network `${INFRA_NETWORK:-infra}`; operators on another machine use [SSH tunnels](ssh-tunnels.md).

```mermaid
flowchart LR
  W[workstation clients] -->|SSH tunnel| V[one VM]
  A[application Compose] --> N[(external network: infra)]
  subgraph V
    N --- P[postgres :5432]
    N --- R[redis :6379]
    N --- S[minio :9000/:9001]
    N --- M[mongo :27017]
    P -->|verified dumps| S
  end
```

## Services, ports, and resources

| Service | Application hostname | Host port | Persistence | Default ceiling |
|---|---|---:|---|---:|
| Timescale PostgreSQL 17 | `postgres` | 5432 | `postgres_data` volume | 1.5 CPU / 2 GiB |
| Redis 7 | `redis` | 6379 | `redis_data` volume, AOF | 0.5 CPU / 512 MiB |
| MinIO API | `minio` | 9000 | `${MINIO_DATA_DIR}` secure bind | 0.75 CPU / 1 GiB |
| MinIO console | `minio` | 9001 | same bind | included above |
| MongoDB 8 | `mongo` | 27017 | `mongo_data` volume | 1 CPU / 1.5 GiB |

The total ceiling is about 3.75 CPUs and 5 GiB. Compose `cpus` and `mem_limit` are ceilings, not reservations. The literal `container_name: postgres` means only one copy may run per Docker host.

The AWS CLI utility service is profile-gated and starts only for S3 operations. Optional browser clients are described in [clients](clients.md).

## PostgreSQL vector extensions

`scripts/postgres/init.sql` runs on first initialization and creates `vectorscale CASCADE`, which installs `vector`. The PostgreSQL healthcheck requires both extensions. Existing volumes do not rerun initialization; verify with:

```bash
docker compose --env-file .env -f compose.yml exec postgres \
  psql -U infra -d app -c "SELECT extname FROM pg_extension WHERE extname IN ('vector','vectorscale');"
```

## Attach an application

`make network` or `make up` creates the external network. An application project attaches without publishing database ports:

```yaml
services:
  api:
    image: example/api:1.0.0
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

Use the complete [`examples/app-compose.yml`](../examples/app-compose.yml). Store credentials in the application's untracked secret mechanism.

## Persistence boundaries

`make down` preserves named volumes and MinIO host data. `make reset` removes all three named database volumes, the MinIO bind directory, and local PostgreSQL backups. A single VM or disk failure can still destroy primary data and local backups; follow the [replication roadmap](minio-replication-roadmap.md).
