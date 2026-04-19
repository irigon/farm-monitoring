# 11. Troubleshooting (continuação)

## 11.6 Redpanda — Topics e Mensagens via CLI

```bash
# Listar topics
docker exec redpanda rpk topic list --brokers localhost:9092

# Consumir mensagens em tempo real (Ctrl+C para sair)
docker exec redpanda rpk topic consume sensors.telemetry --brokers localhost:9092

# Consumir apenas N mensagens
docker exec redpanda rpk topic consume sensors.telemetry --brokers localhost:9092 --num 3

# Detalhes de um topic (partições, offsets, replicas)
docker exec redpanda rpk topic describe sensors.telemetry --brokers localhost:9092

# Consumer groups — verificar lag
docker exec redpanda rpk group describe influx-sensor-writer --brokers localhost:9092
```

## 11.7 Mosquitto — Testar MQTT

```bash
# Publicar mensagem de teste
docker run --rm --network farm-monitoring_monitoring eclipse-mosquitto:2 \
  mosquitto_pub -h mosquitto -p 1883 \
  -u mqtt_user -P '<MQTT_PASSWORD>' \
  -t 'sensors/n01/temp' \
  -m '{"node_id":"n01","type":"temp","value":25.3,"ts":'$(date +%s)'}'

# Subscrever a um topic (tempo real, Ctrl+C para sair)
docker run --rm --network farm-monitoring_monitoring eclipse-mosquitto:2 \
  mosquitto_sub -h mosquitto -p 1883 \
  -u mqtt_user -P '<MQTT_PASSWORD>' \
  -t 'sensors/#'
```

## 11.8 Teste End-to-End (Checklist)

Validação completa do pipeline `MQTT → Redpanda → InfluxDB`:

```bash
# 1. Publicar mensagem MQTT
docker run --rm --network farm-monitoring_monitoring eclipse-mosquitto:2 \
  mosquitto_pub -h mosquitto -p 1883 \
  -u mqtt_user -P '<MQTT_PASSWORD>' \
  -t 'sensors/test/humidity' \
  -m '{"node_id":"test","type":"humidity","value":65.2,"ts":'$(date +%s)'}'

# 2. Verificar no Redpanda Console (http://localhost:8080)
#    → Topic sensors.telemetry deve mostrar a mensagem

# 3. Ou verificar via CLI
docker exec redpanda rpk topic consume sensors.telemetry \
  --brokers localhost:9092 --num 1

# 4. Aguardar batching (até 1s) e consultar InfluxDB
sleep 2
curl -s 'http://localhost:8181/api/v3/query_sql' \
  -G \
  --data-urlencode 'db=farm' \
  --data-urlencode 'q=SELECT * FROM sensor_readings ORDER BY time DESC LIMIT 3' \
  --data-urlencode 'format=json' \
  | python3 -m json.tool
```

Se os 3 passos retornam dados, o pipeline está saudável.

## 11.9 Problemas Comuns

| Sintoma | Causa Provável | Solução |
|---------|---------------|---------|
| InfluxDB healthcheck falha | Auth habilitado sem token | Adicionar `--without-auth` (dev) ou configurar token |
| Redpanda Connect crash loop | Lint error no YAML dos pipelines | Verificar logs; `--chilled` previne crash mas stream não inicia |
| MQTT "not Authorized" | Senha no `.env` diferente do `password_file` | Regenerar: `docker run --rm -v ./config/mosquitto:/mosquitto/config eclipse-mosquitto:2 mosquitto_passwd -b -c /mosquitto/config/password_file <user> <password>` |
| Mensagens não chegam ao InfluxDB | Redpanda Connect não conectou ao MQTT ou Redpanda | Verificar `curl localhost:4195/streams` — stream deve estar `active: true` |
| `serde error: missing field 'format'` no curl | Falta `format=json` na query InfluxDB v3 | Adicionar `--data-urlencode 'format=json'` |
| "Issues deserializing value" no Console | Console tentando Protobuf/MsgPack em payloads JSON | Usar dropdown "JSON" ou verificar env vars no docker-compose |
| Database não encontrada no InfluxDB | Setup script não criou o database | `curl -X POST http://localhost:8181/api/v3/configure/database -H 'Content-Type: application/json' -d '{"db":"farm"}'` |
| Porta não acessível (Connection refused) | Porta não mapeada no docker-compose | Verificar seção `ports:` do serviço no docker-compose.yml |
