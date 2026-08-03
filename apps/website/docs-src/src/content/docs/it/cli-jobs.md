---
title: "Attività persistenti e automazione con la CLI"
description: "Automatizza healthmd in sicurezza con output leggibile dalle macchine, attese limitate, attività persistenti per sette giorni, stati parziali espliciti, ripresa e annullamento confermato."
---

Health.md gestisce le esportazioni connesse e l’acquisizione del contesto come attività persistenti. La durata dell’attività è indipendente da quella del processo che l’ha avviata. La chiusura di un terminale o l’interruzione della connessione di rete non elimina le partizioni già completate.

Questa pagina si applica all’esportazione di file, all’esportazione rigorosa dei dati grezzi, all’estrazione canonica e all’acquisizione aggiornata di un contesto crittografato, salvo che un comando indichi regole più restrittive.

## Regola fondamentale

Un timeout o una disconnessione non equivale a un annullamento.

Dopo un esito incerto, non avviare una copia della stessa operazione. Conserva l’ID dell’attività restituito, controllane lo stato e riprendi l’attività esistente.

Le attività di esportazione, dati grezzi ed estrazione usano i comandi principali del ciclo di vita:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

Le attività di acquisizione del contesto crittografato usano il ciclo di vita dell’agente locale:

```bash
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
```

## Durata di sette giorni

Un’attività persistente ha un valore `expires_at` fisso, impostato a sette giorni dalla creazione. L’avanzamento non proroga la scadenza. Entrambi i dispositivi salvano la richiesta immutabile e lo stato del trasferimento già completato necessario per una ripresa sicura.

Un’attività può conservare:

- le date esatte o gli identificatori risolti per l’intera cronologia;
- l’ambito di metriche, categorie, sorgenti e livello di dettaglio;
- il vincolo al backend e al dispositivo abbinato;
- i criteri per le impostazioni;
- il profilo dei dati grezzi o la selezione per l’estrazione;
- l’identità della destinazione dei file;
- l’impronta della richiesta;
- i manifesti della sessione e del trasferimento;
- la catena dei digest delle partizioni;
- il limite delle partizioni e dei byte salvati;
- la conferma del completamento o dell’annullamento.

La ripresa non può reinterpretare nessuno di questi campi.

## Gli stati non si limitano a in esecuzione o terminato

La risposta relativa a un’attività può includere:

| Campo | Significato |
|---|---|
| `durable` | Indica se l’operazione dispone di uno stato recuperabile |
| `state` | Stato corrente del ciclo di vita persistente |
| `job_id` | Identificatore stabile dell’attività |
| `session_id` | Identificatore della sessione di trasferimento associata |
| `paused` | Indica se il lavoro richiede la riconnessione dello stesso iPhone |
| `processed_days` / `total_days` | Avanzamento logico per giornate di riferimento |
| `committed_partitions` | Partizioni confermate in modo persistente dal destinatario |
| `committed_bytes` | Byte del payload salvati in sicurezza |
| `fraction_complete` | Frazione di avanzamento priva di dati sanitari |
| `expires_at` | Data e ora fisse di scadenza dell’attività |

I campi di stato contengono date, ID, conteggi, byte ed errori che non rivelano dati sanitari. Non devono contenere campioni sanitari.

## Avviare un’attività con un piano di output esplicito

Esportazione dei dati grezzi:

```bash
healthmd export --iphone --last 30 --raw \
  --output health-month.json
```

Estrazione canonica:

```bash
healthmd extract --category Sleep --last 30 \
  --output sleep-month.json
```

File generati in modalità diretta:

```bash
healthmd --backend direct export --last 30 \
  --destination "$HOME/Documents/HealthVault"
```

Scegli l’output o la destinazione finale prima di avviare la richiesta. Un’attività relativa ai dati grezzi vincola il proprio comportamento di output. Un’attività diretta di tipo file incorpora nella richiesta immutabile la radice esatta della destinazione.

## Ripresa

```bash
healthmd resume JOB_UUID --timeout 300
healthmd resume JOB_UUID --output recovered.json
healthmd resume JOB_UUID --output recovered.json --allow-partial
```

Per la modalità diretta, seleziona gli stessi backend, dispositivo, trasporto, porta e iPhone usati dalla richiesta originale:

```bash
healthmd --backend direct --device DEVICE_UUID \
  --transport manual-ip --port 17647 \
  resume JOB_UUID --timeout 300 --output recovered.json
```

Dopo una disconnessione, i byte in sospeso possono essere eliminati. Le partizioni già confermate non vengono ritrasmesse né reinterpretate. Il destinatario accetta una partizione già confermata soltanto se tutti i descrittori immutabili corrispondono.

Durante la ripresa, un’attività di tipo file non accetta una destinazione sostitutiva. Se la radice originale è cambiata, Health.md interrompe l’operazione in sicurezza anziché scrivere in un’altra cartella.

## Annullamento

Usa il ciclo di vita che ha creato l’attività:

```bash
# Export, raw, or extraction
healthmd cancel JOB_UUID

# Encrypted-context acquisition
healthmd agent job cancel JOB_UUID
```

L’annullamento avviene in due fasi:

1. la CLI registra e invia una richiesta di annullamento persistente;
2. l’iPhone conferma l’annullamento, rendendolo definitivo.

Se l’iPhone non è disponibile, l’attività resta nello stato `cancellation_pending`. Riapri lo stesso iPhone e ripeti il comando di annullamento. Non dichiarare annullata un’attività sulla base della sola intenzione locale.

Un processo che riceve Ctrl-C deve terminare senza simulare un annullamento definitivo. Quando vuoi annullare l’attività, usa l’apposito comando.

## Canali di output

Health.md separa i risultati dei comandi dall’avanzamento:

| Canale | Contenuto |
|---|---|
| stdout | Risultato JSON con versione, errore oppure flusso JSON/JSONL richiesto |
| stderr | Istruzioni di abbinamento in testo semplice, avanzamento privo di dati sanitari, ricevuta JSONL durante lo streaming e testo d’uso |
| `--output PATH` | JSON o JSONL contenente dati sanitari, salvato in modo atomico |
| `OUTPUT.receipt.json` | Ricevuta di estrazione priva di dati sanitari per l’output JSONL su file |

`--help` restituisce testo semplice. Gli errori negli argomenti rilevati prima dell’esecuzione usano stderr e il codice di uscita 2. Dopo l’avvio di un comando, gli errori di esecuzione sono espressi in JSON leggibile dalle macchine.

Non unire stdout e stderr in un parser di automazione.

## Codice di uscita e stato dei dati

Il codice di uscita del processo è soltanto uno degli indicatori. Analizza la risposta prima di dichiarare il completamento.

| Risultato | Codice di uscita predefinito |
|---|---|
| Completamento riuscito | Zero |
| Ambito richiesto completo ma privo di dati | Zero |
| Risultato parziale convalidato per dati grezzi rigorosi o estrazione | Diverso da zero |
| Risultato parziale con `--allow-partial` esplicito | Zero, ma la risposta resta parziale |
| Errore negli argomenti | Codice 2 e testo semplice su stderr |
| Errore di convalida o trasporto | Diverso da zero, con errore di esecuzione strutturato |

`--allow-partial` esprime un criterio di accettazione, non ripara i dati. Ogni giornata mancante, query non riuscita, tipo non supportato e avviso resta visibile.

## L’esplorazione delle pagine è distinta dal completamento dell’attività

Le risposte delle query tipizzate sono suddivise in pagine. Un’attività di acquisizione aggiornata può completarsi anche se la query dispone ancora di una pagina successiva.

Senza `--all-pages`, controlla `next_cursor`. Quando è presente una pagina successiva, la CLI di alto livello restituisce `partial_success`, invece di dichiarare completata l’intera esplorazione.

```bash
healthmd query --category Sleep --last 90 --all-pages
```

`--all-pages` segue i cursori opachi, rileva le ripetizioni e applica un limite complessivo al numero di pagine e di byte. Se raggiungi il limite, restringi l’ambito oppure usa l’API di basso livello per consultare manualmente le pagine. Non esiste un limite nascosto al numero totale dei risultati, ma ogni singola esecuzione resta limitata.

## Copertura aggiornata, nella cache e riutilizzata

Per impostazione predefinita, i comandi di query di alto livello acquisiscono dati aggiornati dall’iPhone:

```bash
healthmd query --metric resting_heart_rate --last 30
```

Usa i dati nella cache soltanto se un contesto meno recente è accettabile:

```bash
healthmd query --metric resting_heart_rate --last 30 --cached
```

Usa `--reuse-covered` per evitare l’acquisizione solo dopo che Health.md ha verificato la copertura riepilogativa completa, specifica per le metriche, delle giornate richieste:

```bash
healthmd query --metric resting_heart_rate --last 30 --reuse-covered
```

Il riutilizzo non si applica ai dati senza perdita né alle operazioni appena introdotte che proiettano le sessioni di sonno. Non considera mai un provider diverso o un blocco di dati meno recente come prova del completamento aggiornato della richiesta.

## Esempio per la shell

L’esempio conserva il payload sanitario in un file protetto e mostra soltanto campi di stato sicuri. Presuppone che GNU `timeout` sia installato. Negli altri ambienti di automazione, applica una scadenza appropriata al processo.

```bash
#!/usr/bin/env bash
set -euo pipefail

output="${HOME}/Private/healthmd/sleep-week.json"
mkdir -p "$(dirname "$output")"
chmod 700 "$(dirname "$output")"

set +e
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output "$output" \
  </dev/null > /tmp/healthmd-command.json
exit_code=$?
set -e

if [ -s /tmp/healthmd-command.json ]; then
  jq '{status, job_id, error, message}' /tmp/healthmd-command.json
fi

if [ "$exit_code" -ne 0 ]; then
  echo "healthmd did not report complete success" >&2
  exit "$exit_code"
fi
```

Non attivare `set -x` in prossimità di un comando che potrebbe inviare dati sanitari JSON in streaming o includere percorsi sensibili.

## Comportamento dell’agente dopo un esito incerto

Un agente o un sistema di pianificazione deve procedere in quest’ordine:

1. Leggere l’errore strutturato e l’ID dell’attività.
2. Eseguire localmente `status --job`.
3. Verificare se l’attività è sospesa, definitiva, scaduta o in attesa di conferma.
4. Riaprire lo stesso iPhone quando servono dati aggiornati o una conferma.
5. Riprendere l’attività esistente con gli stessi backend e dispositivo.
6. Avviare una nuova attività soltanto dopo aver accertato l’esito precedente o averne accettato esplicitamente la scadenza.

Ripetere alla cieca un’operazione che modifica lo stato può duplicare il lavoro di origine, anche se il salvataggio dei file è idempotente.

## Errori comuni leggibili dalle macchine

| Codice | Significato | Risposta sicura |
|---|---|---|
| `timed_out` | Il comando ha smesso di attendere prima del completamento dell’attività | Controlla l’attività restituita e riprendila |
| `job_not_found` | Non esiste un record persistente locale con quell’ID | Controlla backend e directory dello stato prima di ricominciare |
| `job_expired` | È trascorso il termine fisso di sette giorni | Registra l’interruzione e, se opportuno, crea una nuova richiesta |
| `direct_export_paused` | L’attività diretta richiede di nuovo l’iPhone abbinato | Riapri l’iPhone e riprendi l’attività |
| `direct_cancellation_pending` | L’intenzione locale di annullare non è stata confermata dall’iPhone | Riapri l’iPhone e ripeti l’annullamento |
| `invalid_direct_raw_response` | La convalida rigorosa dei dati grezzi non è riuscita | Non usare l’output |
| `invalid_direct_file_receipt` | La convalida del manifesto o della ricevuta di salvataggio dei file non è riuscita | Non correggere o aggiungere file manualmente |
| `partial_canonical_extraction` | L’estrazione richiesta è incompleta | Controlla la ricevuta; accetta il risultato parziale solo intenzionalmente |
| `unvalidated_response_too_large` | Un risultato supera gli attuali limiti entro cui può essere esposto dopo la convalida | Restringi l’ambito o usa una modalità di output adeguata |
| `stale_cursor` | Il contesto crittografato è cambiato dopo la creazione del cursore della pagina | Riavvia la query sul corpus corrente |

## Avanzamento senza registrare il payload

Usa `--progress-json` per le fasi delle query di alto livello e l’esplorazione delle pagine:

```bash
healthmd query --category Sleep --last 30 \
  --all-pages --progress-json --output result.json \
  2> progress.jsonl
```

Il flusso JSONL dell’avanzamento può includere fase, numero di pagine, numero di elementi, date e dati diagnostici sicuri. Non deve includere valori sanitari. Tienilo separato dal risultato finale e applica comunque criteri di conservazione adeguati.

## Argomenti correlati

<div class="related">
  <a href="/it/docs/cli/"><span>Configurazione</span>CLI di Health.md: installazione, scelta del backend e output dei comandi.</a>
  <a href="/it/docs/cli-direct/"><span>Modalità diretta</span>CLI diretta per iPhone: abbinamento, periodo limitato in background, destinazione esplicita e ripresa attendibile.</a>
  <a href="/it/docs/agent-queries/"><span>Pagine</span>Ricettario delle query tipizzate: modalità aggiornata e cache, pagine, copertura e ricevute.</a>
  <a href="/it/docs/reference/generated/cli/exit-codes/"><span>Contratto generato</span>Codici di uscita della CLI: stati ed errori generati dagli strumenti di produzione.</a>
</div>
