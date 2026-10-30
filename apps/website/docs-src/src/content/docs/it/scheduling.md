---
title: "Pianifica le esportazioni Apple Health e risolvi i problemi relativi alle esecuzioni perse"
description: "Verifica un'esportazione pianificata, comprendi la ricerca dei giorni completati e recupera le date in sospeso. iPhone il timing in background è il massimo sforzo; cronologia Riprova utilizza le impostazioni correnti."
---

Questa pagina descrive la pianificazione di iPhone . Android prevede autorizzazioni in background e requisiti di acquisto diversi; vedere [Automazione Android](/it/docs/android/).

## Verifica la prima esportazione pianificata

1. Attiva il profilo desiderato. Controlla le sue metriche, i formati, i dettagli dei dati, il comportamento di scrittura e la destinazione. Esegui manualmente una giornata completata e controlla il file salvato o il risultato dell'endpoint prima di abilitare l'automazione.
2. Apri pianificazione, quindi Imposta pianificazione o Gestisci pianificazione. Abilita la pianificazione, scegli Giornaliera, Settimanale o Personalizzata, imposta l'ora e inizia con una ricerca di un giorno completato. Consenti notifiche se desideri promemoria di ripristino locale.
3. Controlla se la pianificazione è abilitata, l'occorrenza successiva e l'ultimo risultato. Dopo un tentativo, controlla i dettagli della cronologia e la destinazione effettiva; un'etichetta o una notifica di esecuzione successiva non costituisce una prova che i dati siano stati scritti.
4. Controlla le date, le unità, la copertura e i dati mancanti esportati. Un file salvato non dimostra di per sé la completa acquisizione della fonte.

Nella versione del telefono abilitata all'abbonamento, le esportazioni pianificate e manuali richiedono una prova attiva, un abbonamento, un acquisto a vita o un accesso permanente conservato. Non è prevista alcuna franchigia di esportazione locale. L'accesso scaduto deve essere ripristinato prima che il lavoro in sospeso possa riprendere. Vedi [sblocco e pagamento](/it/docs/paywall/).

## Comprendere la finestra dei giorni completati

Le pianificazioni giornaliere, settimanali e personalizzate possono avere una visione retrospettiva. La cadenza personalizzata si ripete ogni N giorni, settimane o mesi dalla data di inizio. Ogni nuova occorrenza riesporta l'intera finestra di giorni completati configurata, comprese le date esportate in precedenza. Una ricerca di tre giorni copre ieri e i due giorni precedenti; l'esecuzione ritardata mantiene la finestra ancorata al giorno dell'incendio previsto.

Oggi l'aggiornamento è un lavoro giornaliero separato e non sostituisce la finestra del giorno completato. Ispeziona i percorsi e scrivi il comportamento prima di sovrapporre le esportazioni; non aggiungere insieme istantanee giornaliere ripetute come nuove misurazioni.

## Scegli il percorso di ripristino corretto

- **Recupero pianificato in sospeso:** sblocca iPhone , apri Health.md e controlla il tentativo in sospeso. Conserva le date esatte non risolte, le impostazioni salvate e la destinazione. Le date completate rimangono completate; la ripresa non si espande in una nuova prospettiva.
- **Riprova dalla cronologia:** avvia una nuova esecuzione per quell'intervallo utilizzando le impostazioni e la destinazione attualmente configurate e registra una nuova riga della cronologia. Controllare la configurazione attiva prima di premere Riprova. Non è la stessa cosa che riprendere un tentativo sospeso congelato.
- **Destinazione modificata o non disponibile:** ripristina l'accesso o controlla il profilo in sospeso prima di riprovare. Un vecchio ripristino dell'API iPhone non deve adottare automaticamente un endpoint o una credenziale modificata. Non avviare ripetutamente nuovi tentativi mentre il tentativo originale non è stato risolto.

Esamina il recupero in sospeso, l'identità del profilo e le regole di destinazione in [Esporta profili](/it/docs/export-profiles/).

## Cosa garantisce e cosa non garantisce iOS

L'orario selezionato è un obiettivo, non un orario di completamento garantito. iOS controlla il runtime in background e la protezione dei dispositivi bloccati può impedire le letture HealthKit . Le richieste in background e le notifiche di riattivazione silenziosa non ignorano tale protezione.

Le notifiche di ripristino locale richiedono l'autorizzazione alla notifica e non garantiscono la consegna all'ora prevista. Se ne ricevi uno, sblocca il dispositivo e aprilo per consentire Health.md di tentare il ripristino. Se non arriva alcuna notifica, apri Health.md e controlla il lavoro e la cronologia in sospeso. Verificare il risultato anziché dare per scontato che un avviso o il tempo trascorso significhino successo.

## Controllo programmatico
 <p> È possibile attivare/disattivare la pianificazione da Shortcuts utilizzando l'intento <em> Attiva o disattiva l'esportazione pianificata </em> . <a href="/it/docs/shortcuts/"> Vedi Shortcuts </a> per esempi. </p>

## Orari e cancellazione del profilo

- Ogni profilo può mantenere il proprio programma, inclusa una cadenza personalizzata. Il cambio del profilo attivo non modifica il targeting della pianificazione di un altro profilo.
- Viene visualizzato un avviso di collisione quando i profili potrebbero scrivere gli stessi percorsi renderizzati nella stessa destinazione. Esaminalo prima di abilitare pianificazioni concorrenti. Health.md non modifica silenziosamente nessuno dei due profili.
- Interrompi o Annulla termina solo il tentativo corrente. Le date completate rimangono tali, le date non risolte rimangono ritentabili e la pianificazione rimane abilitata.
- Ogni riga della cronologia rimane fissata al profilo di runtime e all'etichetta di destinazione protetta dalla privacy effettivamente utilizzata.

Gestisci le impostazioni bloccate e la destinazione per profilo in [Esporta profili](/it/docs/export-profiles/).

## Imparentato

<div class="related">
 <a href="/it/docs/export-profiles/"> <span> Flussi di lavoro multipli </span> Esporta profili, assegna a ciascuna configurazione salvata la propria destinazione e cadenza. </a>
 <a href="/it/docs/export/"> <span> Manuale </span> Esportazione, per intervalli di date una tantum. </a>
 <a href="/it/docs/shortcuts/"> <span> Automatizza </span> Shortcuts , attiva/disattiva la pianificazione dalle automazioni. </a>
 <a href="/it/docs/sync/"> <span> Cross-device </span> Mac Sync, pianifica anche su Mac. </a>
 </div>
