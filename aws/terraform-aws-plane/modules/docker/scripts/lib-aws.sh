#!/usr/bin/env bash
# lib-aws.sh: the AWS-specific functions lib-common.sh expects (the only file that differs per cloud).
# Uses AWS_REGION, DATA_VOLUME_ID and BACKUP_BUCKET from /etc/plane/plane.conf and the instance role's credentials.

# The AWS CLI v2 snap (published by AWS; snapd ships on Canonical's AMIs).
ensure_cli() {
  command -v aws >/dev/null 2>&1 && return 0
  retry 3 10 snap install aws-cli --classic
  hash -r
  command -v aws >/dev/null 2>&1 || die "the AWS CLI didn't install"
}

# fetch_secret <secret ARN>: the secret string (a JSON object) on stdout.
fetch_secret() {
  aws --region "$AWS_REGION" secretsmanager get-secret-value --secret-id "$1" --query SecretString --output text
}

# fetch_object <s3://bucket/key> <dest>
fetch_object() {
  case $1 in
  s3://*) aws --region "$AWS_REGION" s3 cp --only-show-errors "$1" "$2" ;;
  *) die "unsupported asset URL: $1 (https:// or s3://)" ;;
  esac
}

# The data volume on Nitro instances: an NVMe device whose by-id name carries the volume ID without the dash.
data_device() {
  printf '/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_%s\n' "${DATA_VOLUME_ID//-/}"
}

# upload_backup <file|-> <key>
upload_backup() {
  aws --region "$AWS_REGION" s3 cp --only-show-errors "$1" "s3://$BACKUP_BUCKET/$2"
}

# sync_backup <dir> <prefix>: the bucket is versioned, so --delete keeps deleted objects as old versions.
sync_backup() {
  aws --region "$AWS_REGION" s3 sync --only-show-errors --delete "$1" "s3://$BACKUP_BUCKET/$2"
}
