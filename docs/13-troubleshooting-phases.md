# 11. Troubleshooting — Serviços por Fase

## 11.10 Phase 4 — Observability Stack

**Serviços adicionados:**

| Serviço | Porta (host) | URL |
|---------|-------------|-----|
| Grafana | 3000 | http://localhost:3000 |
| Prometheus | 9090 | http://localhost:9090 |
| Node Exporter | 9100 | http://localhost:9100/metrics |
| cAdvisor | *(interno)* | Prometheus scrapes `cadvisor:8080` na rede Docker |

**Verificação rápida:**

```bash
# 1. Prometheus targets — todos devem estar UP
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep '"health"'

# 2. Grafana datasources — devem retornar Prometheus e InfluxDB
curl -s -u admin:<GF_PASSWORD> http://localhost:3000/api/datasources | python3 -m json.tool

# 3. Grafana dashboards — devem mostrar sensors e infrastructure
curl -s -u admin:<GF_PASSWORD> http://localhost:3000/api/search | python3 -m json.tool
```

**Notas:**
- cAdvisor usa porta 8080 internamente, que conflita com Redpanda Console no host. Por isso NÃO é exposta ao host.
- No macOS (Docker Desktop), Node Exporter mostra métricas da VM Linux do Docker, não do host real. No Linux final, funciona nativamente.
- Grafana requer feature flag `newInfluxDSConfigPageDesign` para o datasource InfluxDB 3 SQL (Flight SQL).
- Datasource InfluxDB usa `insecureGrpc: true` (sem TLS para ambiente dev).

## 11.11 Phase 2 — Data Lake (MinIO)

**Serviços adicionados:**

| Serviço | Porta (host) | URL |
|---------|-------------|-----|
| MinIO (S3 API) | 9000 | http://localhost:9000 |
| MinIO Console | 9001 | http://localhost:9001 |
| minio-setup | *(one-shot)* | Cria buckets e configura notificações |

**Buckets:** `media`, `exports`, `backups`

**Verificação rápida:**

```bash
# 1. MinIO health
curl -f http://localhost:9000/minio/health/live

# 2. Listar buckets
docker run --rm --network farm-monitoring_monitoring --entrypoint="" minio/mc:latest \
  sh -c "mc alias set farm http://minio:9000 <MINIO_ROOT_USER> <MINIO_ROOT_PASSWORD> && mc ls farm"

# 3. Verificar notificações configuradas
docker run --rm --network farm-monitoring_monitoring --entrypoint="" minio/mc:latest \
  sh -c "mc alias set farm http://minio:9000 <MINIO_ROOT_USER> <MINIO_ROOT_PASSWORD> && mc event list farm/media"

# 4. Upload de teste e verificar no InfluxDB
echo "test" | docker run -i --rm --network farm-monitoring_monitoring --entrypoint="" minio/mc:latest \
  sh -c "mc alias set farm http://minio:9000 <MINIO_ROOT_USER> <MINIO_ROOT_PASSWORD> > /dev/null 2>&1 && mc pipe farm/media/uploads/test.txt"
sleep 3
curl -s 'http://localhost:8181/api/v3/query_sql' -G \
  --data-urlencode 'db=farm' \
  --data-urlencode 'q=SELECT * FROM media_objects ORDER BY time DESC LIMIT 3' \
  --data-urlencode 'format=json' | python3 -m json.tool
```

**Notas:**
- MinIO usa Docker named volume (`minio-data`) em dev. Para produção no Linux, substituir por bind mount para disco externo: `- /mnt/external-hdd/minio:/data`
- Bucket notifications usam ARN `arn:minio:sqs::PRIMARY:kafka` (maiúsculo). O `mc event add` usa `--event put,delete` (não `s3:ObjectCreated:*`).
- `MINIO_PROMETHEUS_AUTH_TYPE=public` permite Prometheus scrape sem bearer token (dev only).
- Pipeline `minio-to-influx` extrai metadados do evento e grava como measurement `media_objects` no InfluxDB.
