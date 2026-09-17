---
title: "CLI do Health.md"
description: "Instale a CLI healthmd autônoma no macOS, Linux ou Windows, emparelhe-a diretamente com um iPhone ou um dispositivo Android, verifique a prontidão, exporte dados, execute consultas e gerencie tarefas persistentes. Nenhum app para Mac é necessário."
---

A CLI `healthmd` autônoma funciona no macOS, Linux e Windows e emparelha diretamente com um app Health.md aberto no iPhone (protocolo v1) ou no Android (protocolo v2). Ela nunca exige o app Health.md para Mac, não tem seleção de backend e nunca lê o Apple Health ou o Health Connect a partir do computador.

<div class="callout">
<strong>Os dados de saúde permanecem no seu telefone.</strong>
<p style="margin-top:6px;">A CLI nunca lê o Apple Health ou o Health Connect a partir do computador. Um app Health.md aberto e atual no iPhone ou no Android executa cada nova leitura de saúde da plataforma. A CLI recebe resultados ou arquivos validados.</p>
</div>

## Instalar a CLI autônoma

<div class="availability preview">
<strong>Pré-visualização pública · ainda sem versão estável qualificada</strong>
<p>A CLI Rust multiplataforma está empacotada publicamente, mas sua matriz móvel exata ainda aguarda a qualificação física de lançamento.</p>
</div>

No macOS ou Linux, instale a pré-visualização com <code>brew install CodyBontecou/tap/healthmd</code>. Use a build móvel exata indicada pelas evidências de lançamento; a publicação do pacote não prova compatibilidade móvel.

A CLI Rust autônoma funciona no macOS, Linux e Windows, usa conexões diretas Manual IP ou Tailscale e não precisa do app para Mac. Ela emparelha com fontes de iPhone pelo protocolo v1 e com fontes de Android pelo protocolo v2, com verificações automatizadas de compatibilidade Swift↔Rust e Kotlin↔Rust. A compatibilidade de protocolos está implementada; a QA de lançamento em dispositivos físicos precisa terminar antes da primeira versão estável qualificada. Arquivos com soma de verificação, um instalador PowerShell e `cargo install healthmd-cli --locked` acompanham cada lançamento.

O cliente portátil suporta emparelhamento, status, exportação bruta, destinos de arquivos gerados, retomada e cancelamento nas três plataformas de desktop para iPhone e Android. A extração canônica e as consultas MCP tipadas são funcionalidades do iPhone. Os snapshots brutos do Android mantêm seu contrato Health Connect nativo do provedor em vez de conversão em dados no formato HealthKit. As consultas tipadas do Android não estão implementadas. Na exportação de arquivos gerados, o telefone trata o destino como um rótulo opaco; a CLI receptora o valida e o vincula de forma durável ao sistema de arquivos do host. O protocolo Android v2 confirma destinos de arquivos em todos os sistemas operacionais da CLI e limita cada tarefa gerada a 4.096 arquivos.

## Mapa de comandos

| Comando | Finalidade |
|---|---|
| `healthmd status` | Inspecionar prontidão em tempo real ou uma tarefa persistente local |
| `healthmd export` | Gravar arquivos gerados ou retornar JSON bruto estrito |
| `healthmd extract` | Adquirir objetos canônicos `healthmd.health_data` selecionados (iPhone) |
| `healthmd query` | Executar operações fixas de consulta tipada (iPhone) |
| `healthmd resume` | Retomar uma tarefa de exportação persistente imutável |
| `healthmd cancel` | Solicitar cancelamento explícito |
| `healthmd direct ...` | Emparelhar, listar e remover confiança direta do telefone |
| `healthmd mcp ...` | Servir ou inspecionar a superfície fixa de ferramentas MCP |
| `healthmd setup codex` | Configurar o Codex e emparelhar um iPhone em um único fluxo |

Os comandos diretos emparelham com fontes de iPhone (protocolo v1) ou de Android (protocolo v2). O `extract` canônico e todos os comandos de consulta tipada são funcionalidades do iPhone; as fontes diretas do Android retornam snapshots brutos Health Connect nativos do provedor e arquivos gerados.

```bash
# Readiness and local trust
healthmd status
healthmd direct devices

# Platform-native raw export; omit --output to stream validated JSON/NDJSON to stdout
healthmd export --yesterday --raw --output yesterday.json
healthmd export --last 7 --raw --output week.json

# Typed query through the same operation registry as MCP (iPhone)
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'

# Scoped canonical extraction (iPhone)
healthmd extract --category Sleep --last 7 --output sleep.json

# Production-generated files on every CLI OS
mkdir -p "$HOME/Documents/HealthVault"
healthmd export --yesterday --destination "$HOME/Documents/HealthVault"

# Durable operations
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --output resumed.json
healthmd cancel JOB_UUID
```

### Exportação portátil de arquivos baseada em perfil

A CLI direta autônoma pode resolver um perfil salvo em qualquer uma das plataformas de telefone suportadas pelo seu ID estável. O perfil fornece suas configurações de saída congeladas; o destino no computador permanece explícito:

```bash
mkdir -p "$HOME/Documents/HealthVault"
healthmd export --last 7 \
  --profile 11111111-2222-4333-8444-555555555555 \
  --destination "$HOME/Documents/HealthVault"
```

`--profile PROFILE_ID` não pode ser combinado com `--use-device-settings` nem com seletores de métrica/categoria, e um ID desconhecido falha de forma segura em vez de usar configurações atuais. Copie o ID em **Ajustes → Perfis de exportação → ID do perfil** no iPhone ou no Android. Consulte [Perfis de exportação](/pt-br/docs/export-profiles/) para automação e comportamento do destino.

O cliente direto portátil pode invocar qualquer operação tipada de iPhone suportada sem envelope MCP:

```bash
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'
```

## Auxiliar do Mac incluído

O Health.md para Mac inclui seus próprios auxiliares Swift assinados `healthmd` e `healthmd-mcp` dentro do app. Esse auxiliar é um recurso do app para Mac, não um backend da CLI autônoma: por padrão ele conversa com o servidor loopback do app para Mac em execução para consultas locais criptografadas, ferramentas MCP e a pasta de destino já selecionada no Health.md para Mac; ele também oferece um modo direto de iPhone compatível, selecionado com `--backend direct`. Os dois clientes nunca trocam de modo silenciosamente.

<div class="availability available">
<strong>Disponível agora · Health.md para Mac</strong>
<p>Os auxiliares Swift assinados de CLI e MCP acompanham o app para Mac publicado.</p>
</div>

Abra o app para Mac e selecione **CLI** para ver os caminhos da sua cópia instalada, comandos de configuração, prompts de agentes e o instalador opcional de habilidades de agente.

Os caminhos normais do pacote do app são:

```text
/Applications/Health.md.app/Contents/Helpers/healthmd
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

Use aliases para uma sessão de shell:

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

Adicione `~/.local/bin` ao `PATH` se o seu shell ainda não o incluir:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Verifique o auxiliar sem iniciar o loop stdio do MCP:

```bash
healthmd --help
healthmd doctor
```

`healthmd doctor` retorna JSON `healthmd.cli_doctor` com a prontidão do Mac, do contexto criptografado e do iPhone. Ele não imprime valores de saúde.

### Comandos do auxiliar incluído

| Comando | Finalidade |
|---|---|
| `healthmd export --iphone ...` | Gravar arquivos gerados ou retornar JSON bruto estrito pelo app para Mac |
| `healthmd status` | Inspecionar prontidão de Mac/iPhone ou uma tarefa persistente |
| `healthmd doctor` | Explicar a prontidão do Mac, do contexto criptografado e do iPhone |
| `healthmd metrics list` | Retornar o catálogo canônico de métricas consultáveis |
| `healthmd query` | Adquirir e consultar métricas tipadas selecionadas |
| `healthmd sleep sessions` | Retornar sessões de sono de primeira classe e janelas fixas |
| `healthmd training align` | Alinhar treinos com o sono anterior e seguinte |
| `healthmd workouts` | Listar treinos tipados com evidências |
| `healthmd coverage` | Inspecionar cobertura de datas e métricas ou dados ausentes |
| `healthmd compare` | Comparar períodos exatos com agregação escolhida pelo chamador |
| `healthmd evidence training` | Construir um pacote de evidências de treino factual |
| `healthmd resume` / `healthmd cancel` | Gerenciar tarefas persistentes |
| `healthmd agent ...` | Chamar a API loopback de baixo nível de consultas e tarefas |
| `healthmd --backend direct ...` | O modo direto de iPhone compatível do auxiliar |

No modo direto do auxiliar, os subcomandos de consulta, evidência, doctor, métricas e atualização de contexto do Mac retornam `backend_unsupported` em vez de trocar para o app para Mac.

### Primeiro fluxo de trabalho com o app para Mac

1. Abra o Health.md no Mac e selecione uma pasta de destino se você planeja gravar arquivos.
2. Abra o Health.md no iPhone emparelhado e aguarde a conectividade com o Mac.
3. Verifique a prontidão.
4. Execute um comando pequeno antes de solicitar um histórico grande.

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --metric sleep_total --yesterday
```

As consultas novas adquirem apenas as métricas, fontes, datas e detalhes de resumo ou sem perdas fornecidos. Elas não alteram as configurações de exportação salvas do iPhone.

### Exportações de arquivos e brutas do auxiliar incluído

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
```

Não há limite atual de dias de calendário. `--all` pede ao iPhone que descubra o registro selecionado disponível mais antigo, fixe o intervalo resolvido e o processe em partições limitadas. O armazenamento disponível e um dia incomumente denso permanecem limites práticos.

`--raw` solicita temporariamente registros canônicos sem perdas sem alterar a preferência do iPhone. Ele não grava arquivos gerados nem inclui sidecars de provedores conectados.

## Extração canônica ou consulta derivada?

Use `extract` quando precisar de dados na forma da origem:

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

Use um comando de consulta quando precisar de uma visão tipada vinculada a evidências. A CLI autônoma expõe operações tipadas fixas; o auxiliar do Mac incluído também oferece os comandos de alto nível abaixo:

```bash
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"exact","range":{"start_date":"2026-07-22","end_date":"2026-07-28"}},"all_pages":true}'
healthmd compare --metric steps:sum \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

`healthmd.health_data` v8 é o contrato público de origem da Apple. Os schemas de consulta, evidência, tarefa e recibo descrevem visões de transporte ou derivadas. Eles não substituem o schema de origem. A extração canônica é uma funcionalidade do iPhone; as fontes diretas do Android expõem snapshots Health Connect nativos do provedor por meio da exportação bruta.

## Comportamento legível por máquina

Os comandos usam JSON versionado no stdout ou no caminho `--output` explícito por padrão. A extração canônica pode emitir JSONL e as consultas de alto nível podem optar por uma tabela deliberadamente com perdas. O progresso sem valores de saúde pode usar o stderr. `--help` é texto simples. Falhas de argumentos antes do início de um comando são texto simples no stderr com código de saída 2.

Uma saída de processo bem-sucedida não é suficiente para provar dados de saúde completos. Verifique:

- o status externo;
- o status do escopo solicitado;
- os resultados por dia e por consulta;
- os intervalos ausentes;
- `next_cursor` ou o recibo de percurso;
- o schema e a versão da origem;
- limitações e avisos.

Um resultado completamente vazio significa que o Health.md representou o escopo solicitado e não encontrou observações. Não é o mesmo que zero, ausente, falho, ignorado ou não suportado.

## Automação segura

Use o tempo limite de processo do seu host de automação e mantenha o stdin fechado para comandos que não devem solicitar entrada. Em sistemas com `timeout` do GNU:

```bash
NO_COLOR=1 TERM=dumb timeout 30 healthmd status </dev/null
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output sleep.json </dev/null
```

Tempo limite, Ctrl-C, término do processo, perda de rede e tempo de plano de fundo do iOS esgotado não cancelam uma tarefa persistente. Inspecione o ID da tarefa e retome-a em vez de iniciar uma duplicata.

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
healthmd cancel JOB_UUID
```

Somente uma confirmação do iPhone torna o cancelamento definitivo.

## Regras de privacidade

A saída bruta e sem perdas pode conter carimbos de data/hora exatos, rotas, registros clínicos, medicamentos, entradas de humor, valores de ECG, proveniência e anexos. Prefira um arquivo de saída à saída no terminal. Não cole payloads em relatórios de problemas, transcrições de agentes, logs de CI nem rastreamentos de shell.

A API de consulta local do auxiliar do Mac incluído não tem token de portador, registro, perfil de acesso nem banco de dados de concessões. A acessibilidade do loopback é sua fronteira de acesso completa. Qualquer processo local pode usá-la enquanto o app para Mac está aberto; nunca faça proxy nem exponha a porta `17645` a outra máquina.

## Próximos guias

<div class="related">
  <a href="/pt-br/docs/cli-direct/"><span>Sem app para Mac</span>CLI direta por telefone: emparelhe com iPhone ou Android, revise transportes, exportações brutas e de arquivos, comportamento em segundo plano e suporte de plataformas.</a>
  <a href="/pt-br/docs/cli-extract/"><span>Dados de origem</span>Extração canônica: selecione métricas, objetos, detalhes, ponteiros JSON, JSONL e recibos.</a>
  <a href="/pt-br/docs/cli-jobs/"><span>Automação</span>Tarefas persistentes: tempos limite, retomada, cancelamento, resultados parciais e scripts seguros.</a>
  <a href="/pt-br/docs/agents/"><span>Agentes</span>Fluxos de agentes locais: contexto criptografado, escopo direto, comandos tipados e evidências.</a>
  <a href="/pt-br/docs/mcp/"><span>MCP</span>Configure o auxiliar stdio isolado e revise a fronteira de ferramentas dele.</a>
  <a href="/pt-br/docs/reference/api-and-cli/"><span>Contrato</span>Referência de API e CLI: rotas exatas, schemas, respostas e fixtures gerados.</a>
</div>
