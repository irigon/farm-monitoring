# Registro de Decisões (ADRs)

> Log enxuto das decisões de arquitetura tomadas até aqui. Cada entrada é
> **durável**: captura *o que* foi decidido, *por quê*, e *a alternativa descartada* —
> para reconstruir o contexto sem reler discussões.
>
> Detalhamento conceitual em [00-conceptual-model.md](00-conceptual-model.md).
> Status possíveis: `proposto` · `aceito` · `supersedido` · `a revisar`.
> Última revisão: 2026-07.
>
> **Índice**
>
> | # | Título | Status |
> |---|---|---|
> | ADR-1 | Plataforma de monitoramento genérica | aceito |
> | ADR-2 | Duas primitivas de armazenamento (blob vs evento) | aceito |
> | ADR-3 | Evento Canônico como unidade central | aceito |
> | ADR-4 | Três eixos ortogonais (`kind` / `source` / `measure`) | aceito |
> | ADR-5 | `kind` fixo com 5 valores | aceito |
> | ADR-6 | Modelo híbrido | supersedido por ADR-3 |
> | ADR-7 | Núcleo isolado — barramento como fronteira | aceito |
> | ADR-8 | YAGNI da abstração de banco | aceito |
> | ADR-9 | Localização — lugar nomeado vs. coordenada precisa | aceito |
> | ADR-10 | Identidade de evento e idempotência | aceito |
> | ADR-11 | Emissão de eventos de mídia — publisher + `object` do storage + path por convenção | aceito |
>
> Questões conhecidas ainda **não decididas** ficam na seção [Questões em Aberto](#questões-em-aberto-diferidas) ao fim — fora da numeração de ADRs, pois não são decisões.
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
- **Consequências:** o sistema passa a ter **dois storages** com ciclos de vida e garantias distintos (o rápido é consultável por série temporal; o lento é referenciado). Surge a necessidade de manter os dois consistentes — um evento pode apontar (`blob_ref`) para um blob que ainda não foi replicado, ou um blob pode existir sem evento de domínio. O preço aceito é essa coordenação entre os dois planos (ver ADR-10 para identidade e a seção de Questões em Aberto para a dupla emissão).
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
    - *Como cada campo é fisicamente gravado* (índice, coluna, documento; "tag vs field")? → plano de **armazenamento**, responsabilidade **exclusiva do adaptador de saída** (ver ADR-7), invisível ao modelo.
  Analogia: um contrato/DTO fixa os campos; o serializador/ORM decide a persistência. Fixar o contrato de antemão é justamente o que *libera* o adaptador para escolher o mapa físico sem afetar o domínio.
- **Alternativa descartada:** (a) um schema ad-hoc por tipo de fonte (o estado atual: `node_id`/`camera`/`bucket` despadronizados) — impede consultas genéricas; (b) um modelo `{kind, context}` puro (todo campo não-promovido dentro de um único contêiner) — logicamente elegante, mas obriga o sistema a decidir item a item o papel físico de cada campo; descartado por custo de busca/indexação. Reconsiderar se o banco mudar para documental.
- **Nota (nível de abstração):** a *abertura* de `context{}`/`attrs{}` — aceitar chaves novas sem migração — é propriedade do **modelo**. Como o adaptador de saída materializa dinamicamente essas chaves (para cumprir a promessa "qualificador novo sem migração") é detalhe do adaptador, tratado no doc de arquitetura, não aqui.
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

### ADR-6: Modelo híbrido — consolidado no ADR-3

> **Consolidado.** Esta decisão (promover `source`/`measure`/`value`/`blob_ref` e manter
> `context{}`/`attrs{}` abertos) era uma paráfrase do critério de dois níveis do ADR-3.
> Para evitar duplicação e risco de divergência, foi **absorvida pelo ADR-3** — incluindo
> a alternativa descartada (`{kind, context}` puro) e a nota sobre a *abertura* ser
> propriedade do modelo. Âncora mantida para não quebrar referências.
- **Status:** supersedido por ADR-3

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
- **Consequências:** trocar de banco no futuro exige **escrever um novo adaptador de saída (consumidor)** do zero — não há interface pronta que garanta portabilidade. Aceita-se pagar esse custo *quando* (e se) um segundo banco entrar em cena, em troca de não carregar maquinaria especulativa agora. O risco é subestimar esse custo futuro; mitigação = manter o modelo canônico neutro (ADR-3), o que já concentra o acoplamento no adaptador.
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
- **Consequências:** cada adaptador de saída carrega a complexidade de derivar identidade e deduplicar — não é "de graça". Onde a fonte não fornece `event_id` nem `blob_ref`, o adaptador **precisa** de um discriminador real para a tripla `source+measure+ts`; se não houver, resta escolher entre risco de **perda silenciosa** (dois eventos legítimos idênticos colapsam) ou de **duplicata no replay**. Esse trade-off é real e não eliminado por este ADR — apenas localizado no adaptador. Recomendação prática: fontes que possam gerar um `event_id` (mesmo um contador monotônico por nó) tornam a dedup determinística e o replay seguro.
- **Fronteira (nível de abstração):** este ADR fixa apenas a *política* de identidade e a responsabilidade (adaptador). O **mecanismo físico** de como o discriminador é calculado e de como a dedup se materializa no banco é detalhe do adaptador de saída — vive no doc de arquitetura, não aqui e nem no [00-conceptual-model.md](00-conceptual-model.md) (o core neutro não conhece garantia de entrega nem dedup).
- **Status:** aceito

---

### ADR-11: Emissão de eventos de mídia — publisher emite o evento de domínio; `object` vem do storage; path por convenção

- **Decisão:** quando um fato do mundo produz um blob, o **publisher emite no máximo um evento de domínio** (`detection`/`annotation`) já contendo o `blob_ref`; ele **não** emite o evento `object` — esse é gerado pelo **storage** (bucket notification do MinIO). O `object_key` é **composto por uma convenção conhecida** a partir de dados que o gerador já possui (ex.: `{tipo}/{data}/{device_id}-{ts}.{ext}`), **nunca hardcoded** no dispositivo e **sem round-trip** de upload. O `blob_ref` é a URI neutra `{esquema}://{bucket}/{object_key}` (ver §0.2). A ligação `object` ↔ domínio é feita **exclusivamente pelo `blob_ref` compartilhado** (realiza a Q1 e §0.5).
- **Por quê:** (1) o `object` já é gerado "de graça" pelo storage — o device também emiti-lo duplicaria o mesmo fato de infraestrutura e gastaria transmissões (crítico em IoT LoRa/bateria/solar). (2) A correlação por `blob_ref` já era decisão registrada (Q1); nada novo é inventado. (3) Como o path é composto de dados que o gerador já tem, ele é conhecido *antes* do upload — esperar o retorno do upload adicionaria round-trip e um estado de erro sem informação nova. (4) Convenção (não hardcode) mantém o firmware/app desacoplado da organização interna do bucket (§0.2/§0.7). (5) Sensores puros seguem emitindo um único `metric`; a questão não se aplica a eles.
- **Exemplo concreto (uma câmera detecta uma pessoa):** um único fato produz **dois** eventos, de duas fontes, ligados pelo mesmo `blob_ref`.
    - Evento de domínio, emitido pelo **Frigate** (`detection`):
      ```jsonc
      {
        "ts": 1709827200000, "kind": "detection",
        "source": "camera-entrada", "measure": "person", "value": null,
        "blob_ref": "s3://media/clips/2026-07-28/camera-entrada-1709827200.mp4",
        "context": { "zone": "garagem" },
        "attrs": { "score": 0.87, "event_id": "1709827200.123-abc" }
      }
      ```
    - Evento de infraestrutura, emitido pelo **MinIO** (`object`), com o **mesmo `blob_ref`**:
      ```jsonc
      {
        "ts": 1709827200450, "kind": "object",
        "source": "media", "measure": "video/mp4", "value": null,
        "blob_ref": "s3://media/clips/2026-07-28/camera-entrada-1709827200.mp4",
        "context": {},
        "attrs": { "size_bytes": 481239, "etag": "9f8c…", "event": "s3:ObjectCreated:Put" }
      }
      ```
    - **`object_key`** = `clips/2026-07-28/camera-entrada-1709827200.mp4` (path relativo ao bucket). **`blob_ref`** = a URI neutra completa `s3://media/{object_key}`. É a igualdade do `blob_ref` que correlaciona os dois eventos, sem correlação mágica.
- **Alternativas descartadas:**
    - (a) **Publisher emite ambos** (`object` + domínio) — duplica o `object` que o MinIO já gera; dobra transmissões pelo pior motivo.
    - (b) **Sistema deriva o evento de domínio do `object`** — exigiria o core reinterpretar a semântica a partir do path; viola a neutralidade (§0.7) e "o adaptador nunca reinterpreta o rótulo" (§0.6).
    - (c) **Path retornado pelo upload (round-trip)** — adiciona complexidade e um estado de erro sem melhoria, já que a convenção torna o path conhecido de antemão.
    - (d) **Path hardcoded no dispositivo** — acopla o firmware à organização interna do bucket; reorganizar prefixos exigiria reprogramar dispositivos de campo.
- **Consequências:** a convenção de nomes vira um **artefato versionado** no repositório (contrato único), implementado por cada gerador. Um blob pode existir (via `object`) sem o evento de domínio correspondente, ou vice-versa — a janela de inconsistência da ADR-2 permanece, mitigada pela correlação por `blob_ref`. A dedup do `object` gerado pelo MinIO segue a ADR-10.
- **Status:** aceito

---

## Questões em Aberto (Diferidas)

> Isto **não é uma decisão** — é uma consequência conhecida cuja *solução física*
> pertence ao adaptador de saída e ainda não foi fixada. Por isso vive fora da
> numeração de ADRs. Quando for resolvida, vira um ADR novo. Registrada
> aqui apenas para não se perder.

### Q1 — Dupla emissão por um fato (`object` + evento de domínio)

Um mesmo fato do mundo pode gerar dois eventos legítimos — ex.: uma `detection`
(domínio) e um `object` (infraestrutura do data lake) que compartilham o mesmo
`blob_ref`. Isto é **característica do domínio, não defeito**: descrevem aspectos
distintos (o que foi reconhecido vs. o que entrou no data lake). O único efeito
colateral é **dupla contagem** em agregações ingênuas; a mitigação (escopo/tabela
separada, tag reservada, ou convenção de query `kind != object`) é escolha do
adaptador, **diferida**. Correlação entre os dois já está garantida pelo `blob_ref`
compartilhado (ver §0.5 do modelo conceitual).
