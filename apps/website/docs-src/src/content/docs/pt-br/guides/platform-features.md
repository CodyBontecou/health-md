---
title: Recursos por plataforma
description: O que o Health.md oferece no iPhone, iPad, Mac, Android, Wear OS e na CLI — recursos compartilhados e as diferenças honestas entre as plataformas.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Visão geral por plataforma</p>
  <p>O que o Health.md faz no iPhone, iPad, Mac, Android, Wear OS e na CLI — compartilhado onde as plataformas permitem, honesto onde elas diferem.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://apps.apple.com/us/app/health-md/id6757763969" target="_blank" rel="noopener">iPhone e Mac</a>
    <a class="docs-button-secondary" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Android</a>
  </div>
</div>

Legenda: ✓ disponível · ◐ disponível com diferenças de plataforma indicadas na linha · △ planejado ou em QA · ? disponibilidade não declarada · — não disponível nessa plataforma.

A CLI não é uma coluna separada de plataforma de dados de saúde: os recursos da CLI aparecem nas linhas de automação e mantêm a semântica da origem no iPhone ou no Android.

## Configuração e permissões

| Recurso | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Permissões de dados de saúde (escolha exatamente o que ler) | ✓ tipos do Apple Health | ◐ lê pelo iPhone emparelhado / destino no Mac | ✓ categorias do Health Connect | — |
| Escolher destino da exportação | ✓ cofre do Obsidian, iCloud Drive, Arquivos | ✓ pastas locais | ✓ qualquer provedor de pastas do Android (Drive, OneDrive, Syncthing, Obsidian Sync…) | — |
| Configuração inicial com prévia de exemplo | ✓ | ✓ | ✓ | — |
| Share My Setup (mover preferências entre dispositivos) | △ em QA | △ em QA | △ em QA | — |

## Leitura e exportação

| Recurso | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Exportações diárias para Markdown, Obsidian Bases, JSON, CSV | ✓ | ✓ (os arquivos chegam do iPhone) | ✓ | — |
| 225+ métricas do Apple Health / 106 métricas do Health Connect | ✓ | ✓ | ✓ | — |
| Prévia antes de gravar | ✓ | ✓ | ✓ | — |
| Perfis de exportação salvos com configurações independentes | ✓ gerenciar no iPhone; ? gerenciamento no iPad não declarado | ? gerenciamento não declarado | ✓ gerenciar no Android | — |
| Resumos semanais, mensais e anuais | ✓ | ✓ | △ planejado; requer um perfil de esquema do Android com revisão separada (as atuais v4/v5 permanecem inalteradas) | — |
| Histórico de exportação e nova tentativa | ✓ | ✓ | ✓ | — |
| Parar ou cancelar a execução ativa sem desativar o agendamento | ✓ datas concluídas preservadas; datas não resolvidas podem ser repetidas | ✓ | ✓ datas concluídas preservadas; datas não resolvidas podem ser repetidas | — |
| Arquivo ZIP de uma única execução | ✓ | ✓ | — | — |
| Detalhe de dados de resumo | ✓ | ✓ | ✓ | — |
| Série temporal detalhada para métricas selecionadas | ✓ | ✓ | ✓ | — |
| Arquivo canônico de registros de origem dos Registros de saúde sem perdas | ✓ `healthmd.healthkit_records` | ✓ | — exclusivo da Apple; veja os snapshots de API brutos | — |
| Exportação de snapshots de API brutos (JSON/NDJSON imutável) | — | — | ✓ Health Connect + Fitbit, Oura, WHOOP, Withings | — |

## Dados avançados

| Recurso | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Rastreamento individual de entradas (treinos, fases do sono, sinais vitais) | ✓ | ✓ | ✓ | — |
| Detalhes dos treinos com gráficos completos e trajetos quando disponíveis | ✓ | ✓ | ✓ | — |
| Exportação de humor / State of Mind | ✓ | ✓ | — (sem equivalente no Health Connect) | — |
| Eventos de doses de medicamentos | ✓ | ✓ | — (sem equivalente no Health Connect) | — |
| Medições de pressão arterial, glicose, oxigênio e temperatura | ✓ | ✓ | ✓ | — |
| Dados de provedores terceiros | ◐ seção WHOOP na exportação (beta) | ◐ | ✓ snapshots brutos nativos do provedor | — |

Alguns dados deliberadamente **não são tratados como equivalentes** entre as plataformas: a variabilidade da frequência cardíaca é SDNN no Apple e RMSSD no Android e no WHOOP — o Health.md as mantém como métricas distintas em vez de misturá-las. A temperatura do pulso do Apple Watch e a temperatura da pele do Health Connect também são mantidas separadas.

## Automatizar e integrar

| Recurso | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Exportações recorrentes agendadas | ✓ notificações + fallback de APNs | ✓ | ✓ WorkManager (+ alarme exato opcional), recuperação após reinicialização | — |
| Automação do sistema | ✓ Atalhos / Siri / App Intents | — | ✓ Tasker, adb, intents de broadcast explícitos | — |
| Enviar exportações para o seu próprio endpoint de API HTTP(S) | ✓ | — | ✓ com armazenamento criptografado de cabeçalhos | — |
| Emparelhamento com a CLI independente (`healthmd`) | ✓ serviço direto em primeiro plano | ✓ incluída + independente | ✓ emparelhamento com código de 20 dígitos | — |
| Despertar para requisições diretas da CLI | ✓ espera limitada + APNs opcional | ✓ iniciador da CLI | ◐ espera limitada; FCM planejado | — |
| Servidor MCP para agentes de IA | ◐ incluído por meio do Mac; o MCP direto portátil e tipado é exclusivo do iPhone | ✓ incluído como `healthmd-mcp` | — MCP direto tipado não compatível | — |

## Dispositivos e superfícies de relance

| Recurso | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Widgets da tela inicial | ✓ resumo, anéis de atividade, faixa cardíaca, sono | — | ✓ resumo, atividade, faixa cardíaca, sono (passos substituem horas em pé) | — |
| Progresso de exportação na Atividade Ao Vivo | ✓ | — | — | — |
| Superfícies do relógio | ✓ app de relógio + 10 complicações | — | — | ✓ blocos + 10 complicações |
| Mac como destino de exportação (transferência local criptografada) | ✓ o iPhone envia | ✓ recebe | — | — |

## Compra e privacidade

| Recurso | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Nível gratuito | ✓ 10 ações de exportação manuais ou agendadas | — | ✓ 10 ações de exportação manuais | — |
| Desbloqueio | ✓ compra única vitalícia (individual / família) | ◐ mesmo desbloqueio da Apple | ✓ compra única vitalícia, com agendamento incluído | — |
| Privacidade com processamento local | ✓ sem nuvem de dados de saúde do Health.md | ✓ | ✓ | ✓ |
| Relatório para o profissional de saúde (um PDF para consultas) | ✓ | — | ✓ | — |

O Health.md não opera uma nuvem de dados de saúde. Os dados de saúde podem existir em destinos que você escolher, em contexto local criptografado e em estado de transferência privada limitado. Cada pasta, Mac, endpoint de API ou destino da CLI é configurado explicitamente. Perfis e agendamentos permanecem locais ao dispositivo onde foram criados. Veja os [perfis de exportação](/pt-br/docs/export-profiles/), o [guia do Android](/pt-br/docs/android/) e o [guia de exportação do iPhone](/pt-br/docs/export/) para o fluxo de trabalho de cada plataforma.
