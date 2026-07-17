# 6. Componentes e Dados

O "porquê" de cada peça da stack, os schemas de dados que o sistema realmente emite e
os dashboards que existem hoje.

## 6.1 Decisões técnicas e justificativas

| Decisão | Alternativas consideradas | Por quê |
|---|---|---|
| **Redpanda** (não Kafka) | Apache Kafka, NATS JetStream | Kafka API compatible sem ZooKeeper/KRaft. Single binary, footprint menor. NATS seria mais leve, mas sem Kafka API. |
| **InfluxDB 3 Core** (não 2.x) | InfluxDB 2.x, TimescaleDB | Motor moderno (Arrow/DataFusion/Parquet), SQL nativo, afinidade com object storage. Sem legado Flux. |
| **Redpanda Connect unificado** | Telegraf + Connect separados, Python custom, Kafka Connect | Já está na stack para os pipelines Kafka→InfluxDB. Absorver o bridge MQTT→Kafka elimina um serviço (Telegraf) e reduz complexidade. |
| **MinIO** (não S3/cloud) | AWS S3, Backblaze B2 | Self-hosted, custo zero (exceto disco), S3-compatible, site replication e bucket notifications nativas. |
| **Frigate** (não scripts ffmpeg) | ffmpeg custom, ZoneMinder, Shinobi | Detecção de objetos built-in, integração MQTT nativa, comunidade ativa. Salva direto no MinIO. |
| **LoRa simples** (não LoRaWAN) | ChirpStack/LoRaWAN, ESP-NOW, Meshtastic | Para 5–20 sensores, star topology é mais simples e barata. Migração futura para LoRaWAN não afeta a stack do servidor. |
| **Grafana Alerting** (não AlertManager) | Prometheus AlertManager | Unifica alertas de múltiplos datasources (InfluxDB + Prometheus) num só lugar. |

## 6.2 Topics do Redpanda

| Topic | Produtor | Consumidor | Conteúdo |
|---|---|---|---|
| `sensors.telemetry` | `mqtt-to-redpanda` (via MQTT) | `sensors-to-influx` | Leituras de sensores (temp, umidade, pH, lux, etc.) |
| `frigate.events` | `mqtt-to-redpanda` (via MQTT) | `frigate-to-influx` | Eventos de detecção do Frigate |
| `minio.events` | MinIO (bucket notification) | `minio-to-influx` | Notificações de criação/deleção de objetos no MinIO |

## 6.3 Buckets do MinIO

| Bucket / prefixo | Conteúdo |
|---|---|
| `media/clips/` | Clips de vídeo gerados pelo Frigate |
| `media/snapshots/` | Snapshots de detecção do Frigate |
| `media/uploads/` | Fotos/vídeos enviados manualmente ou por scripts |
| `exports/` | Exports do InfluxDB (Parquet, CSV) |
| `backups/` | Backups de configuração, dumps, etc. |

## 6.4 Measurements do InfluxDB

Estes são os schemas **realmente emitidos** pelos pipelines em
`config/redpanda-connect/`.

### `sensor_readings` (de `sensors-to-influx`)
| Campo | Tipo | Descrição |
|---|---|---|
| `node_id` | tag | Identificador do nó sensor |
| `sensor_type` | tag | Tipo (`temp`, `humidity`, `soil_moisture`, `ph`, `lux`, …) |
| `location` | tag | Localização (padrão: `default`) |
| `value` | field (float) | Valor lido |

### `frigate_events` (de `frigate-to-influx`)
| Campo | Tipo | Descrição |
|---|---|---|
| `camera` | tag | Câmera de origem |
| `label` | tag | Objeto detectado (`person`, `car`, …) |
| `type` | tag | Tipo do evento (`new`, `end` — eventos `update` são descartados) |
| `zone` | tag | Zona (`none` se vazio) |
| `score` | field (float) | Confiança da detecção |
| `event_id` | field (string) | ID do evento no Frigate |
| `has_clip` | field (string) | `"true"`/`"false"` |
| `has_snapshot` | field (string) | `"true"`/`"false"` |

### `media_objects` (de `minio-to-influx`)
| Campo | Tipo | Descrição |
|---|---|---|
| `bucket` | tag | Bucket de origem |
| `content_type` | tag | Content-type do objeto |
| `source` | tag | Primeiro segmento do path (`clips`, `snapshots`, `uploads`, …) |
| `event` | tag | Nome do evento S3 (ex.: `s3:ObjectCreated:Put`) |
| `object_key` | field (string) | Caminho do objeto (sem o prefixo do bucket) |
| `size_bytes` | field (int) | Tamanho em bytes |
| `etag` | field (string) | ETag do objeto |

## 6.5 Política de retenção

| Camada | Dado | Retenção | Onde |
|---|---|---|---|
| **Hot** | Sensores (bruto, alta resolução) | 30 dias | InfluxDB 3 Core |
| **Warm** | Sensores downsampled (médias horárias/diárias) | 1 ano | InfluxDB 3 Core |
| **Cold** | Mídia (fotos, vídeos, clips) | Indefinido | MinIO (principal + réplica) |
| **Cold** | Exports do InfluxDB | Indefinido | MinIO (`exports/`) |
| **Archive** | Tudo sincronizado | Indefinido | MinIO remoto (resiliência geográfica) |

> O *downsample* (agregar dados >30 dias em médias horárias/diárias) e a réplica
> geográfica são parte do design de retenção; a automação correspondente e o servidor
> remoto ainda não estão presentes no repositório.

## 6.6 Dashboards do Grafana

Datasources provisionados automaticamente:

| Datasource | Tipo | URL | Uso |
|---|---|---|---|
| InfluxDB 3 | InfluxDB (SQL/Flight) | `http://influxdb:8181` | Sensores, eventos, metadados de mídia |
| Prometheus | Prometheus | `http://prometheus:9090` | Métricas de infraestrutura |

Dashboards existentes (`config/grafana/dashboards/`):

| Dashboard | Painéis |
|---|---|
| **Sensors — Overview** (`sensors.json`) | Temperature, Humidity, Soil Moisture, Light (Lux), pH, Latest Readings |
| **Infrastructure — Overview** (`infrastructure.json`) | Scrape Targets Up, Host CPU/Memory/Disk/Network, Container CPU/Memory/Restarts, Redpanda Consumer Lag e Topic Throughput |

Como usar esses dashboards no dia a dia está em [Como Usar](03-usage.md#31-ler-os-dashboards-no-grafana).
