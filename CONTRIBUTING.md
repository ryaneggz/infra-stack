# Contributing

1. Open an issue describing the operational or security impact.
2. Branch from `main` as `feat/<issue>-<slug>` or `fix/<issue>-<slug>`.
3. Never commit `.env`, credentials, data, dumps, checksums, or runtime state.
4. Keep every published port loopback-bound by default and retain amd64/arm64 image support.
5. Run `make init`, `make config`, and `make smoke`. Shell scripts must use strict mode and pass ShellCheck.
6. Update the exact fixed tag in Compose and `.example.env`, image rationale, docs, and `CHANGELOG.md` together; run `python3 scripts/validate-image-tags.py`.
7. Use commits such as `feat: add ...` or `fix: prevent ...`; open a draft PR until CI is green.

Destructive tests must use disposable targets. Never point restore or reset commands at data you need.
