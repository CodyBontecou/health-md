---
title: "Endpoint de API"
description: "Envie JSON selecionado do Apple Health diretamente do iPhone para seu próprio endpoint HTTP(S)."
---

<p>O Endpoint de API é um destino de exportação para usuários que desejam que os dados do Health.md sejam enviados ao próprio servidor, webhook, banco de dados, painel ou automação. O iPhone continua lendo o Apple Health; em vez de gravar arquivos, ele envia o JSON por POST ao endpoint configurado.</p>

<div class="callout">
<strong>Lembrete de privacidade.</strong>
<p style="margin-top:6px;">Este destino envia intencionalmente os dados de saúde selecionados para a URL informada. Use um endpoint que você controle ou no qual confie, dê preferência a HTTPS e limite as métricas ao que seu serviço realmente precisa.</p>
</div>

## Configure o destino

<ol>
<li>Abra o Health.md no iPhone.</li>
<li>Acesse <strong>Exportar</strong>.</li>
<li>Em <strong>Destino da exportação</strong>, escolha <strong>Endpoint de API</strong>.</li>
<li>Insira uma URL, como <code>https://api.example.com/healthmd/ingest</code>.</li>
<li>Opcional: insira um token bearer. O Health.md o armazena nas Chaves.</li>
<li>Toque em <strong>Concluído</strong>, escolha o intervalo de datas e as métricas e toque em <strong>Exportar</strong>.</li>
</ol>

<p>Se você inserir um token simples, o Health.md o enviará como <code>Authorization: Bearer &lt;token&gt;</code>. Se o valor já começar com <code>Bearer </code> ou <code>Basic </code>, o Health.md o enviará exatamente como foi inserido.</p>

## Estrutura do payload

<p>O Health.md envia uma solicitação POST por ação de exportação. O corpo é um envelope <code>healthmd.api_export</code> com versionamento independente, que contém registros diários públicos <code>healthmd.health_data</code> do schema v8. O envelope de API v1 transporta os registros diários; a v2 também pode transportar sidecars de provedores sem alterar o schema dos registros diários.</p>

<div class="options">
<div class="option"><strong><code>records</code></strong><p>Objetos diários completos do schema v8 mantidos para o intervalo solicitado, incluindo registros completos e vazios cujo manifesto de consulta serve como evidência.</p></div>
<div class="option"><strong><code>failed_date_details</code></strong><p>Datas que apresentaram falha antes que um documento diário pudesse ser mantido.</p></div>
<div class="option"><strong><code>daily_record_schema_version</code></strong><p>A versão do schema diário em <code>records</code>. Ela avança independentemente da versão do envelope da API.</p></div>
<div class="option"><strong>Sidecars de provedores</strong><p>Registros externos condicionais da v2, com regras próprias de schema e identidade, quando um provedor conectado está ativado.</p></div>
</div>

<p>Consulte o <a href="/docs/reference/generated/automation/api-export-v1.json">envelope de API v1 completo gerado em produção</a> e o <a href="/docs/reference/generated/automation/api-export-v2-provider-sidecar.json">envelope de sidecar de provedor da API v2</a>. O <a href="/pt-br/docs/reference/api-and-cli/">contrato da API e da CLI</a> documenta todos os campos, limites de versão e regras de aceitação.</p>

## Requisitos do endpoint

<div class="options">
<div class="option"><strong>Método</strong><p>Aceite <code>POST</code>.</p></div>
<div class="option"><strong>Tipo de conteúdo</strong><p>Aceite <code>application/json</code>.</p></div>
<div class="option"><strong>Sucesso</strong><p>Retorne qualquer status <code>2xx</code> depois que o payload for aceito com segurança.</p></div>
<div class="option"><strong>Falhas</strong><p>Retorne <code>4xx</code> ou <code>5xx</code> para solicitações rejeitadas. O Health.md mostra uma breve prévia da resposta quando disponível.</p></div>
</div>

<p>Para uma ingestão confiável, torne seu endpoint idempotente por data. Um usuário pode repetir a exportação do mesmo intervalo depois de alterar as métricas ou corrigir um erro do servidor.</p>

## Dicas

<ul>
<li>Teste com um dia antes de enviar um preenchimento retroativo longo.</li>
<li>Mantenha os Registros de Saúde sem Perdas ativados quando a completude da fonte for importante; reduza o intervalo de datas para rotas densas, documentos clínicos, ECGs ou anexos.</li>
<li>Valide o token no servidor antes de armazenar qualquer payload.</li>
<li>Use <code>records[].date</code> como chave principal de cada dia.</li>
<li>Retorne um corpo de erro conciso; o Health.md exibe apenas uma breve prévia.</li>
</ul>

## Solução de problemas

| Problema | Geralmente significa | Correção |
|---|---|---|
| O destino da API não está pronto | A URL está vazia ou é inválida | Reabra as configurações do Endpoint de API e insira uma URL HTTP(S) válida. |
| HTTP 401 ou 403 | O token está ausente ou foi rejeitado | Atualize o token ou as regras de autenticação do servidor. |
| HTTP 404 | O caminho da URL está incorreto | Verifique a rota no servidor. |
| HTTP 413 | O payload é grande demais | Exporte menos dias; use uma saída somente de resumo apenas quando o receptor não precisar dos registros canônicos da fonte. |
| Algumas datas estão ausentes | Não há dados do HealthKit ativados para essas datas | Verifique <code>failed_date_details</code> e sua seleção de métricas. |

## Relacionados

<div class="related">
  <a href="/pt-br/docs/export/"><span>Fonte</span>Exportação — escolha destinos e intervalos de datas e execute exportações manuais.</a>
  <a href="/pt-br/docs/reference/api-and-cli/"><span>Schema</span>Referência da API e da CLI — envelopes exatos, versões, comportamento de falhas e exemplos gerados.</a>
  <a href="/pt-br/docs/format/"><span>Saída</span>Personalização de formato — JSON, CSV, Markdown, unidades e campos.</a>
</div>
