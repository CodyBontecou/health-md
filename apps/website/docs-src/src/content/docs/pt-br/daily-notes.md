---
title: "Injeção em notas diárias"
description: "Mescle métricas de saúde selecionadas no frontmatter YAML — e, opcionalmente, no corpo — de suas notas diárias existentes no Obsidian ou em qualquer outro app Markdown."
---

## O que faz
<p>Se você mantém notas diárias (por exemplo, <code>Daily/2026-04-28.md</code>), ative este recurso para que o app <em>mescle</em> as métricas selecionadas no frontmatter YAML dessas notas a cada exportação, sem alterar o restante do conteúdo.</p>

<div class="doc-diagram merge-preview" aria-label="Frontmatter da nota diária antes e depois da mesclagem do Health.md">
<div class="merge-card"><strong>Antes</strong>
<pre><code>---
title: Tuesday note
mood: focused
---

Wrote launch notes...</code></pre></div>
<div class="merge-card"><strong>Depois da exportação</strong>
<pre><code>---
title: Tuesday note
mood: focused
steps: 12642
sleep_total_hours: 7.31
workout_count: 1
---

Wrote launch notes...</code></pre></div>
</div>

<p>Opcionalmente, o app também pode inserir seções Markdown — Sono, Atividade, Coração etc. — no corpo da nota. Essas seções são <em>gerenciadas pelo app</em> e substituídas de forma limpa a cada exportação. Os títulos escritos por você permanecem intactos.</p>

## Local
<div class="options"><div class="option"><strong>Pasta</strong><p>Caminho relativo ao cofre para a pasta de notas diárias. Padrão: <code>Daily</code>. Deixe vazio para usar a raiz do cofre. Exemplos: <code>Daily</code>, <code>Journal/Daily</code>.</p></div><div class="option"><strong>Nome do arquivo</strong><p>Padrão do nome sem extensão. O padrão <code>{date}</code> resulta em <code>2026-04-28</code>.</p></div></div>

## Espaços reservados do nome
<p>Combine-os livremente:</p>
<ul><li><code>{date}</code> — data ISO completa (<code>2026-04-28</code>)</li><li><code>{year}</code>, <code>{month}</code>, <code>{day}</code></li><li><code>{weekday}</code> — nome abreviado (<code>Tue</code>)</li><li><code>{monthName}</code> — nome completo (<code>April</code>)</li><li><code>{quarter}</code> — Q1 / Q2 / Q3 / Q4</li></ul>
<p>Exemplo: <code>{year}/{monthName}/{date}-{weekday}</code> → <code>2026/April/2026-04-28-Tue.md</code>. A linha de prévia mostra o caminho resultante em tempo real.</p>

## Opções
<div class="options"><div class="option"><strong>Criar nota se não existir</strong><p>Cria uma nota para a data quando ela não existe. Desative se você cria as notas com o Obsidian Templater ou plugin semelhante.</p></div><div class="option"><strong>Inserir seções de métricas</strong><p>Também grava títulos como Sono, Atividade e Coração no corpo. Gerenciadas pelo app e substituídas a cada exportação. Desativado por padrão.</p></div></div>

## Quais métricas são inseridas
<p>As selecionadas em <em>Métricas de saúde</em>. Não há outro seletor aqui. Ao alterar a seleção, a injeção acompanha a mudança.</p>

## Prévia do frontmatter
<p>No fim da tela há uma prévia em tempo real do frontmatter que será mesclado. Ela muda conforme a seleção de métricas ou os campos de frontmatter da personalização de formato.</p>

<div class="callout"><strong>Como funciona a mesclagem.</strong><p style="margin-top:6px;">Se a nota já tiver frontmatter, o app preserva suas chaves e apenas adiciona ou atualiza as que gerencia. Seções do corpo gerenciadas pelo app ficam entre comentários HTML, para que novas execuções sejam idempotentes.</p></div>

## Relacionados
<div class="related"><a href="/pt-br/docs/metrics/"><span>Pré-requisito</span>Métricas de saúde — escolha o que será inserido.</a><a href="/pt-br/docs/format/"><span>Formato</span>Editor de campos do frontmatter — renomeie chaves e adicione campos.</a><a href="/pt-br/docs/individual-tracking/"><span>Detalhado</span>Rastreamento individual — alternativa para acompanhar cada evento.</a></div>
