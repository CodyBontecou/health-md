---
title: "Datas do sono e notas diárias"
description: "Escolha a data de exportação do sono: janela de meio-dia a meio-dia, sono após a meia-noite, cochilos e resultados vazios."
---

Na terça de manhã, exporte **segunda-feira**, normalmente **Ontem**, para o sono da noite anterior. O resumo diário do Health.md usa uma janela local das **12:00 às 12:00**: de segunda ao meio-dia até terça ao meio-dia, não o limite de meia-noite da atividade.

<div id="sleep-journal-window"></div>

## Por que o sono aparece na nota de ontem

A janela mantém uma noite habitual unida, mesmo quando você se deita após a meia-noite. Inclui o primeiro meio-dia e exclui o seguinte. Sono que cruza o meio-dia pode contribuir para resumos de dias adjacentes. Os horários originais não são alterados para corresponder à nota.

Apple e Android compartilham essa janela nos resumos compatíveis. Métricas, estágios, registros e agregações podem diferir. Não existe opção para mover o resumo para a data de despertar.

<div id="sleep-date-examples"></div>

## Qual data exportar?

Exemplos fictícios em horário local, não dados de saúde:

| Sono ou atividade | Data de exportação |
| --- | --- |
| Segunda 23:45 a terça 07:30 | **Segunda-feira** |
| Terça 01:00 a terça 07:30 | **Segunda-feira**, não terça |
| Cochilo na terça, 14:00 a 14:30 | **Terça-feira** |
| Passos e atividade da terça | **Terça-feira** |
| Noite de segunda e atividade da terça | **Segunda e terça** |

Confira o fuso local da exportação. A data de despertar de outro app ou a hora de modificação do arquivo não determina o dia do diário.

<div id="sleep-empty-checks"></div>

## Se a nota esperada estiver vazia

1. Confira o dia do diário e as métricas de sono selecionadas.
2. Aguarde a sincronização do relógio ou app com Apple Health ou Health Connect; confira a prévia e exporte o dia novamente.
3. Revise os acessos. No iPhone, um resultado vazio do HealthKit não revela se a leitura foi negada. No Android, confirme que a fonte gravou o registro compatível no Health Connect.
4. Confira o destino e os resultados gravados, ignorados ou com falha. Uma prévia não prova que um arquivo foi salvo. Ausente não é zero.

Daily Note Injection e os resumos API Endpoint usam a mesma janela. Para dados atrasados, repita o dia ou revise a janela retrospectiva do agendamento. O trabalho em segundo plano não garante uma gravação bem-sucedida em um horário exato.

<div id="sleep-records-and-queries"></div>

## Resumos, registros e consultas de sessões

Registros brutos ou canônicos mantêm horários e regras de pertencimento próprios. Não reconstrua sessões a partir de um total diário nem some intervalos de origem como sono extra.

Na Apple, o arquivo bruto atribui os registros conforme o horário de início original dentro do dia local, de meia-noite a meia-noite. Já o resumo do sono recorta os intervalos à janela do diário, de meio-dia a meio-dia. Assim, uma consulta bem-sucedida aos registros brutos de Sleep Analysis pode conter registros da manhã enquanto o resumo do sono daquela data está vazio. Exporte a data anterior do diário e confira `time_context.calendar_timezone` antes de investigar um resumo ausente. Por exemplo, os registros de 22 de setembro das 04:03 às 11:52 UTC pertencem inteiramente ao resumo de 21 de setembro em UTC; em Europe/Lisbon, os últimos 52 minutos ficam depois do meio-dia local e contribuem para 22 de setembro.

O sono dividido em estágios não exige um registro explícito `inBed`: quando ele está ausente, os resumos da Apple usam a união dos intervalos disponíveis dos estágios de sono. A falta de dados de tempo na cama não cria uma duração na cama. Uma consulta de resumo que falhou deve aparecer em `diagnostics.partial_failures`; uma consulta bem-sucedida sem intervalos válidos representa uma ausência de dados válida. A frequência cardíaca em repouso usa uma consulta separada por dia do calendário e exige uma medição real de frequência cardíaca em repouso; os estágios de sono ou apenas a permissão de leitura não a fornecem.

`healthmd_sleep_sessions` requer uma configuração CLI/MCP compatível com **Apple Health**. Consultas MCP tipadas no Android não são suportadas atualmente. Veja [capacidades por plataforma](/pt-br/docs/guides/platform-features/) e [MCP](/pt-br/docs/mcp/).

Outros guias: [agendamento](/pt-br/docs/scheduling/), [solução de problemas](/pt-br/docs/troubleshooting/) e [formatos](/pt-br/docs/format/).
