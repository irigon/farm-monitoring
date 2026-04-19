# 4. Fluxos de Dados

## 4.1 Fluxo 1 — Sensores (dados leves, tempo real)

Dados pequenos e frequentes: temperatura, umidade, pH do solo, luminosidade, movimento.

```
ESP32 (campo)
    │
    │ LoRa (pacote ~20 bytes: node_id, timestamp, tipo, valor)
    ▼
Gateway LoRa (ponto elevado)
    │
    │ WiFi direcional → MQTT publish
    │ Topic: sensors/{node_id}/{tipo}
    │ Payload: JSON {"node_id": "n01", "type": "temp", "value": 28.5, "ts": 1709827200}
    ▼
Mosquitto (:1883)
    │
    │ Subscrito por Redpanda Connect (input: mqtt)
    ▼
Redpanda Connect (pipeline: mqtt-to-redpanda)
    │
    │ Consome MQTT, transforma e publica em Kafka topic
    │ Topic: sensors.telemetry
    ▼
Redpanda (:9092)
    │
    │ Consumido por Redpanda Connect (pipeline: sensors-to-influx)
    ▼
Redpanda Connect (pipeline: sensors-to-influx)
    │
    │ Pipeline YAML: mapping → InfluxDB line protocol
    │ POST http://influxdb:8181/api/v2/write
    ▼
InfluxDB 3 Core (:8181)
    │
    │ Measurement: sensor_readings
    │ Tags: node_id, sensor_type, location
    │ Fields: value
    │ Retenção: 30 dias bruto, 1 ano downsampled
    ▼
Grafana (:3000)
    Dashboard de sensores em tempo real
    Alertas: ex. "umidade do solo < 30% → notificar Telegram"
```

## 4.2 Fluxo 2 — Mídia (dados pesados, câmeras)

Vídeos, clips de detecção, snapshots de câmeras IP.

```
Câmera IP (RTSP stream)
    │
    │ RTSP contínuo via rede local
    ▼
Frigate (:5000)
    │
    ├──▶ Detecção de objetos (pessoas, animais, veículos)
    │    Se detectado:
    │    ├── Salva clip de vídeo → MinIO (bucket: media/clips/)
    │    ├── Salva snapshot → MinIO (bucket: media/snapshots/)
    │    └── Publica evento MQTT → Mosquitto
    │         Topic: frigate/events
    │         Payload: {"type": "person", "camera": "cam01", "score": 0.92, ...}
    │
    │    O evento MQTT segue o mesmo caminho do Fluxo 1:
    │    Mosquitto → Redpanda Connect → Redpanda → Redpanda Connect → InfluxDB
    │    (grava metadado do evento com link para o clip/snapshot no MinIO)
    │
    └──▶ Gravação contínua (opcional, consome muito disco)
         → MinIO (bucket: media/recordings/)
```

## 4.3 Fluxo 3 — Eventos MinIO (bucket notifications)

Quando qualquer objeto é adicionado ao MinIO (por Frigate, por upload manual, ou por
scripts do RPi), o MinIO notifica o Redpanda.

```
Objeto criado no MinIO (upload de foto, vídeo, export, backup)
    │
    │ Bucket Notification (configurado por bucket)
    │ Target: Redpanda topic "minio.events"
    ▼
Redpanda (:9092)
    │
    │ Topic: minio.events
    │ Payload: JSON com bucket, key, size, content-type, etag, timestamp
    ▼
Redpanda Connect
    │
    │ Pipeline YAML: extrai metadados, gera link presigned (ou path),
    │ formata como InfluxDB line protocol
    ▼
InfluxDB 3 Core
    │
    │ Measurement: media_objects
    │ Tags: bucket, content_type, source (frigate/manual/script)
    │ Fields: object_key, size_bytes, presigned_url
    │ Retenção: indefinida (metadados são leves)
    ▼
Grafana
    Timeline de mídia com links clicáveis para MinIO
    Ao clicar: abre a foto/vídeo direto do MinIO via presigned URL
```

## 4.4 Fluxo 4 — Alertas

```
Grafana Alerting
    │
    │ Avalia regras periodicamente sobre dados do InfluxDB:
    │   - Umidade do solo < limiar → alerta irrigação
    │   - Temperatura fora do range → alerta geada/calor
    │   - Detecção de pessoa em horário suspeito → alerta segurança
    │   - Sensor offline por > 30 min → alerta manutenção
    │   - Disco do servidor > 85% → alerta infraestrutura
    │
    ▼
Canais de notificação:
    - Telegram (bot)
    - Email
    - Webhook (para automações futuras)
```

## 4.5 Fluxo 5 — Replicação Geográfica do Data Lake

```
MinIO (Servidor Principal)
    │
    │ Site Replication (bidirecional, nativo do MinIO)
    │ Sincroniza: buckets, objetos, políticas, IAM
    │ Via internet/VPN entre os dois locais
    │
    ▼
MinIO (Servidor Remoto, 4-8 GB)
    │
    │ Réplica completa do data lake
    │ Funciona como backup geográfico
    │ Em caso de falha do principal, pode ser promovido
```

## 4.6 Fluxo 6 — Monitoramento da Infraestrutura

```
Prometheus (:9090)
    │
    ├── Scrape: Node Exporter (:9100) — métricas do host
    │   CPU, RAM, disco, temperatura, rede, uptime
    │
    ├── Scrape: cAdvisor (:8088) — métricas dos containers
    │   CPU, RAM, rede, I/O por container
    │
    ├── Scrape: Redpanda (:9644/metrics) — métricas do broker
    │   Topics, partições, consumer lag, throughput
    │
    ├── Scrape: MinIO (:9000/minio/v2/metrics/cluster) — métricas do storage
    │   Espaço usado, objetos, requisições, replicação
    │
    └──▶ Grafana (:3000)
         Dashboard de infraestrutura
         Alertas de saúde do sistema
```
