# 4. Arquitetura — Como funciona

Este documento descreve **como o sistema funciona por dentro**: a infraestrutura
física (hardware e rede), a arquitetura de software (containers no servidor) e a
estrutura de diretórios do repositório.

## 4.1 Infraestrutura física

### Inventário de hardware

| Máquina | Specs | Localização | Papel |
|---|---|---|---|
| **Servidor Principal** | 8+ GB RAM, Linux, headless | Sede da propriedade | Hub central — todos os serviços core rodam aqui 24/7 |
| **Servidor Remoto** | 4–8 GB RAM, Linux, headless | Local geográfico remoto | Réplica do Data Lake (MinIO) para resiliência geográfica |
| **Notebook** | 32 GB RAM, Linux | Sede (uso ocasional) | Estação de trabalho: dashboards, desenvolvimento de configs/scripts, análise offline |
| **Gateway LoRa** | ESP32 + módulo LoRa + antena WiFi direcional | Ponto elevado (~1 km da sede) | Recebe dados LoRa dos sensores e retransmite via WiFi para o servidor |
| **Sensores ESP32** | ESP32 + LoRa + sensores + painel solar + bateria | Espalhados pela agrofloresta | Coletam dados e transmitem via LoRa para o gateway |
| **Câmeras IP** | Câmeras com RTSP (ONVIF ou proprietárias) | Pontos estratégicos | Stream de vídeo contínuo via RTSP para o servidor |
| **Raspberry Pi 3** | 1 GB RAM, ARM | Reserva / uso futuro | Segundo gateway, nó de teste ou ponto de coleta auxiliar |

> O hardware de campo (sensores ESP32 e gateway LoRa) e o servidor remoto de réplica
> **ainda não fazem parte do repositório** — os diretórios `edge/` e `remote/` são
> placeholders. Esta seção descreve a topologia física prevista; o que o servidor já
> faz com os dados recebidos está em [Fluxos de Dados](05-data-flows.md).

### Topologia de rede

```
┌────────────────────────── Agrofloresta (Campo) ──────────────────────────────┐
│                                                                               │
│   [ESP32+LoRa]  [ESP32+LoRa]  [ESP32+LoRa]   ...  [ESP32+LoRa]              │
│   sensor temp    sensor pH     sensor mov           sensor umid              │
│        │              │             │                    │                    │
│        └──── LoRa ────┴───── LoRa ──┴──── LoRa ─────────┘                    │
│                              ▼                                                │
│                   ┌────────────────────┐                                      │
│                   │  Gateway LoRa      │  ESP32 + LoRa RX + WiFi direcional   │
│                   │  (Ponto Elevado)   │  Solar + bateria                     │
│                   └────────┬───────────┘                                      │
│                            │ MQTT via WiFi direcional (~1 km)                 │
└────────────────────────────┼──────────────────────────────────────────────────┘
                             │
┌────────────────────────────┼──────────── Sede da propriedade (rede local) ────┐
│                            ▼                                                   │
│   [Cam IP 1] ──RTSP──┐                                                         │
│   [Cam IP 2] ──RTSP──┤  (RTSP pela rede local — não cruza o link WiFi)         │
│                      ▼                                                         │
│   ┌───────────────────────────────────────────────────────────────────────┐  │
│   │            SERVIDOR PRINCIPAL (8+ GB, Linux, 24/7)                      │  │
│   │  • Gateway LoRa publica MQTT no Mosquitto (via WiFi direcional).        │  │
│   │  • Câmeras IP enviam RTSP ao Frigate (rede local da sede).              │  │
│   └───────────────────────────────────┬───────────────────────────────────┘  │
└───────────────────────────────────────┼──────────────────────────────────────┘
                                         │ MinIO Site Replication (internet/VPN)
                                         ▼
┌───────────────────────────── Local geográfico remoto ────────────────────────┐
│         SERVIDOR REMOTO (4–8 GB, Linux, 24/7) — MinIO Réplica                  │
└───────────────────────────────────────────────────────────────────────────────┘
```

### Gateway LoRa

O gateway é um ESP32 com módulo LoRa (ex.: Heltec WiFi LoRa 32 ou TTGO LoRa32) num
ponto elevado com linha de visada para a agrofloresta e para a sede.

- **Topologia:** estrela simples — todos os sensores transmitem direto para o gateway,
  sem mesh nem multi-hop.
- **Funcionamento:** os sensores acordam do *deep sleep* periodicamente (ex.: a cada
  5 min), leem os valores, transmitem um pacote LoRa curto (~20 bytes) e voltam a
  dormir. O gateway recebe o pacote, decodifica e publica via MQTT no Mosquitto.
- **Conectividade:** WiFi direcional de ~1 km ligando o ponto elevado à rede do servidor.
- **Energia:** painel solar (5–10 W) + bateria; o gateway fica sempre ligado (modo RX).
- **Capacidade:** com SF9/BW125kHz e pacotes de 20 bytes, a utilização estimada é <1%
  — suporta crescer para centenas de sensores sem mudanças.
- **Evolução:** se a rede crescer para 50+ sensores ou precisar de *device management*,
  migrar para LoRaWAN com ChirpStack. **A stack do servidor não muda** — o ChirpStack
  publica no Mosquitto da mesma forma.

## 4.2 Arquitetura de software (servidor principal)

Todos os serviços rodam como containers Docker, orquestrados via Docker Compose.

### Diagrama de componentes

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    SERVIDOR PRINCIPAL — Docker Compose                        │
│                                                                               │
│  ╔═══════════════════════ INGESTÃO ══════════════════════════════════════╗   │
│  ║  ┌──────────┐    ┌───────────────────────────┐    ┌──────────────┐    ║   │
│  ║  │Mosquitto │───▶│     Redpanda Connect      │───▶│ InfluxDB 3   │    ║   │
│  ║  │  :1883   │    │     (YAML pipelines)      │    │ Core :8181   │    ║   │
│  ║  └──────────┘    └──────────────┬────────────┘    └──────────────┘    ║   │
│  ║       ▲                         │                        ▲            ║   │
│  ║  gateway LoRa            ┌───────▼─────┐                  │            ║   │
│  ║  Frigate events         │  Redpanda   │──────────────────┘            ║   │
│  ║                         │   :9092     │  (topics com replay)          ║   │
│  ║                         └─────────────┘                               ║   │
│  ╚═══════════════════════════════════════════════════════════════════════╝   │
│  ╔═══════════════════════ MÍDIA ═══════════════════════════════════════════╗ │
│  ║  ┌──────────────┐    RTSP     ┌──────────────┐  bucket notification     ║ │
│  ║  │   Frigate    │────────────▶│    MinIO     │────────────▶ Redpanda    ║ │
│  ║  │   :5000      │  clips/     │ :9000/:9001  │                          ║ │
│  ║  │  detecção,   │  snapshots  │  (Data Lake) │──── Site Replication ───▶║ │
│  ║  │  MQTT pub    │             └──────────────┘     (Servidor Remoto)    ║ │
│  ║  └──────────────┘                                                       ║ │
│  ╚═══════════════════════════════════════════════════════════════════════╝ │
│  ╔══════════════════════ OBSERVABILIDADE ═════════════════════════════════╗ │
│  ║  ┌──────────┐    ┌───────────┐    ┌────────────┐    ┌──────────────┐    ║ │
│  ║  │ Grafana  │◀───│Prometheus │◀───│Node Export │    │   Redpanda   │    ║ │
│  ║  │  :3000   │    │  :9090    │◀───│ cAdvisor   │    │   Console    │    ║ │
│  ║  └──────────┘    └───────────┘    └────────────┘    │   :8080      │    ║ │
│  ║                                                     └──────────────┘    ║ │
│  ╚═══════════════════════════════════════════════════════════════════════╝ │
└───────────────────────────────────────────────────────────────────────────────┘
```

### Inventário de serviços Docker

| # | Serviço | Imagem | RAM Est. | Portas | Papel |
|---|---|---|---|---|---|
| 1 | **Mosquitto** | `eclipse-mosquitto:2` | ~10 MB | 1883 | Broker MQTT. Ponto de entrada dos dados de sensores e eventos Frigate. |
| 2 | **Redpanda** | `redpandadata/redpanda:latest` | ~1.5 GB | 19092, 18082, 18081, 9644 | Streaming central (Kafka API). Barramento de eventos com replay. Portas internas `9092`/`8082` são expostas ao host como `19092`/`18082`. |
| 3 | **Redpanda Console** | `redpandadata/console:latest` | ~100 MB | 8080 | UI para inspecionar topics, consumer groups e mensagens (debug). |
| 4 | **Redpanda Connect** | `redpandadata/connect:latest` | ~50 MB | 4195 | Pipelines declarativos (YAML): bridge MQTT→Redpanda e consumers Redpanda→InfluxDB. |
| 5 | **InfluxDB 3 Core** | `influxdb:3-core` | ~500 MB | 8181 | Banco time-series. Sensores, eventos Frigate e metadados de mídia. SQL via API HTTP. |
| 6 | **MinIO** | `minio/minio:latest` | ~300 MB | 9000, 9001 | Object storage (Data Lake). Mídia, exports e backups. Bucket notifications → Redpanda. |
| 7 | **Frigate** | `ghcr.io/blakeblackshear/frigate:stable` | ~800 MB–1 GB | 5000, 8554, 8555 | NVR inteligente. RTSP das câmeras, detecção de objetos, clips/snapshots, eventos MQTT. |
| 8 | **Grafana** | `grafana/grafana-oss:latest` | ~200 MB | 3000 | Dashboards e alertas. Datasources: InfluxDB 3 (SQL) e Prometheus. |
| 9 | **Prometheus** | `prom/prometheus:latest` | ~200 MB | 9090 | Monitoramento de infraestrutura (containers + host). |
| 10 | **cAdvisor** | `gcr.io/cadvisor/cadvisor:latest` | ~50 MB | (interno) | Métricas de resource usage dos containers → Prometheus. |
| 11 | **Node Exporter** | `prom/node-exporter:latest` | ~20 MB | 9100 | Métricas da máquina host → Prometheus. |

**RAM total estimada: ~3.7–4.4 GB** (de 8 GB → margem de ~3.6–4.3 GB). Detalhes de
consumo em [Operações](07-operations.md#71-consumo-de-recursos).

> **Nota de escopo — `kind=state`:** O inventário acima cobre `kind` de tipo `metric`,
> `detection`, `object` e `annotation`. O `kind=state` (comando/estado de **atuadores**,
> ex.: acionar irrigação) **não tem implementação nesta fase** — está deferido para
> quando houver hardware atuador integrado. O modelo canônico já o reserva (ver
> [Modelo Conceitual §0.5](00-conceptual-model.md#05-kind-o-discriminador-fixo)).

### Princípio de emissão de eventos de mídia

Sempre que um fato produz uma mídia (clip, foto, áudio), valem duas regras — fixadas
no [ADR-11](decisions.md) e no [Modelo Conceitual](00-conceptual-model.md#05-kind-o-discriminador-fixo):

- **O produtor emite apenas o evento de domínio** (`detection`/`annotation`), já com o
  `blob_ref`. O evento `object` ("um blob entrou no data lake") é gerado pelo **próprio
  MinIO** (bucket notification), não pelo dispositivo. Assim o device nunca transmite
  duas mensagens pelo mesmo fato — relevante para hardware de campo com bateria/LoRa.
- **A ligação entre os dois eventos é o `blob_ref` compartilhado.** O `object_key` é
  composto por uma **convenção de nomes** (ex.: `{tipo}/{data}/{device_id}-{ts}.{ext}`),
  nunca *hardcoded* no dispositivo; o `blob_ref` é a URI neutra `{esquema}://{bucket}/{object_key}`.

Esse princípio é o mesmo para **mídia local** (câmeras na sede, hoje) e para **mídia
remota** (celular/Raspi em campo, futuramente): muda o produtor, não a arquitetura.

## 4.3 Estrutura de diretórios do repositório

```
farm-monitoring/
├── README.md
├── docker-compose.yml          # Orquestração de todos os serviços
├── .env.example                # Template de variáveis de ambiente
├── .gitignore
│
├── docs/                       # Documentação (este diretório)
│
├── config/
│   ├── frigate/
│   │   └── config.yml          # Câmeras, detecção, gravação
│   ├── grafana/
│   │   ├── dashboards/
│   │   │   ├── infrastructure.json   # Dashboard: saúde da infraestrutura
│   │   │   └── sensors.json          # Dashboard: sensores
│   │   └── provisioning/
│   │       ├── dashboards/dashboards.yml
│   │       └── datasources/datasources.yml   # InfluxDB + Prometheus
│   ├── influxdb/               # (vazio — .gitkeep; dados em volume Docker)
│   ├── minio/                  # (vazio — .gitkeep; dados em volume Docker)
│   ├── mosquitto/
│   │   ├── mosquitto.conf       # Configuração do broker
│   │   └── password_file        # Credenciais MQTT (gerado a partir do .env)
│   ├── prometheus/
│   │   └── prometheus.yml        # Scrape targets
│   ├── redpanda/               # (vazio — .gitkeep; config via flags no compose)
│   └── redpanda-connect/
│       ├── mqtt-to-redpanda.yml   # Bridge: MQTT (sensores/frigate/anotações) → topic `events` (Evento Canônico)
│       └── events-to-influx.yml   # Consumer único: `events` + `minio.events` → measurement `events`
│
├── scripts/
│   ├── setup.sh                 # Cria topics Redpanda + database InfluxDB
│   ├── mosquitto-setup.sh       # Gera password_file a partir do .env
│   ├── minio-setup.sh           # Cria buckets + configura notificações
│   └── frigate-to-minio.sh      # Sidecar: espelha mídia do Frigate no MinIO
│
├── test-data/
│   └── video/                   # Clip de teste usado pelo Frigate (dev)
│
├── edge/                        # (vazio — .gitkeep; firmware ESP32 futuro)
│   ├── esp32-sensor/            # Firmware ESP32 sensores (LoRa TX)
│   └── esp32-gateway/           # Firmware ESP32 gateway (LoRa RX → MQTT)
│
└── remote/                      # (vazio — .gitkeep; futura réplica MinIO remota)
```

> **Nota:** `edge/` (com as subpastas `esp32-sensor/` e `esp32-gateway/`) e `remote/`
> contêm apenas `.gitkeep` no momento — reservam o lugar para o firmware dos
> dispositivos de campo e para a configuração do servidor remoto.
