---
title: "Monitoraggio delle singole voci"
description: "Crea facoltativamente un file per ogni voce con data e ora: ogni allenamento, misurazione della pressione sanguigna e registrazione dell’umore avrà il proprio file Markdown, con data e ora incluse nel nome."
---

## Quando utilizzarlo
<p>Le esportazioni giornaliere generano un file al giorno con i relativi riepiloghi. Il <em>monitoraggio delle singole voci</em> è pensato per i casi in cui vuoi <em>citare un singolo evento</em>, ad esempio collegare uno specifico allenamento da una nota del diario oppure aggiungere a una revisione settimanale un backlink a una registrazione dell’umore.</p>

<p>Questa funzionalità si aggiunge all’esportazione giornaliera, non la sostituisce. Se entrambe sono attive, otterrai entrambi i tipi di file.</p>

## Configurazione in due passaggi
<p>L’interfaccia delle impostazioni segue volutamente un processo in due passaggi:</p>
<ol>
<li><strong>Interruttore principale.</strong> Attiva la funzionalità a livello globale.</li>
<li><strong>Selezione per metrica.</strong> Scegli <em>quali</em> metriche devono generare file individuali. La maggior parte delle persone non vuole un file per ogni rilevazione della frequenza cardiaca (10.000 al giorno), ma ne desidera uno per ogni allenamento (~1 al giorno).</li>
</ol>

## Azioni rapide
<div class="options">
<div class="option"><strong>Abilita metriche suggerite</strong><p>Impostazioni predefinite ragionevoli: umore, sintomi, allenamenti, pressione sanguigna e glicemia. Sono le metriche per cui un file per ogni voce è davvero utile.</p></div>
<div class="option"><strong>Abilita tutte le metriche</strong><p>Tutte le metriche. Fai attenzione: questa opzione può generare migliaia di file al giorno.</p></div>
<div class="option"><strong>Disabilita tutte le metriche</strong><p>Deseleziona tutte le metriche senza disattivare l’interruttore principale.</p></div>
</div>

## Struttura delle cartelle
<div class="options">
<div class="option"><strong>Cartella delle voci</strong><p>Percorso relativo al vault in cui vengono salvati i singoli file. Valore predefinito: <code>entries</code>.</p></div>
<div class="option"><strong>Organizza per categoria</strong><p>Se l’opzione è attiva, le voci vengono inserite in sottocartelle suddivise per categoria (<code>entries/workouts/</code>, <code>entries/symptoms/</code>). Se è disattivata, tutte le voci vengono salvate in un’unica cartella senza sottocartelle.</p></div>
</div>

## Modello del nome file
<p>Valore predefinito: <code>{date}_{time}_{metric}</code>. Segnaposto disponibili: <code>{date}</code>, <code>{time}</code>, <code>{metric}</code>, <code>{category}</code>. Esempio di output:</p>

<div class="doc-diagram folder-tree" aria-label="Esempio di struttura dei file delle singole voci">
<span>{vault}/entries/</span>
<span>├─ workouts/2026_07_14_0920_workouts_workouts_71000000-0000-0000-0000-000000000008.md</span>
<span>├─ symptoms/2026_07_14_0916_symptom_headache_symptom_headache_71000000-0000-0000-0000-000000000002.md</span>
<span>└─ vitals/2026_07_14_0918_blood_pressure_blood_pressure_71000000-0000-0000-0000-000000000004.md</span>
</div>

<p>Le voci canoniche supportate da una fonte aggiungono al nome file configurato la metrica selezionata e l’UUID HealthKit in minuscolo. In questo modo, lo stesso record della fonte rimane stabile tra esecuzioni successive e si evitano collisioni tra voci registrate nello stesso minuto. Le voci di compatibilità prive di UUID mantengono il precedente comportamento con nomi file più brevi.</p>

<div class="callout">
<strong>Attenzione.</strong>
<p style="margin-top:6px;">Qui vengono mostrate soltanto le categorie per cui hai abilitato almeno una metrica in <em>Metriche sanitarie</em>. Prima abilita una metrica in quella sezione, quindi torna qui per scegliere se attivare il monitoraggio per singola voce. Prima di creare automazioni basate sui percorsi, consulta il <a href="/it/docs/reference/individual-entry-tracking/">contratto di identità dei record della fonte</a> e la <a href="/it/docs/reference/generated/individual/filename-path-matrix/">matrice generata dei nomi file e dei percorsi</a>.</p>
</div>

## Contenuti correlati

<div class="related">
  <a href="/it/docs/metrics/"><span>Prerequisito</span>Metriche sanitarie — abilita prima le metriche.</a>
  <a href="/it/docs/format/"><span>Output</span>Formato — si applica anche ai file delle singole voci.</a>
  <a href="/it/docs/daily-notes/"><span>Alternativa</span>Inserimento nelle note giornaliere — un modo diverso per allegare le metriche alle note.</a>
  <a href="/it/docs/reference/individual-entry-tracking/"><span>Contratto</span>Riferimento per le singole voci — identità UUID, frontmatter, voci specializzate e fallback di compatibilità.</a>
</div>
