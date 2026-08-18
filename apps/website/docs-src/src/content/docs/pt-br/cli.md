---
title: "CLI do Health.md"
description: "Escolha o app para Mac ou o backend direto para iPhone, instale o healthmd, verifique a prontidão, exporte arquivos, extraia dados canônicos do Apple Health, execute consultas tipadas e automatize tarefas persistentes."
---

O comando `healthmd` tem dois modos de operação. Use o backend do app para Mac quando quiser consultas locais criptografadas, ferramentas MCP ou a pasta de destino já selecionada no Health.md para Mac. Use o backend direto para iPhone quando quiser dados brutos ou arquivos gerados sem executar o app para Mac.

<div class="callout">
<strong>O HealthKit permanece no iPhone.</strong>
<p style="margin-top:6px;">Nenhum dos backends da CLI lê o Apple Health pelo computador. Um app Health.md atualizado e aberto no iPhone realiza cada nova leitura do HealthKit. A CLI recebe resultados ou arquivos validados.</p>
</div>

## Escolha um backend

| Recurso | Backend do app para Mac | Backend direto para iPhone |
|---|---|---|
| Padrão no auxiliar integrado para Mac | Sim | Não, selecione com `--backend direct` |
| Requer que o Health.md para Mac esteja aberto | Sim | Não |
| Requer que o Health.md no iPhone esteja aberto para novos dados | Sim | Sim |
| Destino dos arquivos | Pasta selecionada no app para Mac | Caminho absoluto existente em `--destination` |
| Exportação bruta estrita | Sim | Sim |
| `healthmd extract` canônico | Sim | Sim |
| Contexto criptografado, consultas tipadas e evidências | Sim | Não |
| `healthmd-mcp` | Sim | Não |
| IP manual ou Tailscale | Sincronização com o Mac ou modo direto explícito | Sim |
| Transporte direto por proximidade | Somente no auxiliar Swift integrado | Não está disponível no cliente Rust portátil |

As escolhas de backend e transporte nunca recorrem silenciosamente a uma alternativa. Um comando direto não pode mudar para o app para Mac para atender a uma consulta, e uma conexão Nearby com falha não pode mudar para IP manual.

## Instale os auxiliares integrados para Mac

<div class="availability available">
<strong>Disponível agora · Health.md para Mac</strong>
<p>Os auxiliares assinados Swift para CLI e MCP estão incluídos no app lançado para Mac.</p>
</div>

O Health.md para Mac inclui os auxiliares assinados `healthmd` e `healthmd-mcp`. Abra o app para Mac e selecione **CLI** para ver os caminhos da cópia instalada, os comandos de configuração, os prompts para agentes e o instalador opcional de skill para agentes.

Os caminhos normais do pacote do app são:

```text
/Applications/Health.md.app/Contents/Helpers/healthmd
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

Use aliases durante uma sessão do shell:

```bash
alias healthmd="/Applications/Health.md.app/Contents/Helpers/healthmd"
alias healthmd-mcp="/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
```

Ou crie links simbólicos persistentes em um diretório bin pertencente ao usuário:

```bash
mkdir -p ~/.local/bin
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd" ~/.local/bin/healthmd
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp" ~/.local/bin/healthmd-mcp
```

Adicione `~/.local/bin` ao `PATH` se o shell ainda não o incluir:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Verifique a CLI sem iniciar o loop stdio do MCP:

```bash
healthmd --help
healthmd doctor
```

`healthmd doctor` retorna um JSON `healthmd.cli_doctor` com a prontidão do Mac, do contexto criptografado e do iPhone. Ele não exibe valores de saúde.

## Status da CLI portátil

<div class="availability preview">
<strong>Prévia · ainda sem pacote público</strong>
<p>A CLI Rust multiplataforma aguarda a validação de lançamento em iPhones físicos e seu primeiro pacote qualificado.</p>
</div>

Uma CLI Rust independente está em desenvolvimento na versão `0.1.0-alpha.1`. Ela é executada no macOS, Linux e Windows, usa por padrão conexões diretas por IP manual ou Tailscale e não precisa do app para Mac. A compatibilidade de protocolo e as fixtures entre linguagens estão implementadas, mas a validação de lançamento em iPhones físicos e o empacotamento público ainda precisam ser concluídos antes do primeiro lançamento público.

Até que esse lançamento exista, use o auxiliar integrado para Mac. Não dependa de URLs não publicadas do Homebrew, crates.io, instaladores ou downloads do GitHub.

O cliente portátil permite exportação bruta, extração canônica, emparelhamento, status, retomada, cancelamento e destinos de arquivos gerados nas três plataformas. Para exportação de arquivos com o protocolo v1, o iPhone trata o destino como um rótulo de destino opaco, enquanto a CLI receptora o valida e associa de forma persistente ao sistema de arquivos do host.

## Mapa de comandos

| Comando | Finalidade | Backend |
|---|---|---|
| `healthmd status` | Verificar a prontidão em tempo real ou uma tarefa persistente local | Ambos |
| `healthmd doctor` | Explicar a prontidão do Mac, do contexto criptografado e do iPhone | App para Mac |
| `healthmd metrics list` | Retornar o catálogo canônico de métricas consultáveis | App para Mac |
| `healthmd extract` | Adquirir objetos canônicos selecionados de `healthmd.health_data` | Ambos |
| `healthmd query` | Adquirir e consultar métricas tipadas selecionadas | App para Mac |
| `healthmd sleep sessions` | Retornar sessões de sono de primeira classe e janelas fixas | App para Mac |
| `healthmd training align` | Alinhar treinos ao sono anterior e posterior | App para Mac |
| `healthmd workouts` | Listar treinos tipados com evidências | App para Mac |
| `healthmd coverage` | Verificar a cobertura ou ausência de dados por data e métrica | App para Mac |
| `healthmd compare` | Comparar períodos exatos com a agregação escolhida pelo chamador | App para Mac |
| `healthmd evidence training` | Criar um pacote factual de evidências de treino | App para Mac |
| `healthmd export` | Gravar arquivos gerados ou retornar JSON bruto estrito | Ambos |
| `healthmd resume` | Retomar uma tarefa de exportação persistente e imutável | Ambos |
| `healthmd cancel` | Solicitar cancelamento explícito | Ambos |
| `healthmd agent ...` | Chamar a API de loopback de baixo nível para consultas e tarefas | App para Mac |
| `healthmd direct ...` | Emparelhar, listar e remover relações de confiança diretas com o iPhone | Direto |

## Primeiro fluxo de trabalho com o app para Mac

1. Abra o Health.md no Mac e selecione uma pasta de destino se pretende gravar arquivos.
2. Abra o Health.md no iPhone emparelhado e aguarde a conectividade com o Mac.
3. Verifique a prontidão.
4. Execute um comando pequeno antes de solicitar um histórico extenso.

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --metric sleep_total --yesterday
```

As novas consultas adquirem apenas as métricas, fontes, datas e o nível de detalhe resumido ou sem perdas fornecidos. Elas não alteram as configurações de exportação salvas no iPhone.

## Exportações de arquivos e dados brutos

```bash
# Use the Mac app's selected destination
healthmd export --iphone --yesterday
healthmd export --iphone --last 7
healthmd export --iphone --from 2026-07-01 --to 2026-07-07
healthmd export --iphone --all

# Return strict lossless canonical JSON without writing export files
healthmd export --iphone --yesterday --raw --output yesterday.json
healthmd export --iphone --all --raw --output complete-health-corpus.json

# Replace saved metric scope for this one file job
healthmd export --iphone --last 7 --category Sleep --detail summary

# Mirror saved iPhone settings, including roll-ups
healthmd export --iphone --yesterday --use-iphone-settings

# Run a saved export profile by UUID (frozen settings + destination)
healthmd export --iphone --last 7 --profile 11111111-2222-4333-8444-555555555555
```

`--profile PROFILE_ID` resolve um perfil de exportação salvo no iPhone pelo seu UUID estável: a execução usa a seleção de métricas, os formatos e o destino congelados desse perfil em vez das configurações ativas do app. Não pode ser combinado com `--use-iphone-settings` nem com seletores de métrica/categoria (o perfil é o dono do escopo de configurações), e um UUID desconhecido falha com um erro tipado `profile_not_found` em vez de recorrer às configurações ativas. Leia o UUID no seletor de perfis da aba Exportar do app.

No momento, não há limite de dias corridos. `--all` solicita ao iPhone que encontre o registro mais antigo disponível da fonte selecionada, fixe o intervalo resolvido e o processe em partições limitadas. O armazenamento disponível e um único dia excepcionalmente denso continuam sendo limites práticos.

`--raw` solicita temporariamente registros de origem canônicos e sem perdas sem alterar a preferência do iPhone. Ele não grava arquivos gerados nem inclui sidecars de provedores conectados.

## Extração canônica ou consulta derivada?

Use `extract` quando precisar de dados com a estrutura da fonte:

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

Use um comando de consulta quando precisar de uma visualização tipada e vinculada a evidências:

```bash
healthmd sleep sessions --last-nights 14 --window first:4h
healthmd compare --metric steps:sum \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

`healthmd.health_data` v7 é o contrato público da fonte. Os schemas de consulta, evidência, tarefa e recibo descrevem o transporte ou as visualizações derivadas. Eles não substituem o schema da fonte.

## Comportamento legível por máquina

Por padrão, os comandos usam JSON versionado no stdout ou no caminho explícito de `--output`. A extração canônica pode optar por JSONL, e consultas de alto nível podem optar por uma tabela deliberadamente com perdas. O progresso sem dados de saúde pode usar stderr. `--help` é texto simples. Falhas de argumentos antes do início de um comando são exibidas como texto simples no stderr com código de saída 2.

Uma saída bem-sucedida do processo não basta para comprovar que os dados de saúde estão completos. Verifique:

- o status externo;
- o status do escopo solicitado;
- os resultados por dia e por consulta;
- os intervalos ausentes;
- `next_cursor` ou o recibo de percurso;
- o schema e a versão da fonte;
- as limitações e os avisos.

Um resultado completo e vazio significa que o Health.md representou o escopo solicitado e não encontrou observações. Não é o mesmo que zero, ausente, com falha, ignorado ou sem suporte.

## Automação segura

Use o timeout de processo do host de automação e mantenha o stdin fechado para comandos que não devem solicitar interação. Em sistemas com GNU `timeout`:

```bash
NO_COLOR=1 TERM=dumb timeout 30 healthmd doctor </dev/null
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output sleep.json </dev/null
```

Timeout, Ctrl-C, encerramento do processo, perda de rede e esgotamento do tempo de execução em segundo plano do iOS não cancelam uma tarefa persistente. Verifique o ID da tarefa e retome-a em vez de iniciar uma duplicata.

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
healthmd cancel JOB_UUID
```

Somente uma confirmação do iPhone torna o cancelamento definitivo.

## Regras de privacidade

A saída bruta e sem perdas pode conter timestamps exatos, rotas, registros clínicos, medicamentos, registros de humor, valores de ECG, proveniência e anexos. Prefira um arquivo de saída à saída no terminal. Não cole os payloads em relatórios de problemas, transcrições de agentes, logs de CI ou rastreamentos do shell.

A API local de consultas não tem token bearer, cadastro, perfil de acesso nem banco de dados de concessões. A acessibilidade pelo loopback é todo o seu limite de acesso. Qualquer processo local pode usá-la enquanto o app para Mac estiver aberto, portanto nunca use proxy nem exponha a porta `17645` a outra máquina.

## Próximos guias

<div class="related">
  <a href="/pt-br/docs/cli-direct/"><span>Sem o app para Mac</span>CLI direta para iPhone: emparelhamento, transportes, exportações brutas e de arquivos, comportamento em segundo plano e suporte a plataformas.</a>
  <a href="/pt-br/docs/cli-extract/"><span>Dados de origem</span>Extração canônica: selecione métricas, objetos, nível de detalhe, JSON Pointers, JSONL e recibos.</a>
  <a href="/pt-br/docs/cli-jobs/"><span>Automação</span>Tarefas persistentes: timeouts, retomada, cancelamento, resultados parciais e scripts seguros.</a>
  <a href="/pt-br/docs/agents/"><span>Agentes</span>Fluxos de agentes locais: contexto criptografado, escopo direto, comandos tipados e evidências.</a>
  <a href="/pt-br/docs/mcp/"><span>MCP</span>Configure o auxiliar stdio em sandbox e analise os limites de suas ferramentas.</a>
  <a href="/pt-br/docs/reference/api-and-cli/"><span>Contrato</span>Referência da API e da CLI: rotas, schemas, respostas e fixtures geradas exatas.</a>
</div>
