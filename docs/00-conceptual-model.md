# 0. Modelo Conceitual

> **Documento fundacional.** Descreve o *modelo de dados neutro* sobre o qual toda a
> plataforma é construída — antes de qualquer tecnologia concreta. É o "porquê" que
> justifica a arquitetura descrita nos documentos seguintes.

## 0.1 Propósito e escopo

Este documento define o **modelo conceitual** da plataforma. Ele responde a uma única
pergunta: *"que tipo de dado este sistema movimenta, e com que forma?"*

**O que este documento é:**

- A definição do **Evento Canônico** — a unidade de dado central, neutra de tecnologia.
- A definição das **duas primitivas de armazenamento** (dados rápidos vs. dados lentos).
- O registro das **decisões de design** que levaram a este modelo, com seus porquês.

**O que este documento NÃO é:**

- Não é guia de implementação (isso está em [04-architecture.md](04-architecture.md) e nos pipelines).
- Não menciona marcas nem detalhes físicos de banco *dentro do modelo*. Termos como
  "tag", "field" ou "line protocol" pertencem ao **adaptador** de saída, não ao domínio.

**Escopo do produto.** Esta é uma **plataforma de monitoramento genérica** — um fluxo
para sensores e um fluxo para mídias (áudio, vídeo, texto, fotos). A agrofloresta é
apenas *uma* vertical de uso; o mesmo core serve uma residência, um condomínio ou
qualquer cenário de monitoramento. Nenhum conceito de domínio agrícola vive no core.

## 0.2 As duas primitivas de armazenamento

Fisicamente, só existem dois tipos de dado neste sistema:

| Primitiva | Natureza | Onde vive (hoje) | Exemplos |
|---|---|---|---|
| **Blob** | Conteúdo bruto, pesado, lento, **imutável** | Data lake (object storage) | clip de vídeo, foto, áudio, nota longa, backup |
| **Evento** | Fato leve e rápido: *"algo aconteceu em `t`"* | Banco de métricas (time-series) | leitura de sensor, detecção, mudança de estado |

A regra que une as duas:

> **Todo evento carrega um `value` (a grandeza), um `blob_ref` (ponteiro para um blob no
> data lake), ou ambos.** O `blob_ref` é uma **URI neutra de marca** (ex.:
> `s3://media/clips/…`), nunca um path relativo acoplado a um produto específico. O
> conteúdo pesado nunca entra no banco de métricas — só o fato e, quando aplicável, o
> *ponteiro* para o conteúdo.

Essa separação é o coração do sistema: **dados rápidos são consultados como série
temporal; dados lentos são referenciados, não copiados.**

## 0.3 O Evento Canônico

Toda fonte de dado — sensor, câmera, atuador, observação humana, objeto no data lake —
é normalizada para **um único formato**:

```jsonc
{
  "ts":       1709827200000,  // quando o fato aconteceu (event time, epoch ms)
  "kind":     "reading",      // a FORMA do dado (discriminador fixo)
  "source":   "sensor-n03",   // QUEM/o quê gerou (proveniência)
  "measure":  "luminosity",   // O QUE está sendo medido/detectado
  "value":    843,            // opcional: a grandeza (agregável)
  "blob_ref": null,           // opcional: ponteiro para o blob no data lake
  "context":  {               // qualificadores abertos ("onde"/"qual" extra)
    "location": "estufa-2",
    "zone":     "norte"
  },
  "attrs":    {               // atributos descritivos do fato (alta cardinalidade)
    "gps_accuracy": 4.5       //   ex.: precisão, score, bateria — mapeados como field
  }
}
```

| Campo | Significado | Fixo/Aberto | Obrigatório |
|---|---|---|---|
| `ts` | Instante (event time) em que o fato ocorreu; epoch em ms | — | Sim |
| `kind` | A **forma** do dado (ver §0.5) | **Fixo** (enum) | Sim |
| `source` | A **proveniência** — identificador da fonte | Aberto | Sim |
| `measure` | O **que** é medido/detectado (ex.: `temperature`, `person`) | Aberto | Obrigatório p/ `reading`/`detection`/`state`; opcional p/ `object` |
| `value` | A grandeza numérica; agregável (avg, max, sum) | — | Opcional* |
| `blob_ref` | Ponteiro para o conteúdo no data lake | — | Opcional* |
| `context` | Mapa aberto de qualificadores de baixa cardinalidade | Aberto | Opcional |
| `attrs` | Mapa aberto de atributos descritivos do fato (alta cardinalidade; ex.: `lat`, `lon`, `score`, `battery`) | Aberto | Opcional |

\* Pelo menos um entre `value` e `blob_ref` deve estar presente (ver §0.2).

## 0.4 Os três eixos ortogonais

O modelo separa três dimensões que **respondem a perguntas diferentes** e evoluem de
forma independente. Fundir qualquer par delas num campo só recria o problema que este
modelo evita (explosão de nomes, parsing de strings, impossibilidade de consultar por
uma dimensão isolada).

| Eixo | Pergunta | Campo | Natureza |
|---|---|---|---|
| **Forma** | "que *estrutura* tem este dado?" | `kind` | **Fixo** — você controla o vocabulário |
| **Proveniência** | "*quem* gerou?" | `source` | Aberto — o mundo controla o valor |
| **Semântica** | "*o que* está sendo medido/detectado?" | `measure` | Aberto — o mundo controla o valor |

Consultas que a ortogonalidade torna possíveis, sem conhecimento prévio dos valores:

- Todas as detecções, de qualquer fonte → filtrar por `kind = detection`.
- Todos os sensores de luminosidade → filtrar por `measure = luminosity`.
- Tudo que veio de um nó específico → filtrar por `source = sensor-n03`.

> **Ressalva sobre `measure` e `object`.** `measure` é obrigatório para
> `reading`/`detection`/`state`, mas *opcional* para `object` (ver §0.3) — um evento de
> ciclo de vida de blob pode não ter uma grandeza/classe associada. Logo, filtros por
> `measure` naturalmente ignoram parte dos `object`. Isso é coerente com a regra do
> §0.5 (`kind != object` em consultas de domínio) e não afeta os demais `kind`, onde
> `measure` está sempre presente.

> **Por que não é preciso "conhecer os tipos de antemão".** Apenas `kind` é fechado.
> `source` e `measure` são **campos** cujos *valores* são livres: no dia em que um sensor
> de CO₂ é conectado, ele publica `measure = co2` e as consultas passam a funcionar
> sozinhas — sem migração e sem alterar o schema. É *schema-full na estrutura,
> schema-less no valor.*

## 0.5 `kind`: o discriminador fixo

`kind` é o **único eixo fechado**, e responde *"que forma tem este dado?"* — nunca *"que
aparelho gerou?"*. Sob essa lente, todo o universo de monitoramento colapsa em poucos
valores:

| `kind` | Definição — a *forma* | Engloba |
|---|---|---|
| **`reading`** | Medida numérica escalar num instante | umidade, vento, chuva (mm), temperatura, pressão, altura, luminosidade, CO₂ — **todo sensor** |
| **`detection`** | Algo foi reconhecido/classificado, com confiança; tipicamente com blob | câmera detecta pessoa/carro/animal; sensor de presença que dispara |
| **`state`** | Mudança de estado discreto de um dispositivo | atuador ligou/desligou, portão abriu/fechou, válvula 30%→70% |
| **`annotation`** | Observação humana, aponta para mídia no data lake | áudio ditado, foto, nota de texto |
| **`object`** | Um blob apareceu/sumiu no data lake | notificação de criação/remoção de objeto |

**Critério de fixação.** `kind` é fixo porque **determina como o sistema trata o dado**:
um `reading` vira gráfico de linha e sofre downsample; um `object` gera um ponteiro; um
`detection` casa evento + blob. Um `kind` novo é *código novo* (um jeito novo de
processar). Já `source`/`measure` novos são *dado novo* — o pipeline nem percebe. Essa é
a linha divisória: **`kind` fixo porque muda comportamento; o resto aberto porque só
muda valor.**

Nota sobre atuadores: o **estado reportado** por um atuador ("o irrigador está ligado")
é monitoramento de primeira classe → `state`. O **comando** ("ligue o irrigador") é
controle, fluxo inverso, e está **fora** do escopo desta plataforma.

Nota sobre `object` vs. eventos de domínio: `object` é um evento de **infraestrutura do
data lake** (ciclo de vida do blob). Um mesmo blob pode ter também um evento de
**domínio** que o referencia (`detection`, `annotation`) via o mesmo `blob_ref`. A
correlação entre os dois é feita por `blob_ref` compartilhado. Para evitar dupla
contagem, consultas de domínio devem filtrar `kind != object`.

## 0.6 `source` e `measure`: os eixos abertos

Enquanto `kind` é fechado, `source` e `measure` têm *valores livres*. A distinção entre
eles é a fonte da maior parte das dúvidas de modelagem, então vale fixá-la:

- **`source` = a origem física do dado** — *quem/o quê* o produziu. É um **identificador
  estável** de um aparelho, nó ou publicador. Responde: *"de onde veio?"*.
- **`measure` = a natureza do que foi observado** — *o que* está sendo medido ou
  reconhecido. Responde: *"o que é este dado?"*.

A mesma `source` pode emitir vários `measure`, e o mesmo `measure` pode vir de várias
`source` — é isso que torna os dois eixos **ortogonais**:

| `source` (quem) | `measure` (o quê) | `kind` |
|---|---|---|
| `sensor-n03` | `temperature` | `reading` |
| `sensor-n03` | `humidity` | `reading` |
| `camera-entrada` | `person` | `detection` |
| `camera-entrada` | `car` | `detection` |
| `camera-garagem` | `person` | `detection` |
| `atuador-irrigador-1` | `power_state` | `state` |

**Regra prática:** se o valor identifica *um dispositivo/publicador concreto* → é
`source`. Se descreve *a grandeza ou a classe do que foi observado* → é `measure`.
(No modelo atual despadronizado, `source` corresponde a `node_id`/`camera`/`bucket`, e
`measure` a `sensor_type`/`label`/`content_type`.)

> **Como o modelo cresce (duas portas).** Atributos novos entram por uma de duas portas,
> pela mesma regra da coordenada — *"eu agruparia por isto?"*:
>
> - **`context{}`** — qualificador de agrupamento, baixa cardinalidade (`GROUP BY zone`).
>   Sem migração: basta publicar a chave; o adaptador a mapeia como tag.
> - **`attrs{}`** — descritor do fato, alta cardinalidade (`lat`, `score`, `battery`,
>   `rssi`, `size_bytes`). Mapeado como field. É a generalização canônica dos campos que
>   hoje vivem despadronizados (`score` em `frigate_events`, `etag` em `media_objects`…).

> **Câmeras:** o tipo detectado (`person`, `car`, `dog`…) é um `measure`, exatamente
> como `temperature` é o `measure` de um sensor. Isso dá de graça consultas genéricas —
> `kind='detection' AND measure='person'` é análogo a `kind='reading' AND
> measure='temperature'`. A lista de rótulos é **aberta**: o detector emite o que
> reconhece e o sistema aceita sem conhecê-lo de antemão. Reagrupar rótulos finos em
> superclasses (`dog`→`animal`) é decisão de *consulta/apresentação*, **não** de
> ingestão — o adaptador nunca reinterpreta o rótulo original.

### Mapa dos measurements atuais para o modelo canônico

| Measurement atual | `kind` | `source` (hoje) | `measure` (hoje) |
|---|---|---|---|
| `sensor_readings` | `reading` | `node_id` | `sensor_type` |
| `frigate_events` | `detection` | `camera` | `label` |
| `annotations` | `annotation` | (publisher) | `kind` do payload → **renomeado p/ `measure`** (o `kind` canônico é sempre `annotation`) |
| `media_objects` | `object` | `bucket`/`source` do path | `content_type` |

> Observe que a proveniência já existe hoje — porém com um **nome diferente em cada
> measurement** (`node_id`, `camera`, `bucket`). O modelo canônico apenas unifica isso
> sob `source`, o que é o que torna a plataforma genérica.

## 0.7 Adaptadores e a fronteira do domínio

O modelo canônico é neutro de tecnologia por design: **o domínio não sabe que o banco
de métricas ou qualquer marca de câmera existem.** Marcas e schemas proprietários ficam
confinados às bordas, conectando-se ao núcleo através de uma fronteira única — o
barramento de eventos.

> Esse padrão é conhecido na literatura como **Ports & Adapters** (também chamado
> "arquitetura hexagonal", de Alistair Cockburn) e é aparentado da *Clean Architecture*.
> O termo é dado apenas como referência; o que importa é a ideia descrita acima.

```
        ADAPTADORES DE ENTRADA                FRONTEIRA               ADAPTADORES DE SAÍDA
       (traduzem dialeto → canônico)         (o "port")              (canônico → tecnologia)

  Câmera (NVR) ─┐
  Sensor / gw  ─┤ dialeto próprio   ┌──────────────────────┐   ┌──▶ Banco de métricas (série temporal)
  Observação   ─┤ ────────────────▶ │  EVENTO CANÔNICO      │──▶│
  Obj. no lake ─┘                    │  (barramento de       │   └──▶ (futuro: outro banco = novo adaptador)
                                     │   eventos)            │
                                     └──────────┬───────────┘
                                                └──▶ Data lake (blobs)
```

Pontos-chave:

- **A fronteira do domínio já existe fisicamente:** é o barramento de eventos que
  carrega o Evento Canônico. Tudo *antes* dele são adaptadores de entrada; tudo *depois*
  são adaptadores de saída. O barramento entrega o desacoplamento "de graça".
- **Uma marca de câmera (ex.: Frigate) é uma implementação plugável, não um conceito do
  core.** O core conhece "um produtor de eventos `detection`", não a marca. Trocar a NVR
  = trocar/adicionar um adaptador de entrada, sem tocar no core.
- **O banco de métricas é um adaptador de saída.** Todo conhecimento físico dele
  (indexação, agregação, formato de escrita) vive *apenas* nesse adaptador — nunca no
  modelo.

## 0.8 Decisões de design

**D1 — Modelo neutro de tecnologia.** O Evento Canônico é definido em vocabulário de
domínio. Isto mantém a *regra da dependência*: o banco é um detalhe, não o centro.

**D2 — NÃO construir uma abstração de banco formal agora (YAGNI).** Desenhar
independente de tecnologia (barato, é higiene) é diferente de *construir* uma interface
`EventStore` com múltiplos adaptadores e testes de portabilidade (caro, é maquinaria).
O barramento de eventos já provê o desacoplamento; trocar de banco = escrever um novo
consumidor, sem tocar a montante. A abstração formal só se justifica quando existir um
*segundo* banco real na mesa. Referência de mercado: OpenTelemetry (modelo canônico +
exporters plugáveis) e Grafana (datasources plugáveis) abstraem a dimensão que é o
*valor do produto*; um TSDB não abstrai o storage abaixo dele — e está certo.

**D3 — `value` e `measure` são campos distintos.** São categorias *lógicas* diferentes:
`measure` é um eixo de **busca/agrupamento** (aberto, baixa cardinalidade); `value` é uma
grandeza de **cálculo** (agregável). O mapeamento físico dessa distinção (o que vira
índice, o que vira coluna agregável) é responsabilidade **do adaptador de saída**, não
do modelo.

**D4 — Localização é atributo opcional; distinguir "lugar nomeado" de "coordenada
precisa".** Há dois "ondes", com tratamentos diferentes:

- **Lugar nomeado** (`location=estufa-2`, `zone=norte`): baixa cardinalidade, é dimensão
  natural de agrupamento → vai para `context{}` (mapeado como tag pelo adaptador).
- **Coordenada precisa** (`lat`/`lon`/`gps_accuracy`): **não é `value`** (não é a grandeza
  medida) **nem** tag (cardinalidade altíssima, quase única por ponto, quebraria a
  indexação) **nem `context{}`** (que é eixo de *agrupamento* de baixa cardinalidade —
  ninguém agrupa por coordenada exata; aninhá-la não muda isso). É um **atributo
  descritivo opcional**, que vive no contêiner `attrs{}` do evento — lido junto com ele,
  mas raramente agrupado por ele. Incluído **só quando faz sentido** (ex.: foto/áudio em
  campo) e **omitido** quando ausente ou irrelevante (ex.: sensor fixo, cuja posição
  pode ser registrada uma única vez fora do fluxo de eventos). No mapa físico o adaptador
  o grava como *field*. Busca por raio é feita via *bounding-box* + Haversine na query,
  não por indexação.

## 0.9 Glossário

- **Evento** — um fato leve: "algo aconteceu em `t`", com `value` e/ou `blob_ref`.
- **Blob** — conteúdo bruto, pesado e imutável, guardado no data lake.
- **`kind`** — a *forma* do dado (fixo): `reading`, `detection`, `state`, `annotation`, `object`.
- **`source`** — a *proveniência* (aberto): quem/o quê gerou o evento.
- **`measure`** — a *semântica* (aberto): o que está sendo medido/detectado.
- **`context{}`** — qualificadores de baixa cardinalidade; eixo de agrupamento (→ tag).
- **`attrs{}`** — atributos descritivos do fato, alta cardinalidade (→ field): GPS, score, bateria…
- **Adaptador** — componente de borda que traduz um dialeto específico ↔ o Evento Canônico.
- **Fronteira do domínio ("port")** — o barramento de eventos que carrega o Evento
  Canônico; separa adaptadores de entrada dos de saída. (Vocabulário do padrão
  *Ports & Adapters* / "arquitetura hexagonal".)
