# 7. Operações

Referência operacional: consumo de recursos, verificação e troubleshooting do sistema,
segurança, riscos e glossário.

## 7.1 Consumo de recursos

### RAM (servidor principal)

| Serviço | RAM estimada | Observação |
|---|---|---|
| Sistema operacional | ~500–800 MB | Linux headless minimal |
| Mosquitto | ~10 MB | Extremamente leve |
| Redpanda | ~1.5 GB | Principal consumidor de RAM |
| Redpanda Console | ~100 MB | UI web |
| Redpanda Connect | ~50 MB | Inclui bridge MQTT + consumers |
| InfluxDB 3 Core | ~500 MB | Pode ser limitado via config |
| MinIO | ~300 MB | Cresce com o número de objetos |
| Frigate | ~800 MB–1 GB | Sem Coral; com Coral USB a CPU alivia |
| Grafana | ~200 MB | |
| Prometheus | ~200 MB | Cresce com retenção e targets |
| cAdvisor | ~50 MB | |
| Node Exporter | ~20 MB | |
| **Total** | **~4.2–4.7 GB** | Margem confortável em 8 GB; muito folgado em 16 GB |

### Disco

| Dado | Crescimento estimado | Observação |
|---|---|---|
| Sensores (InfluxDB) | ~1–5 MB/dia (20 sensores @ 5min) | Muito baixo |
| Frigate clips | ~100–500 MB/dia | Principal consumidor |
| Frigate recordings | ~5–20 GB/dia por câmera (se contínuo) | Opcional; requer disco grande |
| Snapshots | ~10–50 MB/dia | Baixo |
| Prometheus | ~50–100 MB/dia | 15 dias de retenção padrão |

**Recomendação:** SSD de 256–512 GB para o sistema + HDD de 1–2 TB (ou mais) para o
MinIO (mídia). Se possível, separar os discos.

### Rede

| Fluxo | Banda | Observação |
|---|---|---|
| Sensores (MQTT) | < 1 Kbps | Negligível |
| Câmeras (RTSP → Frigate) | 2–8 Mbps por câmera | Principal consumidor interno |
| Replicação MinIO | Depende do upload (assíncrono) | Comprime e sincroniza em background |
| Grafana (browser) | < 1 Mbps | Sob demanda |

## 7.2 Verificar o status dos serviços

```bash
# Status geral de todos os containers
docker compose ps

# Logs de um serviço (últimas 30 linhas / follow)
docker compose logs --tail 30 <serviço>
docker compose logs -f <serviço>

# Healthcheck individual
docker inspect --format='{{.State.Health.Status}}' redpanda
docker inspect --format='{{.State.Health.Status}}' influxdb
```

### Redpanda Console (http://localhost:8080)
Interface principal para debug de mensagens e topics.
- **Topics**: `sensors.telemetry`, `frigate.events`, `minio.events`. Clique num topic
  para ver o payload, headers, offset e timestamp das mensagens.
- **Consumer Groups**: verifique lag (mensagens não consumidas).

> Se aparecer "issues deserializing the value", troque o **Value Deserializer** de
> "Auto" para "JSON". As env vars `KAFKA_PROTOBUF_ENABLED=false` e
> `KAFKA_MSGPACK_ENABLED=false` já minimizam isso.

> O Redpanda exibe "Enterprise Trial" — normal. O Community Edition é gratuito; ao
> expirar o trial, só features enterprise (Shadow Indexing, Cluster Links) são
> desabilitadas. Tudo que usamos continua funcionando.

### Redpanda Connect API (http://localhost:4195)
```bash
curl -s http://localhost:4195/ready      # Esperado: OK
curl -s http://localhost:4195/streams | python3 -m json.tool
# Esperado: mqtt-to-redpanda, sensors-to-influx, frigate-to-influx,
#           minio-to-influx com "active": true
curl -s http://localhost:4195/metrics | grep -E 'input_received|output_sent|processor_error'
```
Se um stream não aparece ou está `active: false`: cheque `docker compose logs
--tail 30 redpanda-connect`. Erros de lint no YAML aparecem como warnings (graças ao
`--chilled`), mas impedem o stream de iniciar. Erros de conexão geram retries.

### InfluxDB API (http://localhost:8181)
Sem UI web — tudo via API HTTP. **Sempre inclua `format=json`.**
```bash
curl -s http://localhost:8181/health      # Esperado: OK

# Consultar dados (SQL)
curl -s 'http://localhost:8181/api/v3/query_sql' -G \
  --data-urlencode 'db=farm' \
  --data-urlencode 'q=SELECT * FROM sensor_readings ORDER BY time DESC LIMIT 10' \
  --data-urlencode 'format=json' | python3 -m json.tool

# Listar tabelas / criar database
curl -s 'http://localhost:8181/api/v3/query_sql' -G \
  --data-urlencode 'db=farm' --data-urlencode 'q=SHOW TABLES' \
  --data-urlencode 'format=json'
curl -X POST http://localhost:8181/api/v3/configure/database \
  -H 'Content-Type: application/json' -d '{"db":"farm"}'
```

### Redpanda — topics via CLI
```bash
docker exec redpanda rpk topic list --brokers localhost:9092
docker exec redpanda rpk topic consume sensors.telemetry --brokers localhost:9092 --num 3
docker exec redpanda rpk group describe influx-sensor-writer --brokers localhost:9092
```

### MinIO
```bash
curl -f http://localhost:9000/minio/health/live

# Listar buckets / notificações
docker run --rm --network farm-monitoring_monitoring --entrypoint="" minio/mc:latest \
  sh -c "mc alias set farm http://minio:9000 <MINIO_ROOT_USER> <MINIO_ROOT_PASSWORD> && mc ls farm && mc event list farm/media"
```

## 7.3 Teste end-to-end

Para validar o pipeline completo `MQTT → Redpanda → InfluxDB`, veja o passo a passo em
[Como Usar → Publicar uma leitura de teste](03-usage.md#34-publicar-uma-leitura-de-teste).
Para o Data Lake, faça um upload de teste no MinIO e verifique que o measurement
`media_objects` recebe o registro.

## 7.4 Problemas comuns

| Sintoma | Causa provável | Solução |
|---|---|---|
| InfluxDB healthcheck falha | Auth habilitado sem token | Usar `--without-auth` (local) ou configurar token |
| Redpanda Connect em crash loop | Erro de lint no YAML dos pipelines | Ver logs; `--chilled` evita o crash, mas o stream não inicia |
| MQTT "not Authorized" | Senha no `.env` ≠ `password_file` | `docker compose up -d --force-recreate mosquitto-setup mosquitto` |
| Mensagens não chegam ao InfluxDB | Connect não conectou ao MQTT/Redpanda | Ver `curl localhost:4195/streams` — stream deve estar `active: true` |
| `serde error: missing field 'format'` | Falta `format=json` na query v3 | Adicionar `--data-urlencode 'format=json'` |
| "Issues deserializing value" no Console | Console tentando Protobuf/MsgPack em JSON | Usar o dropdown "JSON" |
| Database não encontrada no InfluxDB | `setup` não criou o database | `curl -X POST .../api/v3/configure/database -d '{"db":"farm"}'` |
| Porta não acessível (Connection refused) | Porta não mapeada | Verificar `ports:` do serviço no `docker-compose.yml` |

**Notas de ambiente:**
- cAdvisor usa a porta 8080 internamente (conflita com Redpanda Console no host), por
  isso **não** é exposta ao host.
- No macOS (Docker Desktop), o Node Exporter reporta a VM Linux do Docker, não o host
  real. No Linux funciona nativamente.
- O datasource InfluxDB 3 SQL usa `insecureGrpc: true` (sem TLS, ambiente dev).
- MinIO usa named volume em dev; para produção, use bind mount para disco externo
  (ex.: `- /mnt/external-hdd/minio:/data`).

## 7.5 Segurança

### Modelo de confiança
O sistema roda em **redes confiáveis** (LAN da sede e LAN da agrofloresta), onde o
acesso é controlado fisicamente pelo proprietário. **O acesso externo é feito
exclusivamente via túnel SSH** (`ssh -L`), encaminhando as portas desejadas.

- Nenhuma porta de serviço (InfluxDB, Grafana, MinIO, Redpanda) fica exposta à internet.
- **O SSH é o perímetro de segurança real** — protege todos os serviços de uma vez.
- Onde investir: **SSH com chave** (não senha), `fail2ban`, não expor a porta 22
  direta na internet, e **não abrir portas de serviço no roteador**.

### Autenticação por serviço
| Serviço | Autenticação |
|---|---|
| Mosquitto | Username/password (`password_file`, gerado do `.env`) |
| InfluxDB 3 | **Sem auth em modo local** (`--without-auth`). Token opcional como hardening. |
| MinIO | Access key / Secret key (S3 API) |
| Grafana | Login local (admin, credenciais via `.env`) |
| Frigate | Sem auth nativo — protegido pela rede/SSH |
| Redpanda | Sem auth em modo local — protegido pela rede |

> O InfluxDB roda com `--without-auth` **por decisão consciente**: no modelo acima, ele
> nunca está acessível de fora, o que mantém o debug simples. Habilitar token é um
> passo de hardening opcional, útil caso o InfluxDB venha a ser exposto por um proxy
> público ou outras pessoas passem a ter acesso à rede.

### Credenciais
Todas as credenciais são gerenciadas via `.env` no Docker Compose. O `.env` **não** é
versionado (está no `.gitignore`); o `.env.example` é o template versionado.

## 7.6 Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| Servidor 8 GB com picos simultâneos (Frigate + Redpanda + InfluxDB) | OOM kills, serviços reiniciando | `mem_limit` por container; monitorar via Prometheus; planejar upgrade para 16 GB |
| Gateway LoRa falha (energia/hardware) | Perda de dados de todos os sensores | Solar + bateria robusta, watchdog no firmware, alerta "sensor offline", buffer local |
| WiFi direcional instável | Perda de conectividade gateway → servidor | Antena de qualidade com suporte rígido; link budget com margem; monitorar latência/perda |
| Disco do MinIO enche | Perda de novos dados de mídia | Alerta quando disco > 80%; lifecycle rules para recordings antigos; expandir disco |
| InfluxDB 3 Core é relativamente novo | Bugs/comportamentos inesperados | Backup periódico para MinIO; fallback para 2.x se necessário |
| Frigate sem Google Coral TPU | Alta carga de CPU na detecção | Limitar FPS de detecção; reduzir resolução; considerar Coral USB |

## 7.7 Glossário

| Termo | Definição |
|---|---|
| **MQTT** | Protocolo leve de mensageria pub/sub, ideal para IoT. |
| **LoRa** | Rádio sub-GHz de longo alcance e baixo consumo para IoT. |
| **LoRaWAN** | Protocolo de rede sobre LoRa com device management e segurança. |
| **Redpanda** | Plataforma de streaming compatível com Kafka API, sem JVM/ZooKeeper. |
| **Redpanda Connect** | Engine de pipelines declarativos (YAML), baseado no Benthos. |
| **InfluxDB** | Banco de dados otimizado para séries temporais. |
| **MinIO** | Object storage self-hosted, compatível com a API S3. |
| **Frigate** | NVR open-source com detecção de objetos via IA. |
| **Grafana** | Plataforma de visualização e dashboards. |
| **Prometheus** | Monitoramento de infraestrutura com coleta pull de métricas. |
| **Bucket Notification** | Mecanismo do MinIO que dispara eventos ao criar/deletar objetos. |
| **Downsample** | Agregar dados de alta resolução em resumos de menor resolução. |
| **Deep Sleep** | Modo de baixo consumo do ESP32. |
| **RTSP** | Protocolo de streaming de vídeo de câmeras IP. |
| **Site Replication** | Sincronização nativa do MinIO entre clusters geograficamente distribuídos. |
