#!/usr/bin/env bash
# =============================================================================
# MinIO Setup — Create buckets and configure bucket notifications
# Runs as a one-shot container using minio/mc image.
# =============================================================================
set -euo pipefail

MINIO_HOST="http://minio:9000"
MINIO_ALIAS="farm"

echo "=== MinIO Setup ==="

# -- Wait for MinIO to be ready -----------------------------------------------
echo ""
echo "--- Waiting for MinIO ---"
ready=false
for i in $(seq 1 30); do
  if mc alias set "$MINIO_ALIAS" "$MINIO_HOST" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" > /dev/null 2>&1; then
    echo "MinIO is ready"
    ready=true
    break
  fi
  echo "Waiting for MinIO... ($i/30)"
  sleep 2
done

if [ "$ready" != "true" ]; then
  echo "ERROR: MinIO not ready at $MINIO_HOST after ~60s (30 attempts). Aborting."
  exit 1
fi

# Verify connection
mc admin info "$MINIO_ALIAS" > /dev/null 2>&1 || {
  echo "ERROR: Cannot connect to MinIO at $MINIO_HOST"
  exit 1
}

# -- Create buckets ------------------------------------------------------------
#
# Path convention inside the "media" bucket. The events-to-influx pipeline derives
# the canonical "source" tag (kind=object) from the FIRST path segment, so keep prefixes
# consistent:
#   clips/      → Frigate video clips
#   snapshots/  → Frigate detection snapshots
#   uploads/    → manual/script uploads
#   audio/      → annotation audio recordings (content lives here; pointer in InfluxDB)
#   photos/     → annotation photos
#   notes/      → annotation text (.txt/.md; content lives here, not in InfluxDB)
# The lightweight annotation event (location/kind/summary/lat/lon/object_key) is
# published separately to MQTT topic annotations/{location} → measurement "annotations".
echo ""
echo "--- Creating buckets ---"

for bucket in media exports backups; do
  if mc ls "$MINIO_ALIAS/$bucket" > /dev/null 2>&1; then
    echo "Bucket '$bucket' already exists (ok)"
  else
    echo "Creating bucket: $bucket"
    mc mb "$MINIO_ALIAS/$bucket"
  fi
done

echo ""
mc ls "$MINIO_ALIAS"

# -- Configure bucket notifications → Redpanda --------------------------------
# MinIO sends S3 events to the Kafka (Redpanda) target configured via
# MINIO_NOTIFY_KAFKA_* environment variables on the MinIO server.
# The ARN is uppercase: arn:minio:sqs::PRIMARY:kafka
# (matching MINIO_NOTIFY_KAFKA_*_PRIMARY env vars on the MinIO server).
# mc event --event flag uses simple names: put, delete, get (not S3-style).
echo ""
echo "--- Configuring bucket notifications ---"

KAFKA_ARN="arn:minio:sqs::PRIMARY:kafka"

for bucket in media exports backups; do
  echo "Setting notifications for bucket: $bucket"

  # put = s3:ObjectCreated:*, delete = s3:ObjectRemoved:*
  mc event add "$MINIO_ALIAS/$bucket" "$KAFKA_ARN" \
    --event "put,delete" \
    --ignore-existing \
    2>&1 || echo "  Warning: failed to add notification for $bucket"
done

echo ""
echo "--- Notification configuration ---"
for bucket in media exports backups; do
  echo "Bucket: $bucket"
  mc event list "$MINIO_ALIAS/$bucket" 2>/dev/null || echo "  (no events)"
done

echo ""
echo "=== MinIO Setup complete ==="
