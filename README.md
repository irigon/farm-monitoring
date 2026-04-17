# Farm Monitoring System

Sistema de monitoramento distribuído para propriedade de agrofloresta. Capaz de ingerir dados heterogêneos — telemetria de sensores, eventos de movimento, fotos, vídeos e áudio — processá-los em tempo real e armazená-los com políticas de retenção diferenciadas.

## Documentação

- [Arquitetura do sistema](docs/architecture.md) — visão completa do design, componentes, fluxos de dados e fases de implementação.

## Stack

| Componente | Papel |
|-----------|-------|
| **Mosquitto** | Broker MQTT — ponto de entrada dos dados de sensores |
| **Redpanda** | Streaming central (Kafka-compatible) — barramento de eventos |
| **Redpanda Connect** | Pipelines declarativos (YAML) — bridges e transformações |
| **InfluxDB 3 Core** | Banco de dados time-series — métricas de sensores |
| **MinIO** | Object storage (Data Lake) — fotos, vídeos, backups |
| **Frigate** | NVR com detecção de objetos — câmeras IP |
| **Grafana** | Dashboards e alertas |
| **Prometheus** | Monitoramento da infraestrutura |

## Pré-requisitos

- Docker e Docker Compose v2+
- Linux (servidor headless, 8+ GB RAM)

## Quick Start

```bash
cp .env.example .env
# Editar .env com suas credenciais

docker compose up -d
```

> O sistema está em fase de implementação. Consulte [docs/architecture.md](docs/architecture.md) para detalhes sobre as fases planejadas.

## Estrutura do Repositório

```
farm-monitoring/
├── docs/                       # Documentação de arquitetura
├── docker-compose.yml          # Orquestração dos serviços
├── .env.example                # Template de variáveis de ambiente
├── config/                     # Configurações dos serviços
│   ├── mosquitto/
│   ├── redpanda/
│   ├── redpanda-connect/
│   ├── influxdb/
│   ├── frigate/
│   ├── grafana/
│   ├── prometheus/
│   └── minio/
├── scripts/                    # Scripts de setup, backup, downsample
└── edge/                       # Firmware ESP32 (sensores e gateway LoRa)
    ├── esp32-sensor/
    └── esp32-gateway/
```

## Status

**Fase 1 — Core Pipeline** (em planejamento)

Veja todas as fases em [docs/architecture.md](docs/architecture.md#12-fases-de-implementação).
