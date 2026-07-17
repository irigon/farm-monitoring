#!/bin/sh
# =============================================================================
# Frigate → MinIO — Continuous media sync sidecar
# =============================================================================
# Frigate writes clips, recordings and exports to its local volume
# (/media/frigate). Frigate has no native S3 backend, so this sidecar mirrors
# that volume into the MinIO "media" bucket using `mc mirror --watch`.
#
# Once objects land in MinIO, bucket notifications fire the `minio.events`
# topic → redpanda-connect (minio-to-influx) → InfluxDB `media_objects`.
# This closes data flows 2 and 3 end-to-end.
#
# Runs as a long-running container (daemon), not a one-shot.
# =============================================================================
set -eu

MINIO_HOST="http://minio:9000"
MINIO_ALIAS="farm"
BUCKET="media"
FRIGATE_DIR="/media/frigate"

echo "=== Frigate → MinIO sync ==="

# -- Wait for MinIO to be ready & configure alias -----------------------------
echo "--- Waiting for MinIO ---"
ready=false
for i in $(seq 1 60); do
  if mc alias set "$MINIO_ALIAS" "$MINIO_HOST" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" > /dev/null 2>&1; then
    echo "MinIO is ready"
    ready=true
    break
  fi
  echo "Waiting for MinIO... ($i/60)"
  sleep 2
done

if [ "$ready" != "true" ]; then
  echo "ERROR: MinIO not ready at $MINIO_HOST after ~120s (60 attempts). Aborting."
  exit 1
fi

mc admin info "$MINIO_ALIAS" > /dev/null 2>&1 || {
  echo "ERROR: Cannot connect to MinIO at $MINIO_HOST"
  exit 1
}

# The "media" bucket is created by minio-setup; verify it exists.
mc ls "$MINIO_ALIAS/$BUCKET" > /dev/null 2>&1 || {
  echo "ERROR: bucket '$BUCKET' does not exist (run minio-setup first)"
  exit 1
}

# -- Mirror each Frigate subdirectory into the media bucket -------------------
# Keep Frigate's directory names as object-key prefixes so that
# minio-to-influx derives source = clips / recordings / exports-frigate.
#
# NOTE: no --remove flag. Frigate applies its own local retention; MinIO (and
# its geo-replica) is the long-term cold storage, so we do NOT delete objects
# from MinIO when Frigate prunes them locally. To make MinIO a strict mirror
# (delete-on-prune), add --remove to the mc mirror commands below.
mirror_dir() {
  src="$1"
  dst_prefix="$2"
  mkdir -p "$src" 2>/dev/null || true
  echo "Mirroring $src → $MINIO_ALIAS/$BUCKET/$dst_prefix"
  mc mirror --watch --overwrite --quiet \
    "$src" "$MINIO_ALIAS/$BUCKET/$dst_prefix" &
}

echo ""
echo "--- Starting continuous mirror (watch mode) ---"
mirror_dir "$FRIGATE_DIR/clips"      "clips"
mirror_dir "$FRIGATE_DIR/recordings" "recordings"
mirror_dir "$FRIGATE_DIR/exports"    "exports-frigate"

echo ""
echo "=== Frigate → MinIO sync running ==="

# Wait on all background mirror jobs; if any exits, the container exits and
# Docker's restart policy brings it back.
wait
