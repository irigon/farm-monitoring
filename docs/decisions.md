# Registro de Decisões (ADRs)

> Log enxuto das decisões de arquitetura tomadas até aqui. Cada entrada é
> **durável**: captura *o que* foi decidido, *por quê*, e *a alternativa descartada* —
> para reconstruir o contexto sem reler discussões.
>
> Detalhamento conceitual em [00-conceptual-model.md](00-conceptual-model.md).
> Status possíveis: `aceito` · `a revisar`.
>
> **Vocabulário mínimo** (definido em detalhe no [modelo conceitual](00-conceptual-model.md)):
> o **Evento Canônico** tem um `ts` (event time) mais oito campos de conteúdo. `kind` =
> a *forma* do dado (enum fechado: `metric`, `detection`, `state`, `annotation`,
> `object`); `source` = *quem/o quê* gerou (proveniência); `measure` = *o que* está sendo
> medido/detectado (semântica); `value` = a grandeza **numérica** (agregável; estado
> categórico é expresso via `measure`, ver ADR-5); `blob_ref` = ponteiro
> para um blob; `context{}` = qualificadores de agrupamento (baixa cardinalidade);
> `attrs{}` = atributos descritivos do fato (alta cardinalidade). Os ADRs abaixo
> assumem esse vocabulário.
>
> Dois exemplos concretos para fixar a ideia:
> - **Leitura de sensor:** `kind=metric`, `source=sensor-n03`, `measure=temperature`,
>   `value=28.5`, `context={location: estufa-2}`. (Um sensor mediu 28,5 na estufa 2.)
> - **Detecção de câmera:** `kind=detection`, `source=camera-entrada`, `measure=person`,
>   `blob_ref=s3://media/clips/…`, `context={zone: garagem}`. (Uma câmera reconheceu
>   uma pessoa e guardou o clipe no data lake.)

---

### ADR-1: Plataforma de monitoramento genérica

- **Decisão:** o produto é uma plataforma de monitoramento genérica (fluxo de sensores + fluxo de mídia); a agrofloresta é apenas *uma vertical de exemplo*.
- **Por quê:** o núcleo técnico já é agnóstico de domínio; o "agro" é apenas vocabulário e apresentação. O mesmo sistema serve residência, condomínio, etc.
- **Alternativa descartada:** manter o foco exclusivo em agrofloresta — desperdiçaria a generalidade já existente e acoplaria o core a um domínio.
- **Status:** aceito

---

### ADR-2: Duas primitivas de armazenamento (blob vs evento)

- **Decisão:** existem só dois tipos de dado — **blob** (bruto, pesado, imutável, no data lake) e **evento** (leve, rápido, no banco de métricas). Todo evento tem `value`, `blob_ref`, ou ambos.
- **Por quê:** reflete a realidade física do sistema (dados rápidos vs. lentos); o conteúdo pesado é referenciado, nunca copiado para o banco de métricas.
- **Alternativa descartada:** um único store para tudo — inviável (mistura séries temporais com blobs pesados).
- **Status:** aceito

---

### ADR-3: Evento Canônico como unidade central

- **Decisão:** toda fonte é normalizada para um único formato — `ts` (event time) mais oito campos de conteúdo: `kind, source, measure, value?, blob_ref?, context{}, attrs{}`.
- **Por quê:** unifica sensores, câmeras, anotações e objetos numa forma só; é o que torna a plataforma genérica e o que permite correlacionar dados por tempo/escopo.
- **Critério de promoção (dois níveis distintos):** a decisão divide-se em dois níveis com critérios *diferentes* — é isso que dissolve a aparente contradição "semântica vs. indexação". **Nível 1 — promover (campo de primeira classe):** critério = **necessidade de domínio**, não padrão de acesso. **Nível 2 — classificar o resíduo não-promovido:** *aqui, e só aqui,* critério = **padrão de acesso / cardinalidade**.
    - `value` / `blob_ref` — **Nível 1**, por **regra de domínio**: são a própria definição de evento (ADR-2, "todo evento tem `value`, `blob_ref` ou ambos"). Ficariam fora do `context` mesmo num banco documental.
    - `source` / `measure` — **Nível 1**, por serem **eixos de consulta universais**: existem consultas "tudo deste `source`" / "tudo com este `measure`" que precisam funcionar para *qualquer* fonte, com nome canônico único (evitando a despadronização atual `node_id`/`camera`/`bucket`). É por isso que `source`, apesar de ser o eixo aberto de maior cardinalidade, é primeira-classe: foi promovido por domínio, logo não passa pelo critério de cardinalidade do Nível 2.
    - `context{}` — **Nível 2**: qualificadores de **baixa cardinalidade**, usados para *agrupar* (`location`, `zone`, `apartment`…).
    - `attrs{}` — **Nível 2**: **atributos descritivos de alta cardinalidade**, lidos/filtrados mas não agrupados (`lat`, `lon`, `score`, `battery`, `rssi`…). (Como o adaptador materializa cada contêiner — p.ex. dimensão de agrupamento vs. atributo — é detalhe do adaptador.)
  Ou seja: **padrão de acesso conta — mas só governa o resíduo não-promovido.** A promoção é anterior e por outra razão (domínio).
- **Dois planos distintos (por que não há contradição):** definir os campos de antemão **não** define como armazená-los. São perguntas separadas:
    - *Quais campos existem e o que significam?* → plano de **modelo/domínio**, fixado aqui pela promoção.
    - *Como cada campo é fisicamente gravado* (índice, coluna, documento; "tag vs field")? → plano de **armazenamento**, responsabilidade **exclusiva do adaptador de saída** (ver ADR-6/ADR-7), invisível ao modelo.
  Analogia: um contrato/DTO fixa os campos; o serializador/ORM decide a persistência. Fixar o contrato de antemão é justamente o que *libera* o adaptador para escolher o mapa físico sem afetar o domínio.
- **Alternativa descartada:** um schema ad-hoc por tipo de fonte (o estado atual: `node_id`/`camera`/`bucket` despadronizados) — impede consultas genéricas.
- **Status:** aceito

---

### ADR-4: Três eixos ortogonais (`kind` / `source` / `measure`)

- **Decisão:** separar três dimensões independentes — **forma** (`kind`, fechado), **proveniência** (`source`, aberto), **semântica da medida** (`measure`, aberto).
- **Por quê:** respondem a perguntas diferentes ("que estrutura?", "quem gerou?", "o que mede?") e evoluem independentemente. Fundir qualquer par recria explosão de nomes e parsing de strings.
- **Alternativa descartada:** um único campo discriminador fundindo forma+proveniência — explosão combinatória (produto cartesiano) e alta cardinalidade.
- **Status:** aceito

---

### ADR-5: `kind` fixo com 5 valores

- **Decisão:** `kind` é um enum fechado: `metric`, `detection`, `state`, `annotation`, `object`.
- **Por quê:** critério de fixação = *"muda comportamento, não só valor"*. Um `kind` novo é código novo (jeito novo de processar); `source`/`measure` novos são só dado. `state` inclui estado reportado por atuadores (comando/controle fica fora de escopo).
- **Alternativa descartada:** (a) `kind` aberto absorvendo tipos de dispositivo/medida — recairia em proveniência; (b) fundir `detection`→`metric` (4 valores) — descartado por `detection` ter semântica própria (blob + "vale olhar"), mas registrado como opção defensável.
- **Status:** aceito

---

### ADR-6: Modelo híbrido (campos promovidos + `context{}` / `attrs{}` abertos)

- **Decisão:** promover `source`, `measure`, `value`, `blob_ref` a campos de primeira classe; manter **dois contêineres abertos** para o restante: `context{}` para qualificadores de agrupamento (ex.: `location`, `zone`) e `attrs{}` para atributos descritivos do fato (ex.: `lat`, `score`, `battery`).
- **Por quê:** a promoção segue o critério de **dois níveis** do ADR-3 — Nível 1 (necessidade de domínio) promove `value`/`blob_ref` (regra de domínio, ADR-2) e `source`/`measure` (eixos de consulta universais); Nível 2 (padrão de acesso/cardinalidade) classifica o resíduo em `context{}` vs. `attrs{}`. O **mapeamento físico** (o que vira índice/tag vs. agregável/field vs. coluna/documento) fica confinado ao **adaptador de saída** — não vaza para o modelo. Ou seja: o modelo pré-define *quais campos existem*; o adaptador decide *como armazená-los*.
- **Alternativa descartada:** modelo `{kind, context}` puro (tudo dentro de `context`) — logicamente elegante, mas obriga o sistema a decidir item a item o papel físico de cada campo; descartado por custo de busca/indexação. Reconsiderar se o banco mudar para documental.
- **Nota (nível de abstração):** a *abertura* de `context{}`/`attrs{}` — aceitar chaves novas sem migração — é propriedade do **modelo**. Como o adaptador de saída materializa dinamicamente essas chaves (para cumprir a promessa "qualificador novo sem migração") é detalhe do adaptador, tratado no doc de arquitetura, não aqui.
- **Status:** aceito

---

### ADR-7: Núcleo isolado — barramento como fronteira, marcas como adaptadores

- **Decisão:** o barramento de eventos (tópicos `*.events`) é a **fronteira do domínio**. Fontes (câmeras, sensores) e destinos (banco de métricas) são **adaptadores** nas bordas. Marcas (Frigate, MinIO, Grafana) são implementações plugáveis, nunca conceitos do core. (Este é o padrão *Ports & Adapters* / "arquitetura hexagonal" — termo dado só como referência.)
- **Por quê:** mantém a regra da dependência (domínio não conhece marcas nem bancos). Trocar uma câmera/NVR = trocar um adaptador de entrada, sem tocar no core. O desacoplamento já existe fisicamente via o barramento.
- **Alternativa descartada:** tratar "Frigate" como um tipo de evento no core — vazamento de marca para dentro do modelo.
- **Status:** aceito

---

### ADR-8: YAGNI da abstração de banco

- **Decisão:** desenhar o modelo neutro de tecnologia (higiene, custo zero), mas **não** construir agora uma interface `EventStore` formal com múltiplos adaptadores e testes de portabilidade.
- **Por quê:** o barramento de eventos já provê o desacoplamento; trocar de banco = escrever um novo consumidor. A abstração formal só se justifica com um *segundo* banco real na mesa. Referência de mercado: OpenTelemetry (modelo canônico + exporters) e Grafana abstraem a dimensão que é o valor do produto; um TSDB não abstrai o storage abaixo dele.
- **Alternativa descartada:** construir a camada de abstração de banco já — over-engineering para futuro hipotético.
- **Status:** aceito

---

### ADR-9: Localização — lugar nomeado vs. coordenada precisa

- **Decisão:** distinguir dois "ondes". **Lugar nomeado** (`location`, `zone`) → `context{}` (baixa cardinalidade, dimensão de agrupamento). **Coordenada precisa** (`lat`/`lon`/`gps_accuracy`) → `attrs{}` (**atributo descritivo** do evento), incluída só quando relevante e omitida quando ausente; nunca `value`, nunca tag, nunca `context{}`.
- **Por quê:** coordenada não é a grandeza medida (logo não é `value`) e tem cardinalidade altíssima (quase única por ponto), o que quebraria a indexação se virasse tag. Muitos eventos são estáticos (sensor fixo) e não precisam repetir GPS; outros (áudio/foto em campo) precisam. Como o adaptador grava a coordenada e como implementa busca por raio é detalhe do adaptador, no doc de arquitetura.
- **Alternativa descartada:** (a) GPS como `value` — categoria errada (não é a medida); (b) GPS como qualificador de agrupamento em `context{}` — explosão de cardinalidade/séries (por isso vai em `attrs{}`, como atributo descritivo).
- **Status:** aceito

---

### ADR-10: Identidade de evento e idempotência (entrega at-least-once)

- **Decisão:** o barramento entrega eventos **at-least-once** (Redpanda com replay). A deduplicação é responsabilidade do **adaptador de saída**, que deriva uma **identidade determinística** do evento. A regra de identidade, em ordem de precedência, é: (1) um `event_id` da fonte, quando presente; senão (2) o `blob_ref`, quando presente; senão (3) a combinação `source + measure + ts` **mais um discriminador** que a torne única. O discriminador é necessário porque `source + measure + ts` **não é único por construção** (eixos ortogonais: a mesma `source` emite vários `measure`; duas detecções podem cair no mesmo `ts`), e usar só a tripla causaria **perda silenciosa** de eventos legítimos. Quando propagado, o `event_id` da fonte é preservado em `attrs{}` (não em `context{}`).
- **Por quê:** replay e reprocessamento (ADR-8: "novo banco = novo consumidor") produzem duplicatas por construção. Sem uma regra de identidade, o histórico do banco de métricas fica inflado e não-reproduzível. A precedência por `event_id`/`blob_ref` resolve a maioria dos casos; o discriminador cobre a colisão legítima da tripla. O `event_id` da fonte vai em `attrs{}` (não em `context{}`) porque é quase-único — mesma razão de cardinalidade que manda o GPS para `attrs{}` no ADR-9.
- **Alternativa descartada:** exigir um `event_id` obrigatório no modelo canônico — acoplaria o domínio a uma semântica de identidade que nem toda fonte fornece.
- **Fronteira (nível de abstração):** este ADR fixa apenas a *política* de identidade e a responsabilidade (adaptador). O **mecanismo físico** de como o discriminador é calculado e de como a dedup se materializa no banco é detalhe do adaptador de saída — vive no doc de arquitetura, não aqui e nem no [00-conceptual-model.md](00-conceptual-model.md) (o core neutro não conhece garantia de entrega nem dedup).
- **Status:** aceito

---

### ADR-11: Questões deliberadamente diferidas para a implementação

> Não são furos do modelo conceitual — são consequências conhecidas cuja *solução
> física* pertence ao adaptador de saída e não precisa (nem deve) ser fixada no plano
> conceitual. Registradas aqui apenas para não se perderem.

- **Dupla emissão por um fato (`object` + evento de domínio).** Um mesmo fato do mundo
  pode gerar dois eventos legítimos — ex.: uma `detection` (domínio) e um `object`
  (infraestrutura do data lake) que compartilham o mesmo `blob_ref`. Isto é
  **característica do domínio, não defeito**: descrevem aspectos distintos (o que foi
  reconhecido vs. o que entrou no data lake). O único efeito colateral é **dupla
  contagem** em agregações ingênuas; a mitigação (escopo/tabela separada, tag
  reservada, ou convenção de query `kind != object`) é escolha do adaptador,
  **decisão diferida**. Correlação entre os dois já está garantida pelo `blob_ref`
  compartilhado (ver §0.5 do modelo conceitual).
- **Cardinalidade física de `source`.** `source` é primeira-classe por **necessidade de
  domínio** (ADR-3, Nível 1) — a promoção não é questionada. Resta apenas uma
  observação de borda: como o adaptador tende a materializar `source` como dimensão de
  agrupamento (tag), ele é o eixo promovido de maior cardinalidade. Se algum dia uma
  fonte for identificada por algo quase-único por evento (por-sessão/por-requisição),
  esse identificador **não é `source`** — vai para `attrs{}`, e o `source` continua
  sendo o publicador estável. Tratamento físico = **decisão diferida** do adaptador; o
  modelo permanece intacto.
- **Status:** aceito (como registro de itens diferidos)
