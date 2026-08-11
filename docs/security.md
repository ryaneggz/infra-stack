# Security and non-goals

## Preserved hardening

- All host ports default to `127.0.0.1`; application traffic uses an external Docker network.
- `make init` creates `.env` atomically at mode `0600` with random 256-bit credentials and never overwrites.
- Preflight rejects symlinked or wrong-owner MinIO/backup paths, enforces directory mode `0700`, and Compose refuses implicit bind creation.
- Dumps, downloaded bytes, sidecars, locks, and test barriers are mode `0600`; restore accepts only clean staged downloads and independently validates SHA-256.
- A host lock plus random 128-bit names prevent local collisions. AWS CLI single PUTs use atomic `If-None-Match: *` for both checksum and artifact. Metadata-bound cleanup deletes only objects owned by that attempt.
- Operator arguments use inherited environment values. Make rejects source-injectable legacy assignments; adversarial tests cover every affected target.
- CI cleanup fails if any project container, volume, network, `.env`, data, or backup path remains.

## Archived MinIO upstream

The MinIO Client source repository became read-only on July 14, 2026. This project removed that runtime entirely and uses the actively maintained official `amazon/aws-cli:2.36.20` image. Live tests prove bucket creation, head/get/list, metadata inspection, and atomic conditional `put-object` behavior against the pinned MinIO server.

The MinIO server source repository is also archived. Operator-approved scope requires retaining `minio/minio:RELEASE.2025-09-07T16-13-09Z` for now, so this repository clearly treats it as frozen legacy infrastructure, not an actively maintained server. Consequences include no expected upstream security fixes, growing dependency/CVE exposure, and possible future client/platform incompatibility. Keep it loopback-only, restrict Docker/host access, monitor advisories, minimize retention of sensitive data, and prioritize the [S3 server migration decision](minio-replication-roadmap.md#decision-gate--s3-server-migration). Do not silently replace the server: migration requires operator approval and restore evidence.

## Credential and transport boundaries

Root credentials are present in `.env`, container environments, and Docker inspection metadata. Docker-daemon administrators can read them. Source only a trusted `.env`. Password authentication does not encrypt plaintext traffic inside the Docker network or loopback mappings. Use restricted SSH, a firewall, host disk encryption, least-privilege application users, credential rotation, and off-host encrypted backups.

## Explicit non-goals

This repository does not provide TLS termination, Internet exposure, firewall automation, secrets management, HA, automatic failover, backup scheduling, retention, encryption, object lock, remote replication, monitoring, auditing, or production compliance. It is a local-first/single-VM foundation. Optional UIs are convenience tools, not a security boundary.

Container images and bundled extensions keep their upstream licenses. Review them independently, including the pinned MinIO server's AGPLv3 terms.
