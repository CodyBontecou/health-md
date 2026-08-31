---
title: Configure seu agente
description: Escolha a interface MCP ou CLI do Health.md, configure Codex, Claude ou outro cliente local e conecte um iPhone emparelhado sem encaminhar o HealthKit por um serviço em nuvem.
---

O app lançado para Mac inclui dois auxiliares locais assinados: `healthmd-mcp` para ferramentas tipadas de agentes e `healthmd` para fluxos explícitos da CLI. A CLI multiplataforma separada com MCP direto para iPhone está empacotada publicamente como uma prévia explicitamente não qualificada; a validação de lançamento em dispositivos físicos continua obrigatória para a primeira versão estável.

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

Reinicie o Codex, chame `healthmd_doctor`, resolva os IDs com `healthmd_metrics`, adquira explicitamente um escopo pequeno com a ferramenta de atualização e consulte-o com uma ferramenta tipada como `healthmd_metric_chart`. O servidor integrado disponibiliza 21 ferramentas, incluindo prontidão do Mac, tarefas persistentes de atualização de contexto criptografado, evidências e visualizações.

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
<strong>Prévia pública · ainda não qualificada como estável</strong>
<p>A CLI Rust multiplataforma, <code>healthmd setup codex</code>, o comando <code>healthmd mcp serve</code> no mesmo binário e o emparelhamento direto no Linux/Windows estão empacotados publicamente como uma prévia explicitamente não qualificada.</p>
</div>

No macOS ou Linux, instale com <code>brew install CodyBontecou/tap/healthmd</code>. Depois, `healthmd setup codex` configura o Codex de forma idempotente e inicia o emparelhamento direto com o iPhone. Use a compilação móvel exata indicada pela evidência da versão; publicar o pacote não comprova compatibilidade móvel. A página [CLI direta para iPhone](/pt-br/docs/cli-direct/) documenta o transporte e o protocolo.

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
<p>Estes são os fluxos portáteis incluídos atualmente no pacote público. O caminho do MCP integrado ao Mac continua usando a conexão existente do app para Mac com o iPhone.</p>
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
  <a href="/pt-br/docs/mcp/"><span>Interface de ferramentas</span>Conheça as 21 ferramentas Mac publicadas, a prévia portátil com 19 ferramentas, MCP Apps, schemas, paginação, exportações e limites do sandbox.</a>
  <a href="/pt-br/docs/agent-queries/"><span>Primeiras perguntas</span>Execute fluxos tipados de métricas, sono, treinos, comparações, cobertura e evidências.</a>
  <a href="/pt-br/docs/cli-extract/"><span>Dados canônicos</span>Extraia documentos selecionados do schema v8 e registros de origem sem colocar grandes conteúdos no chat.</a>
  <a href="/pt-br/docs/reference/"><span>Contratos</span>Consulte estruturas de dados versionadas, inventários de campos, fixtures geradas e receitas de integração.</a>
</div>
