# 1. Visão Geral — O que é e por que importa

## 1.1 O que é

Esta é uma **plataforma de monitoramento genérica**. Ela reúne, num só lugar, dados
vindos de fontes diversas — leituras de **sensores** (temperatura, umidade, pH,
luminosidade, presença…), **anotações** (áudio, foto, texto) e imagens de **câmeras** —
processa esses dados em tempo real e os guarda com segurança, para você poder olhar
tanto o **agora** quanto o **histórico**.

O sistema não é específico de um domínio. Ele se organiza em torno de **dois fluxos**:
um para **dados leves e rápidos** (leituras, eventos) e um para **mídias pesadas e
lentas** (vídeo, áudio, fotos). Por isso serve igualmente a uma **agrofloresta**, a uma
**residência** ou a um **condomínio** — muda o *uso*, não a arquitetura. A base desse
desenho está no [Modelo Conceitual](00-conceptual-model.md).

> Ao longo deste documento, a **agrofloresta** é usada como *vertical de exemplo*, por
> ser concreta e rica em casos de uso. Os mesmos mecanismos aplicam-se a outros cenários.

Tudo roda em **hardware próprio** (sem depender de nuvem paga), como um conjunto de
containers Docker num servidor Linux na sede. Um segundo servidor, em outro local,
guarda uma cópia da mídia para segurança geográfica.

Na prática, a plataforma entrega:

- **Painéis e alertas** — visão do estado atual num relance (hoje via Grafana).
- **Histórico consultável** — leituras e eventos ao longo do tempo, para analisar
  tendências (banco de métricas).
- **Data lake para mídia** — arquivamento de fotos, vídeos e áudios, com réplica em
  outro local (hoje via MinIO).
- **Detecção em vídeo (opcional)** — quando há câmeras, grava e reconhece pessoas,
  animais e veículos (hoje via Frigate). Verticais só-sensores dispensam este componente.

As marcas citadas são as implementações **atuais**; cada uma é um componente plugável,
não um requisito da arquitetura (ver [Modelo Conceitual](00-conceptual-model.md)).

## 1.2 Por que importa

O objetivo não é apenas "coletar dados" — é **tomar decisões melhores no dia a dia** e
permitir **análises ao longo do tempo**. Cada capacidade técnica existe para resolver um
problema real — e a **mesma** capacidade serve propósitos distintos em domínios
distintos. A tabela mostra isso: cada linha é uma capacidade neutra, com um exemplo na
**agrofloresta** e usos análogos em **outros domínios**.

| O que o sistema faz | Exemplo — agrofloresta | Outros domínios |
|---|---|---|
| Mede **umidade** e guarda o histórico | Decidir *quando e onde* irrigar | Jardins e paisagismo; detectar vazamentos; compreender ciclos de variação climática |
| Mede **temperatura** e permite **alertas** | Antecipar geada/calor antes que danifiquem as plantas | Conforto e eficiência energética numa residência; sala de servidores; estufas |
| Mede **grandezas por zona** (pH, luminosidade, nível…) | Condições de cada área do sistema agroflorestal | Nível de reservatório num condomínio; qualidade do ar num ambiente interno |
| **Detecção de objetos** em vídeo | Fauna (predadores/pragas), monitorar vida selvagem | Segurança de perímetro urbano; pessoas/veículos em acessos e garagens |
| **Retenção longa + downsample** | Sazonalidade e evolução do pomar ao longo dos anos | Auditoria de ocorrências; análise de consumo/tendências históricas |
| **Data lake replicado** | Fotos/vídeos do campo com cópia geográfica | Provas de incidentes de segurança; registros com backup fora do local |
| **Anotações** (áudio/foto/texto) | "Pulgão na goiabeira do talhão norte" | Registro de manutenção numa residência; ocorrência da portaria num condomínio |

> A ideia é conectar sempre um **problema real** à **solução do sistema** (o dado que
> ele coleta e o painel que ele mostra). Em todos os casos o sistema não muda: sensores
> viram leituras, câmeras viram detecções, observações humanas viram anotações — o
> *domínio* está no uso, não no core.

## 1.3 Princípios de design

- **Montar certo desde o início**: preferir componentes que escalam sem precisar de
  substituição futura, mesmo que consumam um pouco mais de recursos agora.
- **Custo baixo**: rodar em hardware próprio (sem cloud), com sincronização geográfica
  entre dois pontos físicos.
- **Genérico por design**: todo dado é normalizado para um **Evento Canônico** neutro de
  domínio e de tecnologia — sensores, câmeras, anotações e objetos entram pela mesma
  forma. Detalhes em [Modelo Conceitual](00-conceptual-model.md).
- **Dois fluxos de dados**: dados leves (leituras, eventos) via MQTT/streaming, e dados
  pesados (mídia) direto para object storage, unificados por um barramento de eventos
  central que funciona como a **fronteira do domínio** (marcas e bancos ficam nas bordas).

## 1.4 Por onde seguir

- Para **subir o sistema**, veja [Como Começar](02-getting-started.md).
- Para **usar no dia a dia**, veja [Como Usar](03-usage.md).
- Para **entender como funciona por dentro**, veja [Arquitetura](04-architecture.md).
