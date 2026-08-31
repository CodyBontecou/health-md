---
title: App para Android
description: Configure o Health.md para Android, exporte dados do Health Connect para Markdown, Obsidian Bases, JSON e CSV, escolha pastas pelo Storage Access Framework, agende exportações e automatize com Tasker ou adb.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Do Health Connect para arquivos privados</p>
  <p>O Health.md para Android lê o Health Connect no dispositivo e grava Markdown, Obsidian Bases, JSON ou CSV nas pastas que você escolher. Sem conta do Health.md, sem nuvem de dados de saúde e sem assinatura.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Baixar no Google Play</a>
    <a class="docs-button-secondary" href="/pt-br/docs/export/">Ler a documentação de exportação</a>
  </div>
</div>

<div class="reference-stats">
<div><strong>106</strong><span>métricas selecionáveis do Health Connect</span></div>
<div><strong>4</strong><span>formatos de exportação</span></div>
<div><strong>10</strong><span>ações gratuitas de exportação manual</span></div>
<div><strong>0</strong><span>contas obrigatórias na nuvem do Health.md</span></div>
</div>

## O que o app para Android faz

O Health.md para Android transforma o Health Connect em um diário de saúde que prioriza o armazenamento local. Escolha as métricas importantes para você, visualize a saída e exporte arquivos organizados para uma pasta local, um cofre do Obsidian, uma pasta sincronizada por um provedor ou qualquer provedor de documentos do Android que conceda acesso de gravação.

<div class="options">
  <div class="option"><strong>Health Connect como fonte</strong><p>Lê atividade, sono, coração, sinais vitais, medidas corporais, nutrição, treinos e outras categorias pelas APIs do Health Connect no dispositivo Android.</p></div>
  <div class="option"><strong>Saída nativa para Obsidian</strong><p>Grava notas diárias, YAML/frontmatter, notas compatíveis com Obsidian Bases, entradas individuais e JSON compatível com o plugin Health.md para Obsidian.</p></div>
  <div class="option"><strong>Armazenamento nativo do Android</strong><p>Usa o Storage Access Framework para você escolher pastas disponibilizadas pelo armazenamento local, Obsidian, Google Drive, OneDrive, Syncthing ou outro provedor.</p></div>
</div>

## Requisitos

- Android 9 / API 28 ou mais recente.
- Um dispositivo ou emulador compatível com o Health Connect.
- Dados no Health Connect provenientes de apps Android, dispositivos vestíveis ou serviços que gravem no Health Connect.
- Uma pasta ou um provedor de documentos que permita acesso de gravação para exportações.

## Primeira exportação

1. Instale o Health.md pelo Google Play.
2. Abra a configuração do **Health Connect** e conceda acesso apenas às categorias que você deseja exportar com o Health.md.
3. Escolha o destino de exportação pelo seletor de pastas do Android.
4. Escolha os formatos: Markdown, Obsidian Bases, JSON, CSV ou qualquer combinação.
5. Selecione as métricas e o intervalo de datas.
6. Visualize a saída.
7. Toque em exportar e verifique os arquivos gerados na sua pasta ou no seu cofre.

O plano gratuito inclui 10 ações de exportação manual para você testar permissões, acesso à pasta, formatos e seu fluxo no Obsidian antes de desbloquear exportações ilimitadas.

## Destinos no Android

O Android não usa o destino de rede local iPhone → Mac. Em vez disso, ele usa o Storage Access Framework do Android.

| Destino | Status no Android |
|---|---|
| Pasta local do dispositivo | Compatível pelo seletor de pastas |
| Cofre do Obsidian | Compatível quando a pasta do cofre é disponibilizada ao seletor do Android |
| Google Drive, OneDrive, Syncthing, Obsidian Sync e provedores semelhantes | Compatíveis quando o provedor disponibiliza pastas graváveis |
| Destino de rede local iPhone/Mac | Específico das plataformas Apple; não é usado pelo Android |

Se um provedor não disponibilizar pastas graváveis pelo seletor do Android, o Health.md não poderá gravar diretamente nele com segurança. Escolha uma pasta de provedor que conceda acesso de gravação persistente ou exporte localmente e sincronize com a ferramenta de sua preferência.

## Formatos

O app para Android segue os mesmos objetivos de arquivos simples do app para Apple:

| Formato | Uso indicado |
|---|---|
| Markdown | Resumos diários de saúde legíveis, modelos e notas |
| Obsidian Bases | Notas centradas em frontmatter que podem ser consultadas em visualizações de banco de dados do Obsidian |
| JSON | Payloads diários estruturados para scripts, painéis, notebooks e o plugin Health.md para Obsidian |
| CSV | Fluxos de trabalho em planilhas e análises |

As exportações JSON do Android foram projetadas para serem compatíveis com as visualizações do Health.md no Obsidian. As exportações Markdown e Bases usam o mesmo fluxo centrado em frontmatter documentado no [guia de formatos](/pt-br/docs/format/).

## Agendamento e automação

As exportações agendadas exigem a compra única e vitalícia. As exportações agendadas usam um alarme exato de execução única quando você concede acesso a Alarmes e lembretes do Android, com uma tarefa persistente do WorkManager como alternativa. Sem acesso a alarmes exatos, o WorkManager passa a ser o agendador principal; portanto, o horário selecionado é uma meta, não uma garantia rígida. O Health.md registra o histórico de exportações, pode recuperar datas agendadas perdidas e permite repetir execuções com falha.

Para Tasker, adb ou outras ferramentas de automação, o Health.md disponibiliza intents de broadcast exclusivamente explícitas. Chamadores externos precisam indicar diretamente o componente receptor:

```text
com.healthmd.android/com.healthmd.automation.AutomationReceiver
```

Exemplos:

```bash
adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_YESTERDAY

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_LAST_DAYS \
  --ei com.healthmd.android.extra.DAYS 7

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_RANGE \
  --es com.healthmd.android.extra.START_DATE 2026-03-01 \
  --es com.healthmd.android.extra.END_DATE 2026-03-07
```

A automação usa por padrão o perfil ativo, incluindo destino, formatos, métricas, contabilização e histórico congelados. Um extra `PROFILE` pode selecionar um perfil estável por ID ou nome; uma referência desconhecida falha com segurança em vez de usar as configurações atuais. Execuções agendadas também ficam ligadas ao perfil. Consulte [Perfis de exportação](/pt-br/docs/export-profiles/).

### Requisitos em segundo plano e cancelamento agendado

- Permita leituras do Health Connect em segundo plano para exportações sem supervisão; caso contrário, abra o Health.md.
- Mantenha as notificações ativadas para mostrar trabalho ativo, serviço em primeiro plano e avisos de recuperação.
- Conceda Alarmes e lembretes somente para alarmes exatos. Sem acesso, o trabalho é persistente, mas o horário é aproximado.
- Cancelar uma execução agendada interrompe só a tentativa. Datas concluídas permanecem, as pendentes podem ser repetidas e o agendamento segue ativo.

## Fontes de saúde

O Health Connect é o caminho padrão para exportação local. O app para Android também inclui uma área de configuração de fontes de saúde para ecossistemas como Samsung Health, Huawei Health, Fitbit, Garmin, Withings, Oura, Polar e WHOOP. Quando esses ecossistemas gravam no Health Connect, o Health.md pode exportar os registros resultantes do Health Connect. Importações diretas de provedores em nuvem exigem autorização do provedor e podem ter requisitos adicionais de configuração ou disponibilidade.

O Google Fit foi intencionalmente excluído da lista de provedores compatíveis porque o Health Connect é a camada de dados de saúde preferencial do Android.

### Passos diários locais exatos

Os totais usam os limites exatos do dia local com fuso. O Health.md recorta e divide intervalos do Health Connect à meia-noite local antes de somar, evitando deslocamentos por viagens ou horário de verão.

## Preços e restauração

- O app para Android inclui 10 ações gratuitas de exportação manual.
- Exportações ilimitadas e automação agendada são desbloqueadas por uma compra única e vitalícia pelo Google Play Billing.
- Não há assinatura nem cobrança recorrente.
- O Google Play mostra o preço local vigente antes da compra.
- Restaurar Compra usa a Conta do Google que adquiriu o Premium.

Após uma desconexão temporária do Google Play Billing, o Health.md se reconecta e atualiza o direito automaticamente. Premium não é removido permanentemente; use Restaurar compra apenas se a conta continuar pendente após a conexão voltar.

## Modelo de privacidade

O Health.md para Android prioriza o armazenamento local:

- Os registros do Health Connect são lidos no seu dispositivo Android.
- As exportações são gravadas diretamente nas pastas que você escolher.
- O Health.md não opera um serviço de nuvem para dados de saúde.
- As configurações e o histórico de exportações permanecem no dispositivo.
- A cobrança é processada pelo Google Play.
- Pastas vinculadas a provedores são sincronizadas de acordo com os termos de cada provedor.

Para manter tudo o mais local possível, faça exportações manuais para uma pasta local do dispositivo e mantenha desativadas as exportações agendadas e a sincronização por provedores.

## Documentação relacionada

<div class="related">
  <a href="/pt-br/docs/export-profiles/"><span>Perfis</span>Salve destinos, configurações de saída, agendamentos e IDs estáveis de automação independentes.</a>
  <a href="/pt-br/docs/export/"><span>Exportação</span>Fluxo de exportação manual, intervalos de datas, pré-visualizações, histórico e saída de arquivos.</a>
  <a href="/pt-br/docs/metrics/"><span>Métricas</span>Como funcionam a seleção de métricas e as categorias no Health.md.</a>
  <a href="/pt-br/docs/format/"><span>Formatos</span>Markdown, Bases, JSON, CSV, unidades, nomes de arquivos e frontmatter.</a>
  <a href="/pt-br/docs/visualizations-roadmap/"><span>Obsidian</span>Como JSON e Markdown exportados alimentam as visualizações do Health.md.</a>
</div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">Última atualização: 31/08/2026</p>
