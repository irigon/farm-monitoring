# 5. Dados — Retenção, Topics, Buckets, Measurements

## 5.1 Política de Retenção de Dados

### Camadas de Armazenamento

| Camada | Tipo de Dado | Retenção | Localização | Observação |
|--------|-------------|----------|-------------|------------|
| **Hot** | Dados brutos de sensores | 30 dias | InfluxDB 3 Core | Alta resolução, queries rápidas |
| **Warm** | Dados downsampled (médias horárias/diárias) | 1 ano | InfluxDB 3 Core | Agregações para tendências de longo prazo |
| **Cold** | Mídia (fotos, vídeos, clips) | Indefinido | MinIO (principal + réplica) | Custo de armazenamento = custo do disco |
| **Cold** | Exports periódicos do InfluxDB | Indefinido | MinIO | Backup dos dados de sensores em Parquet/CSV |
| **Archive** | Tudo sincronizado | Indefinido | MinIO (servidor remoto) | Resiliência geográfica |

### Downsample Job

Um cron job (ou script agendado) roda periodicamente para agregar dados antigos:

- **Frequência:** Diário (ex: 02:00 AM).
- **Lógica:** Dados com mais de 30 dias são agregados em médias horárias/diárias e
  gravados como novo measurement (ex: `sensor_readings_hourly`). Os dados brutos
  originais expiram pela política de retenção do InfluxDB.
- **Implementação:** Script Python ou SQL query via cron que:
  1. Consulta dados brutos dos últimos 30-31 dias.
  2. Agrega por hora/dia.
  3. Grava os agregados de volta no InfluxDB (measurement com retenção de 1 ano).
  4. Exporta um backup Parquet/CSV para o MinIO (bucket: `exports/`).

---

## 5.2 Topics Redpanda

| Topic | Produtor | Consumidor | Conteúdo |
|-------|----------|------------|----------|
| `sensors.telemetry` | Redpanda Connect (via MQTT bridge) | Redpanda Connect | Leituras de sensores (temp, umid, pH, lux, etc.) |
| `frigate.events` | Redpanda Connect (via MQTT bridge) | Redpanda Connect | Eventos de detecção do Frigate (pessoa, animal, veículo) |
| `minio.events` | MinIO (bucket notification) | Redpanda Connect | Notificações de criação/deleção de objetos no MinIO |
| `alerts.raw` | (futuro) | (futuro) | Eventos de alerta para processamento adicional |

---

## 5.3 Buckets MinIO

| Bucket | Conteúdo | Retenção | Replicado |
|--------|----------|----------|-----------|
| `media/clips/` | Clips de vídeo gerados pelo Frigate | Indefinido | Sim |
| `media/snapshots/` | Snapshots de detecção do Frigate | Indefinido | Sim |
| `media/recordings/` | Gravação contínua das câmeras (opcional) | Configurável (ex: 30 dias) | Sim |
| `media/uploads/` | Fotos/vídeos enviados manualmente ou por scripts | Indefinido | Sim |
| `exports/` | Exports periódicos do InfluxDB (Parquet, CSV) | Indefinido | Sim |
| `backups/` | Backups de configuração, dumps, etc. | Indefinido | Sim |

---

## 5.4 Measurements InfluxDB

| Measurement | Tags | Fields | Fonte | Retenção |
|-------------|------|--------|-------|----------|
| `sensor_readings` | `node_id`, `sensor_type`, `location` | `value` (float) | Redpanda Connect ← sensores | 30 dias (bruto) |
| `sensor_readings_hourly` | `node_id`, `sensor_type`, `location` | `avg`, `min`, `max`, `count` | Downsample job | 1 ano |
| `sensor_readings_daily` | `node_id`, `sensor_type`, `location` | `avg`, `min`, `max`, `count` | Downsample job | 1 ano |
| `frigate_events` | `camera`, `label`, `zone` | `score`, `duration`, `clip_url`, `snapshot_url` | Redpanda Connect ← Frigate | Indefinido |
| `media_objects` | `bucket`, `content_type`, `source` | `object_key`, `size_bytes`, `url` | Redpanda Connect ← MinIO events | Indefinido |
