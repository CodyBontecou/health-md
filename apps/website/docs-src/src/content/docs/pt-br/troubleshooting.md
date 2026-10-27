---
title: "Faltam dados na exportação do Apple Health? Solução de problemas"
description: "Resolva exportações vazias do Apple Health ou Health Connect, sono ausente, detalhes CSV, falhas de gravação e atrasos. Comece com um dia verificável."
---

Se faltam dados em uma exportação do Apple Health ou Health Connect, diferencie um **problema de leitura** de uma **falha ao gravar o arquivo**. Um dado ausente não é um zero medido.

## Comece por um dia que possa conferir

1. Confirme um valor registrado e sua data no Apple Health ou Health Connect. Aguarde a sincronização do relógio ou app de origem.
2. No Health.md, confira perfil ativo, métrica, datas, formato e destino. Comece com uma métrica compatível de um dia completo.
3. Desbloqueie o telefone, abra o Health.md e use a prévia quando disponível. Depois exporte e confira o resultado e o destino reais. A prévia não comprova que um arquivo foi salvo.

Veja a [primeira exportação no iPhone](/pt-br/docs/iphone-first-export/) ou a [configuração do Android](/pt-br/docs/android/).

## Há dados na origem, mas a exportação está vazia

No iPhone, confira as categorias permitidas ao Health.md no Apple Health. **O HealthKit não informa se a permissão de leitura foi negada**. Um resultado vazio não distingue acesso restrito de ausência de registros correspondentes. Uma solicitação de permissão bem-sucedida também não confirma todas as categorias. Veja a [documentação da Apple](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).

No Android, confirme que o app de origem gravou o registro no Health Connect e que o Health.md pode ler esse tipo compatível. Dados visíveis apenas em outro app podem não estar disponíveis para exportação. Veja a [lista de verificação do Google](https://support.google.com/android/answer/13770384).

Após sincronizar ou alterar permissões, confira métrica e data novamente. Não substitua valores ausentes por zero.

Se um resultado estruturado indicar `complete_empty`, diferencie-o de saída não compatível, parcial, ignorada ou com falha. Ele não comprova um zero medido nem revela uma decisão de permissão de leitura.

## O sono da última noite não aparece em Hoje

O Health.md usa uma janela local de sono **de meio-dia a meio-dia** no Apple e no Android. Na terça de manhã, exporte **Ontem** (segunda), inclusive para sono iniciado após a meia-noite de terça, ou segunda e terça para sono e atividade. Se a fonte sincronizar tarde, repita o dia do diário. Veja os [exemplos de datas](/pt-br/docs/sleep-date-attribution/#sleep-date-examples).

## A prévia mostra dados, mas a pasta está vazia

No iPhone, confira se o perfil ativo grava em pasta local, Connected Mac ou API Endpoint. Para arquivos, verifique pasta, subpasta, nome e resultado: gravado, ignorado ou falhou. Ignorar pode fazer parte do comportamento de gravação escolhido. Selecione novamente uma pasta indisponível e confira seu provedor. Veja [pastas e vaults](/pt-br/docs/folder-vault/) e [perfis](/pt-br/docs/export-profiles/).

## O CSV tem totais, mas não as leituras esperadas

No iPhone, Summary e Detailed Time-Series têm níveis de detalhe diferentes. Confira Data Detail e métricas antes de ampliar as datas. Metadados não são medições de saúde. Preserve unidades e diferencie totais diários de registros de origem. Lossless Health Records tem um status de captura próprio; um resumo não comprova captura completa. Veja a [referência de formatos e cobertura](/pt-br/docs/reference/export-formats/).

## Uma exportação agendada não chegou

O trabalho em segundo plano do iOS e o Android WorkManager usam horários alvo, sem garantir a entrega. Desbloqueie o dispositivo, abra o Health.md e confira histórico e recuperação pendente antes de iniciar outra execução. Uma notificação não comprova uma gravação bem-sucedida. Veja [agendamento no iPhone](/pt-br/docs/scheduling/) ou [automação no Android](/pt-br/docs/android/).

## Timeout da CLI

Timeout não cancela trabalho aceito:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

Antes de afirmar completude, confira estado, datas ausentes, cobertura, `next_cursor`, versão e limitações. `--allow-partial` só muda a política de saída.

## Peça ajuda sem compartilhar registros de saúde

Informe versões do app e do sistema, plataforma, formato e se o problema é dado vazio, saída ignorada ou falha de gravação. Oculte informações privadas de capturas e logs. Não publique valores de saúde, rotas, documentos clínicos, tokens, códigos de pareamento ou caminhos privados.

<div class="related"><a href="/pt-br/docs/cli-jobs/"><span>Trabalhos</span>Retomar e cancelar.</a><a href="/pt-br/docs/release-status/"><span>Versões</span>Compatibilidade.</a></div>
