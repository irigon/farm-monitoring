# Sistema de Monitoramento Genérico para Agrofloresta

## 1. Visão Geral

Sistema de monitoramento distribuído para uma propriedade de agrofloresta, capaz de
ingerir dados heterogêneos — telemetria de sensores, eventos de movimento, fotos,
vídeos e áudio — processá-los em tempo real e armazená-los com políticas de retenção
diferenciadas. O sistema é projetado para começar pequeno e escalar horizontalmente
conforme a propriedade e a quantidade de sensores crescem.

### 1.1 Princípios de Design

- **Montar certo desde o início**: preferir componentes que escalam sem necessidade de
  substituição futura, mesmo que consumam mais recursos agora.
- **Custo baixo**: rodar em hardware próprio (sem cloud), com sincronização geográfica
  entre dois pontos físicos.
- **Genérico**: o sistema aceita qualquer tipo de dado (sensores ambientais, câmeras de
  segurança, drones, áudio, etc.) sem mudanças arquiteturais.
- **Dois fluxos de dados**: dados leves (sensores) via MQTT/streaming e dados pesados
  (mídia) direto para object storage, unificados por um barramento de eventos central.

---

## 2. Infraestrutura Física

### 2.1 Inventário de Hardware

| Máquina | Specs | Localização | Papel |
|---------|-------|-------------|-------|
| **Servidor Principal** | 8+ GB RAM, Linux, headless | Sede da propriedade | Hub central — todos os serviços core rodam aqui 24/7 |
| **Servidor Remoto** | 4-8 GB RAM, Linux, headless | Localização geográfica remota | Réplica do Data Lake (MinIO) para resiliência geográfica |
| **Notebook** | 32 GB RAM, Linux | Sede (uso ocasional) | Estação de trabalho: acessa dashboards via browser, desenvolvimento de configs/scripts, análise offline (Jupyter), backup local |
| **Gateway LoRa** | ESP32 + módulo LoRa + antena WiFi direcional | Ponto elevado (~1 km da sede) | Recebe dados LoRa dos sensores no campo, retransmite via WiFi direcional para o servidor |
| **Sensores ESP32** | ESP32 + LoRa + sensores (temp, umid, pH, lux, movimento) + painel solar + bateria | Espalhados pela agrofloresta | Coletam dados e transmitem via LoRa para o gateway |
| **Câmeras IP** | Câmeras com RTSP (ONVIF ou proprietárias) | Pontos estratégicos da propriedade | Stream de vídeo contínuo via RTSP para o servidor |
| **Raspberry Pi 3** | 1 GB RAM, ARM | Reserva / uso futuro | Pode servir como segundo gateway, nó de teste ou ponto de coleta auxiliar |

### 2.2 Topologia de Rede

```
┌────────────────────────── Agrofloresta (Campo) ──────────────────────────────┐
│                                                                               │
│   [ESP32+LoRa]  [ESP32+LoRa]  [ESP32+LoRa]   ...  [ESP32+LoRa]             │
│   sensor temp    sensor pH     sensor mov           sensor umid              │
│   solar+bat      solar+bat     solar+bat            solar+bat               │
│        │              │             │                    │                    │
│        └──── LoRa ────┴───── LoRa ──┴──── LoRa ─────────┘                   │
│                              │                                                │
│                              ▼                                                │
│                   ┌────────────────────┐                                      │
│                   │  Gateway LoRa      │                                      │
│                   │  (Ponto Elevado)   │                                      │
│                   │                    │                                      │
│                   │  ESP32 + LoRa RX   │                                      │
│                   │  + WiFi Direcional │                                      │
│                   │  Solar + bateria   │                                      │
│                   └────────┬───────────┘                                      │
│                            │ WiFi direcional (~1 km)                          │
│                            │                                                  │
│   [Cam IP 1] ──WiFi/Eth──┐│    [Cam IP 2] ──WiFi/Eth──┐                     │
│     (RTSP)                ││      (RTSP)                │                     │
└───────────────────────────┼┼────────────────────────────┼─────────────────────┘
                            ││                            │
                            ▼▼                            │
┌───────────────────────────────────────────────────────────────────────────────┐
│                                                                               │
│                  SERVIDOR PRINCIPAL (8+ GB, Linux, 24/7)                      │
│                                                                               │
│   WiFi receptor (antena direcional) conectado à rede local do servidor       │
│   O gateway LoRa publica MQTT diretamente no Mosquitto via WiFi              │
│   As câmeras IP enviam RTSP diretamente ao Frigate via rede local            │
│                                                                               │
└───────────────────────────┬───────────────────────────────────────────────────┘
                            │
                            │ MinIO Site Replication (internet/VPN)
                            ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│                  SERVIDOR REMOTO (4-8 GB, Linux, 24/7)                        │
│                  MinIO Réplica (data lake espelhado)                          │
└───────────────────────────────────────────────────────────────────────────────┘
```

### 2.3 Gateway LoRa — Detalhes

O gateway é um ESP32 com módulo LoRa (ex: Heltec WiFi LoRa 32 ou TTGO LoRa32)
posicionado em um ponto elevado com linha de visada para a área da agrofloresta e para
a sede.

**Topologia:** Estrela simples (star). Todos os sensores ESP32 transmitem diretamente
para o gateway. Não há mesh nem multi-hop entre sensores.

**Funcionamento:**
1. Sensores ESP32 acordam do deep sleep periodicamente (ex: a cada 5 minutos).
2. Leem os sensores (temperatura, umidade, pH, luminosidade, movimento).
3. Transmitem um pacote LoRa curto (~20 bytes) com ID do nó, timestamp, e payload.
4. Voltam a dormir.
5. O gateway recebe o pacote LoRa, decodifica, e publica via MQTT (WiFi direcional)
   no Mosquitto do servidor principal.

**Conectividade:** WiFi direcional de ~1 km conectando o ponto elevado à rede local
do servidor. A antena WiFi direcional está conectada ao servidor principal.

**Energia:** Painel solar (5-10W) + bateria. O gateway precisa ficar ligado
continuamente (em modo RX), portanto consome mais energia que um nó sensor.

**Capacidade:**
- Com SF9, BW 125kHz, pacotes de 20 bytes: cada pacote leva ~200ms.
- 20 sensores enviando a cada 5 minutos = 80 pacotes/hora.
- Capacidade teórica do gateway: ~18.000 pacotes/hora (SF9).
- Utilização estimada: <1%. Suporta crescimento para centenas de sensores sem mudanças.

**Caminho de evolução:** Se a rede crescer para 50+ sensores ou se houver necessidade
de device management (OTA, ADR, chaves de segurança), migrar para LoRaWAN com
ChirpStack. A stack do servidor não muda — o ChirpStack publica no Mosquitto da mesma
forma.

---

## 3. Arquitetura de Software (Servidor Principal)

Todos os serviços rodam como containers Docker, orquestrados via Docker Compose.

### 3.1 Diagrama de Componentes

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    SERVIDOR PRINCIPAL — Docker Compose                       │
│                                                                             │
│  ╔═══════════════════════════ INGESTÃO ════════════════════════════════╗    │
│  ║                                                                     ║    │
│  ║  ┌──────────┐    ┌───────────────────────────┐    ┌──────────────┐ ║    │
│  ║  │Mosquitto │───▶│     Redpanda Connect      │───▶│ InfluxDB 3   │ ║    │
│  ║  │  :1883   │    │     (YAML pipelines)      │    │ Core :8181   │ ║    │
│  ║  └──────────┘    │                           │    │ (time-series)│ ║    │
│  ║       ▲          │ Pipeline 1: MQTT→Redpanda │    └──────────────┘ ║    │
│  ║       │ MQTT     │ Pipeline 2: Redpanda→Influx│          ▲         ║    │
│  ║  ESP32 gateway   │ Pipeline 3: MinIO→Influx  │          │         ║    │
│  ║  Frigate events  └──────────────┬────────────┘          │         ║    │
│  ║                                 │                        │         ║    │
│  ║                          ┌──────▼──────┐                 │         ║    │
│  ║                          │  Redpanda   │─────────────────┘         ║    │
│  ║                          │   :9092     │  (topics armazenam        ║    │
│  ║                          │   :8082     │   eventos com replay)     ║    │
│  ║                          └─────────────┘                           ║    │
│  ╚════════════════════════════════╪═══════════════════════════════════╝    │
│                                           │                                │
│  ╔═══════════════════════════ MÍDIA ══════╪════════════════════════════╗   │
│  ║                                        │                            ║   │
│  ║  ┌──────────────┐                      │                            ║   │
│  ║  │   Frigate    │   RTSP das câmeras   │                            ║   │
│  ║  │   :5000      │──────────────────┐   │                            ║   │
│  ║  │  - detecção  │                  │   │                            ║   │
│  ║  │    objetos   │                  ▼   │                            ║   │
│  ║  │  - clips     │           ┌──────────────┐   bucket notification  ║   │
│  ║  │  - snapshots │──────────▶│    MinIO      │──────────────────────▶║   │
│  ║  │  - MQTT pub  │           │ :9000 / :9001 │   (evento → Redpanda) ║   │
│  ║  └──────────────┘           │  (Data Lake)   │                      ║   │
│  ║                             └───────┬────────┘                      ║   │
│  ║                                     │                               ║   │
│  ║                                     │ Site Replication              ║   │
│  ║                                     ▼                               ║   │
│  ║                           Servidor Remoto (MinIO)                   ║   │
│  ║                                                                     ║   │
│  ╚═════════════════════════════════════════════════════════════════════╝   │
│                                                                            │
│  ╔════════════════════ OBSERVABILIDADE ════════════════════════════════╗   │
│  ║                                                                     ║   │
│  ║  ┌──────────┐    ┌───────────┐    ┌───────────┐                    ║   │
│  ║  │ Grafana  │    │Prometheus │◀───│Node Export│                    ║   │
│  ║  │  :3000   │    │  :9090    │    │  :9100    │                    ║   │
│  ║  │          │    │           │◀───┤           │                    ║   │
│  ║  │Datasource│    │           │    │ cAdvisor  │                    ║   │
│  ║  │InfluxDB  │    └───────────┘    │  :8088    │                    ║   │
│  ║  │Prometheus│                     └───────────┘                    ║   │
│  ║  │          │                                                      ║   │
│  ║  │ Alerting │──▶ Telegram / Email / Webhook                       ║   │
│  ║  └──────────┘                                                      ║   │
│  ║                                                                     ║   │
│  ║  ┌──────────────┐                                                  ║   │
│  ║  │  Redpanda    │  (UI para debug de topics e mensagens)           ║   │
│  ║  │  Console     │                                                  ║   │
│  ║  │  :8080       │                                                  ║   │
│  ║  └──────────────┘                                                  ║   │
│  ║                                                                     ║   │
│  ╚═════════════════════════════════════════════════════════════════════╝   │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Serviços Docker — Inventário Completo

| # | Serviço | Imagem Docker | RAM Est. | Portas | Papel |
|---|---------|---------------|----------|--------|-------|
| 1 | **Mosquitto** | `eclipse-mosquitto:2` | ~10 MB | 1883, 9001 | Broker MQTT. Ponto de entrada para todos os dados de sensores e eventos Frigate. |
| 2 | **Redpanda** | `redpandadata/redpanda:latest` | ~1.5 GB | 9092, 8082, 9644 | Streaming central (Kafka API compatible). Barramento de eventos que desacopla produtores de consumidores. Armazena eventos com replay. |
| 3 | **Redpanda Console** | `redpandadata/console:latest` | ~100 MB | 8080 | UI web para inspecionar topics, consumer groups, mensagens. Ferramenta de debug e operação. |
| 4 | **Redpanda Connect** | `redpandadata/connect:latest` | ~50 MB | — | Pipelines declarativos (YAML). Faz o papel de bridge MQTT→Redpanda (substitui Telegraf) e também consome topics do Redpanda para gravar no InfluxDB 3. Roda múltiplos pipelines: ingestão MQTT, processamento de eventos MinIO, e escrita no InfluxDB. |
| 5 | **InfluxDB 3 Core** | `influxdb:3-core` | ~500 MB | 8181 | Banco de dados time-series. Armazena métricas de sensores (dados quentes), metadados de mídia (links para objetos no MinIO) e eventos do Frigate. Motor baseado em Apache Arrow + DataFusion + Parquet. Query via SQL. |
| 6 | **MinIO** | `minio/minio:latest` | ~300 MB | 9000, 9001 | Object storage (Data Lake). Armazena fotos, vídeos, clips, snapshots, exports e backups. S3-compatible. Bucket notifications disparam eventos no Redpanda quando objetos são criados/deletados. |
| 7 | **Frigate** | `ghcr.io/blakeblackshear/frigate:stable` | ~800 MB–1 GB | 5000, 8554, 8555 | NVR inteligente. Consome streams RTSP das câmeras IP, faz detecção de movimento e objetos (pessoas, animais, veículos). Salva clips e snapshots diretamente no MinIO. Publica eventos de detecção via MQTT no Mosquitto. |
| 8 | **Grafana** | `grafana/grafana-oss:latest` | ~200 MB | 3000 | Dashboard e alertas. Datasources: InfluxDB 3 (SQL) e Prometheus. Exibe métricas de sensores, timeline de mídia com links para o MinIO, e saúde da infraestrutura. Alerting envia notificações via Telegram, email ou webhook. |
| 9 | **Prometheus** | `prom/prometheus:latest` | ~200 MB | 9090 | Monitoramento da infraestrutura. Coleta métricas dos containers (via cAdvisor) e da máquina host (via Node Exporter). Não armazena dados de negócio — apenas saúde do sistema. |
| 10 | **cAdvisor** | `gcr.io/cadvisor/cadvisor:latest` | ~50 MB | 8088 | Exporta métricas de resource usage dos containers Docker (CPU, RAM, rede, disco) para o Prometheus. |
| 11 | **Node Exporter** | `prom/node-exporter:latest` | ~20 MB | 9100 | Exporta métricas da máquina host (CPU, RAM, disco, temperatura, rede) para o Prometheus. |

**RAM total estimada: ~3.7–4.4 GB** (de 8 GB disponíveis → margem de ~3.6–4.3 GB).

---

## 4. Fluxos de Dados

### 4.1 Fluxo 1 — Sensores (dados leves, tempo real)

Dados pequenos e frequentes: temperatura, umidade, pH do solo, luminosidade, movimento.

```
ESP32 (campo)
    │
    │ LoRa (pacote ~20 bytes: node_id, timestamp, tipo, valor)
    ▼
Gateway LoRa (ponto elevado)
    │
    │ WiFi direcional → MQTT publish
    │ Topic: sensors/{node_id}/{tipo}
    │ Payload: JSON {"node_id": "n01", "type": "temp", "value": 28.5, "ts": 1709827200}
    ▼
Mosquitto (:1883)
    │
    │ Subscrito por Redpanda Connect (input: mqtt)
    ▼
Redpanda Connect (pipeline: mqtt-to-redpanda)
    │
    │ Consome MQTT, transforma e publica em Kafka topic
    │ Topic: sensors.telemetry
    ▼
Redpanda (:9092)
    │
    │ Consumido por Redpanda Connect (pipeline: sensors-to-influx)
    ▼
Redpanda Connect (pipeline: sensors-to-influx)
    │
    │ Pipeline YAML: mapping → InfluxDB line protocol
    │ POST http://influxdb:8181/api/v2/write
    ▼
InfluxDB 3 Core (:8181)
    │
    │ Measurement: sensor_readings
    │ Tags: node_id, sensor_type, location
    │ Fields: value
    │ Retenção: 30 dias bruto, 1 ano downsampled
    ▼
Grafana (:3000)
    Dashboard de sensores em tempo real
    Alertas: ex. "umidade do solo < 30% → notificar Telegram"
```

### 4.2 Fluxo 2 — Mídia (dados pesados, câmeras)

Vídeos, clips de detecção, snapshots de câmeras IP.

```
Câmera IP (RTSP stream)
    │
    │ RTSP contínuo via rede local
    ▼
Frigate (:5000)
    │
    ├──▶ Detecção de objetos (pessoas, animais, veículos)
    │    Se detectado:
    │    ├── Salva clip de vídeo → MinIO (bucket: media/clips/)
    │    ├── Salva snapshot → MinIO (bucket: media/snapshots/)
    │    └── Publica evento MQTT → Mosquitto
    │         Topic: frigate/events
    │         Payload: {"type": "person", "camera": "cam01", "score": 0.92, ...}
    │
    │    O evento MQTT segue o mesmo caminho do Fluxo 1:
    │    Mosquitto → Redpanda Connect → Redpanda → Redpanda Connect → InfluxDB
    │    (grava metadado do evento com link para o clip/snapshot no MinIO)
    │
    └──▶ Gravação contínua (opcional, consome muito disco)
         → MinIO (bucket: media/recordings/)
```

### 4.3 Fluxo 3 — Eventos MinIO (bucket notifications)

Quando qualquer objeto é adicionado ao MinIO (por Frigate, por upload manual, ou por
scripts do RPi), o MinIO notifica o Redpanda.

```
Objeto criado no MinIO (upload de foto, vídeo, export, backup)
    │
    │ Bucket Notification (configurado por bucket)
    │ Target: Redpanda topic "minio.events"
    ▼
Redpanda (:9092)
    │
    │ Topic: minio.events
    │ Payload: JSON com bucket, key, size, content-type, etag, timestamp
    ▼
Redpanda Connect
    │
    │ Pipeline YAML: extrai metadados, gera link presigned (ou path),
    │ formata como InfluxDB line protocol
    ▼
InfluxDB 3 Core
    │
    │ Measurement: media_objects
    │ Tags: bucket, content_type, source (frigate/manual/script)
    │ Fields: object_key, size_bytes, presigned_url
    │ Retenção: indefinida (metadados são leves)
    ▼
Grafana
    Timeline de mídia com links clicáveis para MinIO
    Ao clicar: abre a foto/vídeo direto do MinIO via presigned URL
```

### 4.4 Fluxo 4 — Alertas

```
Grafana Alerting
    │
    │ Avalia regras periodicamente sobre dados do InfluxDB:
    │   - Umidade do solo < limiar → alerta irrigação
    │   - Temperatura fora do range → alerta geada/calor
    │   - Detecção de pessoa em horário suspeito → alerta segurança
    │   - Sensor offline por > 30 min → alerta manutenção
    │   - Disco do servidor > 85% → alerta infraestrutura
    │
    ▼
Canais de notificação:
    - Telegram (bot)
    - Email
    - Webhook (para automações futuras)
```

### 4.5 Fluxo 5 — Replicação Geográfica do Data Lake

```
MinIO (Servidor Principal)
    │
    │ Site Replication (bidirecional, nativo do MinIO)
    │ Sincroniza: buckets, objetos, políticas, IAM
    │ Via internet/VPN entre os dois locais
    │
    ▼
MinIO (Servidor Remoto, 4-8 GB)
    │
    │ Réplica completa do data lake
    │ Funciona como backup geográfico
    │ Em caso de falha do principal, pode ser promovido
```

### 4.6 Fluxo 6 — Monitoramento da Infraestrutura

```
Prometheus (:9090)
    │
    ├── Scrape: Node Exporter (:9100) — métricas do host
    │   CPU, RAM, disco, temperatura, rede, uptime
    │
    ├── Scrape: cAdvisor (:8088) — métricas dos containers
    │   CPU, RAM, rede, I/O por container
    │
    ├── Scrape: Redpanda (:9644/metrics) — métricas do broker
    │   Topics, partições, consumer lag, throughput
    │
    ├── Scrape: MinIO (:9000/minio/v2/metrics/cluster) — métricas do storage
    │   Espaço usado, objetos, requisições, replicação
    │
    └──▶ Grafana (:3000)
         Dashboard de infraestrutura
         Alertas de saúde do sistema
```

---

## 5. Política de Retenção de Dados

### 5.1 Camadas de Armazenamento

| Camada | Tipo de Dado | Retenção | Localização | Observação |
|--------|-------------|----------|-------------|------------|
| **Hot** | Dados brutos de sensores | 30 dias | InfluxDB 3 Core | Alta resolução, queries rápidas |
| **Warm** | Dados downsampled (médias horárias/diárias) | 1 ano | InfluxDB 3 Core | Agregações para tendências de longo prazo |
| **Cold** | Mídia (fotos, vídeos, clips) | Indefinido | MinIO (principal + réplica) | Custo de armazenamento = custo do disco |
| **Cold** | Exports periódicos do InfluxDB | Indefinido | MinIO | Backup dos dados de sensores em Parquet/CSV |
| **Archive** | Tudo sincronizado | Indefinido | MinIO (servidor remoto) | Resiliência geográfica |

### 5.2 Downsample Job

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

## 6. Topics Redpanda

| Topic | Produtor | Consumidor | Conteúdo |
|-------|----------|------------|----------|
| `sensors.telemetry` | Redpanda Connect (via MQTT bridge) | Redpanda Connect | Leituras de sensores (temp, umid, pH, lux, etc.) |
| `frigate.events` | Redpanda Connect (via MQTT bridge) | Redpanda Connect | Eventos de detecção do Frigate (pessoa, animal, veículo) |
| `minio.events` | MinIO (bucket notification) | Redpanda Connect | Notificações de criação/deleção de objetos no MinIO |
| `alerts.raw` | (futuro) | (futuro) | Eventos de alerta para processamento adicional |

---

## 7. Buckets MinIO

| Bucket | Conteúdo | Retenção | Replicado |
|--------|----------|----------|-----------|
| `media/clips/` | Clips de vídeo gerados pelo Frigate | Indefinido | Sim |
| `media/snapshots/` | Snapshots de detecção do Frigate | Indefinido | Sim |
| `media/recordings/` | Gravação contínua das câmeras (opcional) | Configurável (ex: 30 dias) | Sim |
| `media/uploads/` | Fotos/vídeos enviados manualmente ou por scripts | Indefinido | Sim |
| `exports/` | Exports periódicos do InfluxDB (Parquet, CSV) | Indefinido | Sim |
| `backups/` | Backups de configuração, dumps, etc. | Indefinido | Sim |

---

## 8. Measurements InfluxDB

| Measurement | Tags | Fields | Fonte | Retenção |
|-------------|------|--------|-------|----------|
| `sensor_readings` | `node_id`, `sensor_type`, `location` | `value` (float) | Redpanda Connect ← sensores | 30 dias (bruto) |
| `sensor_readings_hourly` | `node_id`, `sensor_type`, `location` | `avg`, `min`, `max`, `count` | Downsample job | 1 ano |
| `sensor_readings_daily` | `node_id`, `sensor_type`, `location` | `avg`, `min`, `max`, `count` | Downsample job | 1 ano |
| `frigate_events` | `camera`, `label`, `zone` | `score`, `duration`, `clip_url`, `snapshot_url` | Redpanda Connect ← Frigate | Indefinido |
| `media_objects` | `bucket`, `content_type`, `source` | `object_key`, `size_bytes`, `url` | Redpanda Connect ← MinIO events | Indefinido |

---

## 9. Grafana — Datasources e Dashboards

### 9.1 Datasources (provisionados automaticamente)

| Datasource | Tipo | URL | Uso |
|------------|------|-----|-----|
| InfluxDB 3 | InfluxDB (SQL/Flight) | `http://influxdb:8181` | Dados de sensores, eventos, metadados de mídia |
| Prometheus | Prometheus | `http://prometheus:9090` | Métricas de infraestrutura |

### 9.2 Dashboards Planejados

| Dashboard | Conteúdo |
|-----------|----------|
| **Sensores — Tempo Real** | Gráficos de temperatura, umidade, pH, luminosidade por nó. Mapa de calor da propriedade. |
| **Sensores — Tendências** | Dados downsampled. Comparação semanal/mensal. Sazonalidade. |
| **Segurança / Câmeras** | Timeline de eventos Frigate. Snapshots inline. Links para clips no MinIO. |
| **Mídia — Navegador** | Lista de objetos no MinIO com filtros. Links clicáveis para fotos/vídeos. |
| **Infraestrutura** | CPU, RAM, disco, rede do servidor. Status dos containers. Consumer lag do Redpanda. Espaço do MinIO. |
| **Alertas** | Histórico de alertas disparados. Status atual de cada regra. |

### 9.3 Alerting — Regras Planejadas

| Regra | Condição | Canal | Prioridade |
|-------|----------|-------|-----------|
| Umidade do solo baixa | `sensor_type = 'soil_moisture' AND value < 30` por > 15min | Telegram | Alta |
| Temperatura extrema | `sensor_type = 'temperature' AND (value < 2 OR value > 42)` | Telegram | Alta |
| Detecção de pessoa (noite) | Evento Frigate `label = 'person'` entre 22h-06h | Telegram | Alta |
| Sensor offline | Nenhuma leitura de um `node_id` por > 30min | Email | Média |
| Disco do servidor > 85% | Prometheus: `node_filesystem_avail_bytes` | Telegram | Alta |
| Container reiniciando | Prometheus: `rate(container_restart_count)` > 0 | Email | Média |
| Replicação MinIO atrasada | MinIO metrics: replication lag | Email | Média |

---

## 10. Segurança

### 10.1 Rede

- **Fase inicial:** Todos os serviços expostos apenas na rede local. Sem acesso
  externo.
- **Fase futura:** Reverse proxy (Traefik ou Caddy) com HTTPS e autenticação para
  acesso remoto ao Grafana e MinIO Console. VPN (WireGuard) para acesso seguro à
  rede interna.

### 10.2 Autenticação

| Serviço | Autenticação |
|---------|-------------|
| Mosquitto | Username/password (arquivo `password_file`) |
| Redpanda | SASL/SCRAM (quando exposto externamente) |
| InfluxDB 3 | Token-based |
| MinIO | Access key / Secret key (S3 API) |
| Grafana | Login local (admin + usuários) |
| Frigate | (sem auth nativo, proteger via rede/proxy) |

### 10.3 Credenciais

Todas as credenciais são gerenciadas via arquivo `.env` no Docker Compose.
O `.env` **não** é versionado no Git (adicionado ao `.gitignore`).
Um arquivo `.env.example` com valores placeholder é versionado como referência.

---

## 11. Estrutura de Diretórios do Projeto

> **Repositório:** [github.com/irigon/farm-monitoring](https://github.com/irigon/farm-monitoring)

```
farm-monitoring/                        # Raiz do repositório
├── README.md
├── docs/
│   └── architecture.md                 # Este documento
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

---

## 12. Fases de Implementação

### Fase 1 — Core Pipeline (Prioridade máxima) ✓ IMPLEMENTADO

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

### Fase 2 — Data Lake ✓ IMPLEMENTADO

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

### Fase 3 — Câmeras e Detecção

| Passo | Componente | Descrição |
|-------|-----------|-----------|
| 3.1 | Frigate | Configurar câmeras RTSP, detecção de objetos |
| 3.2 | Frigate → MinIO | Clips e snapshots salvos diretamente no MinIO |
| 3.3 | Frigate → MQTT | Eventos de detecção publicados no Mosquitto |
| 3.4 | Redpanda Connect | Pipeline `frigate.events` → InfluxDB |
| 3.5 | Teste | Simular detecção → verificar clip no MinIO e evento no InfluxDB |

### Fase 4 — Observabilidade ✓ IMPLEMENTADO

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

### Fase 5 — Edge Devices

| Passo | Componente | Descrição |
|-------|-----------|-----------|
| 5.1 | Firmware ESP32 sensor | Deep sleep + leitura + LoRa TX |
| 5.2 | Firmware ESP32 gateway | LoRa RX + MQTT publish (WiFi) |
| 5.3 | Hardware gateway | Montagem no ponto elevado + solar + antena direcional |
| 5.4 | Teste campo | Verificar leituras dos sensores chegando ao InfluxDB/Grafana |

### Fase 6 — Replicação Geográfica

| Passo | Componente | Descrição |
|-------|-----------|-----------|
| 6.1 | MinIO remoto | Docker Compose no servidor remoto |
| 6.2 | Site Replication | Configurar replicação bidirecional entre os dois MinIO |
| 6.3 | Conectividade | VPN ou conexão segura entre os dois locais |
| 6.4 | Teste | Upload no principal → verificar réplica no remoto |

### Fase 7 — Retenção e Manutenção

| Passo | Componente | Descrição |
|-------|-----------|-----------|
| 7.1 | Downsample job | Script + cron para agregar dados antigos |
| 7.2 | Export job | Backup periódico do InfluxDB para MinIO (Parquet) |
| 7.3 | Políticas de retenção | Configurar TTL no InfluxDB, lifecycle rules no MinIO |
| 7.4 | Backup de configs | Script para backup de docker-compose, configs, dashboards |

### Fase 8 — Hardening (Futuro)

| Passo | Componente | Descrição |
|-------|-----------|-----------|
| 8.1 | Reverse proxy | Traefik ou Caddy com HTTPS para acesso remoto |
| 8.2 | VPN | WireGuard para acesso seguro à rede interna |
| 8.3 | Monitoramento do monitoramento | Alertas se Prometheus/Grafana caírem |
| 8.4 | Documentação operacional | Runbooks para troubleshooting e manutenção |

---

## 13. Estimativa de Consumo de Recursos (Servidor Principal)

### 13.1 RAM

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

### 13.2 Disco

| Dado | Crescimento Estimado | Observação |
|------|---------------------|------------|
| Sensores (InfluxDB) | ~1-5 MB/dia (20 sensores @ 5min) | Muito baixo |
| Frigate clips | ~100-500 MB/dia (depende de atividade) | Principal consumidor |
| Frigate recordings | ~5-20 GB/dia por câmera (se contínuo) | Opcional; requer disco grande |
| Snapshots | ~10-50 MB/dia | Baixo |
| Prometheus | ~50-100 MB/dia | 15 dias retenção padrão |

**Recomendação:** SSD de 256-512 GB para o sistema + HDD de 1-2 TB (ou mais) para o
MinIO (mídia). Se possível, separar os discos.

### 13.3 Rede

| Fluxo | Banda Estimada | Observação |
|-------|---------------|------------|
| Sensores (MQTT) | < 1 Kbps | Negligível |
| Câmeras (RTSP → Frigate) | 2-8 Mbps por câmera | Principal consumidor de rede interna |
| MinIO replicação | Depende do upload (assíncrono) | Comprime e sincroniza em background |
| Grafana (browser) | < 1 Mbps | Sob demanda |

---

## 14. Decisões Técnicas e Justificativas

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

## 15. Riscos e Mitigações

| Risco | Impacto | Mitigação |
|-------|---------|-----------|
| Servidor 8 GB com pouca margem se Frigate + Redpanda + InfluxDB picos simultâneos | OOM kills, serviços reiniciando | Configurar `mem_limit` por container no Docker Compose. Monitorar via Prometheus + alertas. Planejar upgrade para 16 GB. |
| Gateway LoRa no ponto alto falha (energia, hardware) | Perda de dados de todos os sensores | Solar + bateria robusta, watchdog no firmware, alertas de "sensor offline" no Grafana. Sensores podem ter buffer local (flash) para reenviar. |
| WiFi direcional instável (chuva, vento, desalinhamento) | Perda de conectividade gateway → servidor | Antena de qualidade com suporte rígido. Link budget com margem. Monitorar latência/packet loss. |
| Disco do MinIO enche | Perda de novos dados de mídia | Alertas no Grafana quando disco > 80%. Lifecycle rules para recordings antigos. Expandir disco conforme necessário. |
| InfluxDB 3 Core é relativamente novo | Bugs, comportamentos inesperados | Backup periódico para MinIO. Comunidade ativa. Fallback: migrar para 2.x se necessário (SQL queries precisariam de ajuste). |
| Frigate sem Google Coral TPU | Alta carga de CPU para detecção | Limitar FPS de detecção (ex: 5 fps). Reduzir resolução de detecção. Planejar compra de Coral USB (~R$300). |

---

## 16. Glossário

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

## 17. Troubleshooting e Verificação do Sistema

### 17.1 Interfaces Disponíveis

| Interface | URL | Descrição |
|-----------|-----|-----------|
| **Redpanda Console** | http://localhost:8080 | UI web: topics, mensagens, consumer groups, cluster health |
| **Redpanda Connect API** | http://localhost:4195 | API HTTP: streams ativos, métricas, health |
| **InfluxDB API** | http://localhost:8181 | API HTTP apenas (sem UI web). Queries via curl |
| **Redpanda Admin API** | http://localhost:9644 | Métricas Prometheus, cluster status |
| **Mosquitto** | localhost:1883 | Broker MQTT (pub/sub via CLI) |
| **Redpanda Kafka API** | localhost:19092 | Acesso externo à Kafka API (ferramentas, debug) |

### 17.2 Verificar Status dos Serviços

```bash
# Status geral de todos os containers
docker-compose ps

# Logs de um serviço específico (últimas 30 linhas)
docker-compose logs --tail 30 <serviço>

# Logs em tempo real (follow)
docker-compose logs -f <serviço>

# Logs de todos os serviços
docker-compose logs --tail 50

# Healthcheck individual
docker inspect --format='{{.State.Health.Status}}' redpanda
docker inspect --format='{{.State.Health.Status}}' influxdb
```

### 17.3 Redpanda Console (http://localhost:8080)

A interface principal para debug de mensagens e topics.

- **Topics**: lista todos os topics (`sensors.telemetry`, `frigate.events`, `minio.events`)
- Clique em um topic → visualize mensagens com payload JSON, headers, offset e timestamp
- **Consumer Groups**: verifique o grupo `influx-sensor-writer` e se há lag (mensagens não consumidas)

> **Nota:** Se aparecer "issues deserializing the value", mude o dropdown
> **Value Deserializer** de "Auto" para "JSON" no topo da visualização de mensagens.
> As variáveis `KAFKA_PROTOBUF_ENABLED=false` e `KAFKA_MSGPACK_ENABLED=false` no
> docker-compose já minimizam esse problema.

> **Nota sobre Enterprise Trial:** O Redpanda exibe "Enterprise Trial" na interface.
> Isso é normal — o Redpanda Community Edition é gratuito e open source. Quando o trial
> expirar, apenas features enterprise (Shadow Indexing, Cluster Links) são desabilitadas.
> Tudo que usamos (Kafka API, topics, consumers, Schema Registry) continua funcionando.

### 17.4 Redpanda Connect API (http://localhost:4195)

```bash
# Verificar se o serviço está pronto
curl -s http://localhost:4195/ready
# Esperado: OK

# Listar streams ativos e uptime
curl -s http://localhost:4195/streams | python3 -m json.tool
# Esperado:
# {
#   "mqtt-to-redpanda": { "active": true, "uptime": ... },
#   "sensors-to-influx": { "active": true, "uptime": ... }
# }

# Métricas no formato Prometheus (mensagens processadas, erros, latência)
curl -s http://localhost:4195/metrics | grep -E 'input_received|output_sent|processor_error'
```

**Se um stream não aparece ou está `active: false`:**
1. Verifique os logs: `docker-compose logs --tail 30 redpanda-connect`
2. Erros de lint no YAML aparecem como warnings (graças ao `--chilled`), mas o stream não inicia
3. Erros de conexão (MQTT auth, Redpanda unreachable) geram retries com backoff

### 17.5 InfluxDB API (http://localhost:8181)

O InfluxDB 3 Core **não tem interface web**. Toda interação é via API HTTP.

```bash
# Health check
curl -s http://localhost:8181/health
# Esperado: OK

# Listar databases
curl -s 'http://localhost:8181/api/v3/configure/database' \
  -G --data-urlencode 'format=json'

# Consultar dados (SQL) — IMPORTANTE: sempre incluir format=json
curl -s 'http://localhost:8181/api/v3/query_sql' \
  -G \
  --data-urlencode 'db=farm' \
  --data-urlencode 'q=SELECT * FROM sensor_readings ORDER BY time DESC LIMIT 10' \
  --data-urlencode 'format=json' \
  | python3 -m json.tool

# Contar registros
curl -s 'http://localhost:8181/api/v3/query_sql' \
  -G \
  --data-urlencode 'db=farm' \
  --data-urlencode 'q=SELECT COUNT(*) FROM sensor_readings' \
  --data-urlencode 'format=json'

# Listar measurements (tabelas)
curl -s 'http://localhost:8181/api/v3/query_sql' \
  -G \
  --data-urlencode 'db=farm' \
  --data-urlencode "q=SHOW TABLES" \
  --data-urlencode 'format=json'
```

> **Erro comum:** `serde error: missing field 'format'` — adicione `format=json` em
> todas as chamadas à API v3.

> **Nota:** Em modo dev (--without-auth), nenhum token é necessário. Em produção,
> adicione o header: `Authorization: Bearer <token>`

### 17.6 Redpanda — Topics e Mensagens via CLI

```bash
# Listar topics
docker exec redpanda rpk topic list --brokers localhost:9092

# Consumir mensagens em tempo real (Ctrl+C para sair)
docker exec redpanda rpk topic consume sensors.telemetry --brokers localhost:9092

# Consumir apenas N mensagens
docker exec redpanda rpk topic consume sensors.telemetry --brokers localhost:9092 --num 3

# Detalhes de um topic (partições, offsets, replicas)
docker exec redpanda rpk topic describe sensors.telemetry --brokers localhost:9092

# Consumer groups — verificar lag
docker exec redpanda rpk group describe influx-sensor-writer --brokers localhost:9092
```

### 17.7 Mosquitto — Testar MQTT

```bash
# Publicar mensagem de teste
docker run --rm --network farm-monitoring_monitoring eclipse-mosquitto:2 \
  mosquitto_pub -h mosquitto -p 1883 \
  -u mqtt_user -P '<MQTT_PASSWORD>' \
  -t 'sensors/n01/temp' \
  -m '{"node_id":"n01","type":"temp","value":25.3,"ts":'$(date +%s)'}'

# Subscrever a um topic (tempo real, Ctrl+C para sair)
docker run --rm --network farm-monitoring_monitoring eclipse-mosquitto:2 \
  mosquitto_sub -h mosquitto -p 1883 \
  -u mqtt_user -P '<MQTT_PASSWORD>' \
  -t 'sensors/#'
```

### 17.8 Teste End-to-End (Checklist)

Validação completa do pipeline `MQTT → Redpanda → InfluxDB`:

```bash
# 1. Publicar mensagem MQTT
docker run --rm --network farm-monitoring_monitoring eclipse-mosquitto:2 \
  mosquitto_pub -h mosquitto -p 1883 \
  -u mqtt_user -P '<MQTT_PASSWORD>' \
  -t 'sensors/test/humidity' \
  -m '{"node_id":"test","type":"humidity","value":65.2,"ts":'$(date +%s)'}'

# 2. Verificar no Redpanda Console (http://localhost:8080)
#    → Topic sensors.telemetry deve mostrar a mensagem

# 3. Ou verificar via CLI
docker exec redpanda rpk topic consume sensors.telemetry \
  --brokers localhost:9092 --num 1

# 4. Aguardar batching (até 1s) e consultar InfluxDB
sleep 2
curl -s 'http://localhost:8181/api/v3/query_sql' \
  -G \
  --data-urlencode 'db=farm' \
  --data-urlencode 'q=SELECT * FROM sensor_readings ORDER BY time DESC LIMIT 3' \
  --data-urlencode 'format=json' \
  | python3 -m json.tool
```

Se os 3 passos retornam dados, o pipeline está saudável.

### 17.9 Problemas Comuns

| Sintoma | Causa Provável | Solução |
|---------|---------------|---------|
| InfluxDB healthcheck falha | Auth habilitado sem token | Adicionar `--without-auth` (dev) ou configurar token |
| Redpanda Connect crash loop | Lint error no YAML dos pipelines | Verificar logs; `--chilled` previne crash mas stream não inicia |
| MQTT "not Authorized" | Senha no `.env` diferente do `password_file` | Regenerar: `docker run --rm -v ./config/mosquitto:/mosquitto/config eclipse-mosquitto:2 mosquitto_passwd -b -c /mosquitto/config/password_file <user> <password>` |
| Mensagens não chegam ao InfluxDB | Redpanda Connect não conectou ao MQTT ou Redpanda | Verificar `curl localhost:4195/streams` — stream deve estar `active: true` |
| `serde error: missing field 'format'` no curl | Falta `format=json` na query InfluxDB v3 | Adicionar `--data-urlencode 'format=json'` |
| "Issues deserializing value" no Console | Console tentando Protobuf/MsgPack em payloads JSON | Usar dropdown "JSON" ou verificar env vars no docker-compose |
| Database não encontrada no InfluxDB | Setup script não criou o database | `curl -X POST http://localhost:8181/api/v3/configure/database -H 'Content-Type: application/json' -d '{"db":"farm"}'` |
| Porta não acessível (Connection refused) | Porta não mapeada no docker-compose | Verificar seção `ports:` do serviço no docker-compose.yml |

### 17.10 Phase 4 — Observability Stack

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

### 17.11 Phase 2 — Data Lake (MinIO)

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
