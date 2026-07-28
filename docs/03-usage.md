# 3. Como Usar

Uso cotidiano do sistema: ver os dashboards, consultar dados, olhar as câmeras e
validar que o fluxo funciona. (Para diagnóstico de problemas, veja
[Operações](07-operations.md).)

## 3.1 Ler os dashboards no Grafana

Acesse **http://localhost:3000** e faça login com as credenciais do `.env`
(`GF_SECURITY_ADMIN_USER` / `GF_SECURITY_ADMIN_PASSWORD`). Os dashboards são
provisionados automaticamente. Há dois:

### Sensors — Overview
Mostra as leituras dos sensores da propriedade:

- **Temperature**, **Humidity**, **Soil Moisture**, **Light (Lux)** e **pH** ao longo
  do tempo.
- **Latest Readings** — a última leitura de cada sensor.

> Este dashboard só mostra dados **se houver leituras publicadas**. O hardware de
> campo (ESP32/LoRa) ainda não existe no repositório — enquanto isso, você alimenta o
> dashboard publicando leituras manualmente (veja a seção 3.4).

### Infrastructure — Overview
Mostra a saúde do servidor e dos containers:

- **Scrape Targets Up**, **Host CPU / Memory / Disk / Network I/O**.
- **Container CPU / Memory / Restarts**.
- **Redpanda — Kafka Consumer Lag** e **Topic Throughput**.

## 3.2 Ver as câmeras no Frigate

Acesse **http://localhost:5000** para a UI do Frigate:

- Veja os streams ao vivo das câmeras configuradas em `config/frigate/config.yml`.
- Navegue pelas **detecções** (pessoas, animais, veículos) com seus clips e snapshots.
- Os clips e snapshots são espelhados para o MinIO (veja a seção 3.5).

## 3.3 Consultar dados históricos no InfluxDB

O InfluxDB 3 Core **não tem UI web** — as consultas são feitas via API HTTP com SQL.
Sempre inclua `format=json`.

```bash
# Últimas 10 leituras de sensores (kind=metric)
curl -s 'http://localhost:8181/api/v3/query_sql' -G \
  --data-urlencode 'db=farm' \
  --data-urlencode "q=SELECT * FROM events WHERE kind='metric' ORDER BY time DESC LIMIT 10" \
  --data-urlencode 'format=json' | python3 -m json.tool

# Média de umidade do solo por nó nas últimas 24h
curl -s 'http://localhost:8181/api/v3/query_sql' -G \
  --data-urlencode 'db=farm' \
  --data-urlencode "q=SELECT source, AVG(value) FROM events WHERE kind='metric' AND measure='soil_moisture' AND time > now() - INTERVAL '24 hours' GROUP BY source" \
  --data-urlencode 'format=json' | python3 -m json.tool

# Eventos de detecção recentes do Frigate
curl -s 'http://localhost:8181/api/v3/query_sql' -G \
  --data-urlencode 'db=farm' \
  --data-urlencode "q=SELECT * FROM events WHERE kind='detection' ORDER BY time DESC LIMIT 10" \
  --data-urlencode 'format=json' | python3 -m json.tool

# Mídia arquivada mais recente (metadados)
curl -s 'http://localhost:8181/api/v3/query_sql' -G \
  --data-urlencode 'db=farm' \
  --data-urlencode "q=SELECT * FROM events WHERE kind='object' ORDER BY time DESC LIMIT 10" \
  --data-urlencode 'format=json' | python3 -m json.tool

# Listar as tabelas (measurements) disponíveis
curl -s 'http://localhost:8181/api/v3/query_sql' -G \
  --data-urlencode 'db=farm' \
  --data-urlencode 'q=SHOW TABLES' \
  --data-urlencode 'format=json'
```

Todos os eventos vivem no **measurement único `events`**, discriminados pela tag `kind`
(`metric`, `detection`, `annotation`, `object`). O schema está descrito em
[Componentes → Schema de `events`](06-components.md).

## 3.4 Publicar uma leitura de teste

Para validar que o fluxo `MQTT → Redpanda → InfluxDB` está funcionando de ponta a
ponta, publique uma leitura de sensor manualmente e verifique se ela chega ao InfluxDB.

```bash
# 1. Publicar uma leitura via MQTT
docker run --rm --network farm-monitoring_monitoring eclipse-mosquitto:2 \
  mosquitto_pub -h mosquitto -p 1883 \
  -u mqtt_user -P '<MQTT_PASSWORD>' \
  -t 'sensors/test/humidity' \
  -m '{"node_id":"test","type":"humidity","value":65.2,"ts":'$(date +%s)'}'

# 2. (Opcional) Confirmar que chegou ao topic no Redpanda
docker exec redpanda rpk topic consume events \
  --brokers localhost:9092 --num 1

# 3. Aguardar o batching (~1s) e consultar o InfluxDB
sleep 2
curl -s 'http://localhost:8181/api/v3/query_sql' -G \
  --data-urlencode 'db=farm' \
  --data-urlencode "q=SELECT * FROM events WHERE kind='metric' ORDER BY time DESC LIMIT 3" \
  --data-urlencode 'format=json' | python3 -m json.tool
```

Se a leitura aparecer no passo 3, o pipeline está saudável. Abra o dashboard
**Sensors — Overview** no Grafana e a leitura de teste também aparecerá lá.

> O **formato do payload MQTT** aceito é: tópico `sensors/{node_id}/{tipo}` com JSON
> `{"node_id": "...", "type": "...", "value": <número>, "ts": <epoch_s>}`. O campo
> `location` é opcional. É exatamente essa a interface que o hardware de campo deverá
> respeitar.

## 3.5 Navegar a mídia no MinIO

Acesse o **MinIO Console** em **http://localhost:9001** e faça login com
`MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`. Você verá os buckets:

- **`media`** — clips (`clips/`), snapshots (`snapshots/`) e uploads (`uploads/`).
- **`exports`** — exports do InfluxDB.
- **`backups`** — backups de configuração.

Cada objeto criado dispara uma notificação que grava seus metadados no InfluxDB
(measurement `events`, `kind='object'`), então você também encontra a mídia consultando o
InfluxDB (seção 3.3).
