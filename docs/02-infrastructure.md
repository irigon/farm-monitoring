# 2. Infraestrutura Física

## 2.1 Inventário de Hardware

| Máquina | Specs | Localização | Papel |
|---------|-------|-------------|-------|
| **Servidor Principal** | 8+ GB RAM, Linux, headless | Sede da propriedade | Hub central — todos os serviços core rodam aqui 24/7 |
| **Servidor Remoto** | 4-8 GB RAM, Linux, headless | Localização geográfica remota | Réplica do Data Lake (MinIO) para resiliência geográfica |
| **Notebook** | 32 GB RAM, Linux | Sede (uso ocasional) | Estação de trabalho: acessa dashboards via browser, desenvolvimento de configs/scripts, análise offline (Jupyter), backup local |
| **Gateway LoRa** | ESP32 + módulo LoRa + antena WiFi direcional | Ponto elevado (~1 km da sede) | Recebe dados LoRa dos sensores no campo, retransmite via WiFi direcional para o servidor |
| **Sensores ESP32** | ESP32 + LoRa + sensores (temp, umid, pH, lux, movimento) + painel solar + bateria | Espalhados pela agrofloresta | Coletam dados e transmitem via LoRa para o gateway |
| **Câmeras IP** | Câmeras com RTSP (ONVIF ou proprietárias) | Pontos estratégicos da propriedade | Stream de vídeo contínuo via RTSP para o servidor |
| **Raspberry Pi 3** | 1 GB RAM, ARM | Reserva / uso futuro | Pode servir como segundo gateway, nó de teste ou ponto de coleta auxiliar |

## 2.2 Topologia de Rede

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

## 2.3 Gateway LoRa — Detalhes

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
