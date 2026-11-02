---
title: "Aplicativo Android"
description: "Configure Health.md para Android. Exporte dados Health Connect , selecione pastas do Storage Access Framework, agende exportações e automatize com Tasker ou adb."
---

<div class="docs-hero">
 <p class="docs-eyebrow"> Health Connect para arquivos privados </p>
 <p> Health.md para Android lê Health Connect no dispositivo e grava Markdown , Obsidian Bases, JSON ou CSV nas pastas que você escolher. Este fluxo de trabalho de exportação de pasta não requer conta Health.md . As opções de acesso Google Play e o acesso incluído F-Droid são descritos abaixo. </p>
 <div class="docs-actions">
 <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener"> Entre em Google Play </a>
 <a class="docs-button-secondary" href="#distribution-status"> F-Droid status de publicação </a>
 <a class="docs-button-secondary" href="/pt-br/docs/export/"> Leia documentos de exportação </a>
 </div>
 <p id="distribution-status"> F-Droid a publicação do catálogo está pendente. Obtenha a versão atual do Android em Google Play . </p>
 </div>

<div class="reference-stats">
 <div> <strong> 106 </strong> <span> métricas selecionáveis Health Connect </span> </div>
 <div> <strong> 4 </strong> <span> formatos de exportação </span> </div>
 <div> <strong> 2 </strong> <span> Canais de distribuição Android </span> </div>
 <div> <strong> 0 </strong> <span> Health.md contas na nuvem necessárias </span> </div>
 </div>

## O que o aplicativo Android faz

Health.md para Android transforma Health Connect em um diário de saúde local. Escolha as métricas necessárias e visualize o resultado. Em seguida, exporte os arquivos para uma pasta local, cofre Obsidian , pasta do provedor sincronizado ou provedor de documentos Android graváveis.

<div class="options">
 <div class="option"> <strong> Health Connect fonte </strong> <p> Lê atividade, sono, coração, sinais vitais, medidas corporais, nutrição, exercícios e outras categorias por meio das APIs Health Connect no dispositivo Android. </p> </div>
 <div class="option"> <strong> Obsidian -saída nativa </strong> <p> Escreve notas diárias, YAML/frontmatter, Obsidian notas amigáveis ​​para bases, entradas individuais e JSON compatível com o plugin Health.md Obsidian . </p> </div>
 <div class="option"> <strong> Armazenamento nativo do Android </strong> <p> Usa o Storage Access Framework para que você possa escolher pastas expostas pelo armazenamento local, Obsidian , Google Drive, OneDrive, Syncthing ou outro provedor. </p> </div>
 </div>

## Requisitos

- Android 9/API 28 ou mais recente.
- Um dispositivo ou emulador compatível com Health Connect .
- Health Connect dados de aplicativos, wearables ou serviços Android que gravam em Health Connect .
- Um provedor de pasta ou documento que permite acesso de gravação para exportações.

## Primeira exportação

1. Instale a versão Health.md atual de Google Play .
2. Abra ** Health Connect ** configure e conceda apenas as categorias que você deseja que Health.md exporte.
3. Escolha o destino de exportação através do seletor de pastas do Android.
4. Escolha os formatos: Markdown , Obsidian Bases, JSON, CSV ou qualquer combinação.
5. Selecione métricas e intervalo de datas.
6. Visualize a saída.
7. Toque em exportar e verifique os arquivos gerados em sua pasta ou cofre.

A versão do telefone Google Play habilitada para assinatura requer avaliação ativa, assinatura, vitalícia ou acesso permanente preservado para exportações manuais. As assinaturas qualificadas incluem uma avaliação de 7 dias; Lifetime não tem julgamento. A versão F-Droid inclui acesso ilimitado sem fluxo de compra ou restauração.

## Destinos no Android

O Android não usa o destino de rede local iPhone → Mac. Em vez disso, ele depende do Storage Access Framework do Android.

| Destino | Estado do Android |
| --- | --- |
| Pasta do dispositivo local | Compatível com o seletor de pastas |
| Obsidian cofre | Compatível quando a pasta do vault é exposta ao seletor do Android |
| Google Drive, OneDrive, Syncthing, Obsidian Sync e provedores semelhantes | Compatível quando o provedor expõe pastas graváveis |
| iPhone /destino de rede local Mac | Específico da plataforma Apple; não usado pelo Android |

Se um provedor não expor pastas graváveis ​​por meio do seletor do Android, Health.md não poderá escrever lá diretamente com segurança. Escolha uma pasta de provedor que conceda acesso de gravação persistente ou exporte localmente e sincronize com sua ferramenta preferida.

## Formatos

O aplicativo Android compartilha os mesmos objetivos simples do aplicativo Apple:

| Formatar | Use-o para |
| --- | --- |
| Markdown | Resumos, modelos e notas diárias de saúde legíveis |
| Obsidian Bases | Notas iniciais do Frontmatter que podem ser consultadas nas visualizações do banco de dados Obsidian |
| JSON | Cargas diárias estruturadas para scripts, painéis, notebooks e o plugin Health.md Obsidian |
| CSV | Fluxos de trabalho de planilha e análise |

As exportações JSON do Android são projetadas para serem compatíveis com as visualizações Health.md de Obsidian . As exportações Markdown e Bases usam o mesmo fluxo de trabalho focado no frontmatter documentado no [guia de formato](/pt-br/docs/format/).

## Agendamento e automação

Na versão de telefone Google Play habilitada para assinatura, as exportações programadas exigem avaliação ativa, assinatura, acesso vitalício ou permanente preservado; eles estão incluídos na compilação F-Droid . Eles usam um alarme exato e único quando você concede acesso aos alarmes e lembretes do Android, com WorkManager durável funcionando como backup. Sem acesso ao alarme exato, WorkManager se torna o agendador principal, portanto o horário selecionado é uma meta e não uma garantia definitiva. Health.md registra o histórico de exportação, pode recuperar datas agendadas perdidas e permite repetir execuções com falha.

Para Tasker, adb ou outras ferramentas de automação, Health.md expõe intenções de transmissão apenas explícitas. Os chamadores externos devem abordar diretamente o componente receptor:

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

A automação usa o perfil ativo por padrão, incluindo destino congelado, formatos, métricas, contabilidade e histórico. Um extra `PROFILE` fornecido pode selecionar um ID ou nome de perfil estável. Uma referência desconhecida falha ao ser fechada em vez de usar as configurações atuais. As execuções agendadas também ficam vinculadas ao seu perfil. Consulte [Exportar perfis](/pt-br/docs/export-profiles/).

### Preparação em segundo plano e cancelamento programado

- Permite leituras Health Connect em segundo plano para exportações autônomas. Caso contrário, abra Health.md para concluir a leitura dos dados de saúde.
- Mantenha as notificações ativadas para que o Android possa mostrar trabalho ativo, estado do serviço em primeiro plano, resultados e ações de recuperação.
- Conceda alarmes e lembretes apenas quando desejar agendamento exato de alarmes. Sem ele, o trabalho WorkManager durável permanece disponível, mas o tempo escolhido é aproximado.
- O cancelamento de uma execução agendada interrompe apenas essa tentativa. As datas concluídas permanecem completas, as datas não resolvidas podem ser repetidas e a programação recorrente permanece habilitada.

## Fontes de saúde

Health Connect é o caminho de exportação local em ambos os canais. A construção Google Play também inclui uma área de configuração de fonte de saúde para ecossistemas como Samsung Health, Huawei Health, Fitbit, Garmin, Withings, Oura, Polar e WHOOP. Onde esses ecossistemas são gravados em Health Connect , qualquer construção pode exportar os registros Health Connect resultantes. As importações diretas do provedor de nuvem e os retornos de chamada OAuth são somente Play. O catálogo do provedor F-Droid contém apenas Health Connect .

O Google Fit foi excluído intencionalmente da superfície do provedor compatível porque Health Connect é a camada de dados de saúde preferida do Android.

### Etapas exatas do dia local

Os totais de etapas diárias usam limites exatos de dias locais e zoneados. Antes da agregação, Health.md corta e divide intervalos Health Connect sobrepostos à meia-noite local. Assim, as mudanças nas viagens e no horário de verão não levam ao dia errado.

## Distribuição, preços e troca

- ** Google Play :** o lançamento do telefone habilitado para assinatura oferece assinaturas individuais semanais/anuais e vitalícias. Os assinantes qualificados pela primeira vez recebem uma avaliação de 7 dias e depois renovam automaticamente pelo preço exibido até serem cancelados por meio de Google Play . A vida útil é cobrada uma vez imediatamente, sem teste. Não resta nenhuma permissão local de livre exportação. O acesso permanente existente é preservado. Restore Purchase usa a conta do Google de compra; excluir o aplicativo ou comprar o Lifetime não cancela a assinatura. Compilações lançadas mais antigas podem mostrar a permissão anterior. A versão atual é apenas para telefone. O complemento Wear OS é adiado para um ciclo de qualificação posterior.
- ** F-Droid :** acesso ilimitado incluído. Não há contador gratuito, dependência de faturamento, acesso pago, compra ou ação de restauração.
- ** F-Droid escopo:** somente Health Connect , sem integração com Wear OS, OAuth direto do provedor de nuvem, análise do Play, atribuição ou telemetria de integração Health.md .
- **Resultado compartilhado:** ambos os canais usam a mesma captura Health Connect , exportadores, esquemas, ações de automação e protocolo de dispositivo direto.
- **Troca:** Google Play e F-Droid usam chaves de assinatura diferentes, portanto, mudar de canal requer a desinstalação do aplicativo primeiro.

Uma mudança de canal não migra compras, configurações, histórico, credenciais ou estado de transferência privada. Os arquivos exportados permanecem no destino que você escolheu.

Se Google Play Billing for desconectado temporariamente, o build do Play se reconectará e atualizará o estado de direito automaticamente. Uma perda temporária de serviço não remove permanentemente o Premium. Use Restaurar compra somente se a conta permanecer sem solução após o retorno da conectividade.

## Modelo de privacidade

Health.md para Android prioriza o local:

- Os registros -  Health Connect são lidos no seu dispositivo Android.
- As exportações são gravadas diretamente nas pastas que você escolher.
- Exportações de pastas principais e consultas diretas de dispositivos não criam uma cópia do servidor Health.md por padrão.
- As configurações e o histórico de exportação permanecem no dispositivo.
- O faturamento é feito por Google Play na versão do Play. F-Droid inclui acesso ilimitado sem cobrança e não contém código de telemetria Health.md ou identidade/estado de telemetria.
- As pastas suportadas pelo provedor são sincronizadas de acordo com os próprios termos desse provedor.

Se você quiser a configuração local mais rigorosa, execute exportações manuais para uma pasta de dispositivo local e deixe as exportações agendadas e a sincronização apoiada pelo provedor desativadas.

O piloto separado e opcional do Health.md Cloud é restrito a um único proprietário e guarda apenas exportações de API enviadas intencionalmente. Não há cadastro público nem sincronização automática de dispositivos; este fluxo de pastas não envia dados ao piloto. A [política de privacidade](/privacy-policy.html) descreve retenção, exclusão, cota e riscos de perda sem backup.

## Documentos relacionados

<div class="related">
 <a href="/pt-br/docs/export-profiles/"> <span> Perfis </span> Salve destinos independentes, configurações de saída, programações e IDs de automação estáveis. </a>
 <a href="/pt-br/docs/export/"> <span> Exportar </span> Fluxo de exportação manual, intervalos de datas, visualizações, histórico e saída de arquivo. </a>
 <a href="/pt-br/docs/metrics/"> <span> Métricas </span> Como a seleção de métricas e categorias funcionam em Health.md . </a>
 <a href="/pt-br/docs/format/"> <span> Formatos </span> Markdown , Bases, JSON, CSV, unidades, nomes de arquivos e frontmatter. </a>
 <a href="/pt-br/docs/visualizations-roadmap/"> <span> Obsidian </span> Como JSON exportado e Markdown potencializam visualizações Health.md . </a>
 </div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;"> Última atualização em 04/10/2026 </p>
