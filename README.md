# Farm Monitoring System

Sistema de monitoramento para uma propriedade de **agrofloresta**. Reúne dados de
sensores no campo (temperatura, umidade do solo, pH, luminosidade), anotações e fotos,
e das câmeras de segurança, processa tudo em tempo real e guarda com segurança — para
você ver tanto o **agora** quanto o **histórico** da propriedade, de casa ou pelo campo.

Roda em **hardware próprio** (sem nuvem paga), como containers Docker num servidor
Linux, com uma cópia da mídia replicada para um segundo local.

## Por que importa

- **Umidade do solo + histórico** → decidir quando e onde irrigar; economizar água.
- **Temperatura + alertas** → antecipar risco de geada ou calor extremo.
- **Câmeras com detecção (Frigate)** → perceber intrusão, animais e veículos.
- **Fotos e anotações** → registrar observações de campo e buscá-las ao longo do tempo.
- **Retenção longa** → analisar sazonalidade e a evolução do pomar ao longo dos anos.
- **Dashboards (Grafana)** → ver o estado da propriedade num relance.

## Quick Start

```bash
cp .env.example .env      # edite e troque os "change_me"
docker compose up -d
```

Depois, acesse o **Grafana** em http://localhost:3000. O guia completo (pré-requisitos,
credenciais, interfaces de acesso e validação) está em
[docs/02-getting-started.md](docs/02-getting-started.md).

## Stack

| Componente | Papel |
|---|---|
| **Mosquitto** | Broker MQTT — entrada dos dados de sensores |
| **Redpanda** | Streaming central (Kafka-compatible) — barramento de eventos |
| **Redpanda Connect** | Pipelines declarativos (YAML) — bridges e transformações |
| **InfluxDB 3 Core** | Banco time-series — métricas de sensores e eventos |
| **MinIO** | Object storage (Data Lake) — fotos, vídeos, backups |
| **Frigate** | NVR com detecção de objetos — câmeras IP |
| **Grafana** | Dashboards e alertas |
| **Prometheus** | Monitoramento da infraestrutura |

## Documentação

| # | Documento | Conteúdo |
|---|---|---|
| 1 | [Visão Geral](docs/01-overview.md) | O que é e **por que importa** para a agrofloresta |
| 2 | [Como Começar](docs/02-getting-started.md) | Pré-requisitos, setup, interfaces de acesso, validação |
| 3 | [Como Usar](docs/03-usage.md) | Dashboards, consultar dados, câmeras, publicar leitura de teste |
| 4 | [Arquitetura](docs/04-architecture.md) | Infraestrutura física, software e estrutura do repositório |
| 5 | [Fluxos de Dados](docs/05-data-flows.md) | Como os dados atravessam o sistema |
| 6 | [Componentes e Dados](docs/06-components.md) | Decisões técnicas, schemas e dashboards |
| 7 | [Operações](docs/07-operations.md) | Recursos, troubleshooting, segurança, riscos, glossário |
