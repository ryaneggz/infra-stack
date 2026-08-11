#!/bin/sh
set -eu

name=${1:-}
bucket=${2:-}
token=${3:-}
case "$name" in *[!A-Za-z0-9_.-]*|'') echo "Unsafe test object name" >&2; exit 2 ;; esac
case "$bucket" in *[!a-z0-9.-]*|[-.]*|*[-.]|*..*) echo "Invalid S3 bucket name" >&2; exit 2 ;; esac
case "$token" in *[!a-f0-9]*|'') echo "Invalid test owner token" >&2; exit 2 ;; esac
[ "${#token}" -eq 32 ] || { echo "Test owner token must be 32 hex characters" >&2; exit 2; }

mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
expected="external-conflict-$token"
actual=$(mc cat "local/$bucket/$name")
[ "$actual" = "$expected" ] || { echo "External artifact was overwritten" >&2; exit 1; }
metadata=$(mc stat "local/$bucket/$name")
case "$metadata" in *X-Amz-Meta-Test-Owner*"$token"*) ;; *) echo "External ownership metadata changed" >&2; exit 1 ;; esac
if mc stat "local/$bucket/$name.sha256" >/dev/null 2>&1; then
  echo "Failed upload left its checksum object behind" >&2
  exit 1
fi
# Test cleanup occurs only after proving the external writer still owns the key.
mc rm --force "local/$bucket/$name" >/dev/null
if mc stat "local/$bucket/$name" >/dev/null 2>&1; then
  echo "Could not remove verified test conflict object" >&2
  exit 1
fi
echo "Artifact conflict preserved external bytes and cleaned only owned checksum"
