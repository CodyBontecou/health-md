---
title: "Esportare"
description: "Esporta i dati di Apple Health subito o secondo una pianificazione. Verifica che tutto sia pronto in Archivio, scegli un intervallo in Esporta ora e imposta la destinazione di ogni automazione."
---

<p>Su iPhone, Health.md ha tre schede, <strong>Archivio</strong>, <strong>Automazioni</strong> e <strong>Impostazioni</strong>, più un pulsante rotondo <strong>Esporta ora</strong>. Su iPad le schede passano in una barra laterale.</p>

## Verifica che tutto sia pronto in Archivio
<p>Il calendario di <strong>Archivio</strong> mostra quali date di salute ha coperto ogni automazione. Quando qualcosa blocca le esportazioni, la scheda <strong>Richiede attenzione</strong> in alto lo indica:</p>
<div class="options">
<div class="option"><strong>Apple Health</strong><p>Health.md mostra lo stato di configurazione dell’app, non un accesso in lettura confermato a ogni categoria. HealthKit non rivela le autorizzazioni di lettura negate. Controlla le categorie in Apple Health. Un risultato vuoto può indicare accesso negato o assenza di dati. <a href="/it/docs/troubleshooting/">Risolvi i dati mancanti</a>.</p></div>
<div class="option"><strong>Cartella</strong><p>Scegli o riseleziona la cartella in <strong>Impostazioni → Cartella</strong>. Se iOS perde l’accesso dopo lo spostamento di una cartella, Health.md ti chiede di sceglierla di nuovo; non viene eliminato nulla.</p></div>
</div>

## Scegli dove esporta un’automazione
<p>Ogni automazione ha la propria destinazione. Apri <strong>Automazioni</strong>, scegli l’automazione e poi <strong>Output</strong>:</p>

<div class="options">
<div class="option"><strong>Cartella locale</strong><p>Scrive direttamente nella cartella o nel vault di Obsidian scelto su questo dispositivo.</p></div>
<div class="option"><strong>Mac collegato</strong><p>Invia i dati giornalieri acquisiti e un’istantanea esatta delle impostazioni all’app Mac vicina. L’iPhone legge HealthKit; il Mac genera i formati scelti e scrive i file.</p></div>
<div class="option"><strong>Endpoint API</strong><p>Invia con POST una busta JSON direttamente dall’iPhone a un endpoint HTTP(S) che configuri. <a href="/it/docs/api-endpoint/">Vedi Endpoint API</a>.</p></div>
<div class="option"><strong>Gateway Agent Data</strong><p>Carica ogni file esportato, senza modifiche, sull’endpoint di ingestione del tuo gateway.</p></div>
</div>

## Scegli un intervallo in Esporta ora
<p>Tocca <strong>Esporta ora</strong>, scegli l’automazione se ne hai più di una e poi un intervallo:</p>

<div class="options">
<div class="option"><strong>Ieri</strong><p>La scelta più sicura per le esportazioni giornaliere, perché il giorno è concluso.</p></div>
<div class="option"><strong>7 giorni / 30 giorni</strong><p>L’ultima settimana o l’ultimo mese, fino a ieri. Da 30 giorni in su, Health.md chiede prima una conferma.</p></div>
<div class="option"><strong>Personalizzato</strong><p>Scegli data di inizio e di fine per un intervallo preciso.</p></div>
</div>
<p><strong>Verrà scritto</strong> mostra la destinazione e, in modo approssimativo, quanti file e giorni copre l’esportazione. <strong>Solo riepilogo dell'intervallo</strong> scrive un unico file di riepilogo invece dei file giornalieri. Oggi e Tutto lo storico restano disponibili in <strong>Automazioni → Tutte le impostazioni di esportazione</strong>.</p>

## Anteprima o esportazione
<div class="options">
<div class="option"><strong>Anteprima</strong><p>Mostra i file e i contenuti che verranno generati prima di scrivere qualsiasi cosa.</p></div>
<div class="option"><strong>Esporta</strong><p>Avvia l’esportazione, mostra l’avanzamento sopra la barra delle schede con un pulsante Annulla e registra l’esito nello storico e nel calendario di Archivio.</p></div>
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

Un profilo salvato blocca impostazioni e destinazione per l’esecuzione. Le righe dello storico delle esportazioni pianificate e delle automazioni che conoscono il profilo conservano il profilo usato, mentre lo storico mantiene un’etichetta rispettosa della privacy per la destinazione effettivamente utilizzata. Una riga di esportazione manuale può omettere il nome del profilo. Ridenominazioni e cambi di destinazione successivi non riscrivono lo storico esistente. Se un profilo a cui si fa riferimento manca, l’operazione non riesce senza usare altre impostazioni. Vedi [Profili di esportazione](/it/docs/export-profiles/).

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
