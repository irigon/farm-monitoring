# 10. Operações — Recursos, Decisões, Riscos, Glossário

## 10.1 Estimativa de Consumo de Recursos (Servidor Principal)

### RAM

| Serviço | RAM Estimada | Observação |
|---------|-------------|------------|
| Sistema Operacional | ~500-800 MB | Linux headless minimal |
| Mosquitto | ~10 MB | Extremamente leve |
| Redpanda | ~1.5 GB | Principal consumidor de RAM |
| Redpanda Console | ~100 MB | UI web |
| Redpanda Connect | ~50 MB | Go binary; inclui pipelines MQTT bridge + consumers |
| InfluxDB 3 Core | ~500 MB | Pode ser limitado via config |
| MinIO | ~300 MB | Cresce com número de objetos |
| Frigate | ~800 MB–1 GB | Sem Google Coral; com Coral USB a CPU alivia |
| Grafana | ~200 MB | |
| Prometheus | ~200 MB | Cresce com retenção e targets |
| cAdvisor | ~50 MB | |
| Node Exporter | ~20 MB | |
| **Total** | **~4.2–4.7 GB** | |
| **Margem livre (8 GB)** | **~3.3–3.8 GB** | Suficiente para picos e crescimento |
| **Margem livre (16 GB)** | **~11.3–11.8 GB** | Muito confortável |

### Disco

| Dado | Crescimento Estimado | Observação |
|------|---------------------|------------|
| Sensores (InfluxDB) | ~1-5 MB/dia (20 sensores @ 5min) | Muito baixo |
| Frigate clips | ~100-500 MB/dia (depende de atividade) | Principal consumidor |
| Frigate recordings | ~5-20 GB/dia por câmera (se contínuo) | Opcional; requer disco grande |
| Snapshots | ~10-50 MB/dia | Baixo |
| Prometheus | ~50-100 MB/dia | 15 dias retenção padrão |

**Recomendação:** SSD de 256-512 GB para o sistema + HDD de 1-2 TB (ou mais) para o
MinIO (mídia). Se possível, separar os discos.

### Rede

| Fluxo | Banda Estimada | Observação |
|-------|---------------|------------|
| Sensores (MQTT) | < 1 Kbps | Negligível |
| Câmeras (RTSP → Frigate) | 2-8 Mbps por câmera | Principal consumidor de rede interna |
| MinIO replicação | Depende do upload (assíncrono) | Comprime e sincroniza em background |
| Grafana (browser) | < 1 Mbps | Sob demanda |

---

## 10.2 Decisões Técnicas e Justificativas

| Decisão | Alternativas Consideradas | Justificativa |
|---------|--------------------------|---------------|
| **Redpanda** (não Kafka) | Apache Kafka, NATS JetStream | Kafka API compatible sem ZooKeeper/KRaft. Single binary, menor footprint. NATS seria mais leve mas sem Kafka API compatibility — restringe ecossistema. |
| **InfluxDB 3 Core** (não 2.x) | InfluxDB 2.x, TimescaleDB | Motor moderno (Arrow/DataFusion/Parquet), SQL nativo, afinidade com object storage. Projeto novo (sem legado Flux). 2.x é legado com Flux sendo descontinuado. |
| **Redpanda Connect unificado** (não Telegraf + Connect separados) | Telegraf como MQTT→Kafka bridge, código Python custom, Kafka Connect | Redpanda Connect já existe na stack para os pipelines Kafka→InfluxDB. Absorver também o bridge MQTT→Kafka elimina um serviço (Telegraf), reduz complexidade operacional e configurações. Um componente a menos para manter. O input MQTT do Redpanda Connect (herdado do Benthos) é funcional e suficiente para o volume esperado. |
| **MinIO** (não S3/cloud) | AWS S3, Backblaze B2 | Self-hosted, custo zero (exceto disco), S3-compatible, site replication nativa, bucket notifications nativas. |
| **Frigate** (não scripts ffmpeg) | ffmpeg custom, ZoneMinder, Shinobi | Detecção de objetos built-in, integração MQTT nativa, comunidade ativa. Pode salvar direto no MinIO. |
| **LoRa simples** (não LoRaWAN) | ChirpStack/LoRaWAN, ESP-NOW, Meshtastic | Para 5-20 sensores, star topology é mais simples e barata. Gateway é apenas um ESP32. Migração para LoRaWAN futura não afeta a stack do servidor. |
| **Grafana Alerting** (não AlertManager) | Prometheus AlertManager | Grafana Alerting unifica alertas de múltiplos datasources (InfluxDB + Prometheus) em um só lugar. Mais simples de operar que AlertManager separado. |

---

## 10.3 Riscos e Mitigações

| Risco | Impacto | Mitigação |
|-------|---------|-----------|
| Servidor 8 GB com pouca margem se Frigate + Redpanda + InfluxDB picos simultâneos | OOM kills, serviços reiniciando | Configurar `mem_limit` por container no Docker Compose. Monitorar via Prometheus + alertas. Planejar upgrade para 16 GB. |
| Gateway LoRa no ponto alto falha (energia, hardware) | Perda de dados de todos os sensores | Solar + bateria robusta, watchdog no firmware, alertas de "sensor offline" no Grafana. Sensores podem ter buffer local (flash) para reenviar. |
| WiFi direcional instável (chuva, vento, desalinhamento) | Perda de conectividade gateway → servidor | Antena de qualidade com suporte rígido. Link budget com margem. Monitorar latência/packet loss. |
| Disco do MinIO enche | Perda de novos dados de mídia | Alertas no Grafana quando disco > 80%. Lifecycle rules para recordings antigos. Expandir disco conforme necessário. |
| InfluxDB 3 Core é relativamente novo | Bugs, comportamentos inesperados | Backup periódico para MinIO. Comunidade ativa. Fallback: migrar para 2.x se necessário (SQL queries precisariam de ajuste). |
| Frigate sem Google Coral TPU | Alta carga de CPU para detecção | Limitar FPS de detecção (ex: 5 fps). Reduzir resolução de detecção. Planejar compra de Coral USB (~R$300). |

---

## 10.4 Glossário

| Termo | Definição |
|-------|-----------|
| **MQTT** | Message Queuing Telemetry Transport. Protocolo leve de mensageria pub/sub, ideal para IoT. |
| **LoRa** | Long Range. Tecnologia de rádio sub-GHz de longo alcance e baixo consumo para IoT. |
| **LoRaWAN** | Protocolo de rede sobre LoRa com device management, segurança e escalabilidade. |
| **Redpanda** | Plataforma de streaming compatível com Kafka API, sem dependência de JVM/ZooKeeper. |
| **Redpanda Connect** | Engine de pipelines declarativos (YAML) para integração de dados, baseado no Benthos. |
| **InfluxDB** | Banco de dados otimizado para séries temporais (time-series). |
| **MinIO** | Object storage self-hosted, compatível com API S3 da AWS. |
| **Frigate** | NVR (Network Video Recorder) open-source com detecção de objetos via IA. |
| **Grafana** | Plataforma de visualização e dashboards para dados de métricas e logs. |
| **Prometheus** | Sistema de monitoramento de infraestrutura com modelo pull de coleta de métricas. |
| **Presigned URL** | URL temporária e autenticada que permite acesso direto a um objeto no MinIO/S3. |
| **Bucket Notification** | Mecanismo do MinIO para disparar eventos quando objetos são criados ou deletados. |
| **Downsample** | Processo de agregar dados de alta resolução em resumos de menor resolução. |
| **Deep Sleep** | Modo de baixo consumo do ESP32 onde a maior parte do chip é desligada. |
| **RTSP** | Real Time Streaming Protocol. Protocolo para streaming de vídeo de câmeras IP. |
| **Site Replication** | Funcionalidade nativa do MinIO para sincronizar dados entre clusters geograficamente distribuídos. |
