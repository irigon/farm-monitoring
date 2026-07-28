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
| `events` | `mqtt-to-redpanda` (sensores, Frigate, anotações via MQTT) | `events-to-influx` | Evento Canônico já normalizado (`metric`/`detection`/`annotation`) |
| `minio.events` | MinIO (bucket notification) | `events-to-influx` | Notificações de objetos no MinIO (cru); canonizado para `kind=object` no consumer |

## 6.3 Buckets do MinIO

| Bucket / prefixo | Conteúdo |
|---|---|
| `media/clips/` | Clips de vídeo gerados pelo Frigate |
| `media/snapshots/` | Snapshots de detecção do Frigate |
| `media/uploads/` | Fotos/vídeos enviados manualmente ou por scripts |
| `media/audio/` | Áudios de anotações (conteúdo; ponteiro em `annotations`) |
| `media/photos/` | Fotos de anotações |
| `media/notes/` | Texto de anotações (`.txt`/`.md`; conteúdo fica aqui, não no InfluxDB) |
| `exports/` | Exports do InfluxDB (Parquet, CSV) |
| `backups/` | Backups de configuração, dumps, etc. |

## 6.4 Measurement do InfluxDB — `events` (canônico)

O sistema grava **um único measurement canônico `events`**, emitido pelos pipelines em
`config/redpanda-connect/`. Ele materializa o **Evento Canônico** definido no
[Modelo Conceitual §0.3](00-conceptual-model.md#03-o-evento-canônico) e
[§0.6](00-conceptual-model.md#06-source-e-measure-os-eixos-abertos), e segue o
[ADR-11](decisions.md) para eventos de mídia.

### Schema de `events`
| Campo | Tipo InfluxDB | Origem canônica | Descrição |
|---|---|---|---|
| `kind` | tag | `kind` | Discriminador fixo: `metric`, `detection`, `annotation`, `object` (`state` deferido) |
| `source` | tag | `source` | Quem produziu (nó sensor, câmera, device de anotação, `source` do path no MinIO) |
| `measure` | tag | `measure` | O que foi observado (`temp`, `person`, `audio`, `content_type`, …) |
| `<context.*>` | tag (dinâmica) | `context{}` | Dimensões de agrupamento de baixa cardinalidade (`location`, `zone`, …). Novas chaves entram sem migração — o consumer itera `context{}` e emite cada uma como tag |
| `value` | field (float) | `value` | Valor numérico agregável (omitido quando `null`) |
| `blob_ref` | field (string) | `blob_ref` | URI neutra do blob no data lake (omitido quando `null`) |
| `<attrs.*>` | field (dinâmico) | `attrs{}` | Descritores de alta cardinalidade (`score`, `event_id`, `etag`, `size_bytes`, `lat`, `lon`, `summary`, …). Número → field numérico; demais → field string |
| _timestamp_ | ns | `ts` (ms) | `ts` canônico em ms, convertido para ns na escrita |

> **Identidade / idempotência (ADR-10):** um ponto no InfluxDB é identificado por
> `measurement + tag set + timestamp`, e a escrita é *upsert* (last-write-wins). Como
> `kind+source+measure+context.*` + `ts` (em ms) é único na prática (câmeras/devices têm
> `source` distinto; a colisão da tripla no mesmo ms é irreal), **replay não duplica nem
> sobrescreve** eventos legítimos. Discriminadores como `event_id`/`etag` ficam em `attrs`
> (fields) — não são promovidos a tag para não inflar a cardinalidade de séries.

### Como cada fonte mapeia para `events`
| Fonte (dialeto) | `kind` | `source` | `measure` | Observações |
|---|---|---|---|---|
| Sensores (LoRa→MQTT) | `metric` | `node_id` | `type` | `value` numérico; `context.location` |
| Frigate (MQTT) | `detection` | `camera` | `label` | `context.zone`; `attrs`: `event_id`, `score`, `has_clip`, … (eventos `update` descartados) |
| Anotações (MQTT) | `annotation` | `device_id` (fallback `annotations-app`) | `kind` do payload | `blob_ref` do `object_key`; `attrs`: `summary`, `lat`, `lon`, `gps_accuracy` |
| Objetos MinIO (bucket notification) | `object` | 1º segmento do path (`clips`, `snapshots`, …) | `content_type` | `blob_ref` = `s3://{bucket}/{key}`; `attrs`: `etag`, `size_bytes`, `event_name` |

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

> **Nota — dupla contagem por `blob_ref` (Q1):** Um mesmo fato de mídia gera **dois**
> eventos que compartilham o mesmo `blob_ref`: o de domínio (`detection`/`annotation`) e
> o `object` emitido pelo MinIO. Ao agregar volumes ou contar eventos, os pipelines e
> consultas devem filtrar `kind != object` para não contar o mesmo blob duas vezes.
> Ver [Q1 em decisions.md](decisions.md) e [ADR-11](decisions.md).

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
