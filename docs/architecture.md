# Sistema de Monitoramento Genérico para Agrofloresta

Sistema de monitoramento distribuído para uma propriedade de agrofloresta.
Ingestão de dados heterogêneos (sensores IoT, câmeras, mídia), processamento
em tempo real e armazenamento com políticas de retenção diferenciadas.

## Documentação

| # | Documento | Conteúdo |
|---|-----------|----------|
| 1 | [Visão Geral](01-overview.md) | Princípios de design, objetivos do sistema |
| 2 | [Infraestrutura Física](02-infrastructure.md) | Hardware, topologia de rede, gateway LoRa |
| 3 | [Arquitetura de Software](03-software-architecture.md) | Diagrama de componentes, inventário de serviços Docker |
| 4 | [Fluxos de Dados](04-data-flows.md) | 6 fluxos: sensores, mídia, MinIO events, alertas, replicação, infra |
| 5 | [Schemas de Dados](05-data-schemas.md) | Retenção, topics Redpanda, buckets MinIO, measurements InfluxDB |
| 6 | [Grafana](06-grafana.md) | Datasources, dashboards, regras de alerting |
| 7 | [Segurança](07-security.md) | Rede, autenticação, credenciais |
| 8 | [Estrutura do Projeto](08-project-structure.md) | Árvore de diretórios do repositório |
| 9 | [Fases de Implementação](09-implementation-phases.md) | 8 fases com status (1-4 implementadas) |
| 10 | [Operações](10-operations.md) | Recursos estimados, decisões técnicas, riscos, glossário |
| 11 | [Troubleshooting — Core](11-troubleshooting.md) | Interfaces, status, Redpanda, Connect, InfluxDB |
| 12 | [Troubleshooting — CLI & Testes](12-troubleshooting-services.md) | rpk, MQTT, teste end-to-end, problemas comuns |
| 13 | [Troubleshooting — Por Fase](13-troubleshooting-phases.md) | Verificação da Observability stack e Data Lake |

## Stack

```
ESP32 (LoRa) → Gateway → Mosquitto (MQTT) → Redpanda Connect → Redpanda → Redpanda Connect → InfluxDB 3
Câmeras IP (RTSP) → Frigate → MQTT events + MinIO (clips/snapshots)
Prometheus + Node Exporter + cAdvisor → Grafana
```

## Portas

| Serviço | Porta |
|---------|-------|
| Mosquitto (MQTT) | 1883 |
| Grafana | 3000 |
| Redpanda Connect API | 4195 |
| Frigate Web UI | 5000 |
| Redpanda Console | 8080 |
| InfluxDB 3 API | 8181 |
| Frigate RTSP | 8554 |
| MinIO S3 API | 9000 |
| MinIO Console | 9001 |
| Prometheus | 9090 |
| Node Exporter | 9100 |
| Redpanda Kafka (external) | 19092 |
