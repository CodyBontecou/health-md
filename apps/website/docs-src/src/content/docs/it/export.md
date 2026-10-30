---
title: "Esportare"
description: "Utilizza la scheda Esporta per verificare le connessioni HealthKit e Vault. Seleziona una destinazione ed esporta un intervallo di date."
---

<p> La scheda Esporta è organizzata in tre piccole decisioni: conferma la disponibilità, scegli una destinazione, quindi scegli l'intervallo di date prima di visualizzare l'anteprima o esportare. </p>

## Leggi i badge di stato
 <div class="options">
 <div class="option"> <strong> Badge sanitario </strong> <p>Il verde indica lo stato di configurazione Connesso dell’app, non conferma l’accesso in lettura a ogni categoria. HealthKit non rivela i permessi di lettura negati. Tocca l’indicatore per richiedere l’accesso. iOS può mostrare una finestra per i tipi che richiedono una decisione; se le scelte sono già registrate, Health.md mostra la guida ai permessi. Controlla le categorie in Apple Health. Un risultato vuoto può indicare accesso negato o assenza di dati corrispondenti. <a href="/it/docs/troubleshooting/">Risolvere i dati mancanti</a>.</p> </div>
 <div class="option"> <strong> Badge del deposito </strong> <p> Punto verde = è selezionata una cartella del deposito. Tocca per selezionare nuovamente o modificare il deposito. L'etichetta mostra il nome della cartella. </p> </div>
 </div>
 <p> L'azione <em> Esporta </em> rimane disabilitata finché HealthKit , il formato di output e la destinazione selezionata non sono pronti. Ciò impedisce la modalità di errore più comune: tentare di esportare senza destinazione. </p>

## Scegli una destinazione di esportazione
 <p> La scheda Destinazione di esportazione decide dove vanno i dati: </p>

<div class="options">
 <div class="option"> <strong> Locale iPhone Cartella </strong> <p> Scrive direttamente nella cartella o nel deposito Obsidian selezionato su questo dispositivo. </p> </div>
 <div class="option"> <strong> Mac connesso </strong> <p> Invia i dati giornalieri acquisiti e un'istantanea delle impostazioni esatte all'app Mac vicina. Il iPhone legge HealthKit . Il Mac esegue il rendering dei formati selezionati e scrive i file. </p> </div>
 <div class="option"> <strong> Endpoint API </strong> <p> Effettua il POST di una busta JSON direttamente da iPhone a un endpoint HTTP(S) configurato dall'utente. <a href="/it/docs/api-endpoint/"> Vedi endpoint API </a> . </p> </div>
 </div>

## Scegli un intervallo di date
 <p> Le preimpostazioni della data coprono i percorsi comuni: </p>

<div class="options">
 <div class="option"> <strong> Oggi </strong> <p> Esporta il giorno corrente. Utile per testare la formattazione dell'output. </p> </div>
 <div class="option"> <strong> Ieri </strong> <p> La scelta più sicura per l'esportazione giornaliera perché la giornata è completa. </p> </div>
 <div class="option"> <strong> Tutto il tempo </strong> <p> Backfill dai primi dati HealthKit Health.md riesce a trovare. </p> </div>
 <div class="option"> <strong> Personalizzato </strong> <p> Scegli le date di inizio e fine per un intervallo specifico. </p> </div>
 </div>

## Anteprima o esportazione
 <div class="options">
 <div class="option"> <strong> Anteprima </strong> <p> Mostra i file e i contenuti che verranno generati prima che venga scritto qualsiasi cosa. </p> </div>
 <div class="option"> <strong> Esporta </strong> <p> Esegue l'esportazione, mostra l'avanzamento nella schermata principale e registra il risultato nella cronologia. </p> </div>
 </div>

## Scegli il livello di dettaglio dei dati

<div class="options">
 <div class="option"> <strong> Riepilogo </strong> <p> Totali giornalieri compatti e roll-up per letture, appunti e dashboard. </p> </div>
 <div class="option"> <strong> Serie temporali dettagliate </strong> <p> Campioni e intervalli con timestamp selezionati. Questo livello è disponibile sia su Apple che su Android quando la metrica scelta espone dettagli adeguati. </p> </div>
 <div class="option"> <strong> Lossless Health Records </strong> <p> L'archivio canonico dei record di origine HealthKit . Questo livello è solo per Apple. Android non trasforma i record Health Connect in un archivio HealthKit . </p> </div>
 </div>

## Cosa comporta effettivamente l'"esportazione"
 <ol>
 <li> Per ogni giorno nell'intervallo, acquisisci le proiezioni riepilogative selezionate. Aggiungi campioni compatibili per serie temporali dettagliate. Inoltre, per i record sanitari senza perdite, aggiungi record di origine canonici ed esegui la diagnostica delle query. </li>
 <li> Applica il formato scelto ( Markdown , Bases, JSON o CSV) e il modello. </li>
 <li> Scrivi un file al giorno in <code>{vault}/{subfolder}/</code> , trasferisci file tramite il flusso di lavoro del Mac connesso o PUBBLICA una busta JSON con versione sul tuo endpoint API. </li>
 <li> Se <em> Monitoraggio individuale </em> è attivo, deriva i file Markdown selezionati per voce dall'archivio canonico per target basati su file. </li>
 <li> Se <em> Inserimento note giornaliere </em> è attivo, unisci i campi di riepilogo selezionati nelle note giornaliere. </li>
 </ol>

<p> JSON e CSV possono conservare i record canonici. Markdown e Bases rimangono leggibili ed espongono una diagnostica di acquisizione compatta anziché incorporare l'archivio. Consulta il riferimento completo all'esportazione <a href="/it/docs/reference/"> </a> per gli schemi esatti e le regole di omissione. </p>

## Interrompi, annulla e riprova

L'interruzione o l'annullamento termina solo il tentativo corrente. I file e le date già completati rimangono tali, mentre le date non risolte rimangono disponibili per riprovare. L'annullamento di un tentativo pianificato non ne disabilita la pianificazione ricorrente.

## Profili e storia affidabile

Un profilo salvato blocca le impostazioni e la destinazione della corsa. Le righe della cronologia pianificata e di automazione sensibile al profilo mantengono il profilo di runtime, mentre la cronologia conserva un'etichetta sicura per la privacy per la destinazione effettivamente utilizzata. Una riga manuale della scheda Esporta può omettere il nome del profilo. Le successive ridenominazioni e modifiche della destinazione non riscrivono la cronologia esistente. I riferimenti al profilo mancanti non riescono a chiudersi invece di eseguire il fallback. Vedere [Esporta profili](/it/docs/export-profiles/).

## Barra delle schede

<p> Le quattro schede nella parte inferiore dello schermo, Esporta, Pianificazione, Sincronizzazione, Impostazioni, coprono l'intera superficie dell'app. Tutto il resto vive uno o due strati in profondità nelle Impostazioni. </p>

<div class="callout">
 <strong> Comportamento di sblocco. </strong>
 <p style="margin-top:6px;"> Le versioni del telefono iPhone / iPad e Google Play abilitate all'abbonamento richiedono una prova attiva, un abbonamento, un abbonamento a vita o un accesso permanente conservato per le esportazioni e la pianificazione. Non rimane alcuna indennità locale di libera esportazione. Il compagno Mac e la build con accesso incluso F-Droid mantengono le eccezioni documentate. <a href="/it/docs/paywall/"> Consulta la pagina Paywall </a> per i dettagli sull'acquisto Apple. </p>
 </div>

## Imparentato

<div class="related">
 <a href="/it/docs/export-profiles/"> <span> Configurazioni ripetibili </span> Esporta profili, salva impostazioni indipendenti, destinazioni, pianificazioni e ID di automazione stabili. </a>
 <a href="/it/docs/scheduling/"> <span> Uso quotidiano </span> Pianificazione, automatizza questa operazione in modo da non toccare mai più Esporta. </a>
 <a href="/it/docs/api-endpoint/"> <span> Integra </span> Endpoint API, invia JSON selezionato direttamente al tuo servizio. </a>
 <a href="/it/docs/format/"> <span> Personalizza </span> Personalizzazione del formato, cambia l'aspetto di ciascun file. </a>
 <a href="/it/docs/shortcuts/"> <span> Alimenta </span> Shortcuts , attiva esportazioni da Siri , automazioni o altre app. </a>
 <a href="/it/docs/reference/"> <span> Riferimento </span> Esporta riferimento, schemi, record canonici, diagnostica ed esempi generati. </a>
 </div>
