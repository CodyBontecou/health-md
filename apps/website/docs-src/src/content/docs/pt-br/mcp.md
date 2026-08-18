---
title: "Servidor e app MCP do Health.md"
description: "Use Codex ou Claude para executar análises do Apple Health com escopo definido, renderizar gráficos nativos e iniciar exportações persistentes do Health.md por meio de um app MCP local em sandbox."
---

O Health.md para Mac inclui um auxiliar stdio assinado, o `healthmd-mcp`. Ele permite que Codex, Claude e outros hosts MCP consultem dados factuais do Apple Health, renderizem visualizações, atualizem o contexto local criptografado e executem exportações persistentes aprovadas por meio do app para Mac aberto.

```text
Codex / Claude / another local MCP host
  <-> MCP JSON-RPC over stdio
  <-> signed healthmd-mcp helper
  <-> Health.md Mac loopback API on 127.0.0.1:17645
  <-> connected iPhone for fresh HealthKit reads and exports
```

<div class="availability available">
<strong>Disponível agora · Health.md para Mac</strong>
<p>O servidor integrado disponibiliza 21 ferramentas fixas. Ele próprio não lê o HealthKit, pastas de exportação, bookmarks com escopo de segurança nem arquivos arbitrários.</p>
</div>

<div class="availability preview">
<strong>Prévia · MCP direto portátil</strong>
<p>A topologia separada de 19 ferramentas <code>healthmd mcp serve</code> para macOS, Linux e Windows está implementada, mas ainda não foi disponibilizada publicamente em um pacote. Sua entrada sem nuvem <code>serve-read-only</code> disponibiliza apenas as 13 ferramentas de prontidão e consulta após o emparelhamento local. Os comandos exclusivos da versão portátil nesta página estão marcados como prévia.</p>
</div>

## Requisitos

- Health.md para Mac instalado e aberto.
- Health.md aberto no iPhone conectado quando a ferramenta de atualização ou uma exportação iniciar um novo trabalho do HealthKit.
- Um host MCP local com suporte a stdio.
- O caminho do auxiliar assinado exibido em **Health.md para Mac → CLI**.

O caminho normal do auxiliar é `/Applications/Health.md.app/Contents/Helpers/healthmd-mcp`. As versões compatíveis do protocolo MCP principal são `2024-11-05`, `2025-03-26`, `2025-06-18` e `2025-11-25`. Não inicie `healthmd-mcp` como um comando interativo comum; o host MCP controla stdin e o ciclo de vida do processo.

## Configuração do Codex

Adicione o auxiliar integrado a `~/.codex/config.toml`:

```toml
[mcp_servers.healthmd]
command = "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
args = []
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_files]
approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_job_resume]
approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_job_cancel]
approval_mode = "prompt"
```

Reinicie o Codex, chame `healthmd_doctor`, resolva os IDs com `healthmd_metrics`, adquira explicitamente um escopo pequeno e exato com a ferramenta de atualização e consulte esse escopo com `healthmd_metric_chart`. Hosts sem MCP Apps interativos ainda recebem JSON exato e um gráfico PNG padrão.

## Configuração do Claude

Use esta entrada stdio local na configuração MCP do Claude Desktop ou em um `.mcp.json` confiável do Claude Code:

```json
{
  "mcpServers": {
    "healthmd": {
      "command": "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp",
      "args": []
    }
  }
}
```

Reinicie o Claude Desktop após editar sua configuração. As configurações de projeto do Claude exigem confiança no workspace e aprovação explícita do servidor.

As versões do Claude Desktop que anunciam a extensão estável MCP Apps renderizam a visualização interativa do Health.md diretamente na interface. O Claude Code e outros clientes orientados a texto preservam os fallbacks de JSON e imagem.

## Prévia do MCP direto portátil

Após o lançamento independente, `healthmd setup codex` emparelhará um iPhone em primeiro plano e criará com segurança uma entrada `healthmd mcp serve` do mesmo binário. Essa topologia usa transporte autenticado e criptografado por IP manual ou Tailscale na porta `17647`, armazenamento nativo de credenciais e leituras explícitas do iPhone por solicitação. O Linux também exige um provedor Secret Service desbloqueado; o Windows usa o Credential Manager.

Até que exista uma versão `healthmd-cli/v<version>`, não dependa de URLs de pacotes ou instaladores não publicados. Consulte [CLI direta para iPhone](/pt-br/docs/cli-direct/) para conhecer o contrato de emparelhamento e transporte em preparação.

## Visualizações nativas do MCP App

O Health.md implementa uma negociação estável de `io.modelcontextprotocol/ui` com `text/html;profile=mcp-app`.

Depois que um host anuncia esse tipo MIME, o servidor disponibiliza:

- `ui://healthmd/query-visualization-v1`;
- os métodos padrão `resources/list` e `resources/read`;
- `_meta.ui.resourceUri` nas ferramentas de análise e recibo de exportação;
- `structuredContent` validado junto ao texto JSON exato.

A visualização é um recurso HTML5 autocontido, sem rede, scripts remotos, fontes remotas, armazenamento ou frames aninhados. Sua CSP declarada contém listas vazias de domínios de conexão, recursos, frames e base. Ela segue o ciclo de vida padrão de inicialização, resultado de ferramenta, tema, redimensionamento, cancelamento e encerramento.

Ela pode renderizar:

- gráficos de linhas de métricas com unidades e lacunas explícitas para dados ausentes;
- comparações de períodos com a agregação selecionada pelo chamador;
- sessões de sono e resumos de duração dos estágios;
- treinos e horários factuais de treino e sono;
- cobertura, intervalos ausentes, evidências e limitações;
- recibos de percurso de todas as páginas;
- progresso de exportações persistentes, destinos e recibos de tarefas.

Se o host não for compatível com MCP Apps, as ferramentas continuarão funcionando. `healthmd_metric_chart` adiciona conteúdo `image/png` para hosts compatíveis com imagens, preservando o JSON completo como texto.

## Ferramentas disponíveis

O servidor integrado para Mac disponibiliza 21 ferramentas fixas: 13 de prontidão e consulta, quatro de tarefas de arquivos gerados e quatro de tarefas de atualização do contexto criptografado. A prévia portátil com 19 ferramentas mantém as 13 ferramentas de prontidão/consulta e as quatro de exportação, substitui as tarefas de atualização do Mac por duas ferramentas de emparelhamento direto e executa consultas tipadas diretamente no iPhone em primeiro plano.

### Prontidão e descoberta

| Ferramenta | Finalidade |
|---|---|
| `healthmd_status` | Verificar a prontidão do app para Mac, do contexto, do iPhone e da exportação |
| `healthmd_doctor` | Diagnosticar o auxiliar integrado e a topologia de loopback do Mac |
| `healthmd_capabilities` | Listar recursos de consulta direta, evidências, exportação, schema e paginação |
| `healthmd_metrics` | Listar IDs de métricas canônicos, categorias, unidades e requisitos |

### Análise e visualização

| Ferramenta | Finalidade |
|---|---|
| `healthmd_metric_chart` | Consultar séries de métricas e renderizar gráficos nativos com cobertura e unidades |
| `healthmd_sleep_sessions` | Listar e visualizar sessões de sono estáveis e cobertura fisiológica |
| `healthmd_training_alignment` | Mostrar o horário factual dos treinos em relação ao sono anterior e posterior |
| `healthmd_workouts` | Listar e visualizar treinos |
| `healthmd_coverage` | Inspecionar a cobertura e os dados ausentes por métrica e data |
| `healthmd_compare_periods` | Comparar períodos exatos com semântica de agregação explícita |
| `healthmd_training_evidence` | Criar um pacote factual de evidências de treino |
| `healthmd_query` | Enviar uma solicitação `healthmd.query_request` exata e, opcionalmente, percorrer páginas |
| `healthmd_evidence_packet` | Enviar uma solicitação de evidências exata e, opcionalmente, percorrer páginas |

### Exportações de arquivos gerados

| Ferramenta | Finalidade |
|---|---|
| `healthmd_export_files` | Executar uma exportação persistente por meio do app para Mac para a pasta selecionada |
| `healthmd_export_job_status` | Inspecionar o progresso da exportação e o recibo do destino |
| `healthmd_export_job_resume` | Retomar exatamente a tarefa persistente e imutável de exportação |
| `healthmd_export_job_cancel` | Cancelar explicitamente a tarefa de exportação |

As ferramentas de exportação, retomada e cancelamento são marcadas como gravações potencialmente destrutivas e exigem interação explícita nos hosts Claude atuais, pois os modos de exportação configurados podem atualizar ou sobrescrever arquivos gerados. A configuração do Codex acima solicita aprovação para essas ferramentas como proteção adicional.

### Tarefas de aquisição de contexto criptografado · somente no Mac integrado

| Ferramenta | Finalidade |
|---|---|
| `healthmd_refresh` | Adquirir um escopo aprovado do iPhone em um contexto criptografado descartável no Mac |
| `healthmd_job_status` | Inspecionar o progresso da atualização sem ler valores de saúde |
| `healthmd_job_resume` | Retomar exatamente a tarefa de atualização aceita |
| `healthmd_job_cancel` | Cancelar explicitamente uma tarefa de atualização aceita |

### Descubra o formato completo da consulta

O `tools/list` do MCP inclui JSON Schema aninhado completo para datas, métricas, fontes, paginação, intervalos de períodos, agregações e a solicitação avançada `healthmd.query_request`. As ferramentas tipadas também incluem exemplos concretos. Um agente deve chamar diretamente a ferramenta tipada correspondente, em vez de consultar uma ajuda genérica do shell. Em particular, perguntas sobre sono usam `healthmd_sleep_sessions`; `healthmd extract` produz uma projeção diferente dos dados de origem canônicos.

A prévia portátil permite inspecionar o mesmo schema localmente sem abrir um listener de rede nem entrar em contato com o iPhone. Para o auxiliar Mac publicado, use tools/list do MCP.

```bash
healthmd mcp schema healthmd_sleep_sessions
healthmd mcp schema healthmd_metric_chart
healthmd mcp schema # complete fixed catalog
```

Uma chamada mínima de sono tem este formato (resolva as datas inclusivas para a solicitação real):

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-22",
      "end_date": "2026-07-28"
    }
  },
  "all_pages": true
}
```

As métricas canônicas de sono e os detalhes sem perdas das sessões são fornecidos automaticamente por `healthmd_sleep_sessions`.

## Analise e crie gráficos dos dados

Chame `healthmd_doctor` primeiro e resolva os IDs de métricas com `healthmd_metrics`. Na topologia Mac publicada, as ferramentas de consulta tipadas leem o contexto criptografado do Mac; elas não entram em contato implicitamente com o iPhone. Para dados atuais, chame a ferramenta de atualização com datas, métricas e fontes explícitas, aguarde a conclusão da tarefa persistente e crie o gráfico do mesmo escopo:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-01",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps", "resting_heart_rate"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "all_pages": true
}
```

Passe esse objeto para `healthmd_metric_chart`. A visualização interativa usa pequenos múltiplos com unidades seguras. Um ponto ausente ou parcial interrompe a linha em vez de se tornar zero.

As ferramentas tipadas publicadas para Mac avaliam o contexto local criptografado e retornam páginas acotadas com cobertura, dados ausentes, evidências e limitações. Somente uma atualização explícita entra em contato com o iPhone conectado em primeiro plano e substitui o escopo solicitado do contexto. A prévia portátil avalia cada solicitação tipada diretamente no iPhone emparelhado em primeiro plano.

## Execute uma exportação de arquivos gerados

Primeiro, selecione e mantenha uma pasta de destino gravável no Health.md para Mac. Depois que o host mostrar todos os argumentos e o usuário aprovar, chame `healthmd_export_files`:

```json
{
  "date_selection": "explicit_range",
  "date_range": {
    "start": "2026-07-01",
    "end": "2026-07-07"
  },
  "settings_policy": "requested_dates_only",
  "categories": ["Sleep"],
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

Use `date_selection: "all_available"` sem `date_range` para obter todo o histórico. Os campos opcionais `metric_ids`, `categories` ou `all_metrics` restringem a aquisição no iPhone sem alterar as configurações salvas. `detail_level` se aplica somente quando uma dessas seleções está presente. `all_metrics` não pode ser combinado com listas explícitas de métricas ou categorias.

Para executar um perfil de exportação salvo, defina `settings_policy` como `"profile"` e passe `profile_reference` com o UUID estável do perfil (um `name` de exibição opcional é registrado apenas para erros):

```json
{
  "date_selection": "explicit_range",
  "date_range": { "start": "2026-07-01", "end": "2026-07-07" },
  "settings_policy": "profile",
  "profile_reference": { "profileID": "11111111-2222-4333-8444-555555555555" }
}
```

O perfil é o dono do escopo de configurações: `profile_reference` não pode ser combinado com `metric_ids`, `categories`, `all_metrics` nem com a política de configurações salvas, e um UUID desconhecido falha com um erro tipado em vez de recorrer às configurações ativas.

Inspecione:

- `status` e `state` persistente;
- `job_id`;
- dias processados/totais e progresso;
- arquivos ou Daily Notes gravados;
- destino no desktop validado;
- partições confirmadas e bytes;
- motivo da pausa/falha e expiração.

Um timeout ou o fechamento do processo de espera do MCP não cancela a tarefa persistente. Verifique `healthmd_export_job_status` antes de retomar após um resultado desconhecido. Somente o cancelamento explícito encerra a tarefa.

O transporte de origem bruto e canônico pode conter gigabytes de rotas, textos clínicos, anexos e registros de origem. O Health.md deliberadamente não inclui esses conteúdos em uma conversa MCP. Use a CLI de streaming validada para obter uma saída no formato da origem:

```bash
healthmd extract --metric workouts --last 30 --detail lossless --output workouts.json
healthmd export --iphone --all --raw --output health-corpus.json
```

A análise MCP continua sendo uma visualização factual derivada; as exportações de arquivos gerados continuam usando o contrato público `healthmd.health_data` por meio dos exportadores de produção.

## Paginação e completude

As ferramentas de consulta/evidências disponibilizam `all_pages: true` quando compatível. O auxiliar segue cursores opacos com detecção de ciclos e limites agregados de bytes/páginas, preservando cada resposta versionada em `healthmd.mcp_query_pages` v1. Se um limite de percurso automático for atingido, o wrapper parcial bem-sucedido define `receipt.traversal_complete` como `false` e retorna o `receipt.next_cursor` exato para uma continuação sem perdas. O iPhone retém um snapshot compacto paginado por dez minutos de inatividade em primeiro plano e o limpa ao concluir o percurso ou ir para segundo plano. Uma solicitação tem uma proteção de 366.000 dias e 64 MiB de contexto compacto codificado; `query_scope_too_large` significa que você deve particionar datas ou IDs de métricas entre chamadas, não que o histórico lógico esteja indisponível. As páginas limitam as listas de intervalos ausentes e descritores de origem com campos explícitos de contagem/truncamento e limitações.

O sucesso do transporte não significa completude. Sempre inspecione:

- o escopo solicitado e o status do corpus;
- a cobertura e os intervalos ausentes;
- as limitações e evidências;
- `next_cursor` ou o recibo de percurso;
- omissões não relacionadas;
- o schema e a versão da origem.

O MCP App exibe esses campos em vez de ocultá-los. Se o percurso automático atingir seu limite de segurança, restrinja o escopo ou continue manualmente.

## Limites de segurança e privacidade

O auxiliar não tem prompts, raízes, amostragem, shell, SQL, leituras arbitrárias de arquivos, buscas de URLs arbitrárias, gravações no HealthKit, serviço HTTP de loopback nem endpoint MCP remoto. Seu único recurso MCP é o documento integrado do App. As gravações de arquivos gerados são uma única operação fixa sujeita a aprovação. O auxiliar Mac publicado usa a pasta selecionada no Health.md para Mac; a prévia portátil exige um destino existente explícito, que valida e vincula de forma persistente antes da transferência.

A confiança direta é armazenada no Keychain, Secret Service ou Windows Credential Manager. O emparelhamento usa o protocolo autenticado e criptografado existente; o iPhone deve estar em primeiro plano e explicitamente conectado ao endereço LAN ou Tailscale do computador. As páginas de consulta são limitadas aos limites negociados de bytes/itens, e a agregação automática de todas as páginas tem limites adicionais de bytes/páginas. Conteúdos brutos ilimitados permanecem no fluxo validado da CLI de streaming.

O Health.md relata observações factuais com unidades, proveniência, cobertura e dados ausentes. Ele não diagnostica, recomenda tratamento, infere causalidade nem classifica uma direção como melhor ou pior.

## Solução de problemas

| Sintoma | Ação |
|---|---|
| O host não consegue iniciar o auxiliar | Use o caminho absoluto instalado de `healthmd` ou `.exe` com os argumentos `mcp serve` |
| O auxiliar fica aguardando quando executado no Terminal | Esperado; um host MCP deve enviar JSON-RPC por stdin |
| `healthmd_not_paired` | Execute `healthmd direct pair` e conclua o emparelhamento no iPhone |
| `healthmd_unavailable` | Desbloqueie e mantenha o Health.md em primeiro plano no iPhone, ative o Direct CLI Access e conecte-o ao computador |
| `query_scope_too_large` | Particione datas ou IDs de métricas entre chamadas; o corpus lógico continua disponível entre solicitações |
| Nenhum gráfico interativo | Atualize o host; o servidor ainda retorna JSON exato e um fallback PNG do gráfico de métricas |
| Destino da exportação indisponível | Mac: selecione novamente a pasta salva no Health.md. Prévia portátil: crie e informe um diretório existente, absoluto e que não seja um link simbólico no desktop. |
| O processo de espera da exportação expira | Inspecione a tarefa persistente de exportação pelo ID antes de retomá-la |
| O resultado tem `next_cursor` | Defina `all_pages: true` ou continue o cursor manualmente |

## Relacionados

<div class="related">
  <a href="/pt-br/docs/agents/"><span>Arquitetura</span>Agentes locais, contexto criptografado, escopo da solicitação e evidências.</a>
  <a href="/pt-br/docs/agent-queries/"><span>Análise</span>Receitas de consultas tipadas para métricas, sono, treinos, comparação e cobertura.</a>
  <a href="/pt-br/docs/cli-extract/"><span>Dados de origem</span>Extração canônica validada para resultados grandes no formato da origem.</a>
  <a href="/pt-br/docs/reference/evidence-packets/"><span>Contratos</span>Valores tipados, dados ausentes, evidências e identidades de pacotes.</a>
</div>
