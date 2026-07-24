# 1. Visão Geral — O que é e por que importa

## 1.1 O que é

O **Farm Monitoring** é um sistema de monitoramento para uma propriedade de
agrofloresta. Ele reúne, num só lugar, dados vindos de fontes diversas —
leituras de sensores no campo (temperatura, umidade do solo, pH, luminosidade),
anotações e fotos, além de imagens das câmeras de segurança — processa esses dados
em tempo real e os guarda com segurança, para você poder olhar tanto o **agora**
quanto o **histórico** da propriedade.

Tudo roda em **hardware próprio** (sem depender de nuvem paga), como um conjunto de
containers Docker num servidor Linux na sede. Um segundo servidor, em outro local,
guarda uma cópia da mídia para segurança geográfica.

Na prática, você tem:

- Um **painel** (Grafana) que mostra o estado da propriedade num relance.
- Um **histórico** de sensores para entender tendências ao longo do tempo.
- Um **NVR inteligente** (Frigate) que grava as câmeras e detecta pessoas, animais
  e veículos.
- Um **data lake** (MinIO) que arquiva fotos e vídeos, replicado para um segundo local.

## 1.2 Por que importa para a agrofloresta

O objetivo não é apenas "coletar dados" — é **tomar decisões melhores no dia a dia** e
permitir **análises ao longo do tempo** da
propriedade. Cada capacidade técnica do sistema existe para resolver um problema real:

| O que o sistema faz | Por que isso ajuda na agrofloresta |
|---|---|
| Mede **umidade do solo** e guarda o histórico | Decidir *quando e onde* irrigar, compreender os ciclos e a variação climática |
| Mede **temperatura** e permite alertas | Antecipar riscos de extremos (geada/calor) antes que danifiquem as plantas |
| Mede **pH, luminosidade** e registra informação sobre o solo por zona | Entender as condições específicas de cada área do sistema agroflorestal |
| **Detecção de objetos** nas câmeras (Frigate) | Perceber **intrusão**, animais (predadores/pragas) ou veículos na propriedade |
| Guarda dados com **retenção longa + downsample** | Analisar **sazonalidade** e a evolução ao longo dos anos |
| Mantém um **data lake replicado** (MinIO) | Guardar fotos e vídeos com segurança, com cópia em outro local geográfico |
| Mostra tudo em **dashboards** (Grafana) | Ver o estado da propriedade num relance — de casa ou pelo campo |

> A ideia é conectar sempre um **problema real** (irrigar na hora certa, evitar geada,
> acompanhar o estado das culturas ao longo do tempo, saber quem entrou na propriedade)
> à **solução do sistema** (o dado que ele coleta e o painel que ele mostra).

## 1.3 Princípios de design

- **Montar certo desde o início**: preferir componentes que escalam sem precisar de
  substituição futura, mesmo que consumam um pouco mais de recursos agora.
- **Custo baixo**: rodar em hardware próprio (sem cloud), com sincronização geográfica
  entre dois pontos físicos.
- **Genérico**: o sistema aceita qualquer tipo de dado (sensores ambientais, câmeras,
  áudio, etc.) sem mudanças na arquitetura.
- **Dois fluxos de dados**: dados leves (sensores, anotações de texto) via MQTT/streaming, e dados pesados
  (mídia) direto para object storage, unificados por um barramento de eventos central.

## 1.4 Por onde seguir

- Para **subir o sistema**, veja [Como Começar](02-getting-started.md).
- Para **usar no dia a dia**, veja [Como Usar](03-usage.md).
- Para **entender como funciona por dentro**, veja [Arquitetura](04-architecture.md).
