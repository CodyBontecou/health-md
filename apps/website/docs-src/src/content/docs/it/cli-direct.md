---
title: "CLI diretta per iPhone"
description: "Abbina healthmd a un iPhone tramite IP manuale, Tailscale o un trasporto Nearby supportato, quindi esporta senza avviare Health.md per Mac."
---

Il backend diretto collega `healthmd` all’app Health.md aperta su un iPhone, senza instradare il comando tramite Health.md per Mac. L’iPhone legge HealthKit, prepara il risultato in uno spazio di archiviazione protetto e trasferisce alla CLI partizioni convalidate.

```text
healthmd on the computer
  <-> authenticated encrypted Manual IP, Tailscale, or supported Nearby channel
Health.md on iPhone -> HealthKit -> protected bounded spool / typed query evaluator
  -> canonical JSON, production-generated files, or bounded MCP query pages
```

<div class="availability preview">
<strong>Anteprima · CLI diretta multipiattaforma</strong>
<p>Il backend diretto Swift incluso è disponibile su macOS. Il client Rust multipiattaforma è in versione alpha, in attesa dei test di rilascio su un iPhone fisico e del primo pacchetto pubblico; i comandi per Linux e Windows descrivono il flusso di lavoro previsto.</p>
</div>

## Funzioni supportate dalla modalità diretta

- abbinamento iniziale e riconnessione attendibile;
- controllo locale dei dispositivi attendibili e rimozione dell’abbinamento;
- verifica in tempo reale della disponibilità dell’iPhone;
- esportazione rigorosa dei dati grezzi con schema v7;
- estrazione canonica dei dati selezionati;
- esportazione di file generati dagli strumenti di produzione;
- stato e ripresa delle attività locali persistenti;
- annullamento esplicito;
- server stdio `healthmd mcp serve` nello stesso eseguibile, con query tipizzate dirette, catalogo delle metriche, dati di riscontro, interfaccia MCP Apps e immagini PNG di riserva.

Il backend diretto del comando `healthmd` non emula le route HTTP con contesto crittografato dell’app per Mac. I sottocomandi `doctor`, query, dati di riscontro e aggiornamento destinati al Mac continuano quindi a restituire `backend_unsupported`, anziché cambiare backend. Usa `healthmd mcp serve` per eseguire analisi tipizzate aggiornate direttamente sull’iPhone, oppure esegui `healthmd setup codex` per configurare e abbinare Codex automaticamente. `healthmd mcp schema [TOOL]` mostra in locale lo schema di input MCP annidato esatto e alcuni esempi; per il sonno usa direttamente `healthmd_sleep_sessions`, invece di considerare l’output canonico di `extract` come API per le query tipizzate.

## Requisiti

- Un binario `healthmd` compatibile con la modalità diretta e una versione corrispondente di Health.md per iPhone.
- Health.md aperta in primo piano sull’iPhone per l’abbinamento e l’avvio di nuovi comandi.
- **Impostazioni > Sincronizzazione Mac > Accesso CLI diretto** attivato sull’iPhone.
- Autorizzazioni per HealthKit e la rete locale, dati protetti disponibili e quota di esportazione sufficiente.
- Un indirizzo del computer raggiungibile e la porta TCP `17647` per IP manuale. È possibile usare un indirizzo Tailscale.
- Una destinazione assoluta già esistente per la modalità con file generati.

La CLI resta in ascolto. L’iPhone si collega all’indirizzo del computer inserito nella schermata Accesso CLI diretto.

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

Il comando scrive su stderr un codice di sei cifre, i possibili indirizzi del computer e la porta del listener, lasciando stdout riservato al risultato JSON finale.

Sull’iPhone:

1. Apri **Health.md > Impostazioni > Sincronizzazione Mac > Accesso CLI diretto**.
2. Attiva Accesso CLI diretto.
3. Seleziona **IP manuale**.
4. Inserisci l’indirizzo LAN o Tailscale del computer.
5. Inserisci la porta `17647`, salvo che la CLI usi un’altra opzione globale `--port`.
6. Inserisci il codice di abbinamento e tocca Abbina.
7. Lascia aperta l’app finché entrambi i dispositivi non confermano il completamento.

I codici di abbinamento scadono dopo 10 minuti. Non vengono mai inviati in rete né salvati.

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

Questi comandi leggono o modificano i dati di attendibilità locali e non contattano l’iPhone. Sull’iPhone, usa **Forget Paired CLI** per rimuovere l’altro dispositivo.

Se sono presenti più iPhone attendibili, indica esplicitamente l’installazione desiderata:

```bash
healthmd --backend direct --device DEVICE_UUID status
```

Usa `healthmd direct reset-trust --confirm` solo se i dati di attendibilità locali sono danneggiati o appartengono a un’installazione sostituita. Il comando rimuove tutti gli abbinamenti diretti locali. Prima di ricominciare, rimuovi gli stessi abbinamenti anche dall’iPhone.

## Verificare la disponibilità in tempo reale

```bash
healthmd --backend direct --transport manual-ip status
```

La risposta di stato della modalità diretta descrive la connessione e le condizioni di sicurezza, senza includere valori sanitari. Prima di iniziare, verifica questi campi:

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

## Esportazione rigorosa dei dati grezzi

Scegli un solo selettore per l’intervallo:

```bash
healthmd --backend direct export --yesterday --raw --output yesterday.json
healthmd --backend direct export --last 7 --raw --output week.json
healthmd --backend direct export \
  --from 2026-07-01 --to 2026-07-07 --raw --output range.json
healthmd --backend direct export --all --raw --output complete-health-corpus.json
```

Ometti `--output` per inviare il JSON convalidato a stdout. Per risposte sensibili o di grandi dimensioni, un file di output è più sicuro.

L’esportazione rigorosa dei dati grezzi restituisce `healthmd.raw_result` v1, che contiene normali giornate `healthmd.health_data` con schema v7 e i relativi archivi canonici di origine. Richiede temporaneamente il livello di dettaglio senza perdita, senza modificare le impostazioni salvate sull’iPhone. Prima di esporre il risultato, la CLI convalida date esatte, profilo, schema, archivio, manifesti, catena dei digest, digest finale del corpo e stato di completamento.

Una giornata completa ma priva di dati è un risultato valido. Se i dati richiesti sono mancanti, parziali, non riusciti, annullati, non supportati o ignorati, il risultato è `partial_success` e il codice di uscita è diverso da zero, salvo che sia stata specificata l’opzione `--allow-partial`.

## Estrazione canonica

L’estrazione diretta usa lo stesso trasferimento persistente dei dati grezzi, ma restituisce i dati selezionati nella forma della sorgente, senza l’involucro di trasporto:

```bash
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json

healthmd --backend direct extract \
  --metric workouts --last 14 --object records \
  --detail lossless --output workout-records.json
```

Le selezioni di metrica, categoria, origine e dettaglio raggiungono l’iPhone prima che HealthKit legga i dati. Consulta [Estrazione canonica](/it/docs/cli-extract/) per i selettori degli oggetti, i puntatori JSON, JSONL e le ricevute.

## File generati dagli strumenti di produzione

Nella modalità file diretta, l’iPhone esegue gli strumenti di esportazione di produzione di Health.md e trasferisce i file risultanti a una destinazione esplicita sul computer.

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

Le destinazioni dei file generati funzionano su macOS e Linux. Il protocollo v1 le rifiuta su Windows. In Windows, gli utenti della modalità diretta possono usare l’esportazione dei dati grezzi e l’estrazione.

## Comportamento in primo piano e in background

L’abbinamento e l’avvio di nuove attività richiedono che l’app per iPhone sia in primo piano. Accesso CLI diretto non trasforma iOS in un server di esportazione senza interfaccia e non può riattivare l’app su richiesta.

Se un’esportazione è già connessa quando l’app passa in background, Health.md richiede un periodo limitato di esecuzione in background a iOS. L’esportazione può terminare durante questo intervallo. Se iOS interrompe l’esecuzione, la connessione si chiude e l’attività persistente viene sospesa. Riapri Health.md e riprendi la stessa attività.

Durante le operazioni dirette, l’iPhone mostra un banner generale con fase di acquisizione e trasferimento, giornate completate, avanzamento in byte e stato sospeso o completato, senza visualizzare valori sanitari.

## Ripresa e annullamento delle attività persistenti

Le attività dirette scadono sette giorni dopo la creazione. Timeout, Ctrl-C, chiusura del processo, disconnessione e scadenza dell’esecuzione in background non le annullano.

```bash
healthmd --backend direct status --job JOB_UUID
healthmd --backend direct resume JOB_UUID --timeout 300 --output recovered.json
healthmd --backend direct cancel JOB_UUID
```

La ripresa conserva date, impostazioni, destinazione, impronta della richiesta, dispositivo e limite delle partizioni originali. Durante la ripresa non puoi assegnare una destinazione diversa a un’attività di tipo file.

Il comando di annullamento registra una richiesta persistente, ma l’annullamento diventa definitivo solo dopo la conferma dell’iPhone. Se l’iPhone non è disponibile, lo stato resta `cancellation_pending`. Riapri lo stesso iPhone e ripeti il comando di annullamento.

## Modello di sicurezza

- L’abbinamento usa uno scambio di chiavi Curve25519 effimere e prove della trascrizione legate al codice di sei cifre.
- La riconnessione dimostra il possesso di un segreto casuale salvato e delle identità di entrambe le installazioni.
- Ogni connessione genera nuove chiavi e nuovi nonce.
- I messaggi e i frame binari usano ChaCha20-Poly1305 con controlli monotoni della sequenza.
- Le partizioni usano manifesti SHA-256 e una catena progressiva di digest.
- I dati di attendibilità dell’iPhone sono archiviati nel portachiavi.
- Il client multipiattaforma usa Portachiavi, Secret Service o Gestione credenziali Windows e non ricorre mai al testo non cifrato.
- Gli spool e i registri usano lo spazio privato dell’applicazione e, ove supportato dalla piattaforma, sono esclusi dai backup.

IP manuale resta crittografato sia su una rete locale sia tramite Tailscale. Tailscale protegge anche il percorso di rete, ma non sostituisce l’autenticazione dell’applicazione Health.md.

## Errori comuni

| Errore | Intervento |
|---|---|
| `direct_not_paired` | Abbina questa installazione della CLI all’iPhone. |
| `direct_device_selection_required` | Specifica il dispositivo attendibile desiderato con `--device`. |
| `direct_trust_invalid` | Conserva i dati diagnostici. Reimposta l’attendibilità solo se il ripristino è impossibile. |
| `direct_iphone_unavailable` | Controlla che l’app sia in primo piano, l’accesso sia attivo e indirizzo, porta, autorizzazioni e connessione LAN o Tailscale siano corretti. |
| `direct_export_paused` | Controlla l’attività, riapri l’iPhone e riprendila. |
| `direct_cancellation_pending` | Riapri l’iPhone abbinato e ripeti l’annullamento. |
| `transport_unsupported` | Nel client multipiattaforma usa IP manuale o Tailscale. |
| `backend_unsupported` | Per query, dati di riscontro, diagnostica, metriche o MCP usa il backend dell’app per Mac. |
| `invalid_direct_raw_response` | Non usare l’output. Conserva i dati diagnostici della convalida. |
| `invalid_direct_file_receipt` | Non correggere i file manualmente. Controlla e riprendi l’attività. |
| `job_expired` | Il periodo di conservazione di sette giorni è terminato. Chiedi conferma prima di avviare una nuova attività. |

## Argomenti correlati

<div class="related">
  <a href="/it/docs/cli/"><span>Panoramica</span>CLI di Health.md: installa gli helper inclusi e scegli il backend adatto.</a>
  <a href="/it/docs/cli-extract/"><span>Dati</span>Estrazione canonica: seleziona ed emetti i dati Health.md nella forma della sorgente.</a>
  <a href="/it/docs/cli-jobs/"><span>Affidabilità</span>Attività persistenti e automazione: ripresa, annullamento, risultati parziali e script.</a>
  <a href="/it/docs/reference/connected-mac-iphone-protocol/"><span>Protocollo</span>Riferimento per Mac e iPhone connessi: funzionalità, trasferimento limitato e stati dei risultati.</a>
</div>
