---
title: "Métricas de saúde"
description: "Escolha entre as métricas do catálogo atual do Apple Health no Health.md. Pesquise, ative categorias inteiras de uma vez ou abra cada uma para controlar métricas individualmente."
---

<div class="callout">
<strong>Observação sobre Android.</strong>
<p style="margin-top:6px;">Esta página documenta o seletor de métricas do Apple Health e a referência gerada de dados do HealthKit. O app Android oferece 106 métricas do Health Connect; consulte o <a href="/pt-br/docs/android/">guia do Android</a> para ver a configuração do Health Connect e o comportamento específico da plataforma.</p>
</div>

## Estrutura
<div class="options">
<div class="option"><strong>Cabeçalho de contagens</strong><p>Mostra em tempo real o número de métricas e categorias ativadas. Toque e segure para copiar o estado exato da seleção.</p></div>
<div class="option"><strong>Todas as métricas ativadas</strong><p>Controle mestre que ativa ou desativa todas as categorias. É um bom ponto de partida: ative tudo e depois desative o que não interessa.</p></div>
<div class="option"><strong>Busca</strong><p>Filtro em tempo real por nomes e identificadores de métricas. Experimente "heart", "sleep" ou "vo2".</p></div>
</div>

## Categorias
<p>O seletor agrupa resumos comuns e definições de registros de origem em categorias como Sono, Atividade, Coração, Respiratório, Sinais vitais, Medidas corporais, Mobilidade, Ciclismo, Nutrição, Atenção plena, Saúde reprodutiva, Sintomas, Medicamentos, registros especializados e Exercícios. Cada linha mostra o estado e a contagem atual de definições ativadas. O <a href="/pt-br/docs/reference/generated/core/metric-catalog/">catálogo de métricas</a> gerado em produção é o inventário atual oficial.</p>

<p>Toque em uma categoria para abrir suas métricas. Cada métrica tem seu próprio controle e identificador do HealthKit. A cor do ponto indica se o HealthKit tem dados dessa métrica neste dispositivo.</p>

## Escopo da seleção
<p>Sua seleção de métricas controla <em>tudo</em>:</p>
<ul>
<li>Exportações diárias — apenas métricas ativadas aparecem no arquivo</li>
<li>Rastreamento individual — apenas métricas ativadas geram arquivos por registro</li>
<li>Injeção em notas diárias — apenas métricas ativadas são mescladas ao frontmatter</li>
<li>Atalhos — exportações por intervalo usam a mesma seleção</li>
</ul>

<div class="callout">
<strong>Dica.</strong>
<p style="margin-top:6px;">Comece com pouco. Ative Sono, Atividade e Coração. Faça uma exportação e examine o arquivo. Depois, adicione outras categorias. É mais rápido acrescentar do que percorrer um arquivo de 50 linhas com métricas irrelevantes para você.</p>
</div>

## Relacionados
<div class="related">
  <a href="/pt-br/docs/reference/"><span>Referência</span>Referência de exportação — todas as métricas, chaves, unidades, definições de registros de origem e estruturas de exportação da Apple.</a>
  <a href="/pt-br/docs/android/"><span>Android</span>App Android — configuração, métricas, destinos e automação do Health Connect.</a>
  <a href="/pt-br/docs/format/"><span>Como</span>Formato — altere como as métricas escolhidas são gravadas.</a>
  <a href="/pt-br/docs/individual-tracking/"><span>Detalhado</span>Rastreamento individual — grave também um arquivo por registro com data e hora.</a>
  <a href="/pt-br/docs/daily-notes/"><span>Obsidian</span>Injeção em notas diárias — envie essas métricas para suas notas diárias.</a>
</div>
