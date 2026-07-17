# 8. Estrutura de Diretórios do Projeto

> **Repositório:** [github.com/irigon/farm-monitoring](https://github.com/irigon/farm-monitoring)

```
farm-monitoring/                        # Raiz do repositório
├── README.md
├── docker-compose.yml                  # Orquestração de todos os serviços
├── .env.example                        # Template de variáveis de ambiente
├── .env                                # Variáveis reais (não versionado)
├── .gitignore
│
├── docs/                               # Documentação (este diretório)
│
├── config/
│   ├── frigate/
│   │   └── config.yml                  # Câmeras, detecção, gravação
│   │
│   ├── grafana/
│   │   ├── dashboards/
│   │   │   ├── infrastructure.json     # Dashboard: saúde da infraestrutura
│   │   │   └── sensors.json            # Dashboard: sensores
│   │   └── provisioning/
│   │       ├── dashboards/dashboards.yml   # Provisionamento de dashboards
│   │       └── datasources/datasources.yml # Datasources InfluxDB + Prometheus
│   │
│   ├── influxdb/                       # (vazio — .gitkeep; dados em volume Docker)
│   ├── minio/                          # (vazio — .gitkeep; dados em volume Docker)
│   │
│   ├── mosquitto/
│   │   ├── mosquitto.conf              # Configuração do broker MQTT
│   │   └── password_file               # Credenciais MQTT (gerado a partir do .env)
│   │
│   ├── prometheus/
│   │   └── prometheus.yml              # Scrape targets (node-exporter, cadvisor, etc.)
│   │
│   ├── redpanda/                       # (vazio — .gitkeep; config via flags no compose)
│   │
│   └── redpanda-connect/
│       ├── mqtt-to-redpanda.yml        # Pipeline: MQTT (sensores + frigate) → Redpanda topics
│       ├── sensors-to-influx.yml       # Pipeline: sensors.telemetry → InfluxDB
│       ├── frigate-to-influx.yml       # Pipeline: frigate.events → InfluxDB
│       └── minio-to-influx.yml         # Pipeline: minio.events → InfluxDB
│
├── scripts/
│   ├── setup.sh                        # Cria topics Redpanda + database InfluxDB
│   ├── mosquitto-setup.sh              # Gera password_file a partir do .env
│   ├── minio-setup.sh                  # Cria buckets + configura notificações
│   └── frigate-to-minio.sh             # Sidecar: espelha mídia do Frigate no MinIO
│
├── test-data/
│   └── video/                          # Clip de teste usado pelo Frigate (dev)
│
├── edge/                               # (vazio — .gitkeep; firmware ESP32 futuro)
│   ├── esp32-sensor/                   # Firmware ESP32 sensores (LoRa TX)
│   └── esp32-gateway/                  # Firmware ESP32 gateway (LoRa RX → MQTT)
│
└── remote/                             # (vazio — .gitkeep; futura réplica MinIO remota)
```

> **Nota:** `edge/` e `remote/` contêm apenas `.gitkeep` no momento — reservam o
> lugar para o firmware dos dispositivos de campo e para a configuração do servidor
> remoto, respectivamente.
