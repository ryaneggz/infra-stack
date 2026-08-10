# MinIO backup replication roadmap

The current implementation intentionally stops at local, manually invoked backups. Advance only after restore drills prove the preceding phase.

## Phase 1 — local host-persisted storage (implemented)

MinIO persists to `${MINIO_DATA_DIR:-./data/minio}` on the VM. PostgreSQL scripts stage complete dumps, write SHA-256 files, upload checksum-before-data, and stream the object back for verification. This protects against container replacement, **not host or disk loss**.

## Phase 2 — operator-run remote mirror

Add an independently credentialed remote S3/MinIO alias and run `mc mirror --dry-run` first. Review destination, deletes, overwrite behavior, bandwidth, and object counts before an explicit non-dry-run mirror. Never reuse root MinIO credentials remotely. This phase remains manual.

## Phase 3 — systemd timer, retry, and retention

Wrap the reviewed mirror in a least-privilege systemd service/timer with bounded retries, lock/concurrency control, structured logs, success/failure notification, and explicit retention policy. Test missed-run recovery and disk-pressure behavior. Do not use an unobserved cron one-liner.

## Phase 4 — versioning, object lock, encryption, and restore drills

Evaluate destination versioning and object lock before selecting retention/legal-hold settings. Add encryption in transit and at rest with documented key ownership/recovery. Run scheduled restore drills for custom and cluster formats, record recovery time/objective evidence, and test compromised/deleted-source scenarios.

## Phase 5 — second-site replication and alerting

Replicate to a separately administered region/provider or physical site. Alert on freshness, checksum mismatch, replication lag, capacity, lock failures, and restore-drill regressions. Test loss of the entire primary VM and MinIO host path.

Automatic scheduling, retention, encryption, and replication are deliberately **not implemented** in this repository today.
