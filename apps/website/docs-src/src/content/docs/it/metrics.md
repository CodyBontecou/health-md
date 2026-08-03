---
title: "Metriche sanitarie"
description: "Scegli dal catalogo attuale delle metriche di Apple Health di Health.md. Cerca, attiva o disattiva intere categorie oppure consulta i dettagli per controllare ogni singola metrica."
---

<div class="callout">
<strong>Nota su Android.</strong>
<p style="margin-top:6px;">Questa pagina documenta il selettore delle metriche di Apple Health e il riferimento generato per i dati HealthKit. L'app Android offre 106 metriche di Health Connect; consulta la <a href="/it/docs/android/">guida per Android</a> per la configurazione di Health Connect e il comportamento specifico della piattaforma.</p>
</div>

## Struttura
<div class="options">
<div class="option"><strong>Intestazione dei conteggi</strong><p>Visualizzazione in tempo reale delle metriche e delle categorie abilitate. Tocca e tieni premuto per copiare negli appunti lo stato esatto della selezione.</p></div>
<div class="option"><strong>Tutte le metriche abilitate</strong><p>Interruttore principale che attiva o disattiva tutte le categorie. È utile come punto di partenza: attiva tutto, quindi disabilita ciò che non ti interessa.</p></div>
<div class="option"><strong>Cerca</strong><p>Filtro in tempo reale per nomi e identificatori delle metriche. Prova "heart", "sleep", "vo2".</p></div>
</div>

## Categorie
<p>Il selettore raggruppa i riepiloghi ordinari e le definizioni dei record di origine in categorie quali Sonno, Attività, Cuore, Apparato respiratorio, Parametri vitali, Misure corporee, Mobilità, Ciclismo, Alimentazione, Mindfulness, Salute riproduttiva, Sintomi, Farmaci, record specializzati e Allenamenti. Ogni riga mostra lo stato di attivazione e il conteggio in tempo reale delle definizioni abilitate al suo interno. Il <a href="/it/docs/reference/generated/core/metric-catalog/">catalogo delle metriche</a> generato in produzione costituisce l'inventario corrente di riferimento.</p>

<p>Tocca una categoria per consultarne le metriche. Ogni metrica dispone di un proprio interruttore e identificatore HealthKit. Il colore del punto indica se HealthKit dispone attualmente di dati per quella metrica sul dispositivo.</p>

## Ambito della selezione
<p>La selezione delle metriche determina <em>ogni cosa</em>:</p>
<ul>
<li>Esportazioni giornaliere: nel file vengono incluse solo le metriche abilitate</li>
<li>Monitoraggio individuale: solo per le metriche abilitate vengono creati file separati per ogni voce</li>
<li>Inserimento nelle note giornaliere: solo le metriche abilitate vengono integrate nel frontmatter</li>
<li>Comandi rapidi: le esportazioni per intervallo di date utilizzano la stessa selezione</li>
</ul>

<div class="callout">
<strong>Suggerimento.</strong>
<p style="margin-top:6px;">Inizia con poche metriche. Abilita Sonno, Attività e Cuore. Esegui un'esportazione. Controlla l'aspetto del file. Quindi aggiungi altre categorie. Aggiungerle in seguito è più rapido che districarsi in un file di 50 righe pieno di metriche che non ti interessano.</p>
</div>

## Contenuti correlati

<div class="related">
  <a href="/it/docs/reference/"><span>Riferimento</span>Riferimento per l'esportazione: tutte le metriche Apple, le chiavi, le unità, le definizioni dei record di origine e la struttura delle esportazioni.</a>
  <a href="/it/docs/android/"><span>Android</span>App Android: configurazione di Health Connect, metriche, destinazioni e automazione.</a>
  <a href="/it/docs/format/"><span>Procedura</span>Formato: modifica il modo in cui vengono scritte le metriche selezionate.</a>
  <a href="/it/docs/individual-tracking/"><span>Dettagliato</span>Monitoraggio individuale: crea anche un file per ogni voce con indicazione temporale.</a>
  <a href="/it/docs/daily-notes/"><span>Obsidian</span>Inserimento nelle note giornaliere: aggiungi queste metriche alle tue note giornaliere.</a>
</div>
