#!/bin/sh
# =============================================================================
# Mosquitto Setup — Generate password_file from .env credentials
# Runs as a one-shot container using the eclipse-mosquitto:2 image, BEFORE
# the mosquitto broker starts. Idempotent: rebuilds the file on every run.
# =============================================================================
set -exu

PASSWORD_FILE="/mosquitto/config/password_file"

echo "=== Mosquitto Setup ==="

# -- Validate required credentials --------------------------------------------
if [ -z "${MQTT_USER:-}" ] || [ -z "${MQTT_PASSWORD:-}" ]; then
  echo "ERROR: MQTT_USER and MQTT_PASSWORD must be set (check your .env)"
  exit 1
fi

# -- Create the primary MQTT user (this creates/overwrites the file) ----------
echo "Creating password_file for user: $MQTT_USER"
# -c creates the file (overwrites), -b takes the password on the command line
rm -f "$PASSWORD_FILE"          # ensure idempotency: -c refuses if file exists
mosquitto_passwd -c -b "$PASSWORD_FILE" "$MQTT_USER" "$MQTT_PASSWORD"

# -- Add the Frigate MQTT user if it differs from the primary user ------------
# Frigate publishes detection events to MQTT and needs valid credentials.
if [ -n "${FRIGATE_MQTT_USER:-}" ] && [ "${FRIGATE_MQTT_USER}" != "${MQTT_USER}" ]; then
  if [ -z "${FRIGATE_MQTT_PASSWORD:-}" ]; then
    echo "ERROR: FRIGATE_MQTT_USER set but FRIGATE_MQTT_PASSWORD is empty"
    exit 1
  fi
  echo "Adding Frigate MQTT user: $FRIGATE_MQTT_USER"
  # -b (without -c) appends to the existing file
  mosquitto_passwd -b "$PASSWORD_FILE" "$FRIGATE_MQTT_USER" "$FRIGATE_MQTT_PASSWORD"
else
  echo "Frigate uses the same MQTT user as the primary user (ok)"
fi

# -- Lock down permissions (mosquitto warns if the file is world-readable) ----
chown 1883:1883 "$PASSWORD_FILE" 2>/dev/null || true   # owned by the mosquitto user
chmod 0700 "$PASSWORD_FILE" 2>/dev/null || true

echo ""
echo "--- password_file created ---"
echo "=== Mosquitto Setup complete ==="
