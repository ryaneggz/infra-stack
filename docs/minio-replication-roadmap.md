# MinIO backup replication roadmap

The current implementation intentionally stops at local, manually invoked backups. Advance only after restore drills prove the preceding phase.

## Phase 1 — local host-persisted storage (implemented)

MinIO persists to `${MINIO_DATA_DIR:-./data/minio}` on the VM after an ownership/symlink/mode preflight; Compose refuses to auto-create the bind path. PostgreSQL scripts use exclusive locking and 128-bit object names, stage complete mode-`0600` dumps and checksums under mode-`0700` directories, reject existing remote keys, and upload checksum-before-data with attempt-bound cleanup. Restore tooling downloads both remote objects into a clean staging directory, verifies SHA-256, and restores only downloaded bytes. This protects against container replacement and unverified restore sources, **not host or disk loss**.

## Phase 2 — operator-run remote mirror

Add an independently credentialed remote S3/MinIO alias and run `mc mirror --dry-run` first. Review destination, deletes, overwrite behavior, bandwidth, and object counts before an explicit non-dry-run mirror. Never reuse root MinIO credentials remotely. This phase remains manual.

## Phase 3 — systemd timer, retry, and retention

Wrap the reviewed mirror in a least-privilege systemd service/timer with bounded retries, lock/concurrency control, structured logs, success/failure notification, and explicit retention policy. Test missed-run recovery and disk-pressure behavior. Do not use an unobserved cron one-liner.

## Phase 4 — versioning, object lock, encryption, and restore drills

Evaluate destination versioning and object lock before selecting retention/legal-hold settings. Add encryption in transit and at rest with documented key ownership/recovery. Run scheduled restore drills for custom and cluster formats, record recovery time/objective evidence, and test compromised/deleted-source scenarios.

## Phase 5 — second-site replication and alerting

Replicate to a separately administered region/provider or physical site. Alert on freshness, checksum mismatch, replication lag, capacity, lock failures, and restore-drill regressions. Test loss of the entire primary VM and MinIO host path.

Automatic scheduling, retention, encryption, and replication are deliberately **not implemented** in this repository today.
