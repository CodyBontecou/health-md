---
title: "Applicazione Android"
description: "Configura Health.md per Android. Esporta i dati Health Connect , seleziona le cartelle Storage Access Framework, pianifica le esportazioni e automatizza con Tasker o adb."
---

<div class="docs-hero">
 <p class="docs-eyebrow"> Health Connect nei file privati </p>
 <p> Health.md per Android legge Health Connect sul dispositivo e scrive Markdown , Obsidian Bases, JSON o CSV nelle cartelle scelte. Questo flusso di lavoro di esportazione della cartella non richiede alcun account Health.md . Le opzioni di accesso Google Play e l'accesso incluso F-Droid sono descritte di seguito. </p>
 <div class="docs-actions">
 <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener"> Accedi a Google Play </a>
 <a class="docs-button-secondary" href="#distribution-status"> F-Droid stato pubblicazione </a>
 <a class="docs-button-secondary" href="/it/docs/export/"> Leggi Esporta Documenti </a>
 </div>
 <p id="distribution-status"> F-Droid la pubblicazione del catalogo è in sospeso. Ottieni la versione corrente di Android su Google Play . </p>
 </div>

<div class="reference-stats">
 <div> <strong> 106 </strong> <span> selezionabile Health Connect metriche </span> </div>
 <div> <strong> 4 </strong> <span> formati di esportazione </span> </div>
 <div> <strong> 2 </strong> <span> Canali di distribuzione Android </span> </div>
 <div> <strong> 0 </strong> <span> Health.md account cloud richiesti </span> </div>
 </div>

## Cosa fa l'app Android

Health.md per Android trasforma Health Connect in un diario sanitario locale. Scegli le metriche di cui hai bisogno e visualizza l'anteprima dell'output. Quindi esporta i file in una cartella locale, Obsidian vault, cartella del provider sincronizzato o provider di documenti Android scrivibili.

<div class="options">
 <div class="option"> <strong> Health Connect source </strong> <p> Legge attività, sonno, cuore, parametri vitali, misurazioni corporee, alimentazione, allenamenti e altre categorie tramite le API Health Connect integrate nel dispositivo Android. </p> </div>
 <div class="option"> <strong> Obsidian -output nativo </strong> <p> Scrive note giornaliere, YAML/frontmatter, Obsidian Note base-friendly, voci individuali e JSON compatibili con Health.md Obsidian plugin. </p> </div>
 <div class="option"> <strong> Spazio di archiviazione nativo di Android </strong> <p> Utilizza Storage Access Framework in modo da poter scegliere le cartelle esposte dall'archivio locale, Obsidian , Google Drive, OneDrive, Syncthing o un altro provider. </p> </div>
 </div>

## Requisiti

- Android 9/API 28 o versione successiva.
- Un dispositivo o emulatore compatibile con Health Connect .
- Health Connect dati da app, dispositivi indossabili o servizi Android che scrivono su Health Connect .
- Una cartella o un provider di documenti che consente l'accesso in scrittura per le esportazioni.

## Prima esportazione

1. Installa la versione corrente Health.md da Google Play .
2. Apri ** Health Connect ** configura e concedi solo le categorie che desideri che Health.md esporti.
3. Scegli la destinazione di esportazione tramite il selettore di cartelle di Android.
4. Scegli i formati: Markdown , Obsidian Bases, JSON, CSV o qualsiasi combinazione.
5. Seleziona le metriche e l'intervallo di date.
6. Anteprima dell'output.
7. Tocca Esporta e verifica i file generati nella cartella o nel deposito.

La versione del telefono Google Play abilitata all'abbonamento richiede una prova attiva, un abbonamento, un accesso a vita o un accesso permanente conservato per le esportazioni manuali. Gli abbonamenti idonei includono una prova di 7 giorni; La vita non ha prova. La build F-Droid include accesso illimitato senza flusso di acquisto o ripristino.

## Destinazioni su Android

Android non utilizza la destinazione di rete locale iPhone → Mac. Si basa invece sullo Storage Access Framework di Android.

| Destinazione | Stato dell'Android |
| --- | --- |
| Cartella del dispositivo locale | Supportato tramite il selettore di cartelle |
| Obsidian caveau | Supportato quando la cartella del vault è esposta al selettore di Android |
| Google Drive, OneDrive, Syncthing, Obsidian Sync e fornitori simili | Supportato quando il provider espone cartelle scrivibili |
| iPhone /Destinazione rete locale Mac | Specifico per la piattaforma Apple; non utilizzato da Android |

Se un provider non espone cartelle scrivibili tramite il selettore di Android, Health.md non può scrivervi direttamente in modo sicuro. Scegli una cartella del provider che garantisca accesso in scrittura persistente o esporti localmente e sincronizzati con il tuo strumento preferito.

## Formati

L'app Android condivide gli stessi obiettivi di file semplici dell'app Apple:

| Formato | Usalo per |
| --- | --- |
| Markdown | Riepiloghi, modelli e note sulla salute quotidiana leggibili |
| Obsidian Bases | Note in primo piano che possono essere interrogate nelle visualizzazioni del database Obsidian |
| JSON | Payload giornalieri strutturati per script, dashboard, notebook e il plugin Health.md Obsidian |
| CSV | Foglio di calcolo e flussi di lavoro di analisi |

Le esportazioni JSON Android sono progettate per essere compatibili con le visualizzazioni Obsidian di Health.md . Le esportazioni di Markdown e Bases utilizzano lo stesso flusso di lavoro incentrato sul frontmatter documentato nella [guida al formato](/it/docs/format/).

## Pianificazione e automazione

Nella versione del telefono Google Play abilitata all'abbonamento, le esportazioni pianificate richiedono una prova attiva, un abbonamento, un accesso a vita o un accesso permanente conservato; sono inclusi nella build F-Droid . Utilizzano un allarme esatto one-shot quando concedi l'accesso ad Allarmi e promemoria di Android, con WorkManager duraturo che funziona come backup. Senza l'accesso esatto all'allarme, WorkManager diventa lo scheduler principale, quindi l'orario selezionato è un obiettivo piuttosto che una garanzia concreta. Health.md registra la cronologia delle esportazioni, può recuperare le date pianificate perse e ti consente di riprovare le esecuzioni non riuscite.

Per Tasker, adb o altri strumenti di automazione, Health.md espone intenti di trasmissione solo espliciti. I chiamanti esterni devono rivolgersi direttamente al componente ricevente:

```text
com.healthmd.android/com.healthmd.automation.AutomationReceiver
```

Esempi:

```bash
adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_YESTERDAY

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_LAST_DAYS \
  --ei com.healthmd.android.extra.DAYS 7

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_RANGE \
  --es com.healthmd.android.extra.START_DATE 2026-03-01 \
  --es com.healthmd.android.extra.END_DATE 2026-03-07
```

L'automazione utilizza il profilo attivo per impostazione predefinita, inclusa la destinazione bloccata, i formati, le metriche, la contabilità e la cronologia. Un `PROFILE` extra fornito può selezionare un ID o un nome di profilo stabile. Un riferimento sconosciuto non riesce a chiudersi invece di utilizzare le impostazioni correnti. Anche le corse pianificate rimangono legate al loro profilo. Vedere [Esporta profili](/it/docs/export-profiles/).

### Preparazione dello sfondo e cancellazione programmata

- Consenti letture in background Health Connect per esportazioni automatiche. Altrimenti apri Health.md per completare la lettura dei dati sanitari.
- Mantieni abilitate le notifiche in modo che Android possa mostrare il lavoro attivo, lo stato del servizio in primo piano, i risultati e le azioni di ripristino.
- Concedi allarmi e promemoria solo quando desideri una pianificazione esatta degli allarmi. Senza di esso, il lavoro durevole WorkManager rimane disponibile ma il tempo scelto è approssimativo.
- L'annullamento di un'esecuzione pianificata interrompe solo quel tentativo. Le date completate rimangono tali, le date non risolte possono essere ritentate e la pianificazione ricorrente rimane abilitata.

## Fonti sanitarie

Health Connect è il percorso di esportazione locale in entrambi i canali. La build Google Play include anche un'area di configurazione delle fonti sanitarie per ecosistemi come Samsung Health, Huawei Health, Fitbit, Garmin, Withings, Oura, Polar e WHOOP. Laddove tali ecosistemi scrivono in Health Connect , entrambe le build possono esportare i record Health Connect risultanti. Le importazioni dirette dal provider cloud e i callback OAuth sono di sola riproduzione. Il catalogo del fornitore F-Droid contiene solo Health Connect .

Google Fit è intenzionalmente escluso dalla superficie dei fornitori supportati perché Health Connect è il livello di dati sanitari preferito di Android.

### Passi esatti del giorno locale

I totali dei passi giornalieri utilizzano i limiti esatti del giorno locale suddiviso in zone. Prima dell'aggregazione, Health.md ritaglia e divide sovrapponendo gli intervalli Health Connect alla mezzanotte locale. Pertanto, i cambiamenti di viaggio e di ora legale non spostano i passi nel giorno sbagliato.

## Distribuzione, prezzi e cambio

- ** Google Play :** la versione telefonica abilitata all'abbonamento offre abbonamenti individuali settimanali/annuali e a vita. Gli abbonati idonei che si abbonano per la prima volta ricevono una prova di 7 giorni, quindi rinnovano automaticamente al prezzo visualizzato fino all'annullamento tramite Google Play . La durata viene addebitata una volta immediatamente senza prova. Non rimane alcuna indennità locale di libera esportazione. L'accesso permanente esistente viene mantenuto. Ripristina acquisto utilizza l'account Google acquirente; l'eliminazione dell'app o l'acquisto di Lifetime non annulla l'abbonamento. Le build rilasciate meno recenti possono mostrare l'indennità precedente. La versione attuale è solo per telefono. Il compagno Wear OS viene rinviato a un ciclo di qualificazione successivo.
- ** F-Droid :** è incluso l'accesso illimitato. Non sono previsti contatori gratuiti, dipendenza dalla fatturazione, paywall, acquisto o azione di ripristino.
- ** F-Droid ambito:** solo Health Connect , senza integrazione del sistema operativo Wear, OAuth diretto del provider cloud, revisione di Play, attribuzione o telemetria di onboarding Health.md .
- **Risultato condiviso:** entrambi i canali utilizzano la stessa Health Connect acquisizione, esportatori, schemi, azioni di automazione e protocollo diretto al dispositivo.
- **Cambio:** Google Play e F-Droid utilizzano chiavi di firma diverse, quindi cambiare canale richiede prima la disinstallazione dell'app.

Un cambio di canale non esegue la migrazione di acquisti, impostazioni, cronologia, credenziali o stato di trasferimento privato. I file esportati rimangono nella destinazione scelta.

Se Google Play Billing si disconnette temporaneamente, la build di Play si riconnette e aggiorna automaticamente lo stato dei diritti. Una perdita temporanea del servizio non rimuove permanentemente Premium. Utilizzare Ripristina acquisto solo se l'account rimane irrisolto dopo il ripristino della connettività.

## Modello di privacy

Health.md per Android è innanzitutto locale:

- I record -  Health Connect vengono letti sul tuo dispositivo Android.
- Le esportazioni vengono scritte direttamente nelle cartelle scelte.
- Le esportazioni delle cartelle principali e le query dirette sul dispositivo non creano una copia sul server Health.md per impostazione predefinita.
- Le impostazioni e la cronologia delle esportazioni rimangono sul dispositivo.
- La fatturazione è gestita da Google Play nella build Play. F-Droid include l'accesso illimitato senza fatturazione e non contiene alcun codice di telemetria Health.md o identità/stato di telemetria.
- Le cartelle supportate dal provider vengono sincronizzate in base ai termini del provider.

Se desideri la configurazione locale più rigorosa, esegui le esportazioni manuali in una cartella del dispositivo locale e lascia disabilitate le esportazioni pianificate e la sincronizzazione supportata dal provider.

Il progetto pilota cloud separato e facoltativo Health.md Cloud conserva solo le esportazioni API caricate intenzionalmente al suo interno. Non è prevista alcuna registrazione pubblica né sincronizzazione automatica del dispositivo; il flusso di lavoro di questa cartella non viene caricato su di essa. Consulta l'[informativa sulla privacy](/privacy-policy.html) per i rischi di conservazione, eliminazione, quota e archiviazione senza supporto.

## Documenti correlati

<div class="related">
 <a href="/it/docs/export-profiles/"> <span> Profili </span> Salva destinazioni indipendenti, impostazioni di output, pianificazioni e ID di automazione stabili. </a>
 <a href="/it/docs/export/"> <span> Esporta </span> Flusso di esportazione manuale, intervalli di date, anteprime, cronologia e output di file. </a>
 <a href="/it/docs/metrics/"> <span> Metriche </span> Come funzionano la selezione delle metriche e le categorie in Health.md . </a>
 <a href="/it/docs/format/"> <span> Formati </span> Markdown , basi, JSON, CSV, unità, nomi file e frontmatter. </a>
 <a href="/it/docs/visualizations-roadmap/"> <span> Obsidian </span> Come esportare JSON e Markdown alimentano le visualizzazioni Health.md . </a>
 </div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;"> Ultimo aggiornamento 2026-10-04 </p>
