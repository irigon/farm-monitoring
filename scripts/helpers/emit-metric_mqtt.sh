#!/usr/bin/env bash
# emit-metric_mqtt.sh — publica métricas via MQTT, imitando um sensor ESP32.
#
# Publica no Mosquitto (localhost:1883) no formato aceito pelo bridge
# redpanda-connect (sensors/#), que então flui: Mosquitto → Redpanda → InfluxDB 3.
#
# Contrato (docs/03-usage.md):
#   tópico:  sensors/{node_id}/{tipo}
#   payload: {"node_id":"...","type":"...","value":<número>,"ts":<epoch_s>}
#
# Uso:
#   Métrica única:
#     ./emit-metric_mqtt.sh <tipo> <valor_float>
#     ./emit-metric_mqtt.sh temperature 23.5
#
#   Lista de valores, uma métrica a cada N segundos:
#     ./emit-metric_mqtt.sh --interval <segundos> <tipo> <v1> <v2> ...
#     ./emit-metric_mqtt.sh --interval 5 temperature 20 21 22.5 23
#
# Config via env vars:
#   MQTT_HOST      (default: localhost)
#   MQTT_PORT      (default: 1883)
#   MQTT_USER      (default: lido do .env, se existir)
#   MQTT_PASSWORD  (default: lido do .env, se existir)
#   NODE_ID        (default: esp32-01)      — identifica o "sensor"
#   LOCATION       (default: default)       — vira context.location

set -euo pipefail

# --- carrega .env (para MQTT_USER/MQTT_PASSWORD) se existir e não vier do ambiente ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
if [[ -f "$ENV_FILE" ]]; then
  # exporta apenas as chaves MQTT_ do .env, sem sobrescrever o que já veio do ambiente
  while IFS='=' read -r key val; do
    [[ "$key" =~ ^MQTT_(USER|PASSWORD)$ ]] || continue
    [[ -n "${!key:-}" ]] && continue
    val="${val%\"}"; val="${val#\"}"
    export "$key=$val"
  done < <(grep -E '^MQTT_(USER|PASSWORD)=' "$ENV_FILE" || true)
fi

# --- config ---
MQTT_HOST="${MQTT_HOST:-localhost}"
MQTT_PORT="${MQTT_PORT:-1883}"
MQTT_USER="${MQTT_USER:-}"
MQTT_PASSWORD="${MQTT_PASSWORD:-}"
NODE_ID="${NODE_ID:-esp32-01}"
LOCATION="${LOCATION:-default}"

usage() {
  cat >&2 <<EOF
uso:
  $0 <tipo> <valor_float>
  $0 --interval <segundos> <tipo> <v1> <v2> ...

exemplos:
  $0 temperature 23.5
  $0 --interval 5 temperature 20 21 22.5 23
  NODE_ID=esp32-cage3 LOCATION=galpao-2 $0 humidity 61
EOF
  exit 1
}

command -v mosquitto_pub >/dev/null 2>&1 || {
  echo "erro: 'mosquitto_pub' não encontrado (instale mosquitto-clients)" >&2
  exit 1
}

is_number() {
  [[ "$1" =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

emit() {
  local metric="$1" value="$2"
  local ts_s topic payload
  ts_s="$(date +%s)"
  topic="sensors/${NODE_ID}/${metric}"
  payload="{\"node_id\":\"${NODE_ID}\",\"type\":\"${metric}\",\"value\":${value},\"location\":\"${LOCATION}\",\"ts\":${ts_s}}"

  local auth_args=()
  if [[ -n "$MQTT_USER" ]]; then
    auth_args+=(-u "$MQTT_USER")
    [[ -n "$MQTT_PASSWORD" ]] && auth_args+=(-P "$MQTT_PASSWORD")
  fi

  mosquitto_pub \
    -h "$MQTT_HOST" -p "$MQTT_PORT" \
    "${auth_args[@]}" \
    -q 1 \
    -t "$topic" \
    -m "$payload"

  echo "ok: publicado -> ${topic} ${payload}"
}

# --- parse de argumentos ---
if [[ $# -eq 0 ]]; then
  usage
fi

if [[ "$1" == "--interval" ]]; then
  # modo lista: --interval N tipo v1 v2 ...
  [[ $# -ge 4 ]] || usage
  interval="$2"
  metric="$3"
  shift 3

  is_number "$interval" || { echo "erro: intervalo '$interval' inválido" >&2; exit 1; }

  total=$#
  idx=0
  for value in "$@"; do
    idx=$((idx + 1))
    if ! is_number "$value"; then
      echo "aviso: pulando valor inválido '$value'" >&2
      continue
    fi
    emit "$metric" "$value"
    # não dorme após o último valor
    if [[ "$idx" -lt "$total" ]]; then
      sleep "$interval"
    fi
  done
else
  # modo único: tipo value
  [[ $# -eq 2 ]] || usage
  metric="$1"
  value="$2"
  is_number "$value" || { echo "erro: valor '$value' não é um número válido" >&2; exit 1; }
  emit "$metric" "$value"
fi
