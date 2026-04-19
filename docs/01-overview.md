# 1. Visão Geral

Sistema de monitoramento distribuído para uma propriedade de agrofloresta, capaz de
ingerir dados heterogêneos — telemetria de sensores, eventos de movimento, fotos,
vídeos e áudio — processá-los em tempo real e armazená-los com políticas de retenção
diferenciadas. O sistema é projetado para começar pequeno e escalar horizontalmente
conforme a propriedade e a quantidade de sensores crescem.

## 1.1 Princípios de Design

- **Montar certo desde o início**: preferir componentes que escalam sem necessidade de
  substituição futura, mesmo que consumam mais recursos agora.
- **Custo baixo**: rodar em hardware próprio (sem cloud), com sincronização geográfica
  entre dois pontos físicos.
- **Genérico**: o sistema aceita qualquer tipo de dado (sensores ambientais, câmeras de
  segurança, drones, áudio, etc.) sem mudanças arquiteturais.
- **Dois fluxos de dados**: dados leves (sensores) via MQTT/streaming e dados pesados
  (mídia) direto para object storage, unificados por um barramento de eventos central.
