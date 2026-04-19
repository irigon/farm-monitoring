# 6. Grafana — Datasources e Dashboards

## 6.1 Datasources (provisionados automaticamente)

| Datasource | Tipo | URL | Uso |
|------------|------|-----|-----|
| InfluxDB 3 | InfluxDB (SQL/Flight) | `http://influxdb:8181` | Dados de sensores, eventos, metadados de mídia |
| Prometheus | Prometheus | `http://prometheus:9090` | Métricas de infraestrutura |

## 6.2 Dashboards Planejados

| Dashboard | Conteúdo |
|-----------|----------|
| **Sensores — Tempo Real** | Gráficos de temperatura, umidade, pH, luminosidade por nó. Mapa de calor da propriedade. |
| **Sensores — Tendências** | Dados downsampled. Comparação semanal/mensal. Sazonalidade. |
| **Segurança / Câmeras** | Timeline de eventos Frigate. Snapshots inline. Links para clips no MinIO. |
| **Mídia — Navegador** | Lista de objetos no MinIO com filtros. Links clicáveis para fotos/vídeos. |
| **Infraestrutura** | CPU, RAM, disco, rede do servidor. Status dos containers. Consumer lag do Redpanda. Espaço do MinIO. |
| **Alertas** | Histórico de alertas disparados. Status atual de cada regra. |

## 6.3 Alerting — Regras Planejadas

| Regra | Condição | Canal | Prioridade |
|-------|----------|-------|-----------|
| Umidade do solo baixa | `sensor_type = 'soil_moisture' AND value < 30` por > 15min | Telegram | Alta |
| Temperatura extrema | `sensor_type = 'temperature' AND (value < 2 OR value > 42)` | Telegram | Alta |
| Detecção de pessoa (noite) | Evento Frigate `label = 'person'` entre 22h-06h | Telegram | Alta |
| Sensor offline | Nenhuma leitura de um `node_id` por > 30min | Email | Média |
| Disco do servidor > 85% | Prometheus: `node_filesystem_avail_bytes` | Telegram | Alta |
| Container reiniciando | Prometheus: `rate(container_restart_count)` > 0 | Email | Média |
| Replicação MinIO atrasada | MinIO metrics: replication lag | Email | Média |
