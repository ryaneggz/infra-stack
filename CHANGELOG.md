# Changelog

All notable changes follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Add the local-first four-database stack, optional clients, verified PostgreSQL backups/restores, SSH tunnels, focused documentation, and CI ([#1](https://github.com/ryaneggz/infra-stack/issues/1)).

### Changed

- Replace the archived MinIO client runtime with pinned official AWS CLI 2.36.20 and a neutral S3 CLI contract.
- Use concise fixed semantic/release image tags instead of user-facing digest suffixes, with explicit multi-architecture and upgrade verification.
- Disclose the archived MinIO server and add an operator-gated migration roadmap for an actively maintained S3-compatible server.

### Security

- Restore only checksum-verified S3 downloads, enforce restrictive backup modes and secure bind preflight, reject shell-source Make arguments, atomically prevent concurrent/replayed S3 publication, and bound fresh PostgreSQL target readiness before cluster restore.
