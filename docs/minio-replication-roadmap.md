# S3 backup replication and server-migration roadmap

The current implementation intentionally stops at local, manually invoked backups. The pinned MinIO server source repository is archived and no longer an actively maintained security baseline. Its legacy client was archived July 14, 2026 and has already been removed from this project; backup tooling uses official AWS CLI 2.36.20 instead.

## Phase 1 — local host-persisted storage (implemented)

MinIO persists to `${MINIO_DATA_DIR:-./data/minio}` after ownership/symlink/mode preflight; Compose refuses to create the bind source implicitly. PostgreSQL scripts use exclusive locking and 128-bit object names, stage mode-`0600` dumps/checksums under mode-`0700` directories, and publish checksum-before-data with atomic conditional single PUTs. Restore tooling downloads both objects into a clean stage, verifies SHA-256, and restores only downloaded bytes. This protects against container replacement and unverified restore sources, not host/disk loss or an unpatched archived server.

## Decision gate — S3 server migration

Before expanding MinIO's role, obtain operator approval for one of two explicit choices:

1. time-bound acceptance of the archived pinned server with compensating controls; or
2. migration to an actively maintained S3-compatible server.

Evaluate currently maintained candidates at decision time rather than hard-coding a replacement now. Candidate classes include Garage, SeaweedFS, Ceph Object Gateway, and other official S3-compatible distributions. Verify current maintenance status, license, vulnerability response, Linux `amd64`/`arm64` images, resource fit, single-node operation, conditional `If-None-Match: *` semantics, metadata fidelity, list/head/get/delete behavior, multipart limits, versioning/object lock, backup tooling, and an exit path.

A migration must preserve the external S3 contract and backup format:

- bucket/key names and paired artifact plus `.sha256` objects;
- custom PostgreSQL dumps and gzip cluster SQL bytes unchanged;
- object metadata used for attempt ownership;
- HTTP 412 behavior for both independently raced conditional PUTs;
- downloaded-byte checksum validation and both restore drills;
- rollback export/import evidence and zero unexplained object differences.

Run a copy into a disposable candidate, compare object count/size/hash/metadata, execute the full smoke and restore suite, document rollback, then request operator approval. Do not silently replace MinIO in this scope.

## Phase 2 — operator-run off-host copy

Use independently credentialed least-privilege source/destination accounts. Select and pin an actively maintained replication tool only after proving dry-run behavior, metadata preservation, delete/overwrite defaults, bandwidth controls, resumability, and end-to-end checksums. Review the complete plan before an explicit copy. Never reuse root server credentials at the destination.

## Phase 3 — timer, retry, and retention

Wrap the reviewed copy in a least-privilege systemd service/timer with bounded retries, lock/concurrency control, structured logs, success/failure notification, and explicit retention. Test missed-run recovery and disk-pressure behavior. Do not use an unobserved cron one-liner.

## Phase 4 — versioning, object lock, encryption, and restore drills

Evaluate destination versioning and object lock before selecting retention/legal-hold settings. Add encryption in transit and at rest with documented key ownership/recovery. Schedule custom and cluster restore drills, record recovery evidence, and test compromised/deleted-source scenarios.

## Phase 5 — second site and alerting

Replicate to a separately administered provider, region, or physical site. Alert on freshness, checksum mismatch, lag, capacity, lock failures, and restore-drill regressions. Test loss of the entire primary VM and local S3 path.

Scheduling, retention, encryption, automatic replication, and server migration are deliberately not implemented today.
