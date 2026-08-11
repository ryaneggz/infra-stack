# Changelog

All notable changes follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Add the local-first four-database stack, optional clients, verified PostgreSQL backups/restores, SSH tunnels, documentation, and CI ([#1](https://github.com/ryaneggz/infra-stack/issues/1)).

### Security

- Restore only checksum-verified MinIO downloads, enforce restrictive backup modes and secure bind preflight, reject shell-source Make arguments, and atomically prevent concurrent/replayed S3 publication.
