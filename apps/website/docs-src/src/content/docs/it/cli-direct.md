---
title: "CLI diretta dal telefono"
description: "Abbina healthmd a un iPhone o a un telefono Android tramite IP manuale o Tailscale, quindi esporta senza avviare Health.md per Mac."
---

Il backend diretto collega `healthmd` all’app Health.md aperta su un iPhone o su un telefono Android, senza instradare il comando tramite Health.md per Mac. Il telefono legge l’archivio sanitario della propria piattaforma — HealthKit su iPhone, Health Connect su Android —, prepara il risultato in uno spazio di archiviazione protetto e trasferisce alla CLI partizioni convalidate.

```text
healthmd on the computer
  <-> authenticated encrypted Manual IP, Tailscale, or supported Nearby channel
Health.md on iPhone or Android -> HealthKit / Health Connect -> protected bounded spool
  -> raw snapshots, production-generated files, or (iPhone) canonical and typed query data
```

<div class="availability preview">
<strong>Anteprima · CLI diretta multipiattaforma</strong>
<p>Il backend diretto Swift incluso è disponibile su macOS e si abbina all’iPhone. Android con protocollo applicativo v2 fa parte dell’anteprima pubblicamente distribuita del client Rust multipiattaforma. Le versioni attuali di iOS e Android usano lo stesso selettore 3 e lo stesso QR universale per i nuovi abbinamenti portatili. La connettività fisica di base è confermata su entrambe le piattaforme mobili, ma la matrice di rilascio completa con build esatte resta in attesa; il flusso di lavoro rimane quindi esplicitamente non qualificato.</p>
</div>

## Compatibilità mobile per 0.1.0-alpha.6

Questa tabella autonoma è la matrice operativa dell’anteprima esplicitamente non qualificata. La connettività di base con iPhone e Android è stata confermata fisicamente; nessuna coppia pubblica CLI/dispositivo mobile ha ancora completato e conservato l’intera matrice di qualificazione.

| Sorgente mobile | Protocollo | Controparte tag-SHA esatta / soglia non qualificata | Operazioni Rust portatili | Stato pubblico |
|---|---|---|---|---|
| iPhone con esportazione | selettore 3 attuale (1 precedente) / applicazione v1 | iOS 3.3.0 (build 202609032317) / iOS 3.0.3 | Stato, dati grezzi, estrazione, file, ripresa, annullamento | Connettività confermata; qualificazione completa in sospeso |
| iPhone con query | selettore 3 attuale (1 precedente) / applicazione v1 + query v3 | iOS 3.3.0 (build 202609032317) / iOS 3.0.3 | V1 più MCP/query locale con 19 strumenti | Connettività confermata; qualificazione completa in sospeso |
| Android | selettore 3 attuale (2 precedente) / applicazione v2 | Android 1.8.2 (`versionCode 31`) / Android 1.5.4 (`versionCode 25`) | Stato, dati nativi, file, ripresa, annullamento | Connettività confermata; qualificazione completa in sospeso |
| Query MCP tipizzata Android | Non disponibile | Non implementata | Gli strumenti richiedono iPhone v3 | Non supportata |

## Funzioni supportate dalla modalità diretta

- abbinamento iniziale tramite il selettore condiviso 3 e riconnessione attendibile con sorgenti iPhone (protocollo applicativo v1) o Android (protocollo applicativo v2);
- controllo locale dei dispositivi attendibili e rimozione dell’abbinamento;
- verifica in tempo reale della disponibilità del telefono;
- esportazione rigorosa dei dati grezzi — `healthmd.health_data` con schema v8 su iPhone, snapshot nativi del provider di Health Connect su Android;
- estrazione canonica dei dati selezionati (solo iPhone);
- esportazione di file generati dagli strumenti di produzione su entrambe le piattaforme telefoniche;
- stato e ripresa delle attività locali persistenti;
- annullamento esplicito;
- server stdio `healthmd mcp serve` nello stesso eseguibile, con query tipizzate dirette, catalogo delle metriche, dati di riscontro, interfaccia MCP Apps e immagini PNG di riserva (solo iPhone).

Il backend diretto del comando `healthmd` non emula le route HTTP con contesto crittografato dell’app per Mac. I sottocomandi `doctor`, query, dati di riscontro e aggiornamento destinati al Mac continuano quindi a restituire `backend_unsupported`, anziché cambiare backend. Usa `healthmd mcp serve` per eseguire analisi tipizzate aggiornate direttamente sull’iPhone, oppure esegui `healthmd setup codex` per configurare e abbinare Codex automaticamente. `healthmd mcp schema [TOOL]` mostra in locale lo schema di input MCP annidato esatto e alcuni esempi; per il sonno usa direttamente `healthmd_sleep_sessions`, invece di considerare l’output canonico di `extract` come API per le query tipizzate.

## Requisiti

- Un binario `healthmd` compatibile con la modalità diretta e una versione corrispondente di Health.md: iPhone (protocollo applicativo v1) o Android (protocollo applicativo v2). L’abbinamento con Android richiede il client Rust multipiattaforma; l’helper incluso per macOS si abbina solo all’iPhone.
- Health.md aperta in primo piano sul telefono per l’abbinamento e l’avvio di nuovi comandi.
- **Impostazioni > Sincronizzazione Mac > Accesso CLI diretto** attivato sull’iPhone, oppure **Impostazioni → Direct CLI** su Android.
- Autorizzazione sanitaria della piattaforma (HealthKit o Health Connect), dati protetti disponibili, autorizzazione per la rete locale e quota di esportazione sufficiente.
- Un indirizzo del computer raggiungibile e la porta TCP `17647` per IP manuale. È possibile usare un indirizzo Tailscale.
- Una destinazione assoluta già esistente per la modalità con file generati.

La CLI resta in ascolto. Il telefono si collega all’indirizzo del computer inserito nella schermata Accesso CLI diretto.

## Trasporti supportati

| Trasporto | Helper Swift incluso su macOS | Client Rust multipiattaforma |
|---|---:|---:|
| IP manuale su una LAN | Sì | macOS, Linux, Windows |
| Indirizzo Tailscale | Sì | macOS, Linux, Windows |
| Nearby / MultipeerConnectivity | Sì | No |

Nearby usa la sessione Multipeer crittografata di Apple, oltre all’autenticazione e alla crittografia dell’applicazione Health.md già impiegate con IP manuale. Per Nearby, il client multipiattaforma restituisce `transport_unsupported`.

## Primo abbinamento tramite IP manuale

Avvia il listener sul computer:

```bash
healthmd direct pair --transport manual-ip
```

Il client Rust multipiattaforma mostra un QR universale per iOS e Android e scrive su stderr il relativo codice condiviso di 20 cifre, i possibili indirizzi del computer, la porta del listener e un codice di riserva di sei cifre per le versioni iOS precedenti. L’helper incluso per macOS continua a mostrare soltanto il vecchio codice iPhone di sei cifre. stdout resta riservato al risultato JSON finale.

Sull’iPhone:

1. Apri **Health.md > Impostazioni > Sincronizzazione Mac > Accesso CLI diretto** e attiva l’accesso.
2. Tocca **Scansiona QR di abbinamento** e scansiona il QR universale; l’abbinamento inizia subito dopo questa scansione esplicita.
3. Se la scansione non è disponibile, seleziona **IP manuale** e inserisci indirizzo, porta e codice condiviso di 20 cifre. Una CLI precedente può ancora usare il codice di sei cifre.
4. Lascia aperta l’app finché entrambi i dispositivi non confermano il completamento.

## Abbinare un telefono Android

1. Apri **Health.md > Impostazioni → Direct CLI** sul telefono Android.
2. Tocca **Scansiona QR di abbinamento** e scansiona il QR universale; l’abbinamento inizia subito dopo questa scansione esplicita.
3. Senza fotocamera o autorizzazione, inserisci manualmente indirizzo, porta e lo stesso codice condiviso di 20 cifre.
4. Lascia aperta l’app; per una sessione diretta attiva, Android esegue un servizio in primo piano di sincronizzazione dei dati, visibile e avviato dall’utente.

I codici monouso non vengono mai inviati in rete né salvati. Dopo l’abbinamento, Keychain o Android Keystore protegge l’attendibilità per la riconnessione.

Se necessario, usa un’altra porta:

```bash
healthmd --port 18000 direct pair --transport manual-ip
healthmd --backend direct --port 18000 status
```

Continua a specificare la stessa porta per i successivi comandi di stato, esportazione, ripresa e annullamento.

## Abbinamento tramite Nearby

Nearby è disponibile solo nell’helper Swift incluso:

```bash
healthmd direct pair --transport nearby
```

Seleziona Nearby nella schermata Accesso CLI diretto sull’iPhone, inserisci il codice visualizzato e lascia aperti entrambi i dispositivi finché l’abbinamento non termina. Se un’operazione Nearby non riesce, il sistema non passa a IP manuale.

## Dispositivi attendibili

L’abbinamento crea un rapporto di attendibilità distinto da quello usato per la sincronizzazione con l’app Health.md per Mac.

```bash
healthmd direct devices
healthmd direct unpair DEVICE_UUID
```

Questi comandi leggono o modificano i dati di attendibilità locali e non contattano il telefono. Sull’iPhone, usa **Forget Paired CLI** per rimuovere l’altro dispositivo; su Android, rimuovi l’abbinamento da **Impostazioni → Direct CLI**.

Se sono presenti più telefoni attendibili, indica esplicitamente l’installazione desiderata:

```bash
healthmd --backend direct --device DEVICE_UUID status
```

Usa `healthmd direct reset-trust --confirm` solo se i dati di attendibilità locali sono danneggiati o appartengono a un’installazione sostituita. Il comando rimuove tutti gli abbinamenti diretti locali. Prima di ricominciare, rimuovi gli stessi abbinamenti anche dal telefono.

## Verificare la disponibilità in tempo reale

```bash
healthmd --backend direct --transport manual-ip status
```

La risposta di stato della modalità diretta descrive la connessione e le condizioni di sicurezza, senza includere valori sanitari. Il client multipiattaforma indica la sorgente nel campo `source` con una `platform` pari a `ios` o `android`; l’helper incluso espone i campi `iphone` riportati di seguito. Prima di iniziare, verifica questi campi (è mostrata la sorgente iPhone):

| Campo | Stato richiesto |
|---|---|
| `backend` | `direct` |
| `mac_app` | `bypassed` |
| `direct_cli.paired` | `true` |
| `iphone.connected` | `true` |
| `iphone.app_active` | `true` per avviare nuove attività |
| `iphone.protected_data_available` | `true` |
| `iphone.can_trigger_raw_exports` | `true` per dati grezzi ed estrazione |
| `iphone.can_trigger_exports` | `true` per i file generati |

Nello stato della modalità diretta, la destinazione resta non selezionata. La modalità file usa esclusivamente l’opzione `--destination` fornita esplicitamente al comando.

Una sorgente Android riporta `platform: "android"` con `app_active`, `protected_data_available`, `export_in_progress` e i propri prodotti grezzi disponibili, al posto dei flag di attivazione dell’iPhone.

## Esportazione rigorosa dei dati grezzi (iPhone)

Scegli un solo selettore per l’intervallo:

```bash
healthmd --backend direct export --yesterday --raw --output yesterday.json
healthmd --backend direct export --last 7 --raw --output week.json
healthmd --backend direct export \
  --from 2026-07-01 --to 2026-07-07 --raw --output range.json
healthmd --backend direct export --all --raw --output complete-health-corpus.json
```

Ometti `--output` per inviare il JSON convalidato a stdout. Per risposte sensibili o di grandi dimensioni, un file di output è più sicuro.

L’esportazione rigorosa dei dati grezzi su iPhone restituisce `healthmd.raw_result` v1, che contiene normali giornate `healthmd.health_data` con schema v8 e i relativi archivi canonici di origine. Richiede temporaneamente il livello di dettaglio senza perdita, senza modificare le impostazioni salvate sull’iPhone. Prima di esporre il risultato, la CLI convalida date esatte, profilo, schema, archivio, manifesti, catena dei digest, digest finale del corpo e stato di completamento.

Una giornata completa ma priva di dati è un risultato valido. Se i dati richiesti sono mancanti, parziali, non riusciti, annullati, non supportati o ignorati, il risultato è `partial_success` e il codice di uscita è diverso da zero, salvo che sia stata specificata l’opzione `--allow-partial`.

## Esportazione grezza nativa del provider (Android)

Il client Rust multipiattaforma usa per impostazione predefinita la modalità diretta, quindi i comandi per i dati grezzi di Android omettono il flag `--backend`:

```bash
healthmd export --last 7 --raw --provider health_connect \
  --raw-format ndjson --output health-connect.ndjson
```

`--provider` indica un unico provider esplicito e per impostazione predefinita è `health_connect`. `--raw-format` per impostazione predefinita è NDJSON, la forma consigliata per gli snapshot di grandi dimensioni; la convalida JSON in memoria è limitata a 64 MiB. La selezione delle metriche supporta `--metric` e `--all-metrics`, ma non i selettori canonici o dei file generati: quelle restano funzionalità dell’iPhone.

Gli snapshot grezzi di Android mantengono il contratto nativo del provider di Health Connect. Non vengono mai convertiti in giornate `healthmd.health_data` in stile HealthKit, e le statistiche simili ma diverse conservano identità proprie.

## Estrazione canonica

L’estrazione diretta usa lo stesso trasferimento persistente dei dati grezzi, ma restituisce i dati selezionati nella forma della sorgente, senza l’involucro di trasporto. È una funzionalità dell’iPhone:

```bash
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json

healthmd --backend direct extract \
  --metric workouts --last 14 --object records \
  --detail lossless --output workout-records.json
```

Le selezioni di metrica, categoria, origine e dettaglio raggiungono l’iPhone prima che HealthKit legga i dati. Consulta [Estrazione canonica](/it/docs/cli-extract/) per i selettori degli oggetti, i puntatori JSON, JSONL e le ricevute.

Mentre l’app resta in primo piano, una sessione diretta attendibile può riconnettersi automaticamente dopo un’interruzione temporanea, con tentativi e attese limitati. Questo non riattiva né promette accesso a un’app in background; riapri Health.md prima di riprendere.

## File generati dagli strumenti di produzione

Nella modalità file diretta, il telefono esegue gli strumenti di esportazione di produzione di Health.md e trasferisce i file risultanti a una destinazione esplicita sul computer.

```bash
mkdir -p "$HOME/Documents/HealthVault"

healthmd --backend direct export --yesterday \
  --destination "$HOME/Documents/HealthVault"

healthmd --backend direct export --last 7 \
  --category Sleep --detail summary \
  --destination "$HOME/Documents/HealthVault"

healthmd --backend direct export --yesterday --use-iphone-settings \
  --destination "$HOME/Documents/HealthVault"
```

La destinazione deve già esistere, essere assoluta e non risolversi tramite un collegamento simbolico. La modalità diretta non tenta mai di indovinarla e non usa i segnalibri dell’app per Mac. `--output` serve per l’output dei dati grezzi o dell’estrazione; `--destination` serve per i file generati.

Per impostazione predefinita, una richiesta conserva formati, sottocartella Health, nomi dei file, modelli, modalità di scrittura, Daily Note Injection e Daily Notes Only salvati. Per quella specifica attività, disattiva i riepiloghi aggregati e la modalità con soli riepiloghi. Le opzioni ripetibili `--metric` o `--category`, insieme a `--detail`, sostituiscono soltanto l’ambito delle metriche e il livello di dettaglio dell’attività. `--use-iphone-settings` riproduce tutte le impostazioni salvate e non può essere combinata con i selettori.

L’iPhone può preparare JSON, CSV, Markdown, ZIP, dizionari dei dati, riepiloghi aggregati, record individuali, note giornaliere e file complementari dei provider. Prima di salvare, la CLI convalida ogni percorso relativo, numero di byte, digest, manifesto dei file, identità della destinazione e impronta della richiesta. Rifiuta l’attraversamento delle directory, i collegamenti simbolici nelle directory superiori, le modifiche alla radice, le collisioni tra percorsi e le variazioni dei digest. La sovrascrittura è atomica. L’aggiunta e l’unione di file Markdown usano piani salvati, così la ripetizione dell’operazione non duplica il contenuto.

Le destinazioni dei file generati funzionano con il protocollo v1 dell’iPhone e il protocollo v2 di Android su ogni sistema operativo della CLI — macOS, Linux e Windows. Android limita ogni attività a 4.096 file.

Le attività file del protocollo v2 di Android prendono le impostazioni di output dalle selezioni salvate sul dispositivo oppure da `--profile PROFILE_ID`; i selettori CLI di metrica, categoria e dettaglio vengono rifiutati. Su entrambe le piattaforme telefoniche, `--profile` risolve le impostazioni di output congelate, mentre il parametro `--destination` obbligatorio continua a indicare la cartella esplicita sul computer.
Per ID stabili e fallimenti sicuri, consulta [Profili di esportazione](/it/docs/export-profiles/).

## Comportamento in primo piano e in background

L’abbinamento e l’avvio di nuove attività richiedono che l’app sul telefono sia in primo piano. Accesso CLI diretto non trasforma il telefono in un server di esportazione senza interfaccia e non può riattivare l’app su richiesta.

Sull’iPhone, se un’esportazione è già connessa quando l’app passa in background, Health.md richiede un periodo limitato di esecuzione in background a iOS. L’esportazione può terminare durante questo intervallo. Se iOS interrompe l’esecuzione, la connessione si chiude e l’attività persistente viene sospesa. Riapri Health.md e riprendi la stessa attività.

Su Android, una sessione diretta attiva esegue un servizio in primo piano di sincronizzazione dei dati, visibile e avviato dall’utente. Tieni l’app in primo piano per l’abbinamento e le nuove attività.

Sull’iPhone, un banner generale durante le operazioni dirette mostra la fase di acquisizione e trasferimento, le giornate completate, l’avanzamento in byte e lo stato sospeso o completato, senza visualizzare valori sanitari.

Finché l’app del telefono resta in primo piano, una sessione diretta attendibile può riconnettersi automaticamente dopo un’interruzione temporanea. I tentativi usano ritardi crescenti fino a un breve valore massimo. Questo non riattiva né garantisce l’accesso a un’app in background; riapri Health.md prima di riprendere se l’app non è più in primo piano.

La finestra di attesa limitata di 120 secondi mantiene aperta la stessa richiesta mentre la persona sblocca il telefono e apre Health.md. Puoi configurarla con `--wake-timeout SECONDS`; `0` la disattiva. MCP usa `HEALTHMD_WAKE_TIMEOUT`. I binari alpha.6 pubblicati si limitano all’attesa. Nelle build ufficiali successive, un iPhone registrato riceve anche un’unica notifica APNs best effort tramite il servizio di riattivazione di Health.md riservato alle notifiche; Android e gli iPhone non registrati restano in sola attesa. La notifica può ripristinare la presenza della persona, ma non autorizza mai una lettura HealthKit né invia l’ambito sanitario attraverso il Worker.

## Ripresa e annullamento delle attività persistenti

Le attività dirette scadono sette giorni dopo la creazione. Timeout, Ctrl-C, chiusura del processo, disconnessione e scadenza dell’esecuzione in background non le annullano.

```bash
healthmd --backend direct status --job JOB_UUID
healthmd --backend direct resume JOB_UUID --timeout 300 --output recovered.json
healthmd --backend direct cancel JOB_UUID
```

La ripresa conserva date, impostazioni, destinazione, impronta della richiesta, dispositivo e limite delle partizioni originali. Durante la ripresa non puoi assegnare una destinazione diversa a un’attività di tipo file.

Il comando di annullamento registra una richiesta persistente, ma l’annullamento diventa definitivo solo dopo la conferma del telefono abbinato. Se il telefono non è disponibile, lo stato resta `cancellation_pending`. Riapri lo stesso telefono e ripeti il comando di annullamento.

## Modello di sicurezza

- Gli abbinamenti portatili attuali usano uno scambio di chiavi effimero e prove della trascrizione del selettore 3 legate a un codice condiviso iOS/Android ad alta entropia di 20 cifre (circa 66 bit). I precedenti flussi Apple selettore 1 e Android selettore 2 restano compatibili byte per byte.
- I passaggi QR sono accettati solo dagli scanner espliciti nell’app per indirizzi privati LAN/Tailscale canonici; l’apertura di un URL personalizzato esterno non può autorizzare l’abbinamento.
- La riconnessione dimostra il possesso di un segreto casuale salvato e delle identità di entrambe le installazioni.
- Ogni connessione genera nuove chiavi e nuovi nonce.
- I messaggi e i frame binari usano ChaCha20-Poly1305 con controlli monotoni della sequenza.
- Le partizioni usano manifesti SHA-256 e una catena progressiva di digest.
- I dati di attendibilità dell’iPhone sono archiviati nel portachiavi; l’attendibilità di riconnessione di Android è basata su Keystore.
- Il client multipiattaforma usa Portachiavi, Secret Service o Gestione credenziali Windows e non ricorre mai al testo non cifrato.
- Gli spool e i registri usano lo spazio privato dell’applicazione e, ove supportato dalla piattaforma, sono esclusi dai backup.

IP manuale resta crittografato sia su una rete locale sia tramite Tailscale. Tailscale protegge anche il percorso di rete, ma non sostituisce l’autenticazione dell’applicazione Health.md.

## Errori comuni

| Errore | Intervento |
|---|---|
| `direct_not_paired` | Abbina questa installazione della CLI alla sorgente mobile prevista. |
| `direct_device_selection_required` | Specifica il dispositivo attendibile desiderato con `--device`. |
| `direct_trust_invalid` | Conserva i dati diagnostici. Reimposta l’attendibilità solo se il ripristino è impossibile. |
| `direct_iphone_unavailable` | Controlla che l’app sia in primo piano, l’accesso sia attivo e indirizzo, porta, autorizzazioni e connessione LAN o Tailscale siano corretti. |
| `direct_export_paused` | Controlla l’attività, riapri il telefono abbinato e riprendila. |
| `direct_cancellation_pending` | Riapri il telefono abbinato e ripeti l’annullamento. |
| `transport_unsupported` | Nel client multipiattaforma usa IP manuale o Tailscale. |
| `backend_unsupported` | Per query, dati di riscontro, diagnostica, metriche o MCP usa il backend dell’app per Mac. |
| `invalid_direct_raw_response` | Non usare l’output. Conserva i dati diagnostici della convalida. |
| `invalid_direct_file_receipt` | Non correggere i file manualmente. Controlla e riprendi l’attività. |
| `job_expired` | Il periodo di conservazione di sette giorni è terminato. Chiedi conferma prima di avviare una nuova attività. |

## Argomenti correlati

<div class="related">
  <a href="/it/docs/cli/"><span>Panoramica</span>CLI di Health.md: installa gli helper inclusi e scegli il backend adatto.</a>
  <a href="/it/docs/android/"><span>Android</span>Health.md per Android: sorgenti Health Connect, destinazioni a cartelle e automazione sul dispositivo.</a>
  <a href="/it/docs/cli-extract/"><span>Dati</span>Estrazione canonica: seleziona ed emetti i dati Health.md nella forma della sorgente (iPhone).</a>
  <a href="/it/docs/cli-jobs/"><span>Affidabilità</span>Attività persistenti e automazione: ripresa, annullamento, risultati parziali e script.</a>
  <a href="/it/docs/reference/connected-mac-iphone-protocol/"><span>Protocollo</span>Riferimento per Mac e iPhone connessi: funzionalità, trasferimento limitato e stati dei risultati.</a>
</div>
