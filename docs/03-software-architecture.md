# 3. Arquitetura de Software (Servidor Principal)

Todos os serviços rodam como containers Docker, orquestrados via Docker Compose.

## 3.1 Diagrama de Componentes

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    SERVIDOR PRINCIPAL — Docker Compose                       │
│                                                                             │
│  ╔═══════════════════════════ INGESTÃO ════════════════════════════════╗    │
│  ║                                                                     ║    │
│  ║  ┌──────────┐    ┌───────────────────────────┐    ┌──────────────┐ ║    │
│  ║  │Mosquitto │───▶│     Redpanda Connect      │───▶│ InfluxDB 3   │ ║    │
│  ║  │  :1883   │    │     (YAML pipelines)      │    │ Core :8181   │ ║    │
│  ║  └──────────┘    │                           │    │ (time-series)│ ║    │
│  ║       ▲          │ Pipeline 1: MQTT→Redpanda │    └──────────────┘ ║    │
│  ║       │ MQTT     │ Pipeline 2: Redpanda→Influx│          ▲         ║    │
│  ║  ESP32 gateway   │ Pipeline 3: MinIO→Influx  │          │         ║    │
│  ║  Frigate events  └──────────────┬────────────┘          │         ║    │
│  ║                                 │                        │         ║    │
│  ║                          ┌──────▼──────┐                 │         ║    │
│  ║                          │  Redpanda   │─────────────────┘         ║    │
│  ║                          │   :9092     │  (topics armazenam        ║    │
│  ║                          │   :8082     │   eventos com replay)     ║    │
│  ║                          └─────────────┘                           ║    │
│  ╚════════════════════════════════╪═══════════════════════════════════╝    │
│                                           │                                │
│  ╔═══════════════════════════ MÍDIA ══════╪════════════════════════════╗   │
│  ║                                        │                            ║   │
│  ║  ┌──────────────┐                      │                            ║   │
│  ║  │   Frigate    │   RTSP das câmeras   │                            ║   │
│  ║  │   :5000      │──────────────────┐   │                            ║   │
│  ║  │  - detecção  │                  │   │                            ║   │
│  ║  │    objetos   │                  ▼   │                            ║   │
│  ║  │  - clips     │           ┌──────────────┐   bucket notification  ║   │
│  ║  │  - snapshots │──────────▶│    MinIO      │──────────────────────▶║   │
│  ║  │  - MQTT pub  │           │ :9000 / :9001 │   (evento → Redpanda) ║   │
│  ║  └──────────────┘           │  (Data Lake)   │                      ║   │
│  ║                             └───────┬────────┘                      ║   │
│  ║                                     │                               ║   │
│  ║                                     │ Site Replication              ║   │
│  ║                                     ▼                               ║   │
│  ║                           Servidor Remoto (MinIO)                   ║   │
│  ║                                                                     ║   │
│  ╚═════════════════════════════════════════════════════════════════════╝   │
│                                                                            │
│  ╔════════════════════ OBSERVABILIDADE ════════════════════════════════╗   │
│  ║                                                                     ║   │
│  ║  ┌──────────┐    ┌───────────┐    ┌───────────┐                    ║   │
│  ║  │ Grafana  │    │Prometheus │◀───│Node Export│                    ║   │
│  ║  │  :3000   │    │  :9090    │    │  :9100    │                    ║   │
│  ║  │          │    │           │◀───┤           │                    ║   │
│  ║  │Datasource│    │           │    │ cAdvisor  │                    ║   │
│  ║  │InfluxDB  │    └───────────┘    │  :8088    │                    ║   │
│  ║  │Prometheus│                     └───────────┘                    ║   │
│  ║  │          │                                                      ║   │
│  ║  │ Alerting │──▶ Telegram / Email / Webhook                       ║   │
│  ║  └──────────┘                                                      ║   │
│  ║                                                                     ║   │
│  ║  ┌──────────────┐                                                  ║   │
│  ║  │  Redpanda    │  (UI para debug de topics e mensagens)           ║   │
│  ║  │  Console     │                                                  ║   │
│  ║  │  :8080       │                                                  ║   │
│  ║  └──────────────┘                                                  ║   │
│  ║                                                                     ║   │
│  ╚═════════════════════════════════════════════════════════════════════╝   │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

## 3.2 Serviços Docker — Inventário Completo

| # | Serviço | Imagem Docker | RAM Est. | Portas | Papel |
|---|---------|---------------|----------|--------|-------|
| 1 | **Mosquitto** | `eclipse-mosquitto:2` | ~10 MB | 1883, 9001 | Broker MQTT. Ponto de entrada para todos os dados de sensores e eventos Frigate. |
| 2 | **Redpanda** | `redpandadata/redpanda:latest` | ~1.5 GB | 9092, 8082, 9644 | Streaming central (Kafka API compatible). Barramento de eventos que desacopla produtores de consumidores. Armazena eventos com replay. |
| 3 | **Redpanda Console** | `redpandadata/console:latest` | ~100 MB | 8080 | UI web para inspecionar topics, consumer groups, mensagens. Ferramenta de debug e operação. |
| 4 | **Redpanda Connect** | `redpandadata/connect:latest` | ~50 MB | — | Pipelines declarativos (YAML). Faz o papel de bridge MQTT→Redpanda (substitui Telegraf) e também consome topics do Redpanda para gravar no InfluxDB 3. Roda múltiplos pipelines: ingestão MQTT, processamento de eventos MinIO, e escrita no InfluxDB. |
| 5 | **InfluxDB 3 Core** | `influxdb:3-core` | ~500 MB | 8181 | Banco de dados time-series. Armazena métricas de sensores (dados quentes), metadados de mídia (links para objetos no MinIO) e eventos do Frigate. Motor baseado em Apache Arrow + DataFusion + Parquet. Query via SQL. |
| 6 | **MinIO** | `minio/minio:latest` | ~300 MB | 9000, 9001 | Object storage (Data Lake). Armazena fotos, vídeos, clips, snapshots, exports e backups. S3-compatible. Bucket notifications disparam eventos no Redpanda quando objetos são criados/deletados. |
| 7 | **Frigate** | `ghcr.io/blakeblackshear/frigate:stable` | ~800 MB–1 GB | 5000, 8554, 8555 | NVR inteligente. Consome streams RTSP das câmeras IP, faz detecção de movimento e objetos (pessoas, animais, veículos). Salva clips e snapshots diretamente no MinIO. Publica eventos de detecção via MQTT no Mosquitto. |
| 8 | **Grafana** | `grafana/grafana-oss:latest` | ~200 MB | 3000 | Dashboard e alertas. Datasources: InfluxDB 3 (SQL) e Prometheus. Exibe métricas de sensores, timeline de mídia com links para o MinIO, e saúde da infraestrutura. Alerting envia notificações via Telegram, email ou webhook. |
| 9 | **Prometheus** | `prom/prometheus:latest` | ~200 MB | 9090 | Monitoramento da infraestrutura. Coleta métricas dos containers (via cAdvisor) e da máquina host (via Node Exporter). Não armazena dados de negócio — apenas saúde do sistema. |
| 10 | **cAdvisor** | `gcr.io/cadvisor/cadvisor:latest` | ~50 MB | 8088 | Exporta métricas de resource usage dos containers Docker (CPU, RAM, rede, disco) para o Prometheus. |
| 11 | **Node Exporter** | `prom/node-exporter:latest` | ~20 MB | 9100 | Exporta métricas da máquina host (CPU, RAM, disco, temperatura, rede) para o Prometheus. |

**RAM total estimada: ~3.7–4.4 GB** (de 8 GB disponíveis → margem de ~3.6–4.3 GB).
