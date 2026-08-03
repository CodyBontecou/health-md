---
title: Configure seu agente
description: Escolha a interface MCP ou CLI do Health.md, configure Codex, Claude ou outro cliente local e conecte um iPhone emparelhado sem encaminhar o HealthKit por um serviço em nuvem.
---

O app lançado para Mac inclui dois auxiliares locais assinados: `healthmd-mcp` para ferramentas tipadas de agentes e `healthmd` para fluxos explícitos da CLI. Uma CLI multiplataforma separada, com MCP direto para iPhone, está documentada como prévia até que seu primeiro pacote público conclua a validação de lançamento em dispositivos físicos.

<div class="callout">
<strong>O HealthKit permanece no iPhone.</strong>
<p style="margin-top:6px;">A configuração dá a um cliente local acesso às interfaces limitadas do Health.md. Ela não dá ao computador ou ao agente acesso direto ao HealthKit nem envia sua base de dados de origem para uma nuvem do Health.md.</p>
</div>

## Escolha uma interface

| Objetivo | Comece com | Prossiga para |
|---|---|---|
| Permitir que Codex ou Claude consultem e criem gráficos de dados de saúde no Mac | `healthmd-mcp` integrado por stdio | [Servidor e ferramentas MCP](/pt-br/docs/mcp/) |
| Exportar JSON canônico ou arquivos gerados em um script no Mac | CLI `healthmd` integrada | [CLI](/pt-br/docs/cli/) |
| Conectar diretamente a um iPhone aberto sem o app para Mac | CLI direta portátil (**prévia**) | [Acesso direto ao iPhone](/pt-br/docs/cli-direct/) |
| Desenvolver com base em envelopes exatos de solicitação e resposta | API de loopback ou contratos públicos | [API de loopback](/pt-br/docs/agent-api/) |
| Analisar schemas, registros, evidências ou fixtures geradas | Referência versionada | [Contratos de dados](/pt-br/docs/reference/) |

As escolhas de backend e transporte são explícitas; o Health.md não muda silenciosamente do acesso direto ao iPhone para o app para Mac.

## Codex com o app para Mac

<div class="availability available">
<strong>Disponível agora · auxiliar assinado para Mac</strong>
<p>Instale o Health.md para Mac, abra a tela <strong>CLI</strong> e copie o caminho exibido do MCP integrado caso o app não esteja em <code>/Applications</code>.</p>
</div>

Adicione o auxiliar assinado separado `healthmd-mcp` a `~/.codex/config.toml`:

```toml
[mcp_servers.healthmd]
command = "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
args = []
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"
```

Reinicie o Codex, chame `healthmd_doctor` e depois chame `healthmd_metrics` e uma ferramenta tipada pequena, como `healthmd_metric_chart`. O servidor integrado disponibiliza 21 ferramentas, incluindo prontidão do Mac, tarefas persistentes de atualização de contexto criptografado, evidências e visualizações.

## Claude Desktop ou Claude Code no Mac

Adicione o auxiliar integrado à configuração MCP do Claude Desktop ou a um `.mcp.json` confiável do Claude Code:

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

Reinicie o cliente depois de alterar a configuração. Configurações no escopo do projeto ainda exigem confiança no workspace e aprovação explícita do servidor. Mantenha os apps do Mac e do iPhone abertos quando uma ferramenta precisar de dados recentes do HealthKit.

## Qualquer cliente MCP stdio no Mac

Configure um processo local:

```text
command: /Applications/Health.md.app/Contents/Helpers/healthmd-mcp
arguments: none
transport: stdio
```

O host controla stdin e o ciclo de vida do processo. Não inicie o auxiliar como um comando interativo comum nem o envolva em um shell que altere a saída JSON-RPC. Use `tools/list` do MCP para conhecer os schemas exatos disponibilizados pelo app instalado.

## Configuração direta portátil

<div class="availability preview">
<strong>Prévia · ainda sem pacote público</strong>
<p>A CLI Rust multiplataforma, <code>healthmd setup codex</code>, o comando <code>healthmd mcp serve</code> no mesmo binário e o emparelhamento direto no Linux/Windows estão implementados, mas aguardam o primeiro lançamento público validado.</p>
</div>

Após a publicação, `healthmd setup codex` configurará o Codex de forma idempotente e iniciará o emparelhamento direto com o iPhone. Até lá, não dependa de URLs não publicadas do Homebrew, crates.io, instaladores ou versões do GitHub. A página [CLI direta para iPhone](/pt-br/docs/cli-direct/) documenta o comportamento de transporte e protocolo em preparação.

## Fluxos explícitos da CLI

Para extração canônica ou automação orientada a arquivos, invoque `healthmd` diretamente, em vez de pedir a um host MCP que transporte um grande corpo de origem:

```bash
healthmd status
healthmd extract --category Sleep --last 7 --output sleep.json
healthmd export --last 7 --destination "$HOME/Documents/HealthVault"
```

A disponibilidade e a gramática diferem entre o auxiliar integrado para Mac e a CLI multiplataforma independente. Consulte [CLI do Health.md](/pt-br/docs/cli/) antes de copiar comandos para uma automação não supervisionada.

## Emparelhamento e prontidão portáteis

<div class="availability preview">
<strong>Prévia · fluxos diretos portáteis</strong>
<p>Estas etapas descrevem o futuro pacote multiplataforma. O caminho do MCP integrado lançado para Mac usa a conexão existente do app para Mac com o iPhone.</p>
</div>

Os fluxos diretos do MCP e da CLI exigem um emparelhamento confiável, feito uma única vez, com o Health.md no iPhone. O emparelhamento usa um canal autenticado e criptografado e armazenamento nativo de credenciais no macOS, Linux ou Windows.

1. Ative **Acesso ao Direct CLI** no Health.md para iPhone.
2. Inicie o emparelhamento com `healthmd setup codex` ou `healthmd direct pair`.
3. Aprove a solicitação de emparelhamento limitada no iPhone.
4. Mantenha o Health.md em primeiro plano ao iniciar uma consulta ou exportação.
5. Chame `healthmd_doctor` no MCP ou `healthmd status` na CLI portátil antes de tarefas maiores.

Consulte [Acesso direto ao iPhone](/pt-br/docs/cli-direct/) para saber mais sobre IP manual, Tailscale, porta, dispositivo confiável, primeiro plano e recuperação.

## Limites da configuração

Uma configuração de agente local **não** concede:

- leituras ou gravações arbitrárias no HealthKit;
- acesso arbitrário ao sistema de arquivos;
- URLs, comandos de shell, prompts, raízes ou amostragem arbitrários pelo MCP;
- permissão para ocultar dados ausentes, cobertura, unidades, evidências ou limitações;
- permissão para retomar, cancelar ou sobrescrever arquivos gerados sem a aprovação aplicável.

Para obter um resultado completo, verifique o escopo solicitado, a cobertura, o percurso, as limitações e o schema de origem — não apenas o sucesso do processo.

## Continue

<div class="related">
  <a href="/pt-br/docs/mcp/"><span>Interface de ferramentas</span>Conheça as 21 ferramentas disponíveis no Mac, a prévia portátil com 17 ferramentas, MCP Apps, schemas, paginação, exportações e limites do sandbox.</a>
  <a href="/pt-br/docs/agent-queries/"><span>Primeiras perguntas</span>Execute fluxos tipados de métricas, sono, treinos, comparações, cobertura e evidências.</a>
  <a href="/pt-br/docs/cli-extract/"><span>Dados canônicos</span>Extraia documentos selecionados do schema v7 e registros de origem sem colocar grandes conteúdos no chat.</a>
  <a href="/pt-br/docs/reference/"><span>Contratos</span>Consulte estruturas de dados versionadas, inventários de campos, fixtures geradas e receitas de integração.</a>
</div>
