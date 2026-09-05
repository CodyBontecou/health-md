---
title: "Conecte um agente em 10 minutos"
description: "Conecte o auxiliar MCP do Health.md para Mac lançado ao Codex ou Claude, adquira um escopo explícito do iPhone, execute uma consulta limitada e verifique a completude com segurança."
---

<div class="availability available">
<strong>Disponível agora · Health.md para Mac</strong>
<p>Este caminho usa o auxiliar <code>healthmd-mcp</code> assinado que acompanha o app para Mac lançado. Ele não usa a prévia portátil da CLI, o Direct CLI Access, um código QR de emparelhamento nem a porta 17647.</p>
</div>

Você vai conectar um host MCP local, verificar a prontidão sem ler valores de saúde, atualizar explicitamente um escopo pequeno a partir do iPhone e consultar esse contexto criptografado do Mac. Reserve cerca de dez minutos quando os dois apps já estiverem instalados e na mesma rede local.

## 1. Instale e abra o Health.md

[Baixe o Health.md da App Store](https://apps.apple.com/us/app/health-md/id6757763969) no Mac e no iPhone. Abra os dois apps.

O HealthKit fica no iPhone. O app para Mac hospeda o auxiliar MCP assinado e um contexto de consulta criptografado e descartável; ele não lê o HealthKit diretamente.

## 2. Conecte o iPhone e o Mac

1. No Mac, deixe o Health.md aberto.
2. No iPhone, abra **Health.md → Sincronizar** e ative a conectividade com o Mac.
3. Mantenha os dois dispositivos na mesma rede local acessível e mantenha o Health.md em primeiro plano no iPhone enquanto um trabalho novo começa.
4. Confirme que o app do Mac mostra a conexão de iPhone pretendida. Se não mostrar, reabra os dois apps e revise a [prontidão da sincronização com o Mac](/pt-br/docs/sync/).

Esta é a conexão de Mac lançada. Não execute `healthmd direct pair`; esse comando pertence à prévia portátil separada.

## 3. Copie o caminho do auxiliar assinado

Abra **Health.md para Mac → CLI** e copie o caminho do auxiliar MCP exibido. Uma instalação normal em `/Applications` usa:

```text
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

Use o caminho exibido se o app estiver instalado em outro lugar. Configure o auxiliar diretamente: não o envolva em um shell nem o inicie como um comando interativo.

## 4. Configure o Codex ou o Claude

### Codex

Adicione isto ao `~/.codex/config.toml`, substituindo o caminho do auxiliar quando necessário:

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

Reinicie o Codex depois de salvar o arquivo.

### Claude Desktop ou Claude Code

Adicione esta entrada stdio local à configuração MCP do Claude Desktop ou a um `.mcp.json` confiável do Claude Code:

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

Reinicie o Claude Desktop, ou confie no workspace do Claude Code e aprove o servidor. Mantenha os avisos de aprovação ativados para as operações de atualização, exportação, retomada e cancelamento.

## 5. Verifique a prontidão

Chame `healthmd_doctor`. Ele lê apenas a prontidão, sem valores de saúde.

Um resultado pronto contém estes campos:

```json
{
  "schema": "healthmd.local_readiness",
  "schema_version": 1,
  "status": "ready"
}
```

O resultado completo também inclui verificações e próximas ações. Resolva toda verificação bloqueante antes de continuar. Um auxiliar conectado **não** prova que o contexto criptografado está atualizado.

Em seguida, chame `healthmd_metrics` e confirme o ID de métrica canônico e a unidade que você pretende solicitar. Este passo a passo usa `steps` apenas como exemplo.

## 6. Atualize explicitamente um escopo pequeno

Resolva as datas que você realmente quer e então chame `healthmd_refresh` com um intervalo exato e inclusivo. O exemplo solicita um dia de dados resumidos:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-14",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

Revise os argumentos, aprove a aquisição e mantenha os dois apps abertos. A atualização não grava arquivos de exportação nem altera as configurações de exportação salvas no iPhone. Guarde o `job_id` retornado até a tarefa alcançar um estado terminal.

## 7. Execute a primeira consulta limitada

Depois que a atualização terminar, chame `healthmd_metric_chart` com as mesmas datas, métrica, seleção de fontes e nível de detalhe:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-14",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "all_pages": true
}
```

`all_pages: true` percorre cursores opacos somente dentro dos limites agregados de páginas e bytes do auxiliar. Para o sono, chame `healthmd_sleep_sessions` em vez de substituir a extração canônica.

## 8. Verifique a completude antes de responder

Não trate o sucesso de uma ferramenta como prova de cobertura completa de saúde. Verifique tudo o seguinte:

- a atualização alcançou um estado terminal de sucesso para as mesmas datas exatas, métricas, fontes e nível de detalhe;
- o esquema e a versão da resposta são reconhecidos;
- o intervalo solicitado e o fuso horário correspondem à pergunta;
- cada valor declarado mantém seu ID de métrica canônico e sua unidade;
- o status de cobertura, os dias considerados, os dias com valores e cada intervalo ausente são relatados;
- `complete_empty`, `partial`, `failed`, `unsupported`, `skipped` e `cancelled` não são convertidos em zero;
- o percurso foi concluído, ou qualquer cursor ou limite agregado restante é divulgado;
- os descritores de evidência e de origem e as limitações permanecem anexados à resposta;
- a direção factual não vira diagnóstico, conselho de tratamento, causalidade ou linguagem de «melhor/pior».

### Leia resultados parciais sem descartar dados úteis

Uma consulta tipada pode retornar um `healthmd.query_response` válido enquanto apenas parte do escopo solicitado foi concluída. O [fixture gerado de resposta parcial](/docs/reference/generated/automation/agent-query-response-partial.json) mantém um item de passos disponível e relata o dia com falha separadamente:

```json
{
  "schema": "healthmd.query_response",
  "schema_version": 1,
  "coverage": {
    "status": "partial",
    "days_considered": 2,
    "days_with_values": 1,
    "missing": [
      {
        "status": "failed",
        "range": {
          "start_date": "2026-03-16",
          "end_date": "2026-03-16"
        }
      }
    ]
  },
  "items": ["one retained typed item"],
  "limitations": ["one or more requested days did not complete"]
}
```

As strings dentro de `items` e `limitations` acima são abreviações explicativas; use o fixture gerado para download para os campos e as evidências exatos. Preserve juntos o item retido, o intervalo com falha, as contagens de cobertura e a limitação.

Não adicione `status: "partial_success"` ao `healthmd.query_response`. Esse status pertence aos envelopes de CLI e exportação de nível superior quando a aquisição, o percurso ou a geração de arquivos está incompleta. Um tempo limite é outra coisa: é um resultado desconhecido de uma tarefa persistente que deve ser inspecionado pelo ID da tarefa.

Falhas estruturadas usam `healthmd.query_error` v1 em vez de uma resposta parcial. Inspecione [agent-query-error.json](/docs/reference/generated/automation/agent-query-error.json) para o formato de produção gerado, com código estável, mensagem, possibilidade de nova tentativa e detalhes tipados.

## 9. Recupere-se de um tempo limite com segurança

Um tempo limite, um host fechado ou uma espera de MCP cancelada não cancela uma atualização aceita.

1. Guarde o `job_id` retornado.
2. Chame `healthmd_job_status` com esse ID.
3. Se a tarefa imutável for retomável, revise e aprove `healthmd_job_resume` com o mesmo ID e um tempo limite de espera finito.
4. Inicie uma nova atualização somente depois que o status provar que nenhuma tarefa aceita ainda pode ser concluída.
5. Use `healthmd_job_cancel` somente quando quiser encerrar a tarefa; o cancelamento é terminal apenas após a confirmação do iPhone.

Nunca repita às cegas após um resultado desconhecido. As tarefas persistentes de atualização preservam o escopo aceito e a fronteira confirmada.

## Você está conectado

O primeiro fluxo somente leitura está completo quando o doctor está pronto, a atualização explícita é terminal, a consulta limitada tem o percurso completo e você inspecionou cobertura, evidências, unidades e limitações.

As exportações de arquivos gerados são um fluxo separado que exige aprovação. A ferramenta de Mac lançada grava na pasta já selecionada no Health.md para Mac; ela não aceita um argumento de destino arbitrário.

<div class="related">
  <a href="/pt-br/docs/mcp/"><span>Catálogo de ferramentas</span>Revise todas as ferramentas de Mac lançadas, os esquemas exatos, MCP Apps, a paginação e os limites de segurança.</a>
  <a href="/pt-br/docs/configuration/"><span>Outros clientes</span>Escolha entre a integração de Mac lançada e a prévia portátil claramente marcada.</a>
  <a href="/pt-br/docs/agent-queries/"><span>Próximas perguntas</span>Execute fluxos tipados de métricas, sono, treinos, comparações, cobertura e evidências.</a>
  <a href="/pt-br/docs/agents/"><span>Modelo de confiança</span>Entenda o contexto criptografado, o escopo das solicitações, a retenção, as evidências e as regras de relato.</a>
</div>
