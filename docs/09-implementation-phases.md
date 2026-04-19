# 9. Fases de Implementação

## Fase 1 — Core Pipeline (Prioridade máxima) ✓ IMPLEMENTADO

**Objetivo:** Ter o pipeline básico funcionando de ponta a ponta.
**Status:** Completo. Commit `0c27f22`.

| Passo | Componente | Descrição |
|-------|-----------|-----------|
| 1.1 | Docker Compose base | Estrutura de diretórios, `.env`, rede Docker |
| 1.2 | Mosquitto | Broker MQTT funcional com autenticação |
| 1.3 | Redpanda | Broker de streaming, topics criados |
| 1.4 | InfluxDB 3 Core | Banco configurado, databases criados |
| 1.5 | Redpanda Connect | Pipeline MQTT→Redpanda (bridge) + pipeline `sensors.telemetry` → InfluxDB |
| 1.6 | Teste end-to-end | Publicar MQTT manualmente → verificar dado no InfluxDB |

## Fase 2 — Data Lake ✓ IMPLEMENTADO

**Status:** Completo. MinIO (`:9000` API, `:9001` Console), 3 buckets (`media`, `exports`, `backups`).
Bucket notifications (Kafka) → Redpanda `minio.events` → Redpanda Connect → InfluxDB `media_objects`.
Prometheus scrapes MinIO métricas (`/minio/v2/metrics/cluster`).
Dev: Docker named volume. Produção: montar disco externo em `/data`.

| Passo | Componente | Descrição |
|-------|-----------|-----------|
| 2.1 | MinIO | Buckets criados, acesso S3 configurado |
| 2.2 | Bucket notifications | MinIO → Redpanda (`minio.events`) |
| 2.3 | Redpanda Connect | Pipeline `minio.events` → InfluxDB (metadados) |
| 2.4 | Teste | Upload manual de arquivo → verificar metadado no InfluxDB |

## Fase 3 — Câmeras e Detecção ✓ IMPLEMENTADO

**Status:** Completo. Frigate NVR (`:5000`) com CPU-based detection, go2rtc RTSP restream (`:8554`),
MQTT events → Redpanda `frigate.events` → Redpanda Connect → InfluxDB `frigate_events`.
Test camera: looping MP4 via `exec:ffmpeg` em go2rtc. Produção: substituir por câmeras RTSP reais + Google Coral TPU.

| Passo | Componente | Descrição |
|-------|-----------|-----------|
| 3.1 | Frigate | Configurar câmeras RTSP, detecção de objetos |
| 3.2 | Frigate → MinIO | Clips e snapshots salvos diretamente no MinIO |
| 3.3 | Frigate → MQTT | Eventos de detecção publicados no Mosquitto |
| 3.4 | Redpanda Connect | Pipeline `frigate.events` → InfluxDB |
| 3.5 | Teste | Simular detecção → verificar clip no MinIO e evento no InfluxDB |

> **Nota:** Passo 3.2 (Frigate → MinIO) requer configuração adicional.
> Frigate grava clips/snapshots localmente em `/media/frigate`. Para sincronizar com MinIO,
> será necessário um sidecar (e.g., `mc mirror` ou inotifywait + mc cp) ou usar Frigate's
> export API. Este passo será completado em iteração futura.

## Fase 4 — Observabilidade ✓ IMPLEMENTADO

**Status:** Completo. Grafana (`:3000`), Prometheus (`:9090`), Node Exporter (`:9100`), cAdvisor (interno).
Datasources provisionados automaticamente: Prometheus + InfluxDB 3 (SQL/Flight SQL).
Dashboards provisionados: Sensors Overview (InfluxDB SQL) + Infrastructure Overview (Prometheus).

| Passo | Componente | Descrição |
|-------|-----------|-----------|
| 4.1 | Grafana | Instalação, provisioning de datasources |
| 4.2 | Prometheus | Configuração de scrape targets |
| 4.3 | Node Exporter + cAdvisor | Métricas de host e containers |
| 4.4 | Dashboards Grafana | Sensores, mídia, infra |
| 4.5 | Alertas Grafana | Regras de alerting + canais (Telegram) |

## Fase 5 — Edge Devices

| Passo | Componente | Descrição |
|-------|-----------|-----------|
| 5.1 | Firmware ESP32 sensor | Deep sleep + leitura + LoRa TX |
| 5.2 | Firmware ESP32 gateway | LoRa RX + MQTT publish (WiFi) |
| 5.3 | Hardware gateway | Montagem no ponto elevado + solar + antena direcional |
| 5.4 | Teste campo | Verificar leituras dos sensores chegando ao InfluxDB/Grafana |

## Fase 6 — Replicação Geográfica

| Passo | Componente | Descrição |
|-------|-----------|-----------|
| 6.1 | MinIO remoto | Docker Compose no servidor remoto |
| 6.2 | Site Replication | Configurar replicação bidirecional entre os dois MinIO |
| 6.3 | Conectividade | VPN ou conexão segura entre os dois locais |
| 6.4 | Teste | Upload no principal → verificar réplica no remoto |

## Fase 7 — Retenção e Manutenção

| Passo | Componente | Descrição |
|-------|-----------|-----------|
| 7.1 | Downsample job | Script + cron para agregar dados antigos |
| 7.2 | Export job | Backup periódico do InfluxDB para MinIO (Parquet) |
| 7.3 | Políticas de retenção | Configurar TTL no InfluxDB, lifecycle rules no MinIO |
| 7.4 | Backup de configs | Script para backup de docker-compose, configs, dashboards |

## Fase 8 — Hardening (Futuro)

| Passo | Componente | Descrição |
|-------|-----------|-----------|
| 8.1 | Reverse proxy | Traefik ou Caddy com HTTPS para acesso remoto |
| 8.2 | VPN | WireGuard para acesso seguro à rede interna |
| 8.3 | Monitoramento do monitoramento | Alertas se Prometheus/Grafana caírem |
| 8.4 | Documentação operacional | Runbooks para troubleshooting e manutenção |
