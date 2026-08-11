#!/bin/sh

: "${S3_ENDPOINT:=http://minio:9000}"
: "${AWS_DEFAULT_REGION:=us-east-1}"
export AWS_DEFAULT_REGION AWS_EC2_METADATA_DISABLED=true AWS_PAGER=""

s3api() {
  aws --endpoint-url "$S3_ENDPOINT" --no-cli-pager s3api "$@"
}

head_object() {
  _head_bucket=$1
  _head_key=$2
  shift 2
  s3api head-object --bucket "$_head_bucket" --key "$_head_key" "$@"
}

get_object() {
  _get_bucket=$1
  _get_key=$2
  _get_destination=$3
  shift 3
  s3api get-object --bucket "$_get_bucket" --key "$_get_key" "$@" "$_get_destination"
}

create_bucket_if_missing() {
  _create_bucket=$1
  if ! s3api head-bucket --bucket "$_create_bucket" >/dev/null 2>&1; then
    s3api create-bucket --bucket "$_create_bucket" >/dev/null 2>&1 ||
      s3api head-bucket --bucket "$_create_bucket" >/dev/null
  fi
}
