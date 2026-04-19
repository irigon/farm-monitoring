# 11. Troubleshooting e Verificação do Sistema

## 11.1 Interfaces Disponíveis

| Interface | URL | Descrição |
|-----------|-----|-----------|
| **Redpanda Console** | http://localhost:8080 | UI web: topics, mensagens, consumer groups, cluster health |
| **Redpanda Connect API** | http://localhost:4195 | API HTTP: streams ativos, métricas, health |
| **InfluxDB API** | http://localhost:8181 | API HTTP apenas (sem UI web). Queries via curl |
| **Redpanda Admin API** | http://localhost:9644 | Métricas Prometheus, cluster status |
| **Mosquitto** | localhost:1883 | Broker MQTT (pub/sub via CLI) |
| **Redpanda Kafka API** | localhost:19092 | Acesso externo à Kafka API (ferramentas, debug) |

## 11.2 Verificar Status dos Serviços

```bash
# Status geral de todos os containers
docker-compose ps

# Logs de um serviço específico (últimas 30 linhas)
docker-compose logs --tail 30 <serviço>

# Logs em tempo real (follow)
docker-compose logs -f <serviço>

# Logs de todos os serviços
docker-compose logs --tail 50

# Healthcheck individual
docker inspect --format='{{.State.Health.Status}}' redpanda
docker inspect --format='{{.State.Health.Status}}' influxdb
```

## 11.3 Redpanda Console (http://localhost:8080)

A interface principal para debug de mensagens e topics.

- **Topics**: lista todos os topics (`sensors.telemetry`, `frigate.events`, `minio.events`)
- Clique em um topic → visualize mensagens com payload JSON, headers, offset e timestamp
- **Consumer Groups**: verifique o grupo `influx-sensor-writer` e se há lag (mensagens não consumidas)

> **Nota:** Se aparecer "issues deserializing the value", mude o dropdown
> **Value Deserializer** de "Auto" para "JSON" no topo da visualização de mensagens.
> As variáveis `KAFKA_PROTOBUF_ENABLED=false` e `KAFKA_MSGPACK_ENABLED=false` no
> docker-compose já minimizam esse problema.

> **Nota sobre Enterprise Trial:** O Redpanda exibe "Enterprise Trial" na interface.
> Isso é normal — o Redpanda Community Edition é gratuito e open source. Quando o trial
> expirar, apenas features enterprise (Shadow Indexing, Cluster Links) são desabilitadas.
> Tudo que usamos (Kafka API, topics, consumers, Schema Registry) continua funcionando.

## 11.4 Redpanda Connect API (http://localhost:4195)

```bash
# Verificar se o serviço está pronto
curl -s http://localhost:4195/ready
# Esperado: OK

# Listar streams ativos e uptime
curl -s http://localhost:4195/streams | python3 -m json.tool
# Esperado:
# {
#   "mqtt-to-redpanda": { "active": true, "uptime": ... },
#   "sensors-to-influx": { "active": true, "uptime": ... }
# }

# Métricas no formato Prometheus (mensagens processadas, erros, latência)
curl -s http://localhost:4195/metrics | grep -E 'input_received|output_sent|processor_error'
```

**Se um stream não aparece ou está `active: false`:**
1. Verifique os logs: `docker-compose logs --tail 30 redpanda-connect`
2. Erros de lint no YAML aparecem como warnings (graças ao `--chilled`), mas o stream não inicia
3. Erros de conexão (MQTT auth, Redpanda unreachable) geram retries com backoff

## 11.5 InfluxDB API (http://localhost:8181)

O InfluxDB 3 Core **não tem interface web**. Toda interação é via API HTTP.

```bash
# Health check
curl -s http://localhost:8181/health
# Esperado: OK

# Listar databases
curl -s 'http://localhost:8181/api/v3/configure/database' \
  -G --data-urlencode 'format=json'

# Consultar dados (SQL) — IMPORTANTE: sempre incluir format=json
curl -s 'http://localhost:8181/api/v3/query_sql' \
  -G \
  --data-urlencode 'db=farm' \
  --data-urlencode 'q=SELECT * FROM sensor_readings ORDER BY time DESC LIMIT 10' \
  --data-urlencode 'format=json' \
  | python3 -m json.tool

# Contar registros
curl -s 'http://localhost:8181/api/v3/query_sql' \
  -G \
  --data-urlencode 'db=farm' \
  --data-urlencode 'q=SELECT COUNT(*) FROM sensor_readings' \
  --data-urlencode 'format=json'

# Listar measurements (tabelas)
curl -s 'http://localhost:8181/api/v3/query_sql' \
  -G \
  --data-urlencode 'db=farm' \
  --data-urlencode "q=SHOW TABLES" \
  --data-urlencode 'format=json'
```

> **Erro comum:** `serde error: missing field 'format'` — adicione `format=json` em
> todas as chamadas à API v3.

> **Nota:** Em modo dev (--without-auth), nenhum token é necessário. Em produção,
> adicione o header: `Authorization: Bearer <token>`
