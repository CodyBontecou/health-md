---
title: Comece com o Health.md.
description: Exporte dados do Apple Health ou do Health Connect, conecte o auxiliar assinado para Mac a um agente local e desenvolva com base nos contratos versionados do Health.md.
---

<div class="docs-hero" data-strand-stage>
  <canvas class="docs-dna" data-three-strand aria-hidden="true"></canvas>
  <div class="docs-hero-copy">
    <p class="docs-eyebrow">Disponível agora · auxiliar assinado para Mac</p>
    <p>Exporte dados de saúde do seu celular, conecte um agente local pelos auxiliares assinados para Mac ou desenvolva com base em contratos versionados. As leituras do HealthKit permanecem no iPhone, e as leituras do Health Connect permanecem no Android.</p>
    <div class="docs-command" aria-label="Comando integrado de verificação de prontidão do Health.md"><span aria-hidden="true">$</span> "/Applications/Health.md.app/Contents/Helpers/healthmd" doctor</div>
    <p class="docs-command-note">Instalou em outro local? Copie o caminho do auxiliar integrado em <strong>Health.md para Mac → CLI</strong>.</p>
    <div class="docs-actions">
      <a class="docs-button" href="/pt-br/docs/iphone-first-export/">Primeira exportação no iPhone</a>
      <a class="docs-button-secondary" href="/pt-br/docs/configuration/">Conectar um agente</a>
      <a class="docs-button-secondary" href="/pt-br/docs/reference/">Ver contratos</a>
    </div>
  </div>
</div>

<div class="agent-path" aria-label="Escolha um objetivo no Health.md">
  <a href="/pt-br/docs/iphone-first-export/"><span>01 · Exportar</span><strong>Comece no iPhone</strong>Autorize o Apple Health, escolha uma pasta, visualize a saída e faça a primeira exportação.</a>
  <a href="/pt-br/docs/configuration/"><span>02 · Perguntar</span><strong>Conecte um agente local</strong>Use o auxiliar MCP assinado para Mac com Codex, Claude ou outro cliente stdio.</a>
  <a href="/pt-br/docs/reference/"><span>03 · Desenvolver</span><strong>Use contratos estáveis</strong>Integre schemas, registros, evidências, fixtures geradas e envelopes exatos.</a>
</div>

<div class="reference-stats">
<div><strong>21</strong><span>ferramentas MCP integradas para Mac</span></div>
<div><strong>4</strong><span>formatos de exportação</span></div>
<div><strong>v7</strong><span>schema público de exportação</span></div>
<div><strong>0</strong><span>etapas obrigatórias na nuvem do Health.md</span></div>
</div>

<p class="docs-section-kicker">Disponível agora · macOS</p>

## Início rápido com um agente local em cinco minutos

Abra o Health.md no Mac. Em seguida, abra o Health.md no iPhone emparelhado e aguarde a conexão. O auxiliar integrado verifica a prontidão sem retornar valores de saúde, lista as métricas de Sono e executa uma consulta de um dia:

```bash
HMD="/Applications/Health.md.app/Contents/Helpers/healthmd"
"$HMD" doctor
"$HMD" metrics list --category Sleep
"$HMD" query --category Sleep --yesterday
```

Um resultado pronto de `doctor` usa o schema `healthmd.cli_doctor` e inclui as próximas ações quando a configuração está incompleta. Para Codex ou Claude, prossiga para [Configurar seu agente](/pt-br/docs/configuration/) e indique ao cliente o auxiliar assinado `healthmd-mcp`, que é separado.

<p class="docs-section-kicker">Escolha por objetivo</p>

## Configure e conecte

<div class="related">
  <a href="/pt-br/docs/configuration/"><span>Disponível agora · Mac</span>Configuração — conecte Codex, Claude ou outro cliente stdio ao auxiliar MCP assinado.</a>
  <a href="/pt-br/docs/mcp/"><span>Disponível agora · Mac</span>Servidor MCP &amp; app — conheça 21 ferramentas integradas, renderize visualizações privadas e entenda a prévia portátil.</a>
  <a href="/pt-br/docs/cli/"><span>Disponível agora · Mac</span>CLI do Health.md — instale o auxiliar integrado, verifique a prontidão, consulte dados e diferencie a prévia portátil.</a>
  <a href="/pt-br/docs/agents/"><span>Arquitetura</span>Contexto do agente — conheça o escopo das solicitações, a confiança local, o contexto criptografado, as evidências, a retenção e a privacidade.</a>
</div>

<p class="docs-section-kicker">Operações do dia a dia</p>

## Consulte, extraia e automatize

<div class="related">
  <a href="/pt-br/docs/agent-queries/"><span>Consultas tipadas</span>Pergunte sobre métricas, sessões de sono, treinos, comparações, cobertura e evidências factuais.</a>
  <a href="/pt-br/docs/cli-direct/"><span>Prévia · CLI portátil</span>Acesso direto ao iPhone — entenda o emparelhamento por IP manual ou Tailscale antes do lançamento do pacote independente.</a>
  <a href="/pt-br/docs/cli-extract/"><span>Dados de origem</span>Extração canônica — obtenha dias selecionados do schema v7, registros de origem, projeções ou JSONL.</a>
  <a href="/pt-br/docs/cli-jobs/"><span>Execuções confiáveis</span>Tarefas persistentes — lide com timeouts, resultados desconhecidos, retomada, cancelamento e resultados parciais com segurança.</a>
  <a href="/pt-br/docs/agent-api/"><span>Baixo nível</span>API de loopback — use rotas exatas de consulta, evidência, cursor, atualização e tarefas persistentes.</a>
  <a href="/pt-br/docs/reference/integration-recipes/"><span>Padrões</span>Receitas de integração — analise e valide as saídas do Health.md sem enfraquecer seus contratos.</a>
</div>

<p class="docs-section-kicker">Interfaces estáveis</p>

## Contratos e estruturas de dados

<div class="related">
  <a href="/pt-br/docs/reference/"><span>Mapa de contratos</span>Referência de exportação — consulte schemas, métricas, formatos, registros e fixtures de interoperabilidade.</a>
  <a href="/pt-br/docs/reference/api-and-cli/"><span>Automação</span>Contratos da API &amp; CLI — verifique envelopes, rotas, comportamento de saída e exemplos gerados.</a>
  <a href="/pt-br/docs/reference/evidence-packets/"><span>Resultados do agente</span>Consultas &amp; evidências — valores tipados, cobertura, dados ausentes, operações e identidades determinísticas.</a>
  <a href="/pt-br/docs/reference/daily-records/"><span>Schema v7</span>Registros diários — entenda o documento público de origem e suas regras de propriedade.</a>
  <a href="/pt-br/docs/shared-metric-registry/"><span>Vocabulário</span>Registro de métricas — use IDs de métricas estáveis entre plataformas, categorias, unidades e metadados de perfil.</a>
  <a href="/pt-br/docs/reference/generated/"><span>Legível por máquina</span>Artefatos gerados — abra campos canônicos, fixtures, inventários de mensagens e contratos da CLI.</a>
</div>

<p class="docs-section-kicker">Fluxos do produto</p>

## Apps e exportações

<div class="related">
  <a href="/pt-br/docs/iphone-first-export/"><span>Comece aqui · iPhone</span>Primeira exportação — autorize o Apple Health, escolha uma pasta, visualize a saída e verifique os arquivos gravados.</a>
  <a href="/pt-br/docs/android/"><span>Android</span>Health Connect — escolha uma pasta de um provedor de documentos e configure a automação da plataforma.</a>
  <a href="/pt-br/docs/export/"><span>Arquivos</span>Exportação — execute intervalos de datas explícitos em Markdown, CSV, JSON ou Obsidian Bases.</a>
  <a href="/pt-br/docs/format/"><span>Estrutura</span>Personalização do formato — controle unidades, datas, frontmatter, nomes de arquivos e comportamento de gravação.</a>
  <a href="/pt-br/docs/scheduling/"><span>Segundo plano</span>Agendamento — entenda o comportamento das exportações diárias e semanais e os limites das plataformas.</a>
  <a href="/pt-br/docs/shortcuts/"><span>Automação</span>Atalhos &amp; App Intents — acione exportações, resumos e verificações de status em fluxos da Apple.</a>
</div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:12px; font-family:var(--sl-font-mono);">Estrutura da documentação atualizada em 02/08/2026</p>
