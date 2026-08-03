---
title: "Tarefas persistentes da CLI e automação"
description: "Automatize o Health.md com segurança usando saída legível por máquina, esperas limitadas, tarefas persistentes por sete dias, estados parciais explícitos, retomada e cancelamento confirmado."
---

O Health.md trata a exportação conectada e a aquisição de contexto como tarefas persistentes. O ciclo de vida da tarefa é separado do processo que a iniciou. Um terminal pode ser fechado ou uma conexão de rede pode falhar sem descartar as partições concluídas.

Esta página se aplica à exportação de arquivos, exportação raw estrita, extração canônica e aquisição recente de contexto criptografado, a menos que um comando documente uma regra mais restrita.

## A regra central

Um timeout ou uma desconexão não significa cancelamento.

Não inicie uma tarefa duplicada após um resultado desconhecido. Salve o ID da tarefa retornado, verifique seu estado e retome a mesma tarefa.

Tarefas de exportação, raw e extração usam os comandos de ciclo de vida de nível superior:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

Tarefas de aquisição de contexto criptografado usam o ciclo de vida do agente local:

```bash
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
```

## Duração de sete dias

Uma tarefa persistente tem um `expires_at` fixado em sete dias após a criação. O progresso não o prorroga. Ambas as partes persistem a solicitação imutável e o estado de transferência confirmado suficiente para uma retomada segura.

Uma tarefa pode persistir:

- datas exatas ou identificadores resolvidos de todo o histórico;
- escopo de métrica, categoria, fonte e detalhes;
- vinculação ao backend e ao dispositivo emparelhado;
- política de configurações;
- perfil raw ou seleção de extração;
- identidade do destino do arquivo;
- fingerprint da solicitação;
- manifestos de sessão e transferência;
- cadeia de digests das partições;
- fronteira confirmada de partições e bytes;
- confirmação de conclusão ou cancelamento.

A retomada não pode reinterpretar nenhum desses campos.

## O estado não se resume a em execução ou concluído

A resposta de uma tarefa pode incluir:

| Campo | Significado |
|---|---|
| `durable` | Se a operação tem estado de tarefa recuperável |
| `state` | Estado atual do ciclo de vida persistente |
| `job_id` | Identificador estável da tarefa |
| `session_id` | Identificador da sessão de transferência vinculada |
| `paused` | Se o trabalho exige que o mesmo iPhone se reconecte |
| `processed_days` / `total_days` | Progresso lógico em dias do proprietário |
| `committed_partitions` | Partições persistidas e confirmadas pelo receptor |
| `committed_bytes` | Bytes de payload confirmados com segurança |
| `fraction_complete` | Fração de progresso sem dados de saúde |
| `expires_at` | Timestamp fixo de expiração da tarefa |

Os campos de status contêm datas, IDs, contagens, bytes e erros seguros. Eles não devem conter amostras de saúde.

## Inicie uma tarefa com um plano explícito de saída

Exportação raw:

```bash
healthmd export --iphone --last 30 --raw \
  --output health-month.json
```

Extração canônica:

```bash
healthmd extract --category Sleep --last 30 \
  --output sleep-month.json
```

Arquivos gerados diretamente:

```bash
healthmd --backend direct export --last 30 \
  --destination "$HOME/Documents/HealthVault"
```

Escolha a saída ou o destino final antes do início da solicitação. Uma tarefa raw vincula seu comportamento de saída. Uma tarefa de arquivo direto vincula a raiz exata do destino à solicitação imutável.

## Retomar

```bash
healthmd resume JOB_UUID --timeout 300
healthmd resume JOB_UUID --output recovered.json
healthmd resume JOB_UUID --output recovered.json --allow-partial
```

No modo direto, selecione o mesmo backend, dispositivo, transporte, porta e iPhone usados pela solicitação original:

```bash
healthmd --backend direct --device DEVICE_UUID \
  --transport manual-ip --port 17647 \
  resume JOB_UUID --timeout 300 --output recovered.json
```

Bytes pendentes podem ser descartados após uma desconexão. Partições confirmadas não são retransmitidas nem reinterpretadas. O receptor aceita uma partição já confirmada somente quando todos os descritores imutáveis correspondem.

Uma tarefa de arquivo não aceita um destino substituto durante a retomada. Se a raiz original tiver mudado, o Health.md falhará de forma segura, em vez de gravar em uma pasta diferente.

## Cancelar

Use o ciclo de vida que criou a tarefa:

```bash
# Export, raw, or extraction
healthmd cancel JOB_UUID

# Encrypted-context acquisition
healthmd agent job cancel JOB_UUID
```

O cancelamento tem duas etapas:

1. a CLI registra e envia uma solicitação persistente de cancelamento;
2. o iPhone confirma o cancelamento e o torna terminal.

Se o iPhone estiver indisponível, a tarefa permanecerá como `cancellation_pending`. Reabra o mesmo iPhone e tente cancelar novamente. Não informe que uma tarefa foi cancelada com base apenas na intenção local.

Um processo que recebe Ctrl-C deve encerrar sem inventar um cancelamento terminal. Use o comando explícito de cancelamento quando essa for a intenção.

## Canais de saída

O Health.md separa os resultados dos comandos do progresso:

| Canal | Conteúdo |
|---|---|
| stdout | Resultado de comando versionado em JSON, erro ou stream JSON/JSONL solicitado |
| stderr | Instruções de emparelhamento em texto simples, progresso sem dados de saúde, recibo JSONL durante streaming e texto de uso |
| `--output PATH` | JSON ou JSONL com dados de saúde, confirmado atomicamente |
| `OUTPUT.receipt.json` | Recibo de extração sem dados de saúde para saída de arquivo JSONL |

`--help` usa texto simples. Falhas de argumentos antes da execução usam stderr e código de saída 2. Depois que um comando é executado, as falhas em tempo de execução usam JSON legível por máquina.

Não combine stdout e stderr em um parser de automação.

## Status de saída e status dos dados

O status de saída do processo é apenas um sinal. Analise a resposta antes de declarar sucesso.

| Resultado | Comportamento de saída padrão |
|---|---|
| Sucesso completo | Zero |
| Escopo solicitado completo e vazio | Zero |
| Raw estrito ou extração parcial validada | Diferente de zero |
| Parcial com `--allow-partial` explícito | Zero, mas a resposta continua parcial |
| Erro de argumento | Saída 2, texto simples em stderr |
| Falha de validação ou transporte | Diferente de zero, com erro estruturado em tempo de execução |

`--allow-partial` é uma política de aceitação, não um reparo de dados. Cada dia ausente, consulta com falha, tipo sem suporte e aviso continua visível.

## A navegação pelas páginas é separada da conclusão da tarefa

As respostas de consultas tipadas são paginadas. Uma tarefa de aquisição recente pode ser concluída enquanto a consulta ainda tem outra página.

Sem `--all-pages`, verifique `next_cursor`. Quando há uma próxima página, a CLI de alto nível informa `partial_success` em vez de declarar que toda a navegação foi concluída.

```bash
healthmd query --category Sleep --last 90 --all-pages
```

`--all-pages` segue cursores opacos, verifica repetições e impõe um limite agregado de páginas e bytes. Se o limite for atingido, restrinja o escopo ou use a API de baixo nível para paginar manualmente. Não há um limite total oculto de resultados, mas cada invocação permanece limitada.

## Cobertura recente, em cache e reutilizada

Por padrão, os comandos de consulta de alto nível adquirem dados recentes do iPhone:

```bash
healthmd query --metric resting_heart_rate --last 30
```

Use dados em cache somente quando um contexto desatualizado for aceitável:

```bash
healthmd query --metric resting_heart_rate --last 30 --cached
```

Use `--reuse-covered` para pular a aquisição somente depois que o Health.md verificar a cobertura completa de resumos, considerando as métricas, para os dias solicitados:

```bash
healthmd query --metric resting_heart_rate --last 30 --reuse-covered
```

O atalho de reutilização não se aplica a dados sem perdas nem a operações recém-projetadas de sessões de sono. Ele nunca trata um provedor diferente ou um blob desatualizado mais antigo como prova da conclusão recente desta solicitação.

## Exemplo de shell

Este exemplo mantém o payload de saúde em um arquivo protegido e exibe apenas campos de status seguros. Ele pressupõe que o GNU `timeout` esteja instalado. Outros hosts de automação devem aplicar seu próprio prazo ao processo.

```bash
#!/usr/bin/env bash
set -euo pipefail

output="${HOME}/Private/healthmd/sleep-week.json"
mkdir -p "$(dirname "$output")"
chmod 700 "$(dirname "$output")"

set +e
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output "$output" \
  </dev/null > /tmp/healthmd-command.json
exit_code=$?
set -e

if [ -s /tmp/healthmd-command.json ]; then
  jq '{status, job_id, error, message}' /tmp/healthmd-command.json
fi

if [ "$exit_code" -ne 0 ]; then
  echo "healthmd did not report complete success" >&2
  exit "$exit_code"
fi
```

Não habilite `set -x` em torno de um comando que possa transmitir JSON de saúde ou incluir caminhos confidenciais.

## Comportamento do agente após um resultado desconhecido

Um agente ou agendador deve seguir esta ordem:

1. Leia o erro estruturado e o ID da tarefa.
2. Execute `status --job` localmente.
3. Verifique se a tarefa está pausada, terminal, expirada ou aguardando confirmação.
4. Reabra o mesmo iPhone quando for necessário realizar trabalho recente ou obter confirmação.
5. Retome a tarefa existente com o mesmo backend e dispositivo.
6. Inicie uma nova tarefa somente depois que o resultado anterior for conhecido ou que a expiração seja explicitamente aceita.

Repetir uma mutação às cegas pode duplicar o trabalho na fonte, mesmo quando as confirmações de arquivos são idempotentes.

## Erros comuns legíveis por máquina

| Código | Significado | Resposta segura |
|---|---|---|
| `timed_out` | O comando deixou de aguardar antes da conclusão da tarefa | Verifique a tarefa retornada e retome-a |
| `job_not_found` | Não existe registro persistente local para esse ID | Confirme o backend e o diretório de estado antes de recomeçar |
| `job_expired` | O prazo fixo de sete dias expirou | Registre a lacuna e crie uma nova solicitação, se apropriado |
| `direct_export_paused` | O trabalho direto precisa novamente do iPhone emparelhado | Reabra o iPhone e retome |
| `direct_cancellation_pending` | A intenção local de cancelamento não tem confirmação do iPhone | Reabra o iPhone e tente cancelar novamente |
| `invalid_direct_raw_response` | A validação raw estrita falhou | Não consuma a saída |
| `invalid_direct_file_receipt` | A validação do manifesto do arquivo ou do recibo de confirmação falhou | Não repare nem acrescente conteúdo aos arquivos manualmente |
| `partial_canonical_extraction` | A extração solicitada está incompleta | Verifique o recibo; aceite o resultado parcial somente quando apropriado |
| `unvalidated_response_too_large` | Um resultado não pode ser exposto sob os limites atuais de validação | Restrinja o escopo ou use um modo de saída apropriado |
| `stale_cursor` | O contexto criptografado mudou depois que o cursor da página foi emitido | Reinicie essa consulta usando o corpus atual |

## Progresso sem registro de payload

Use `--progress-json` para fases de consultas de alto nível e navegação pelas páginas:

```bash
healthmd query --category Sleep --last 30 \
  --all-pages --progress-json --output result.json \
  2> progress.jsonl
```

O JSONL de progresso pode incluir fase, contagem de páginas, contagem de itens, datas e diagnósticos seguros. Ele não deve incluir valores de saúde. Mantenha-o separado do resultado final e aplique uma política de retenção apropriada mesmo assim.

## Relacionado

<div class="related">
  <a href="/pt-br/docs/cli/"><span>Configuração</span>CLI do Health.md: instale, escolha um backend e entenda a saída dos comandos.</a>
  <a href="/pt-br/docs/cli-direct/"><span>Direto</span>CLI direta para iPhone: emparelhamento, tempo finito em segundo plano, destino explícito e retomada confiável.</a>
  <a href="/pt-br/docs/agent-queries/"><span>Paginação</span>Receitas de consultas tipadas: modos recente e em cache, navegação pelas páginas, cobertura e recibos.</a>
  <a href="/pt-br/docs/reference/generated/cli/exit-codes/"><span>Contrato gerado</span>Códigos de saída da CLI: comportamento de status e erros gerado em produção.</a>
</div>
