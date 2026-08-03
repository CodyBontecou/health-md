---
title: "API de consulta de loopback"
description: "Chame as rotas locais versionadas do Health.md para consultas, evidências, atualização, prontidão, métricas e tarefas persistentes por HTTP ou pelo comando de baixo nível healthmd agent."
---

O Health.md para Mac disponibiliza uma API local versionada em `/v1/agent/`. Ela oferece consultas ao contexto criptografado, pacotes de evidências, aquisição do iPhone no escopo da solicitação, prontidão e tarefas persistentes de aquisição.

A API é vinculada ao loopback na porta `17645`. Ela aceita somente pares de loopback IPv4 ou IPv6 validados.

<div class="callout">
<strong>Não exponha esta porta.</strong>
<p style="margin-top:6px;">Não há token de portador, registro de chamador, perfil de acesso nem base de dados de concessões. A acessibilidade por loopback é todo o limite de autorização. Qualquer processo local pode emitir solicitações enquanto o Health.md estiver aberto.</p>
</div>

## Rotas

| Método | Rota | Finalidade |
|---|---|---|
| `GET` | `/v1/agent/capabilities` | Listar schemas versionados, suporte a escopos e limites de página |
| `GET` | `/v1/agent/metrics` | Retornar IDs canônicos de métricas consultáveis, categorias, unidades e requisitos |
| `GET` | `/v1/agent/readiness` | Retornar a prontidão do contexto criptografado e de dados recentes do iPhone, com as próximas ações |
| `POST` | `/v1/agent/query` | Executar uma página de consulta tipada e limitada |
| `POST` | `/v1/agent/evidence` | Derivar uma página limitada de um pacote factual de evidências |
| `POST` | `/v1/agent/refresh` | Adquirir do iPhone um escopo explícito para o contexto criptografado do Mac |
| `GET` | `/v1/agent/jobs/{id}` | Inspecionar uma tarefa local persistente de aquisição |
| `POST` | `/v1/agent/jobs/{id}/resume` | Retomar a solicitação imutável de aquisição |
| `POST` | `/v1/agent/jobs/{id}/cancel` | Solicitar cancelamento explícito |

As antigas rotas `/v1/agent/profiles` e `/v1/agent/activity/query` retornam `410 removed_endpoint`.

O backend direto do iPhone não hospeda essas rotas HTTP. O comando independente `healthmd` o utiliza para extração e exportação canônicas, enquanto `healthmd mcp serve` implementa ferramentas de consulta tipada com dados recentes, evidências, catálogo de métricas, prontidão, visualização e exportação persistente diretamente pelo protocolo de consulta do iPhone v3. O emparelhamento e o MCP usam a mesma identidade do executável; a atualização e o contexto criptografado do Mac continuam específicos desta API HTTP.

## Prefira o adaptador da CLI

A CLI de baixo nível mantém os corpos das solicitações exatos e trata erros do transporte de loopback:

```bash
healthmd agent capabilities
healthmd agent query --input query-body.json
healthmd agent query --input - < query-body.json
healthmd agent evidence --input evidence-body.json
healthmd agent refresh --input refresh-body.json
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
healthmd agent job cancel JOB_UUID
```

Use `--json JSON` em vez de `--input` para um corpo pequeno. A CLI não amplia nem restringe silenciosamente o JSON fornecido a esses comandos.

Use comandos de alto nível, como `healthmd query`, `healthmd sleep sessions` ou `healthmd compare`, para fluxos comuns. Eles validam os seletores e constroem a operação tipada para você.

## Corpo da consulta

`POST /v1/agent/query` aceita somente `request` e o campo opcional `detail_level` no nível superior:

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "metric_series"
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144
    }
  },
  "detail_level": "summary"
}
```

Campos desconhecidos no invólucro são rejeitados. O contrato da solicitação de consulta define métricas, fontes, datas, operação e controles de página. `detail_level` pode ser `summary` ou `lossless`.

A resposta é `healthmd.query_response` v1. Ela contém itens tipados, cobertura, evidências, descritores de fontes, limitações e um `next_cursor` opcional.

Consulte uma resposta sintética completa em [`agent-query-response.json`](/docs/reference/generated/automation/agent-query-response.json).

## Continuar a partir de um cursor

Para solicitar a próxima página, envie a mesma solicitação semântica e coloque o cursor retornado em `page.cursor`:

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "metric_series"
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144,
      "cursor": "OPAQUE_CURSOR_FROM_PRIOR_RESPONSE"
    }
  },
  "detail_level": "summary"
}
```

Siga `next_cursor` até que ele não esteja mais presente. Os cursores são autenticados e vinculados à solicitação e à revisão do corpus criptografado. O Health.md rejeita cursores modificados, incompatíveis e obsoletos.

Os limites de página protegem cada solicitação sem impor um limite total ao histórico ou aos resultados.

## Corpo de evidências

`POST /v1/agent/evidence` usa o mesmo invólucro. A operação é `derive_packet`, com um tipo de pacote e detalhes selecionados explicitamente.

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps", "resting_heart_rate"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "derive_packet",
      "kind": "doctor_visit",
      "detail_ids": []
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144
    }
  },
  "detail_level": "summary"
}
```

A resposta continua sendo uma resposta de consulta paginada e contém um fragmento de `healthmd.evidence_packet` v1. Os fatos incluem valores tipados e evidências. O pacote inclui a limitação de somente observações factuais.

Consulte [`agent-evidence-response.json`](/docs/reference/generated/automation/agent-evidence-response.json) para ver uma resposta sintética completa.

## Corpo da atualização

A atualização adquire somente um escopo explícito. O corpo aceita datas, métricas, fontes, nível de detalhes e um tempo limite finito de espera:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-01",
      "end_date": "2026-07-07"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["sleep_total"]
  },
  "sources": {
    "type": "explicit",
    "source_ids": ["apple_health"],
    "provider_ids": []
  },
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

O Mac valida o escopo com base nos catálogos atuais e o transforma em uma seleção canônica imutável. O iPhone lê somente os tipos comuns selecionados do HealthKit. As configurações no escopo da solicitação não alteram as preferências salvas de exportação do iPhone.

A atualização usa um modo de transferência dedicado `encrypted_context`:

- não grava arquivos de exportação;
- não consome a cota de exportação de arquivos;
- transfere partições limitadas e retomáveis;
- o Mac confirma cada dia compacto e determinístico do proprietário antes da confirmação de recebimento;
- a solicitação exata permanece salva com a tarefa persistente.

Um escopo somente de provedores não exige uma leitura do Apple Health. O histórico nativo do provedor continua sendo uma evidência nativa do provedor e não é convertido em métricas sintéticas do Apple Health.

## Seleção de tudo disponível

Os seletores de métricas e datas podem usar `all_available`:

```json
{
  "dates": {"type": "all_available"},
  "metrics": {"type": "all_available"},
  "sources": {"type": "all_available"},
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

O iPhone determina o registro mais antigo disponível e selecionado do Apple Health e todos os dias do calendário da fonte até hoje. A aquisição de provedores segue os cursores de histórico nativos de cada provedor. Os identificadores determinados são fixados antes da transferência para que uma retomada não altere a solicitação.

Não há limite fixo de datas ou resultados. Partições, páginas, descriptografia de um dia por vez, espaço em disco e esperas finitas fornecem limites de recursos.

## Tarefas persistentes de aquisição

A espera por uma atualização pode atingir o tempo limite enquanto a tarefa continua. A resposta inclui um ID da tarefa e um progresso seguro.

```bash
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
healthmd agent job cancel JOB_UUID
```

A tarefa expira sete dias após a criação. A retomada reutiliza a mesma solicitação, Mac, iPhone, escopo de fontes e fronteira confirmada.

O cancelamento só é terminal após a confirmação do iPhone. Um iPhone indisponível pode deixar a tarefa no estado de cancelamento pendente.

## Chamadas HTTP diretas

A CLI é preferível, mas softwares locais podem chamar o HTTP diretamente:

```bash
curl --fail-with-body --max-time 5 \
  http://127.0.0.1:17645/v1/agent/readiness

curl --fail-with-body --max-time 30 \
  -H 'Content-Type: application/json' \
  --data @query-body.json \
  http://127.0.0.1:17645/v1/agent/query
```

O listener impõe limites a cabeçalhos e corpos JSON, método e tipo de conteúdo explícitos, prazos de recebimento e comportamento finito das solicitações.

Mantenha os clientes HTTP diretos no mesmo Mac. Não adicione vinculação à LAN, proxy, túnel nem invólucro MCP HTTP remoto.

## Valores tipados e ausência de dados

Os resultados das consultas preservam o tipo e a unidade. Os valores podem ser quantidades, durações, contagens, strings, categorias, booleanos, timestamps, datas de calendário, matrizes aninhadas ou valores tipados futuros desconhecidos.

Os estados de ausência incluem vazio completo, parcial, falha, sem suporte, ignorado, cancelado, não solicitado, indisponível em versão legada, ocultado e não sincronizado. Os consumidores não devem convertê-los em zero.

A cobertura inclui intervalos solicitados e disponíveis, dias considerados, dias com valores e intervalos ausentes compactados com indicação de estado.

## Tratamento de erros

Os erros usam `healthmd.query_error` v1 com código estável, mensagem, possibilidade de nova tentativa e detalhes tipados. Erros distintos abrangem:

- controles de página inválidos;
- cursores malformados ou adulterados;
- incompatibilidade entre cursor e consulta;
- revisão obsoleta do corpus;
- intervalo de datas inválido;
- validação de métricas ou fontes;
- incompatibilidade de unidade ou agregação;
- operação sem suporte;
- violação do escopo de evidências;
- prontidão do iPhone ou do armazenamento criptografado;
- estado da tarefa persistente.

Não tente executar novamente uma atualização às cegas após um resultado desconhecido. Primeiro, inspecione o estado da tarefa.

## Conteúdo relacionado

<div class="related">
  <a href="/pt-br/docs/agents/"><span>Visão geral</span>Agentes locais e contexto de saúde: configuração, armazenamento criptografado, escopo e regras de relatórios.</a>
  <a href="/pt-br/docs/agent-queries/"><span>Alto nível</span>Receitas de consultas tipadas: comandos validados para perguntas comuns sobre métricas, sono, treinos e evidências.</a>
  <a href="/pt-br/docs/mcp/"><span>Ferramentas</span>Servidor MCP local: configuração de stdio, ferramentas tipadas, paginação e limites do sandbox.</a>
  <a href="/pt-br/docs/reference/api-and-cli/"><span>Referência</span>Contrato da API e da CLI: exportação, extração, consulta, backend direto e limites operacionais.</a>
  <a href="/pt-br/docs/reference/evidence-packets/"><span>Contratos de dados</span>Consultas compactas e pacotes de evidências: tipos, cursores, operações e IDs determinísticos de pacotes.</a>
</div>
