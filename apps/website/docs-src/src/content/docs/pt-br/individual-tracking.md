---
title: "Rastreamento de registros individuais"
description: "Opcionalmente, grave um arquivo para cada registro com data e hora — cada exercício, leitura de pressão ou registro de humor recebe seu próprio arquivo Markdown com a data e a hora no nome."
---

## Quando usar
<p>As exportações diárias geram um arquivo por dia com resumos. O <em>rastreamento individual</em> serve quando você quer <em>citar um único evento</em>: vincular um exercício específico a uma nota ou criar um backlink de um registro de humor em uma revisão semanal.</p>
<p>Ele complementa a exportação diária, não a substitui. Com ambos ativos, você recebe os dois tipos de arquivo.</p>

## Configuração em duas etapas
<ol><li><strong>Controle mestre.</strong> Ative o recurso globalmente.</li><li><strong>Seleção por métrica.</strong> Escolha quais métricas geram arquivos individuais. A maioria das pessoas não quer um arquivo para cada leitura de frequência cardíaca (10,000 / day), mas quer um por exercício (~1 / day).</li></ol>

## Ações rápidas
<div class="options"><div class="option"><strong>Ativar métricas sugeridas</strong><p>Padrões sensatos: humor, sintomas, exercícios, pressão arterial e glicemia.</p></div><div class="option"><strong>Ativar todas as métricas</strong><p>Todas. Cuidado: isso pode gerar milhares de arquivos por dia.</p></div><div class="option"><strong>Desativar todas as métricas</strong><p>Limpa a seleção sem desligar o controle mestre.</p></div></div>

## Estrutura de pastas
<div class="options"><div class="option"><strong>Pasta de registros</strong><p>Caminho relativo ao cofre. Padrão: <code>entries</code>.</p></div><div class="option"><strong>Organizar por categoria</strong><p>Quando ativo, cria subpastas (<code>entries/workouts/</code>, <code>entries/symptoms/</code>). Quando desativado, mantém tudo em uma pasta única.</p></div></div>

## Modelo do nome do arquivo
<p>Padrão: <code>{date}_{time}_{metric}</code>. Espaços reservados: <code>{date}</code>, <code>{time}</code>, <code>{metric}</code>, <code>{category}</code>. Exemplo:</p>
<div class="doc-diagram folder-tree" aria-label="Exemplo de árvore de arquivos de registros individuais">
<span>{vault}/entries/</span>
<span>├─ workouts/2026_07_14_0920_workouts_workouts_71000000-0000-0000-0000-000000000008.md</span>
<span>├─ symptoms/2026_07_14_0916_symptom_headache_symptom_headache_71000000-0000-0000-0000-000000000002.md</span>
<span>└─ vitals/2026_07_14_0918_blood_pressure_blood_pressure_71000000-0000-0000-0000-000000000004.md</span>
</div>
<p>Registros canônicos com origem acrescentam a métrica e o UUID do HealthKit em minúsculas depois do nome configurado. Isso mantém o registro estável entre execuções e evita colisões no mesmo minuto. Registros de compatibilidade sem UUID mantêm o comportamento legado mais curto.</p>
<div class="callout"><strong>Atenção.</strong><p style="margin-top:6px;">Só aparecem categorias com pelo menos uma métrica ativada em <em>Métricas de saúde</em>. Ative uma métrica lá e volte para escolher o rastreamento. Consulte o <a href="/pt-br/docs/reference/individual-entry-tracking/">contrato de identidade dos registros de origem</a> e a <a href="/pt-br/docs/reference/generated/individual/filename-path-matrix/">matriz de nomes</a> antes de criar automações baseadas em caminhos.</p></div>

## Relacionados
<div class="related"><a href="/pt-br/docs/metrics/"><span>Pré-requisito</span>Métricas de saúde — ative primeiro.</a><a href="/pt-br/docs/format/"><span>Saída</span>Formato — também se aplica aos arquivos de registros.</a><a href="/pt-br/docs/daily-notes/"><span>Alternativa</span>Injeção em notas diárias — outra forma de anexar métricas.</a><a href="/pt-br/docs/reference/individual-entry-tracking/"><span>Contrato</span>Referência de registros individuais — identidade UUID, frontmatter e compatibilidade.</a></div>
