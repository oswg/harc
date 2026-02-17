#!/bin/bash
# Full resync: delete all MP3s from S3, then re-upload from local assets/audio.
# Use when S3 files are corrupted or need a fresh copy.
#
# Requires: aws CLI, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
# Usage: ./scripts/resync_audio_to_s3.sh

set -e
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

S3_BUCKET="${HARC_S3_BUCKET:-harc-assets}"
S3_PREFIX="${HARC_S3_PREFIX:-audio}"
AUDIO_DIR="assets/audio"

if [[ ! -d "$AUDIO_DIR" ]]; then
  echo "No $AUDIO_DIR directory."
  exit 1
fi

echo "Deleting existing MP3s from s3://${S3_BUCKET}/${S3_PREFIX}/..."
aws s3 rm "s3://${S3_BUCKET}/${S3_PREFIX}/" --recursive --exclude "*" --include "*.mp3"

echo "Syncing local $AUDIO_DIR to s3://${S3_BUCKET}/${S3_PREFIX}/..."
aws s3 sync "$AUDIO_DIR/" "s3://${S3_BUCKET}/${S3_PREFIX}/" \
  --exclude "*" --include "*.mp3" \
  --cache-control "max-age=31536000" \
  --content-type "audio/mpeg"

echo "Done."
