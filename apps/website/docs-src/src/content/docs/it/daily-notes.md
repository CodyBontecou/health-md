---
title: "Inserimento nelle note giornaliere"
description: "Unisci le metriche sanitarie selezionate nel frontmatter YAML (e, facoltativamente, nel corpo) delle note giornaliere esistenti, quelle che scrivi in Obsidian o in qualsiasi altra app Markdown."
---

## Come funziona
<p>Se utilizzi note giornaliere (ad esempio <code>Daily/2026-04-28.md</code>), attiva questa opzione e, a ogni esportazione, l'app <em>unirà</em> le metriche selezionate nel frontmatter YAML di tali note, senza modificare il resto del loro contenuto.</p>

<div class="doc-diagram merge-preview" aria-label="Frontmatter della nota giornaliera prima e dopo l’unione di Health.md">
<div class="merge-card">
<strong>Prima</strong>
<pre><code>---
title: Tuesday note
mood: focused
---

Wrote launch notes...</code></pre>
</div>
<div class="merge-card">
<strong>Dopo l'esportazione</strong>
<pre><code>---
title: Tuesday note
mood: focused
steps: 12642
sleep_total_hours: 7.31
workout_count: 1
---

Wrote launch notes...</code></pre>
</div>
</div>

<p>Facoltativamente, l'app può anche inserire sezioni Markdown (Sonno, Attività, Cuore e così via) nel corpo della nota. Queste sezioni sono <em>gestite dall'app</em> e vengono sostituite in modo pulito a ogni esportazione. Le intestazioni che scrivi personalmente rimangono inalterate.</p>

## Posizione
<div class="options">
<div class="option"><strong>Cartella</strong><p>Percorso relativo al vault della cartella delle note giornaliere. Il valore predefinito è <code>Daily</code>. Lascia vuoto per usare la radice del vault. Esempi: <code>Daily</code>, <code>Journal/Daily</code>.</p></div>
<div class="option"><strong>Nome file</strong><p>Schema per il nome della nota senza estensione. Il valore predefinito <code>{date}</code> viene risolto come <code>2026-04-28</code>.</p></div>
</div>

## Segnaposto per il nome file
<p>Puoi combinarli liberamente:</p>
<ul>
<li><code>{date}</code> — data ISO completa (<code>2026-04-28</code>)</li>
<li><code>{year}</code>, <code>{month}</code>, <code>{day}</code></li>
<li><code>{weekday}</code> — nome abbreviato (<code>Tue</code>)</li>
<li><code>{monthName}</code> — nome completo (<code>April</code>)</li>
<li><code>{quarter}</code> — Q1 / Q2 / Q3 / Q4</li>
</ul>
<p>Esempio: <code>{year}/{monthName}/{date}-{weekday}</code> → <code>2026/April/2026-04-28-Tue.md</code>. La riga di anteprima sotto il campo mostra in tempo reale il percorso risultante.</p>

## Opzioni
<div class="options">
<div class="option"><strong>Crea la nota se non esiste</strong><p>Se la nota giornaliera non esiste per una determinata data, ne crea una nuova. Lascia questa opzione disattivata se crei autonomamente le note giornaliere tramite Obsidian Templater o un plugin simile.</p></div>
<div class="option"><strong>Inserisci sezioni delle metriche</strong><p>Scrive anche le intestazioni Sonno, Attività, Cuore e così via nel corpo della nota. Sono gestite dall'app e vengono sostituite in modo pulito a ogni esportazione. L'opzione è disattivata per impostazione predefinita.</p></div>
</div>

## Quali metriche vengono inserite
<p>Vengono inserite tutte le metriche selezionate in <em>Metriche sanitarie</em>. Qui non è disponibile un selettore separato. Modifica lì la selezione delle metriche e l'Inserimento nelle note giornaliere si adeguerà di conseguenza.</p>

## Anteprima del frontmatter
<p>Nella parte inferiore della schermata Iniezione nelle note giornaliere è disponibile un'anteprima in tempo reale del frontmatter che verrà unito. Si aggiorna quando modifichi la selezione delle metriche o i campi del frontmatter nella personalizzazione del formato.</p>

<div class="callout">
<strong>Come funziona l'unione.</strong>
<p style="margin-top:6px;">Se la nota giornaliera esistente contiene già un frontmatter, l'app conserva le tue chiavi e aggiunge o aggiorna esclusivamente quelle che gestisce. Le sezioni del corpo gestite dall'app sono racchiuse tra commenti HTML, così le esecuzioni successive risultano idempotenti.</p>
</div>

## Correlati

<div class="related">
  <a href="/it/docs/metrics/"><span>Prerequisito</span>Metriche sanitarie — scegli quali inserire.</a>
  <a href="/it/docs/format/"><span>Formato</span>Editor dei campi del frontmatter — rinomina le chiavi e aggiungi campi personalizzati.</a>
  <a href="/it/docs/individual-tracking/"><span>Dettaglio granulare</span>Monitoraggio individuale — un'alternativa per monitorare i singoli eventi.</a>
</div>
