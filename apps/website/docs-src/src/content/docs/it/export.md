---
title: "Esportazione"
description: "Il pannello Esportazione è l'area di lavoro principale. Mostra se HealthKit e il vault sono connessi, consente di scegliere una destinazione e di eseguire esportazioni una tantum per l'intervallo di date selezionato."
---

<p>Il pannello Esportazione è organizzato attorno a tre semplici decisioni: verificare che tutto sia pronto, scegliere una destinazione, quindi selezionare l'intervallo di date prima di visualizzare l'anteprima o avviare l'esportazione.</p>

## Leggere gli indicatori di stato
<div class="options">
<div class="option"><strong>Indicatore Salute</strong><p>Punto verde = HealthKit autorizzato. Rosso = autorizzazione non concessa. Tocca per riprovare ad aprire la richiesta di autorizzazione di iOS (funziona solo la prima volta per ogni installazione; successivamente iOS non mostra nulla e devi modificare l'autorizzazione in Impostazioni → Privacy e sicurezza → Salute).</p></div>
<div class="option"><strong>Indicatore Vault</strong><p>Punto verde = è selezionata una cartella del vault. Tocca per selezionare nuovamente o cambiare il vault. L'etichetta mostra il nome della cartella.</p></div>
</div>
<p>L'azione <em>Esporta</em> rimane disabilitata finché HealthKit, il formato di output e la destinazione selezionata non sono pronti. In questo modo si evita l'errore più comune: tentare di esportare senza una destinazione.</p>

## Scegliere una destinazione di esportazione
<p>La scheda Destinazione esportazione stabilisce dove vengono inviati i dati:</p>

<div class="options">
<div class="option"><strong>Cartella locale su iPhone</strong><p>Scrive direttamente nella cartella o nel vault Obsidian selezionato su questo dispositivo.</p></div>
<div class="option"><strong>Mac connesso</strong><p>Invia i dati giornalieri acquisiti e un'istantanea esatta delle impostazioni all'app sul Mac nelle vicinanze. L'iPhone legge HealthKit; il Mac genera i formati selezionati e scrive i file.</p></div>
<div class="option"><strong>Endpoint API</strong><p>Invia tramite POST un involucro JSON direttamente dall'iPhone a un endpoint HTTP(S) configurato dall'utente. <a href="/it/docs/api-endpoint/">Consulta Endpoint API</a>.</p></div>
</div>

## Scegliere un intervallo di date
<p>Le opzioni predefinite coprono gli utilizzi più comuni:</p>

<div class="options">
<div class="option"><strong>Oggi</strong><p>Esporta il giorno corrente. Utile per verificare la formattazione dell'output.</p></div>
<div class="option"><strong>Ieri</strong><p>La scelta più sicura per l'esportazione giornaliera, perché la giornata è completa.</p></div>
<div class="option"><strong>Dall'inizio</strong><p>Recupera tutti i dati a partire dai primi dati HealthKit che Health.md riesce a trovare.</p></div>
<div class="option"><strong>Personalizzato</strong><p>Scegli le date di inizio e fine per un intervallo specifico.</p></div>
</div>

## Anteprima o Esporta
<div class="options">
<div class="option"><strong>Anteprima</strong><p>Mostra i file e i contenuti che verranno generati prima che venga scritto qualsiasi dato.</p></div>
<div class="option"><strong>Esporta</strong><p>Avvia l'esportazione, ne mostra l'avanzamento nella schermata principale e registra il risultato nella cronologia.</p></div>
</div>

## Che cosa avviene durante l'esportazione
<ol>
<li>Per ogni giorno dell'intervallo, acquisisce le proiezioni di riepilogo selezionate e, quando Lossless Health Records è abilitato, i relativi record sorgente canonici e la diagnostica delle query.</li>
<li>Applica il formato scelto (Markdown, Obsidian Bases, JSON o CSV) e il modello.</li>
<li>Scrive un file per ogni giorno in <code>{vault}/{subfolder}/</code>, trasferisce i file tramite il flusso di lavoro del Mac connesso oppure invia tramite POST un involucro JSON con versione al tuo endpoint API.</li>
<li>Se <em>Monitoraggio individuale</em> è attivo, ricava dall'archivio canonico i file Markdown selezionati per ciascuna voce per le destinazioni basate su file.</li>
<li>Se <em>Inserimento nelle note giornaliere</em> è attivo, integra i campi di riepilogo selezionati nelle note giornaliere.</li>
</ol>

<p>JSON e CSV possono conservare i record canonici. Markdown e Obsidian Bases rimangono leggibili e mostrano una diagnostica di acquisizione compatta anziché incorporare l'archivio. Consulta il <a href="/it/docs/reference/">riferimento completo sull'esportazione</a> per gli schemi esatti e le regole di omissione.</p>

## Barra dei pannelli

<p>I quattro pannelli nella parte inferiore dello schermo — Esportazione, Programmazione, Sincronizzazione, Impostazioni — comprendono l'intera superficie dell'app. Tutto il resto si trova uno o due livelli più in profondità nelle Impostazioni.</p>

<div class="callout">
<strong>Funzionamento dello sblocco.</strong>
<p style="margin-top:6px;">Full Access sblocca un numero illimitato di esportazioni, le esportazioni programmate, le destinazioni Mac e Comandi Rapidi. <a href="/it/docs/paywall/">Consulta la pagina Paywall</a> per maggiori dettagli.</p>
</div>

## Contenuti correlati

<div class="related">
  <a href="/it/docs/scheduling/"><span>Uso quotidiano</span>Programmazione — automatizza l'operazione per non dover più toccare Esporta.</a>
  <a href="/it/docs/api-endpoint/"><span>Integrazione</span>Endpoint API — invia i dati JSON selezionati direttamente al tuo servizio.</a>
  <a href="/it/docs/format/"><span>Personalizzazione</span>Personalizzazione del formato — modifica l'aspetto di ciascun file.</a>
  <a href="/it/docs/shortcuts/"><span>Funzioni avanzate</span>Comandi Rapidi — avvia le esportazioni tramite Siri, automazioni o altre app.</a>
  <a href="/it/docs/reference/"><span>Riferimento</span>Riferimento sull'esportazione — schemi, record canonici, diagnostica ed esempi generati.</a>
</div>
