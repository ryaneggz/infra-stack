#!/bin/sh
set -eu
umask 077

# shellcheck source=scripts/s3cli/common.sh
. /scripts/s3cli/common.sh

name=${1:-}
bucket=${2:-}
token=${3:-}
case "$name" in *[!A-Za-z0-9_.-]*|'') echo "Unsafe test object name" >&2; exit 2 ;; esac
case "$bucket" in *[!a-z0-9.-]*|[-.]*|*[-.]|*..*) echo "Invalid S3 bucket name" >&2; exit 2 ;; esac
case "$token" in *[!a-f0-9]*|'') echo "Invalid test owner token" >&2; exit 2 ;; esac
[ "${#token}" -eq 32 ] || { echo "Test owner token must be 32 hex characters" >&2; exit 2; }

stage=$(mktemp -d /tmp/s3cli-conflict.XXXXXX)
trap 'rm -rf "$stage"' HUP INT TERM EXIT
get_object "$bucket" "$name" "$stage/$name" >/dev/null
expected="external-conflict-$token"
actual=$(cat "$stage/$name")
[ "$actual" = "$expected" ] || { echo "External artifact was overwritten" >&2; exit 1; }
owner=$(head_object "$bucket" "$name" --query 'Metadata."test-owner"' --output text)
[ "$owner" = "$token" ] || { echo "External ownership metadata changed" >&2; exit 1; }
if head_object "$bucket" "$name.sha256" >/dev/null 2>&1; then
  echo "Failed upload left its checksum object behind" >&2
  exit 1
fi
# Test cleanup occurs only after proving the external writer still owns the key.
s3api delete-object --bucket "$bucket" --key "$name" >/dev/null
if head_object "$bucket" "$name" >/dev/null 2>&1; then
  echo "Could not remove verified test conflict object" >&2
  exit 1
fi
rm -rf "$stage"
trap - HUP INT TERM EXIT
echo "Artifact conflict preserved external bytes and cleaned only owned checksum"
