---
title: "Guia prático de consultas tipadas"
description: "Execute consultas novas ou em cache de métricas, sono, treinamento, treinos, cobertura, comparação de períodos e evidências do Health.md, com paginação explícita e indicação de dados ausentes."
---

Os comandos de alto nível da CLI transformam perguntas comuns sobre dados de saúde em operações de consulta fixas e tipadas. Por padrão, eles obtêm do iPhone os dados solicitados, consultam o contexto criptografado no Mac e retornam JSON versionado com evidências e cobertura.

Use a [extração canônica](/pt-br/docs/cli-extract/) quando precisar de dias completos de `healthmd.health_data` ou de registros de origem.

## Verifique a prontidão e descubra métricas

```bash
healthmd doctor
healthmd metrics list
healthmd metrics list --category Sleep
```

O catálogo de métricas retorna IDs canônicos, nomes de exibição, categorias, unidades e requisitos de disponibilidade. Ele não afirma que a autorização do HealthKit foi concedida para uma métrica.

Copie os IDs do catálogo em vez de tentar adivinhá-los.

## Consulte séries de métricas

```bash
healthmd query \
  --metric sleep_total \
  --metric sleep_deep \
  --from 2026-07-01 --to 2026-07-14 \
  --all-pages
```

As categorias são expandidas de acordo com o catálogo atual:

```bash
healthmd query --category Sleep --yesterday
healthmd query --category Heart --last 30 --all-pages
```

Vários sinalizadores de métrica e categoria são combinados. A aquisição de dados novos envia a seleção expandida ao iPhone sem alterar as configurações de exportação salvas.

A resposta usa um envelope `healthmd.cli_metric_query` v1. Ele mantém os diagnósticos de aquisição junto à resposta de consulta tipada aninhada.

## Dados novos, em cache e com reutilização de cobertura

Dados novos são o padrão:

```bash
healthmd query --metric resting_heart_rate --last 30
```

Isso solicita o escopo exato ao iPhone conectado, confirma a atualização dos dias criptografados do proprietário e então os consulta.

O modo em cache não entra em contato com o iPhone:

```bash
healthmd query --metric resting_heart_rate --last 30 --cached
```

Use o modo em cache para análise offline somente quando o horário de captura e a cobertura armazenados forem aceitáveis.

`--reuse-covered` verifica primeiro a cobertura criptografada dos resumos:

```bash
healthmd query --metric resting_heart_rate --last 30 --reuse-covered
```

O Health.md ignora a aquisição somente quando cada métrica e cada dia solicitados têm cobertura de resumo completa e compatível. Solicitações sem perdas e operações recém-projetadas de sessões de sono não usam esse atalho.

## Entenda os campos de conclusão

As respostas de consultas com dados novos separam três conceitos:

| Campo | Pergunta respondida |
|---|---|
| `requested_scope_status` | Todas as métricas, fontes, provedores e dias do proprietário solicitados foram concluídos nesta aquisição? |
| `corpus_status` | Outros ramos do corpus capturado relataram avisos, itens ignorados ou falhas? |
| `unrelated_skips` | Quais ramos ignorados ou sem suporte estavam fora do escopo solicitado? |

Um escopo solicitado completo pode coexistir com itens ignorados não relacionados no corpus. O Health.md mantém ambos os fatos, em vez de rebaixar falsamente o resultado solicitado ou ocultar os diagnósticos do corpus.

No caso de dados novos, a conclusão contabiliza somente os blobs substituídos após o início dessa atualização. Valores obsoletos em cache não podem satisfazer uma solicitação com falha.

## Percorra as páginas de resultados

Sem `--all-pages`, o comando retorna uma página limitada. Inspecione `next_cursor`:

```bash
healthmd query --category Activity --last 365 --output activity-page-1.json
jq '.query.next_cursor' activity-page-1.json
```

Um cursor não nulo significa que existem mais resultados. O status externo de alto nível permanece `partial_success` até que o percurso seja concluído.

O percurso automático segue cursores opacos com verificações de repetição:

```bash
healthmd query --category Activity --last 365 \
  --all-pages --output activity-all-pages.json
```

A resposta mantém o primeiro `healthmd.query_response` em `query`, as respostas versionadas posteriores em `pages` e um `healthmd.cli_query_receipt` v1 contendo as contagens de páginas, itens, fatos e evidências, além do status final do percurso.

O percurso automático tem limites agregados de páginas e bytes. Se eles forem atingidos, restrinja a seleção de datas ou métricas, ou use a [API de baixo nível](/pt-br/docs/agent-api/) para percorrer as páginas manualmente.

## Progresso e saída em tabela

Grave no stderr o progresso das fases, sem dados de saúde, e das páginas como JSONL:

```bash
healthmd query --category Sleep --last 90 \
  --all-pages --progress-json --output sleep.json \
  2> sleep-progress.jsonl
```

JSON é a saída completa. O modo de tabela é uma visualização TSV opcional e com perdas, destinada a uma pessoa no terminal:

```bash
healthmd query --metric resting_heart_rate --last 30 --format table
```

O rodapé da tabela preserva observações sobre cobertura, fonte, limitações, conclusão e itens ignorados não relacionados. Não use a saída em tabela quando um script precisar de valores tipados exatos ou evidências.

## Sessões de sono

Os estágios de sono do Apple Health atravessam a meia-noite e podem se sobrepor por fonte. O comando de sono cria sessões estáveis em vez de tratar cada dia do proprietário como um único total numérico.

```bash
healthmd sleep sessions --last-nights 14
healthmd sleep sessions --last-nights 14 --include-naps
healthmd sleep sessions --last-nights 14 \
  --window first:4h --physiology-metric heart_rate
```

Também estão disponíveis datas exatas e seleção de todo o histórico:

```bash
healthmd sleep sessions \
  --from 2026-07-01 --to 2026-07-14 \
  --window first:3h --all-pages

healthmd sleep sessions --all --all-pages
```

Cada sessão pode informar:

- identidade estável da sessão;
- data do proprietário e fuso horário local;
- timestamps exatos de início e término, locais e em UTC;
- classificação como sono noturno ou cochilo;
- totais dos estágios selecionados;
- duração observada e não monitorada;
- integridade e exclusões;
- janela fixa relativa à sessão;
- cobertura fisiológica de dias adjacentes;
- evidências de origem.

A aquisição de sessões solicita intervalos canônicos sem perdas dos estágios de sono e o conjunto canônico completo de métricas de estágio. O Health.md lê no máximo um dia técnico adjacente do proprietário para determinar os limites e então exclui do resultado as datas não relacionadas.

As fontes de estágios sobrepostas são deduplicadas para calcular a duração total do sono. O contexto em cache contendo apenas agregados é rotulado como `aggregated`; ele não alega cobertura de observação dos intervalos. Uma janela fixa `first:4h` nunca distribui proporcionalmente um agregado diário por quatro horas.

## Alinhamento entre treinos e sono

```bash
healthmd training align --last 14
healthmd training align --last 14 --workout running
healthmd training align --last 14 --workout running \
  --sleep-window first:4h \
  --physiology-metric heart_rate \
  --all-pages
```

Para cada treino selecionado, o Health.md encontra as sessões de sono elegíveis mais próximas, anteriores e posteriores, dentro de 36 horas. Ele informa:

- IDs estáveis de treinos e sessões;
- intervalos temporais exatos;
- janelas de sono solicitadas;
- contagens de amostras fisiológicas;
- cobertura dos estágios e das sessões;
- evidências e exclusões.

A operação é um alinhamento temporal determinístico. Ela não afirma que um treino causou um resultado de sono nem que o sono causou um determinado desempenho no treino. Ela lê no máximo dois dias técnicos adjacentes do proprietário e não retorna dados não relacionados.

## Listagem de treinos

```bash
healthmd workouts --yesterday
healthmd workouts --last 14 --all-pages
healthmd workouts \
  --from 2026-07-01 --to 2026-07-31 \
  --format table
```

A listagem de treinos preserva identidade estável, timestamps exatos, detalhes tipados, evidências e dados ausentes. Os resultados são ordenados pelo timestamp de início e pela identidade estável do treino. Não há um limite total fixo de treinos; os controles de página limitam cada resposta.

## Cobertura

Use a cobertura quando a pergunta for "Quais dados eu tenho?", em vez de "Qual é o valor?".

```bash
healthmd coverage --category Sleep --last 30
healthmd coverage \
  --metric steps --metric resting_heart_rate \
  --from 2026-01-01 --to 2026-06-30 \
  --all-pages
```

A cobertura retorna os intervalos solicitados e disponíveis, os dias considerados, os dias com valores e os intervalos de ausência acompanhados de status. Intervalos adjacentes com o mesmo status e motivo podem ser compactados sem perda de significado.

Um dia sem observações correspondentes pode ser `complete_empty`. Um dia que nunca foi sincronizado tem um status diferente. Nenhum deles se torna zero.

## Compare períodos exatos

A CLI nunca tenta adivinhar se uma métrica deve ser somada, ter sua média, mínimo ou máximo calculado, ser contada ou ter o valor mais recente selecionado. Informe a agregação ao lado de cada ID de métrica:

```bash
healthmd compare \
  --metric steps:sum \
  --metric resting_heart_rate:average \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

As agregações compatíveis são:

- `sum`
- `average`
- `minimum`
- `maximum`
- `latest`
- `count`
- `duration_sum`

Incompatibilidades de unidade ou tipo causam falha, em vez de serem combinadas silenciosamente. Um período sem dados não tem valor agregado. Uma linha de base igual a zero no primeiro período tem uma alteração absoluta, mas não uma alteração percentual, e inclui `zero_baseline` como limitação.

A direção é factual: `increased`, `decreased`, `unchanged` ou `not_comparable`. Ela nunca significa melhor ou pior.

## Pacotes de evidências de treinamento

```bash
healthmd evidence training \
  --category Sleep \
  --metric resting_heart_rate \
  --last 14 \
  --all-pages
```

Solicite detalhes específicos dos treinos somente quando necessário:

```bash
healthmd evidence training \
  --category Sleep \
  --workout-detail distance \
  --workout-detail duration \
  --last 14 --all-pages
```

A seleção de detalhes dos treinos solicita o escopo sem perdas necessário para essa solicitação. O pacote contém valores factuais, cobertura, descritores de origem, localizadores de evidências e limitações.

Os IDs dos pacotes são resumos SHA-256 determinísticos do conteúdo semântico. Gerar novamente o mesmo pacote em outro momento preserva o ID semântico, embora os metadados de geração possam mudar.

Os tipos de pacote de evidências no contrato v1 incluem `daily_wellness`, `training` e `doctor_visit`. No momento, o comando de conveniência de alto nível expõe o pacote de treinamento. Use a API de baixo nível para corpos de solicitação exatos.

## Propriedade das datas e fuso horário

As datas das consultas são valores `owner_date` do contexto compacto. Cada dia também preserva o intervalo UTC exato e semiaberto e o fuso horário IANA capturado que foi usado para formá-lo.

As sessões de sono preservam os timestamps locais e as datas que atravessam a meia-noite. As leituras técnicas adjacentes existem para que uma sessão possa atravessar o limite de um dia do proprietário sem mover dados de acordo com o fuso horário atual do Mac.

Ao fazer uma pergunta sensível a datas a um agente, inclua as datas do proprietário pretendidas e inspecione o fuso horário retornado, em vez de presumir o fuso horário do computador.

## Não oculte dados ausentes na resposta de um agente

Um resumo seguro deve preservar:

- ID da métrica e unidade canônica;
- intervalo de datas e fuso horário;
- modo de dados novos, em cache ou com reutilização de cobertura;
- status do escopo solicitado e do corpus;
- conclusão do percurso das páginas;
- referências de evidências ou resumo da origem;
- intervalos completamente vazios e ausentes;
- avisos, limitações e itens ignorados não relacionados.

Não descarte dias com falha ao calcular médias, não trate a ausência como zero nem descreva o alinhamento temporal como causa.

## Conteúdo relacionado

<div class="related">
  <a href="/pt-br/docs/agents/"><span>Arquitetura</span>Agentes locais e contexto de saúde: configuração, criptografia, escopo da solicitação, evidências e retenção.</a>
  <a href="/pt-br/docs/mcp/"><span>MCP</span>Auxiliar MCP local: equivalentes tipados para consultas, sono, alinhamento, treinos, cobertura, comparação e evidências.</a>
  <a href="/pt-br/docs/agent-api/"><span>Contratos brutos</span>API de consulta de loopback: solicitações exatas, respostas de uma página, atualização e rotas de tarefas.</a>
  <a href="/pt-br/docs/reference/evidence-packets/"><span>Referência</span>Consultas compactas e pacotes de evidências: valores tipados, cursores, operações, cobertura e IDs.</a>
</div>
