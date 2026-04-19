# 8. Estrutura de Diretórios do Projeto

> **Repositório:** [github.com/irigon/farm-monitoring](https://github.com/irigon/farm-monitoring)

```
farm-monitoring/                        # Raiz do repositório
├── README.md
├── docs/
│   └── architecture.md                 # Índice da documentação
├── docker-compose.yml                  # Orquestração de todos os serviços
├── .env.example                        # Template de variáveis de ambiente
├── .env                                # Variáveis reais (não versionado)
├── .gitignore
│
├── config/
│   ├── mosquitto/
│   │   ├── mosquitto.conf              # Configuração do broker MQTT
│   │   └── password_file               # Credenciais MQTT (não versionado)
│   │
│   ├── redpanda/
│   │   └── redpanda.yml                # Configuração do broker Redpanda
│   │
│   ├── redpanda-connect/
│   │   ├── mqtt-to-redpanda.yml        # Pipeline: MQTT (sensores + frigate) → Redpanda topics
│   │   ├── sensors-to-influx.yml       # Pipeline: sensors.telemetry → InfluxDB
│   │   ├── frigate-to-influx.yml       # Pipeline: frigate.events → InfluxDB
│   │   └── minio-to-influx.yml         # Pipeline: minio.events → InfluxDB
│   │
│   ├── influxdb/                       # Configuração do InfluxDB 3 Core
│   │
│   ├── frigate/
│   │   └── config.yml                  # Câmeras, detecção, armazenamento MinIO
│   │
│   ├── grafana/
│   │   ├── grafana.ini                 # Configuração geral do Grafana
│   │   └── provisioning/
│   │       ├── datasources/
│   │       │   ├── influxdb.yml        # Datasource InfluxDB 3
│   │       │   └── prometheus.yml      # Datasource Prometheus
│   │       └── dashboards/
│   │           └── *.json              # Dashboards pré-configurados
│   │
│   ├── prometheus/
│   │   └── prometheus.yml              # Scrape targets (node-exporter, cadvisor, etc.)
│   │
│   └── minio/
│       └── bucket-notifications.sh     # Script para configurar notificações → Redpanda
│
├── scripts/
│   ├── setup.sh                        # Setup inicial: criar buckets, topics, etc.
│   ├── downsample.py                   # Cron job de agregação de dados antigos
│   └── backup.sh                       # Backup manual de configs e dados críticos
│
├── edge/                               # Firmware e scripts para dispositivos de campo
│   ├── esp32-sensor/                   # Firmware para ESP32 sensores (LoRa TX)
│   │   └── src/
│   ├── esp32-gateway/                  # Firmware para ESP32 gateway (LoRa RX → MQTT)
│   │   └── src/
│   └── README.md                       # Instruções de flash e configuração
│
└── remote/                             # Configuração do servidor remoto (MinIO réplica)
    ├── docker-compose.yml              # Apenas MinIO
    ├── .env.example
    └── .env
```
