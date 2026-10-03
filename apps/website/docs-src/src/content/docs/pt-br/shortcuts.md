---
title: "Atalhos e App Intents"
description: "Use sete ações do Health.md no Atalhos e na Siri. As ações de atualização do contexto do Mac são propostas, não disponíveis."
---

<div class="availability preview"><strong>Sete ações registradas no código</strong><p>Refresh Mac Health Context e Get Mac Context Refresh Status são propostas, não implementadas nem disponíveis em desenvolvimento. Acompanhe a <a href="https://github.com/CodyBontecou/health-md/issues/173">issue #173</a>; a disponibilidade exige implementação, qualificação e notas de uma versão Apple exata.</p></div>

## Ações

- exportar ontem, uma data, um intervalo ou os últimos N dias;
- obter resumo de saúde ou último estado;
- ativar ou suspender o agendamento.

### Ações de contexto do Mac propostas (não disponíveis)

A ação solicitada **Refresh Mac Health Context** usaria escopo explícito de perfil e datas, dispositivos compatíveis autenticados e aquisição durável de contexto sem arquivos de exportação nem consumo da cota de exportação de arquivos. **Get Mac Context Refresh Status** informaria o estado pendente/concluído/falho com uma identidade de tarefa recuperável. Esses são requisitos, não nomes de ações, parâmetros ou resultados suportados no aplicativo atual.

A atualização via MCP pelo computador não atende a uma automação pessoal do iOS. Não use Atalhos de exportação comuns como substitutos: eles mantêm a semântica de pasta do iPhone. Nenhuma automação pode prometer despertar um Mac em repouso ou contornar dados protegidos do HealthKit. A verificação da automação em um iPhone físico após despertar ainda é necessária antes de qualificar esse recurso.

As quatro ações de exportação aceitam um **Perfil** opcional. Nome desconhecido falha sem fallback. Atalhos comuns gravam na pasta do iPhone e não mudam silenciosamente para API Endpoint ou Connected Mac.

Permitir execução bloqueada não desbloqueia o HealthKit. O Health.md preserva a solicitação e mostra **Health Export Needs Attention**.

### Automação matinal

1. Crie automação por horário.
2. Adicione **Export Yesterday's Health Data**.
3. Adicione **Get Last Export Status** e uma notificação.

Ontem inclui o sono cuja noite começou ontem. Veja [Datas do sono](/pt-br/docs/sleep-date-attribution/).

<div class="related"><a href="/pt-br/docs/export-profiles/"><span>Perfis</span>Identidades estáveis.</a><a href="/pt-br/docs/release-status/"><span>Compatibilidade</span>Versões qualificadas.</a></div>
