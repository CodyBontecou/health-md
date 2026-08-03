---
title: "Personalizzazione del formato"
description: "Controlla la formattazione dell'output senza modificare i dati raccolti. Scegli il formato dei file, le convenzioni per data, ora e unità, personalizza il frontmatter YAML e seleziona un modello Markdown."
---

## Formati di output
<div class="options">
<div class="option"><strong>Markdown (.md)</strong><p>Formato predefinito. Un file al giorno. Frontmatter YAML (facoltativo) seguito da sezioni con intestazioni per ogni categoria.</p></div>
<div class="option"><strong>Obsidian Bases</strong><p>Markdown con frontmatter strutturato e ottimizzato per il plugin <a href="https://help.obsidian.md/Plugins/Bases">Bases</a> di Obsidian. Le proprietà numeriche restano numeri e le date restano date.</p></div>
<div class="option"><strong>JSON</strong><p>Un file JSON al giorno. I riepiloghi giornalieri schema-v7 possono incorporare l'archivio autorevole <code>healthmd.healthkit_records</code> v1 quando è abilitata l'opzione Dati sanitari senza perdita.</p></div>
<div class="option"><strong>CSV</strong><p>Un file CSV al giorno con l'intestazione <code>Date,Category,Metric,Value,Unit,Timestamp</code>. Le righe di riepilogo per compatibilità contengono cinque campi e omettono la colonna del timestamp; le righe con timestamp e quelle dei record canonici contengono tutti e sei i campi.</p></div>
</div>

<div class="callout">
<strong>Ti serve il contratto esatto?</strong>
<p style="margin-top:6px;">Consulta il <a href="/it/docs/reference/export-formats/">riferimento dei formati</a> basato sul comportamento in produzione, i <a href="/it/docs/reference/generated/core/csv-row-contracts/">contratti delle righe CSV</a> e i fixture completi scaricabili.</p>
</div>

## Data e ora
<p>Scegli il formato della data (ad es. <code>YYYY-MM-DD</code>, <code>MMM d, yyyy</code>) e quello dell'ora (12 o 24 ore). Il riquadro di anteprima in fondo alla schermata si aggiorna in tempo reale quando modifichi le impostazioni.</p>

## Sistema di unità
<p>Passa da <em>Metrico</em> a <em>Imperiale</em>. Questa impostazione influisce su distanza (m/km rispetto a ft/mi), peso (kg rispetto a lb), temperatura (°C rispetto a °F) e alcune altre misure. HealthKit archivia sempre i dati in unità canoniche; la conversione avviene al momento dell'esportazione.</p>

## Campi del frontmatter
<p>Toccando <em>Campi del frontmatter</em> si apre un editor dedicato:</p>
<ul>
<li>Attiva o disattiva singolarmente i campi integrati (data, giorno della settimana, totalSteps e così via)</li>
<li>Rinomina un campo, utile se la tua configurazione di Obsidian richiede chiavi diverse</li>
<li>Aggiungi campi personalizzati con valori statici (ad es. <code>type: health</code>)</li>
<li>Aggiungi campi segnaposto che vengono risolti al momento dell'esportazione (ad es. <code>weather: {weather}</code>)</li>
</ul>

## Modello Markdown
<p>Toccando <em>Modello Markdown</em> si apre un editor di modelli con diversi stili integrati (Compatto, Sezioni, Dettagliato) e una modalità completamente personalizzata. Il riquadro di anteprima mostra il risultato usando i dati di oggi.</p>

## Anteprima
<p>In fondo alla schermata Formato, un riquadro di anteprima in tempo reale visualizza i dati di oggi con le impostazioni correnti. È il modo più rapido per perfezionare il risultato: modifica un'opzione, controlla l'anteprima e ripeti.</p>

## Pagine correlate

<div class="related">
  <a href="/it/docs/metrics/"><span>Cosa</span>Metriche sanitarie — scegli prima i dati.</a>
  <a href="/it/docs/individual-tracking/"><span>Granulare</span>Monitoraggio individuale — un output completamente diverso (file per ogni voce).</a>
  <a href="/it/docs/daily-notes/"><span>Obsidian</span>Inserimento nelle note giornaliere — usa gli stessi campi del frontmatter.</a>
  <a href="/it/docs/reference/export-formats/"><span>Contratto</span>Formati di esportazione — comportamento esatto di JSON, CSV, Markdown e Bases.</a>
</div>
