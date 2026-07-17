# 2. Como Começar

Este guia leva você do zero até um sistema **rodando e validado**.

## 2.1 Pré-requisitos

- **Docker** e **Docker Compose v2** (comando `docker compose`, não o antigo
  `docker-compose`).
- **Linux** (servidor headless recomendado). Também funciona em macOS com Docker
  Desktop para desenvolvimento — com uma ressalva: o Node Exporter reporta métricas
  da VM Linux do Docker, não do host real.
- **8+ GB de RAM** (o sistema usa ~4–4,7 GB; veja [Operações](07-operations.md#71-consumo-de-recursos)).
- Espaço em disco: um SSD para o sistema e, idealmente, um disco maior para a mídia
  do MinIO.

## 2.2 Setup

```bash
# 1. Copie o template de variáveis de ambiente
cp .env.example .env

# 2. Edite o .env e defina credenciais reais (troque todos os "change_me")
#    Veja a seção 2.4 para o que cada variável faz.

# 3. Suba todos os serviços
docker compose up -d
```

Ao subir, alguns serviços *one-shot* rodam automaticamente **antes** dos serviços
principais, preparando o ambiente:

- **`mosquitto-setup`** — gera o `config/mosquitto/password_file` a partir das
  credenciais MQTT do `.env`. Você **não** precisa criá-lo à mão.
- **`setup`** — cria os *topics* do Redpanda e o *database* do InfluxDB.
- **`minio-setup`** — cria os *buckets* do MinIO e configura as notificações.

> Se você alterar as credenciais MQTT no `.env` depois, recrie o broker:
> ```bash
> docker compose up -d --force-recreate mosquitto-setup mosquitto
> ```

## 2.3 Variáveis de ambiente (`.env`)

| Variável | Serviço | Para que serve |
|---|---|---|
| `MQTT_USER` / `MQTT_PASSWORD` | Mosquitto | Credenciais do broker MQTT |
| `FRIGATE_MQTT_USER` / `FRIGATE_MQTT_PASSWORD` | Frigate → Mosquitto | Credenciais que o Frigate usa para publicar eventos |
| `INFLUXDB_DATABASE` | InfluxDB | Nome do database (padrão: `farm`) |
| `INFLUXDB_TOKEN` | InfluxDB | Token (reservado; em modo local o InfluxDB roda sem auth) |
| `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` | MinIO | Credenciais do object storage (senha ≥ 8 caracteres) |
| `GF_SECURITY_ADMIN_USER` / `GF_SECURITY_ADMIN_PASSWORD` | Grafana | Login admin do Grafana |

> O `.env` **não** é versionado no Git (está no `.gitignore`). O `.env.example` é o
> template versionado, com valores placeholder.

## 2.4 Interfaces de acesso

Depois de `docker compose up -d`, estas são as interfaces disponíveis:

| Interface | URL / Porta | O que é | Credenciais |
|---|---|---|---|
| **Grafana** | http://localhost:3000 | Dashboards e alertas | `GF_SECURITY_ADMIN_USER` / `GF_SECURITY_ADMIN_PASSWORD` |
| **Frigate Web UI** | http://localhost:5000 | Câmeras, gravações e detecções | — (protegido pela rede/SSH) |
| **MinIO Console** | http://localhost:9001 | Navegar a mídia arquivada | `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` |
| **Redpanda Console** | http://localhost:8080 | Inspecionar topics e mensagens (debug) | — |
| **MinIO S3 API** | http://localhost:9000 | API S3 (uploads, scripts) | `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` |
| **InfluxDB API** | http://localhost:8181 | API HTTP (sem UI; queries via curl) | — (sem auth em modo local) |
| **Redpanda Connect API** | http://localhost:4195 | Status dos pipelines (debug) | — |
| **Prometheus** | http://localhost:9090 | Métricas de infraestrutura | — |
| **Mosquitto (MQTT)** | localhost:1883 | Broker MQTT (pub/sub) | `MQTT_USER` / `MQTT_PASSWORD` |
| **Redpanda Kafka (externo)** | localhost:19092 | Kafka API para ferramentas externas | — |

> **Acesso remoto:** de fora da propriedade, o acesso é feito **exclusivamente via
> túnel SSH** (`ssh -L`), encaminhando as portas desejadas. Nenhuma porta de serviço
> fica exposta à internet. Veja o modelo de segurança em
> [Operações](07-operations.md#75-segurança).

## 2.5 Validar que subiu com sucesso

Um checklist rápido de ponta a ponta:

```bash
# 1. Todos os containers de pé
docker compose ps

# 2. Health dos serviços centrais
curl -s http://localhost:8181/health          # InfluxDB → OK
curl -s http://localhost:4195/ready           # Redpanda Connect → OK
curl -f http://localhost:9000/minio/health/live  # MinIO → 200

# 3. Pipelines do Redpanda Connect ativos
curl -s http://localhost:4195/streams | python3 -m json.tool
#    Esperado: "mqtt-to-redpanda", "sensors-to-influx",
#    "frigate-to-influx", "minio-to-influx" com "active": true
```

Para uma **validação real do fluxo** (publicar uma leitura e vê-la chegar ao
InfluxDB), siga o teste em [Como Usar](03-usage.md#34-publicar-uma-leitura-de-teste).
Se algo falhar, consulte [Operações → Troubleshooting](07-operations.md).
