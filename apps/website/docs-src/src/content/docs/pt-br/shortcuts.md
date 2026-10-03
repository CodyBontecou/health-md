---
title: "Atalhos e App Intents"
description: "Use sete ações publicadas e duas ações de contexto do Mac do código em desenvolvimento no Atalhos e na Siri."
---

<div class="availability preview"><strong>Sete ações publicadas · nove no código atual</strong><p>As duas ações de contexto do Mac exigem builds compatíveis de iPhone e Mac. Consulte as notas da versão exata.</p></div>

## Ações

- exportar ontem, uma data, um intervalo ou os últimos N dias;
- obter resumo de saúde ou último estado;
- ativar ou suspender o agendamento;
- **Refresh Mac Health Context** (desenvolvimento): atualização criptografada durável vinculada ao perfil;
- **Get Mac Context Refresh Status** (desenvolvimento): estado e job ID.

As quatro ações de exportação aceitam um **Perfil** opcional. Nome desconhecido falha sem fallback. Atalhos comuns gravam na pasta do iPhone e não mudam silenciosamente para API Endpoint ou Connected Mac.

Permitir execução bloqueada não desbloqueia o HealthKit. O Health.md preserva a solicitação e mostra **Health Export Needs Attention**.

### Automação matinal

1. Crie automação por horário.
2. Adicione **Export Yesterday's Health Data**.
3. Adicione **Get Last Export Status** e uma notificação.

Ontem inclui o sono cuja noite começou ontem. Veja [Datas do sono](/pt-br/docs/sleep-date-attribution/).

<div class="related"><a href="/pt-br/docs/export-profiles/"><span>Perfis</span>Identidades estáveis.</a><a href="/pt-br/docs/release-status/"><span>Compatibilidade</span>Versões qualificadas.</a></div>
