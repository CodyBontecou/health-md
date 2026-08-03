---
title: "Extração de dados de saúde canônicos"
description: "Use healthmd extract para obter métricas selecionadas do Apple Health e emitir documentos canônicos do schema v7, registros de origem, projeções de JSON Pointer ou JSONL com recibos explícitos."
---

`healthmd extract` é o comando de dados de origem para scripts e agentes. Ele solicita ao iPhone que obtenha apenas as métricas e o nível de detalhe selecionados, valida a transferência persistente, remove o envelope de transporte e emite documentos canônicos `healthmd.health_data` v7 ou projeções claramente identificadas.

Use a extração quando precisar dos dados originais do Health.md. Use [consultas tipadas](/pt-br/docs/agent-queries/) quando precisar de sessões, comparações, alinhamento de treinos, cobertura ou pacotes de evidências.

## Estrutura básica

Uma extração precisa de:

1. pelo menos um seletor de métrica, categoria, objeto ou `--all-metrics`;
2. um seletor de data;
3. opções de detalhe, objeto, campo, formato, saída, tempo limite e resultados parciais.

```bash
healthmd extract \
  (--metric ID | --category NAME | --object NAME | --all-metrics) ... \
  (--from DATE --to DATE | --last N | --yesterday | --all) \
  [--detail summary|lossless] \
  [--source apple_health] \
  [--field /JSON/POINTER] ... \
  [--format json|jsonl] \
  [--timeout 5...900] \
  [--allow-partial] \
  [--output PATH]
```

A fonte atual de extração canônica é `apple_health`. Os sidecars nativos dos provedores permanecem em seus próprios contratos e não são traduzidos em valores sintéticos do Apple Health.

## Comece com uma solicitação restrita

```bash
# One category, one day, summary detail
healthmd extract --category Sleep --yesterday --output sleep.json

# One metric for the last 30 complete days
healthmd extract --metric resting_heart_rate --last 30 \
  --output resting-heart-rate.json

# Every selected source object for one exact range
healthmd extract --all-metrics \
  --from 2026-07-01 --to 2026-07-07 \
  --detail lossless --output health-week.json
```

Os nomes de métricas e categorias são validados com base no catálogo atual antes de qualquer operação no iPhone. Repita os seletores para combiná-los.

```bash
healthmd extract \
  --metric sleep_total \
  --metric resting_heart_rate \
  --category Workouts \
  --last 14 --output recovery-context.json
```

## A seleção ocorre antes das leituras do HealthKit

A extração não obtém uma exportação salva com todas as métricas para depois reduzi-la. A CLI transforma seu seletor em uma `CanonicalHealthDataSelection` imutável e a envia ao iPhone. O Health.md verifica e lê apenas os tipos comuns do HealthKit que dão suporte às métricas selecionadas.

Essa distinção é importante para privacidade, desempenho e integridade:

- métricas não selecionadas não são obtidas;
- as preferências de métricas salvas no iPhone não são alteradas;
- solicitações de resumo não criam um arquivo de origem oculto;
- solicitações sem perdas obtêm apenas os tipos de origem necessários para a seleção;
- a seleção passa a fazer parte da impressão digital da solicitação persistente.

Seletores de objeto e JSON Pointer restringem os dados emitidos após a captura. Seletores de métrica, categoria, origem e detalhe restringem a própria obtenção no iPhone.

## Detalhes resumidos e sem perdas

O resumo é o padrão:

```bash
healthmd extract --category Activity --last 7 --detail summary
```

A saída resumida pode incluir resumos diários tipados, diagnósticos de consulta e `raw_capture_status: not_requested`. Esse status é fiel: o comando não obteve registros de origem canônicos.

Solicite detalhes sem perdas quando objetos de origem, UUIDs, horários exatos, procedência ou diagnósticos do arquivo forem importantes:

```bash
healthmd extract --metric workouts --last 14 \
  --detail lossless --output workouts-lossless.json
```

Objetos relacionados ao arquivo, como `records`, implicam detalhes sem perdas mesmo quando `--detail` é omitido.

## Seletores de objeto

Use `--object` para manter uma parte conhecida de cada dia selecionado. Os nomes atuais incluem:

| Objeto | Conteúdo típico |
|---|---|
| `sleep` | Campos de resumo diário do sono |
| `activity` | Passos, energia, distância, exercício e resumos de atividades relacionados |
| `heart` | Frequência cardíaca, frequência cardíaca em repouso, VFC e resumos relacionados |
| `vitals` | Pressão arterial, glicose, temperatura, oxigênio e outros resumos de sinais vitais |
| `body` | Peso, composição corporal, altura e medidas corporais |
| `nutrition` | Resumos de nutrientes e hidratação |
| `mindfulness` | Sessões de atenção plena e resumos de bem-estar mental |
| `mobility` | Campos de caminhada, marcha e mobilidade |
| `hearing` | Campos de exposição sonora e audição |
| `reproductive-health` | Campos de saúde reprodutiva, gravidez e ciclo |
| `cycling` | Resumos de ciclismo |
| `vitamins` / `minerals` | Resumos específicos de nutrientes |
| `symptoms` | Dados de sintomas |
| `medications` | Dados de medicamentos quando disponíveis e autorizados |
| `workouts` | Objetos canônicos de resumo de treinos |
| `archive` | Envelope canônico do arquivo do HealthKit |
| `records` | Registros de origem canônicos; implica detalhes sem perdas |
| `external-records` | Registros externos já presentes no dia público |
| `query-results` | Resultados de captura por consulta |
| `warnings` | Avisos de integridade |

Exemplos:

```bash
healthmd extract --metric workouts --last 30 \
  --object workouts --output workout-summaries.json

healthmd extract --metric workouts --last 30 \
  --object records --detail lossless --output workout-records.json

healthmd extract --category Sleep --last 7 \
  --object sleep --object query-results --output sleep-with-status.json
```

## Projeção de JSON Pointer

Repita `--field` com JSON Pointers RFC 6901 para emitir valores exatos ou entradas de status:

```bash
healthmd extract --category Sleep --last 7 \
  --field /sleep/totalDuration \
  --field /sleep/deepSleep \
  --field /raw_capture_status \
  --output selected-sleep-fields.json
```

Os resultados de ponteiros são projeções, não documentos diários completos. Eles fazem referência ao schema e ao dia de origem, mas não incluem `schema: healthmd.health_data` de uma forma que possa fazer uma subárvore parecer uma exportação completa.

Um caminho selecionado ausente é relatado com vazio completo ou com o status incompleto do dia. O Health.md não converte ausência em zero.

## Saída JSON

A saída JSON padrão contém uma destas coleções de dados:

- `health_data` para documentos diários canônicos completos; ou
- `projections` para resultados de objetos ou ponteiros.

Ela também contém `healthmd.extract_receipt`, que registra:

- a seleção e o intervalo de datas resolvidos;
- a origem e o nível de detalhe;
- os resultados de cada dia;
- as contagens de itens mantidos e capturas;
- as datas ausentes;
- os diagnósticos de resultados parciais ou falhas;
- o status de conclusão da saída.

O recibo é um metadado do protocolo. Ele não substitui o schema de origem.

## Saída JSONL

Use JSONL para processamento de streams:

```bash
healthmd extract --category Sleep --last 30 \
  --format jsonl --output sleep.jsonl
```

Cada linha é um item de dados. O recibo não é misturado ao stream de dados de saúde:

- com `--output`, ele é gravado em `OUTPUT.receipt.json`;
- sem `--output`, ele é gravado em stderr.

Isso torna os pipelines previsíveis:

```bash
healthmd extract --metric workouts --last 30 \
  --object workouts --format jsonl --output workouts.jsonl

jq -c 'select(.workouts != null)' workouts.jsonl
jq '{status, retained_item_count, missing_dates}' workouts.jsonl.receipt.json
```

Não redirecione stderr para o analisador de JSONL, pois stderr contém o recibo e o progresso sem dados de saúde.

## Resultados completos, vazios e parciais

O Health.md mantém estes estados distintos:

| Estado | Significado |
|---|---|
| `success` | Todas as ramificações solicitadas foram concluídas, incluindo ramificações completamente vazias |
| `complete_empty` | O escopo solicitado foi representado e não continha observações |
| `partial_success` | Alguns dados solicitados são mantidos, mas pelo menos uma ramificação solicitada está incompleta |
| `failed` | Uma ramificação solicitada falhou |
| `unsupported` | A plataforma ou o HealthKit não oferece suporte à ramificação solicitada |
| `skipped` | O Health.md não consultou essa ramificação intencionalmente |
| `cancelled` | O iPhone confirmou o cancelamento |
| `missing` | Um dia ou uma ramificação solicitada não foi representada |

Por padrão, uma extração parcial não emite dados mantidos. Adicione `--allow-partial` somente quando seu consumidor estiver preparado para aceitar e preservar um escopo incompleto:

```bash
healthmd extract --category Sleep --last 30 \
  --allow-partial --output sleep-partial.json
```

A flag altera a emissão e o comportamento de saída. Ela não remove os diagnósticos nem transforma dados parciais em dados completos.

## App para Mac e backends diretos

O comando funciona por qualquer um dos backends:

```bash
# Bundled helper default: Mac app loopback and connected iPhone
healthmd extract --category Sleep --last 7 --output sleep.json

# Direct-capable helper: bypass the Mac app
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json
```

Os dois caminhos usam o mesmo schema diário público e uma validação rigorosa. O transporte, o emparelhamento, o armazenamento e os registros de tarefas são diferentes.

## Históricos extensos

`--all` não tem um limite fixo de datas:

```bash
healthmd extract --metric steps --all --output all-steps.json
```

O iPhone identifica o registro selecionado mais antigo disponível, fixa todos os dias do calendário da origem até hoje e transfere partições limitadas. A CLI faz a montagem e a validação em disco, em vez de criar uma única resposta ilimitada na memória.

Use JSONL ou uma seleção mais restrita quando o corpus for grande. O espaço disponível em disco e um único dia com densidade excepcional continuam sendo limites práticos.

## Checklist de privacidade

- Prefira `--output` para qualquer resultado que contenha dados de saúde.
- Proteja os arquivos de saída e de recibo com o mesmo cuidado dedicado à origem do Apple Health.
- Não use rastreamento de shell ao executar comandos de saúde.
- Mantenha os conteúdos fora de logs de CI e transcrições de agentes.
- Ao solucionar problemas, inspecione apenas os campos de recibo, contagem, status, schema e ausência de dados.
- Exclua as exportações temporárias depois que o consumidor pretendido as armazenar com segurança.

## Relacionados

<div class="related">
  <a href="/pt-br/docs/cli/"><span>CLI</span>CLI do Health.md: configuração, seleção de backend, mapa de comandos e regras de saída.</a>
  <a href="/pt-br/docs/agent-queries/"><span>Visualizações derivadas</span>Guia de consultas tipadas: séries de métricas, sono, treinos, alinhamento, comparações e evidências.</a>
  <a href="/pt-br/docs/reference/daily-records/"><span>Schema</span>Registros diários: o contrato completo do documento diário do schema v7.</a>
  <a href="/pt-br/docs/reference/canonical-healthkit-records/"><span>Arquivo de origem</span>Registros canônicos do Apple Health: identidade, procedência, relações e conteúdos.</a>
  <a href="/pt-br/docs/reference/api-and-cli/"><span>Protocolo</span>Referência da API e da CLI: solicitações de extração, recibos, validação rigorosa e comportamento de saída.</a>
</div>
