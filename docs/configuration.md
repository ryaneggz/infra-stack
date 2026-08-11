# Configuration and image upgrades

## Environment

Only `.example.env` is tracked. Run `make init` once; it copies the template through an atomic mode-`0600` temporary file, replaces every `CHANGE_ME_` secret with 256 random bits, and refuses to overwrite `.env`.

| Group | Variables | Purpose |
|---|---|---|
| Project/network | `COMPOSE_PROJECT_NAME`, `BIND_HOST`, `INFRA_NETWORK` | Compose identity, loopback bind, shared network |
| PostgreSQL | `POSTGRES_IMAGE`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `POSTGRES_PORT`, `POSTGRES_CPUS`, `POSTGRES_MEMORY` | Image, credentials, port, limits |
| Redis | `REDIS_IMAGE`, `REDIS_PASSWORD`, `REDIS_PORT`, `REDIS_CPUS`, `REDIS_MEMORY` | Image, auth, port, limits |
| MinIO/S3 | `MINIO_IMAGE`, `AWS_CLI_IMAGE`, `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`, `MINIO_PORT`, `MINIO_CONSOLE_PORT`, `MINIO_DATA_DIR`, `MINIO_CPUS`, `MINIO_MEMORY`, `POSTGRES_BACKUP_BUCKET` | Server, official S3 CLI, root auth, storage, limits, backup bucket |
| MongoDB | `MONGO_IMAGE`, `MONGO_ROOT_USERNAME`, `MONGO_ROOT_PASSWORD`, `MONGO_INITDB_DATABASE`, `MONGO_PORT`, `MONGO_CPUS`, `MONGO_MEMORY` | Image, credentials, port, limits |
| Backups | `POSTGRES_BACKUP_DIR`; process-only `INFRA_RESTORE_READY_TIMEOUT` | Mode-`0700` local dump/download root; optional 1–600 second cluster-target readiness limit (default 180) |
| Clients | `CLOUDBEAVER_IMAGE`, `CLOUDBEAVER_PORT`, `PGADMIN_IMAGE`, `PGADMIN_DEFAULT_EMAIL`, `PGADMIN_DEFAULT_PASSWORD`, `PGADMIN_PORT`, `REDISINSIGHT_IMAGE`, `REDISINSIGHT_PORT`, `MONGO_EXPRESS_IMAGE`, `MONGO_EXPRESS_PORT`, `MONGO_EXPRESS_BASICAUTH_USERNAME`, `MONGO_EXPRESS_BASICAUTH_PASSWORD` | Optional UI images, ports, auth |

Keep `BIND_HOST=127.0.0.1` unless a separately reviewed firewall/TLS design requires otherwise. Relative data paths resolve from the repository root.

## Image tag policy

User-facing references use concise fixed semantic or upstream release tags, never `latest` and never digest suffixes. Examples: `redis:7.4.7-alpine` and `amazon/aws-cli:2.36.20`. Compose defaults and `.example.env` must match. Every current image tag resolves to Linux `amd64` and `arm64`; CI verifies that claim against Docker Hub.

**Tradeoff:** fixed tags make versions readable and upgrades reviewable, but registry owners can mutate a tag. A digest gives byte-level immutability and stronger supply-chain reproducibility, at the cost of noisy references and platform-specific review complexity. This project accepts tag mutability for operator readability. It compensates with exact tags, manifest checks, explicit upgrades, smoke/restore tests, and CI. For higher-assurance deployments, record the resolved `RepoDigest` in release evidence or enforce approved digests in deployment policy without putting them in user-facing Compose.

Tags do not float to security fixes. Operators must monitor upstream advisories. The MinIO server is a special archived-upstream risk; see [security](security.md#archived-minio-upstream).

## Exact upgrade procedure

1. Read upstream release notes, CVEs, license changes, and migration notes. Choose an exact semantic/release tag, never `latest`.
2. Change the image variable in `.example.env` and the matching fallback in `compose.yml` or `compose.clients.yml`. Update your untracked `.env` separately; `make init` intentionally will not overwrite it.
3. Prove both supported manifests resolve:

   ```bash
   python3 scripts/validate-image-tags.py
   ```

4. Pull and record what the current host resolved:

   ```bash
   make pull
   docker image inspect redis:7.4.7-alpine --format '{{json .RepoDigests}}'
   ```

   Substitute the upgraded reference in the inspect command. Review unexpected registry/digest changes before continuing.
5. Validate configuration, security controls, all four live services, S3 conditional writes, downloads, and both restore formats:

   ```bash
   make config
   make security-test
   make smoke
   ```

6. Update documentation and `CHANGELOG.md` in the same commit. Push only while the PR is draft; require GitHub Actions and GitGuardian to pass before review.

The image validator checks all nine configured images, including optional clients and AWS CLI, for Linux `amd64` and `arm64` manifests.
