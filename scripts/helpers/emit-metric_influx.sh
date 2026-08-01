#!/usr/bin/env bash
# emit-metric.sh — envia métricas (float) para o InfluxDB 3 Core via line protocol.
#
# Uso:
#   Métrica única:
#     ./emit-metric.sh <nome_da_metrica> <valor_float>
#     ./emit-metric.sh temperature 23.5
#
#   Lista de valores, uma métrica a cada N segundos:
#     ./emit-metric.sh --interval <segundos> <nome_da_metrica> <v1> <v2> ...
#     ./emit-metric.sh --interval 5 temperature 20 21 22.5 23
#
# Config via env vars (com defaults do stack):
#   INFLUXDB_URL       (default: http://localhost:8181)
#   INFLUXDB_DATABASE  (default: farm)
#   INFLUXDB_TOKEN     (default: vazio — dev mode --without-auth)

set -euo pipefail

# --- config ---
INFLUXDB_URL="${INFLUXDB_URL:-http://localhost:8181}"
INFLUXDB_DATABASE="${INFLUXDB_DATABASE:-farm}"
INFLUXDB_TOKEN="${INFLUXDB_TOKEN:-}"

usage() {
  cat >&2 <<EOF
uso:
  $0 <nome_da_metrica> <valor_float>
  $0 --interval <segundos> <nome_da_metrica> <v1> <v2> ...

exemplos:
  $0 temperature 23.5
  $0 --interval 5 temperature 20 21 22.5 23
EOF
  exit 1
}

is_number() {
  [[ "$1" =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

emit() {
  local metric="$1" value="$2"
  local ts_ns line
  ts_ns="$(date +%s)000000000"
  line="${metric} value=${value} ${ts_ns}"

  local auth_args=()
  if [[ -n "$INFLUXDB_TOKEN" ]]; then
    auth_args=(-H "Authorization: Bearer ${INFLUXDB_TOKEN}")
  fi

  curl -sS -f -X POST \
    "${INFLUXDB_URL}/api/v3/write_lp?db=${INFLUXDB_DATABASE}&precision=nanosecond" \
    "${auth_args[@]}" \
    --data-binary "${line}"

  echo "ok: enviado -> ${line}"
}

# --- parse de argumentos ---
if [[ $# -eq 0 ]]; then
  usage
fi

if [[ "$1" == "--interval" ]]; then
  # modo lista: --interval N metric v1 v2 ...
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
  # modo único: metric value
  [[ $# -eq 2 ]] || usage
  metric="$1"
  value="$2"
  is_number "$value" || { echo "erro: valor '$value' não é um número válido" >&2; exit 1; }
  emit "$metric" "$value"
fi
