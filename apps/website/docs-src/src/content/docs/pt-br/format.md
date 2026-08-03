---
title: "Personalização do formato"
description: "Controle a formatação da saída sem alterar o que é coletado. Escolha o formato de arquivo, as convenções de data, hora e unidades, personalize o frontmatter YAML e escolha um modelo Markdown."
---

## Formatos de saída
<div class="options">
<div class="option"><strong>Markdown (.md)</strong><p>Padrão. Um arquivo por dia. Frontmatter YAML opcional e seções com títulos por categoria.</p></div>
<div class="option"><strong>Obsidian Bases</strong><p>Markdown com frontmatter estruturado e otimizado para o plugin <a href="https://help.obsidian.md/Plugins/Bases">Bases</a> do Obsidian. Propriedades numéricas continuam numéricas e datas continuam sendo datas.</p></div>
<div class="option"><strong>JSON</strong><p>Um arquivo JSON por dia. Resumos diários do schema v7 podem incorporar o arquivo oficial <code>healthmd.healthkit_records</code> v1 quando os registros de saúde sem perdas estão ativados.</p></div>
<div class="option"><strong>CSV</strong><p>Um arquivo CSV por dia com o cabeçalho <code>Date,Category,Metric,Value,Unit,Timestamp</code>. Linhas de resumo de compatibilidade contêm cinco campos e omitem a coluna de data e hora; linhas com data e hora e linhas de registros canônicos contêm os seis campos.</p></div>
</div>

<div class="callout"><strong>Precisa do contrato exato?</strong><p style="margin-top:6px;">Consulte a <a href="/pt-br/docs/reference/export-formats/">referência de formatos</a> baseada em produção, os <a href="/pt-br/docs/reference/generated/core/csv-row-contracts/">contratos de linhas CSV</a> e os fixtures completos para download.</p></div>

## Data e hora
<p>Seletores de formato de data (por exemplo, <code>YYYY-MM-DD</code>, <code>MMM d, yyyy</code>) e de hora (12 ou 24 horas). O bloco de prévia no fim da tela é atualizado em tempo real.</p>

## Sistema de unidades
<p>Alterne entre <em>Métrico</em> e <em>Imperial</em>. Isso afeta distância (m/km ou ft/mi), peso (kg ou lb), temperatura (°C ou °F) e algumas outras medidas. O HealthKit sempre armazena unidades canônicas; a conversão ocorre durante a exportação.</p>

## Campos do frontmatter
<p>Toque em <em>Campos do frontmatter</em> para abrir um editor dedicado:</p>
<ul><li>Ative campos integrados individualmente (data, dia da semana, totalSteps etc.)</li><li>Renomeie um campo — útil se sua configuração do Obsidian espera outras chaves</li><li>Adicione campos personalizados com valores estáticos (por exemplo, <code>type: health</code>)</li><li>Adicione campos de espaço reservado resolvidos na exportação (por exemplo, <code>weather: {weather}</code>)</li></ul>

## Modelo Markdown
<p>Toque em <em>Modelo Markdown</em> para abrir um editor com estilos integrados — Compacto, Seções e Detalhado — e um modo totalmente personalizado. A prévia mostra o resultado com os dados de hoje.</p>

## Prévia
<p>No fim da tela Formato, um bloco de prévia renderiza os dados de hoje com as configurações atuais. É a maneira mais rápida de iterar: altere um controle, veja a prévia e repita.</p>

## Relacionados
<div class="related">
<a href="/pt-br/docs/metrics/"><span>O quê</span>Métricas de saúde — escolha primeiro os dados.</a>
<a href="/pt-br/docs/individual-tracking/"><span>Detalhado</span>Rastreamento individual — uma saída diferente, com arquivos por registro.</a>
<a href="/pt-br/docs/daily-notes/"><span>Obsidian</span>Injeção em notas diárias — usa os mesmos campos do frontmatter.</a>
<a href="/pt-br/docs/reference/export-formats/"><span>Contrato</span>Formatos de exportação — comportamento exato de JSON, CSV, Markdown e Bases.</a>
</div>
