#!/usr/bin/env bash
# =============================================================================
# Farm Monitoring — Initial Setup
# Creates Redpanda topics and InfluxDB database.
# Runs as a one-shot container via docker compose.
# =============================================================================
set -euo pipefail

REDPANDA_BROKER="redpanda:9092"
INFLUXDB_URL="http://influxdb:8181"
DB_NAME="${INFLUXDB_DATABASE:-farm}"

echo "=== Farm Monitoring Setup ==="

# -- Create Redpanda topics ---------------------------------------------------
echo ""
echo "--- Creating Redpanda topics ---"

for topic in sensors.telemetry frigate.events minio.events; do
  echo "Creating topic: $topic"
  rpk topic create "$topic" \
    --brokers "$REDPANDA_BROKER" \
    --partitions 1 \
    --replicas 1 \
    2>/dev/null || echo "  Topic $topic already exists (ok)"
done

echo ""
echo "--- Topics created ---"
rpk topic list --brokers "$REDPANDA_BROKER"

# -- Create InfluxDB database -------------------------------------------------
echo ""
echo "--- Creating InfluxDB database: $DB_NAME ---"

# Wait for InfluxDB to be ready
for i in $(seq 1 30); do
  if curl -sf "$INFLUXDB_URL/health" > /dev/null 2>&1; then
    echo "InfluxDB is ready"
    break
  fi
  echo "Waiting for InfluxDB... ($i/30)"
  sleep 2
done

# Create database using the v3 API (POST /api/v3/configure/database)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "$INFLUXDB_URL/api/v3/configure/database" \
  -H "Content-Type: application/json" \
  -d "{\"db\": \"$DB_NAME\"}")

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
  echo "Database '$DB_NAME' created successfully"
elif [ "$HTTP_CODE" = "409" ]; then
  echo "Database '$DB_NAME' already exists (ok)"
else
  echo "Warning: unexpected response code $HTTP_CODE when creating database"
  echo "Trying v1 compatible endpoint..."
  curl -s -X POST "$INFLUXDB_URL/query" \
    --data-urlencode "q=CREATE DATABASE $DB_NAME" || true
fi

echo ""
echo "=== Setup complete ==="
