#!/usr/bin/env bash
# Copy the updated strike CSVs to S3. Turn on bucket versioning if you
# want every previous version kept automatically.
set -euo pipefail

prefix="${S3_PREFIX:-}"
prefix="${prefix#/}"
prefix="${prefix%/}"

for f in $FILES; do
  [ -f "data/$f" ] || { echo "$f: nothing to upload"; continue; }
  dest="s3://$S3_BUCKET/${prefix:+$prefix/}$f"
  aws s3 cp "data/$f" "$dest" --only-show-errors --content-type text/csv
  echo "$f -> $dest"
done
