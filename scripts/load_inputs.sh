#!/usr/bin/env bash
# Put the current strike CSVs into data/ before the notebook runs.
# Order: S3 (if configured) -> gzipped seed in the repo -> nothing (the
# notebook then rebuilds the file from START_DATE).
# Any S3 error other than "not found" stops the run, so a permissions
# problem can never cause S3 to be overwritten from a stale seed.
set -euo pipefail

mkdir -p data
prefix="${S3_PREFIX:-}"
prefix="${prefix#/}"
prefix="${prefix%/}"

for f in $FILES; do
  if [ "${USE_S3:-false}" = "true" ]; then
    key="${prefix:+$prefix/}$f"
    # A prefixed list works with the role's prefix-scoped ListBucket grant.
    if ! keys=$(aws s3api list-objects-v2 --bucket "$S3_BUCKET" --prefix "$key" \
                  --query "Contents[].Key" --output text 2>&1); then
      echo "::error::Cannot list s3://$S3_BUCKET/$key -> $keys"
      exit 1
    fi
    if tr '\t' '\n' <<<"$keys" | grep -Fxq "$key"; then
      aws s3 cp "s3://$S3_BUCKET/$key" "data/$f" --only-show-errors
      echo "$f: loaded from s3://$S3_BUCKET/$key"
      continue
    fi
    echo "$f: not in S3 yet"
  fi

  if [ -f "seed/$f.gz" ]; then
    gunzip -c "seed/$f.gz" > "data/$f"
    echo "$f: seeded from repo (seed/$f.gz)"
  else
    echo "$f: no existing file, notebook will rebuild it from START_DATE"
  fi
done
