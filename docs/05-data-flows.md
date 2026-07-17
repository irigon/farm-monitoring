# 5. Fluxos de Dados

Como os dados atravessam o sistema hoje. Onde um fluxo depende de hardware que ainda
não existe no repositório (ESP32/LoRa/gateway, servidor remoto), ele é descrito como a
**interface esperada** — ou seja, o formato que o servidor já sabe processar.

## 5.1 Fluxo 1 — Sensores (dados leves)

Dados pequenos e frequentes: temperatura, umidade, pH do solo, luminosidade.

```
ESP32 (campo)  →  Gateway LoRa  →  publica MQTT
   [interface esperada: o gateway publica no Mosquitto]
        │
        │ Topic:  sensors/{node_id}/{tipo}
        │ Payload: {"node_id":"n01","type":"temp","value":28.5,"ts":1709827200}
        │          (campo "location" é opcional)
        ▼
Mosquitto (:1883)
        │  subscrito pelo pipeline mqtt-to-redpanda
        ▼
Redpanda topic: sensors.telemetry
        │  consumido pelo pipeline sensors-to-influx
        ▼
InfluxDB 3 Core  →  measurement: sensor_readings
        │  tags: node_id, sensor_type, location  |  field: value
        ▼
Grafana  →  dashboard "Sensors — Overview"
```

> A parte à esquerda de "publica MQTT" (hardware de campo) ainda não existe. O que já
> funciona é: **qualquer coisa que publique nesse formato MQTT** entra no pipeline e
> chega ao InfluxDB. Veja como testar em [Como Usar](03-usage.md#34-publicar-uma-leitura-de-teste).

## 5.2 Fluxo 2 — Mídia (câmeras)

Clips e snapshots de detecção das câmeras IP.

```
Câmera IP (RTSP)
        │  stream contínuo via rede local
        ▼
Frigate (:5000)
        │  detecção de objetos (pessoas, animais, veículos)
        │  quando detecta:
        ├──▶ salva clip     → MinIO (bucket media/, prefixo clips/)
        ├──▶ salva snapshot → MinIO (bucket media/, prefixo snapshots/)
        └──▶ publica evento MQTT → Mosquitto (topic frigate/events)
                 │  payload: {"type":"new|update|end","after":{camera,label,score,...}}
                 ▼
        segue o mesmo caminho do Fluxo 1:
        Mosquitto → mqtt-to-redpanda → Redpanda (frigate.events)
                  → frigate-to-influx → InfluxDB
                 │  measurement: frigate_events (eventos "update" são descartados)
```

> A cópia dos clips/snapshots do Frigate para o MinIO é feita pelo sidecar
> `scripts/frigate-to-minio.sh`.

## 5.3 Fluxo 3 — Eventos MinIO (bucket notifications)

Sempre que um objeto é criado/deletado no MinIO (por Frigate, upload manual ou script),
o MinIO notifica o Redpanda.

```
Objeto criado/deletado no MinIO
        │  Bucket Notification → Redpanda topic: minio.events
        ▼
pipeline minio-to-influx
        │  extrai bucket, object_key, size, content_type, etag, event, timestamp
        ▼
InfluxDB 3 Core  →  measurement: media_objects
        │  tags: bucket, content_type, source, event
        │  fields: object_key, size_bytes, etag
```

Assim, cada objeto de mídia fica indexado no InfluxDB, e o link para o objeto pode ser
montado a partir de `bucket` + `object_key`.

## 5.4 Fluxo 4 — Monitoramento da infraestrutura

```
Prometheus (:9090)
        ├── scrape: Node Exporter (:9100)  — CPU, RAM, disco, rede do host
        ├── scrape: cAdvisor              — CPU, RAM, I/O por container
        └── scrape: Redpanda (:9644)      — topics, consumer lag, throughput
                 ▼
        Grafana (:3000) → dashboard "Infrastructure — Overview"
```

## 5.5 Fluxo 5 — Replicação geográfica (interface esperada)

O servidor remoto ainda não faz parte do repositório (`remote/` é um placeholder).
Quando existir, a réplica usará a **Site Replication** nativa do MinIO:

```
MinIO (Servidor Principal)  ──Site Replication (via internet/VPN)──▶  MinIO (Servidor Remoto)
        sincroniza buckets, objetos, políticas e IAM
        funciona como backup geográfico; pode ser promovido em caso de falha
```
