---
title: "Profili di esportazione"
description: "Salva insieme le impostazioni di esportazione e una destinazione, quindi esegui o pianifica la configurazione da iPhone, Android, Comandi rapidi, CLI, Tasker o adb."
---

I profili di esportazione riuniscono una configurazione ripetibile. Gestiscili in Health.md su iPhone o Android. Sulle piattaforme Apple, l’attuale flusso di gestione è documentato e testato solo su iPhone; non viene dichiarata un’interfaccia di gestione su iPad o Mac.

## Gestire e modificare i profili

Apri **Impostazioni → Profili di esportazione**. L’elenco indica il profilo attivo e consente di creare, rinominare, duplicare, eliminare, attivare o esaminare i profili. Apri i dettagli di un profilo per copiarne l’ID stabile. L’ultimo profilo non può essere eliminato.

La scheda Esporta modifica il profilo attivo. Attivane un altro prima di cambiare le impostazioni se non vuoi aggiornare quello corrente.

Ogni profilo congela le opzioni necessarie per ripetere un’esecuzione:

- metriche selezionate, dettaglio dei dati, formati, modelli, nomi dei file, unità e comportamento di scrittura;
- la propria cartella di destinazione e sottocartella, un endpoint API o un Mac connesso quando supportato dalla piattaforma;
- note giornaliere, voci individuali, riepiloghi e altre opzioni di output supportate dalla piattaforma.

La pianificazione è legata separatamente all’identità stabile del profilo. Cambiare il profilo attivo non reindirizza quella pianificazione. Un’esecuzione usa l’istantanea salvata invece di prendere le impostazioni modificate da un altro profilo.

## Eseguire e pianificare in sicurezza

- Ogni profilo può avere una pianificazione ricorrente, compresa la cadenza personalizzata offerta dall’app.
- Restano validi i diritti della piattaforma: la quota gratuita Apple può includere azioni pianificate, mentre la pianificazione Android richiede l’acquisto a vita.
- Health.md avvisa quando più profili potrebbero scrivere gli stessi percorsi generati nella stessa destinazione. L’avviso non modifica silenziosamente né i profili né le pianificazioni.
- Interrompere o annullare riguarda solo il tentativo corrente. Le date completate restano tali, quelle irrisolte possono essere riprovate e la pianificazione rimane attiva.
- Se il profilo indicato manca, Health.md si arresta in modo sicuro. Non ripiega mai sul profilo attivo o su un’altra destinazione.

## Nomi, ID stabili e automazione

Il nome visualizzato è pensato per le persone e può cambiare. L’ID stabile consente automazioni resistenti alle rinomine. Copialo in **Impostazioni → Profili di esportazione → ID profilo**.

- I Comandi rapidi Apple selezionano un profilo tramite il nome visualizzato; un parametro profilo vuoto usa quello attivo.
- Le trasmissioni Tasker e adb su Android possono fornire l’extra `PROFILE` con un ID stabile o un nome. Preferisci l’ID per i flussi che devono resistere alle rinomine.
- La CLI diretta accetta `--profile PROFILE_ID` per le attività supportate con file generati. Il profilo fornisce le impostazioni di output congelate; il parametro `--destination` obbligatorio continua a selezionare la cartella esistente sul computer.

Consulta la guida di automazione della piattaforma prima di attivare un flusso non presidiato.

## Cronologia, ripristino e privacy

Le righe della cronologia relative a esecuzioni pianificate e automatizzate associate a un profilo registrano il profilo usato. La cronologia conserva inoltre un’etichetta rispettosa della privacy per la destinazione effettiva. Un’esecuzione manuale dal pannello Esportazione potrebbe non allegare il nome del profilo, pur usando le impostazioni del profilo attivo. Rinominare un profilo, cambiarne la destinazione o selezionarne un altro non riscrive la cronologia esistente.

Un nuovo tentativo avviato dalla cronologia delle esportazioni usa le impostazioni e la destinazione configurate al momento, quindi crea una nuova riga con ciò che ha realmente utilizzato. Non attribuisce il tentativo al profilo originale. Il recupero o la ripresa di un tentativo pianificato irrisolto conserva invece date, impostazioni e destinazione esatte di quel tentativo.

Profili e pianificazioni sono impostazioni locali del dispositivo. Non si sincronizzano tra iPhone, iPad, Mac e Android. Ricrea la configurazione prevista su ogni dispositivo e verifica la destinazione prima di attivare l’automazione.

## Correlati

<div class="related">
  <a href="/it/docs/export/"><span>Esportazione</span>Scegli il dettaglio, visualizza l’anteprima ed esporta un intervallo di date.</a>
  <a href="/it/docs/scheduling/"><span>Pianificazione</span>Comprendi cadenze, ripristino e limiti temporali della piattaforma.</a>
  <a href="/it/docs/shortcuts/"><span>Comandi rapidi</span>Seleziona un profilo salvato nelle automazioni Apple.</a>
  <a href="/it/docs/android/"><span>Automazione Android</span>Usa azioni Tasker e adb compatibili con i profili.</a>
  <a href="/it/docs/cli-direct/"><span>CLI diretta</span>Esegui le impostazioni salvate del profilo in una cartella esplicita del computer.</a>
</div>
