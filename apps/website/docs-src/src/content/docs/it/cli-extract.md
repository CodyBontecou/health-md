---
title: "Estrazione canonica dei dati sanitari"
description: "Usa healthmd extract per acquisire metriche selezionate di Apple Health ed emettere documenti canonici con schema v8, record di origine, proiezioni mediante puntatori JSON o JSONL con ricevute esplicite."
---

`healthmd extract` è il comando per fornire dati di origine a script e agenti. Chiede all’iPhone di acquisire soltanto le metriche e il livello di dettaglio selezionati, convalida il trasferimento persistente, rimuove l’involucro di trasporto ed emette documenti canonici `healthmd.health_data` v8 o proiezioni chiaramente identificate.

L’estrazione canonica è una funzionalità di iPhone, supportata dal backend dell’app Mac e dal protocollo diretto v1 di iOS. Le sorgenti dirette di Android restituiscono invece snapshot Health Connect nativi del fornitore tramite l’[esportazione raw](/it/docs/cli-direct/).

Usa l’estrazione quando ti servono i dati originali di Health.md. Usa le [query tipizzate](/it/docs/agent-queries/) quando ti servono sessioni, confronti, correlazioni con gli allenamenti, copertura o pacchetti di dati di riscontro.

## Struttura di base

Un’estrazione richiede:

1. almeno un selettore per metrica, categoria, oggetto o `--all-metrics`;
2. un selettore per la data;
3. eventuali opzioni per dettaglio, oggetto, campo, formato, output, timeout e risultati parziali.

```bash
healthmd extract \
  (--metric ID | --category NAME | --object NAME | --all-metrics) ... \
  (--from DATE --to DATE | --last N | --yesterday | --all) \
  [--detail summary|lossless] \
  [--source apple_health] \
  [--field /JSON/POINTER] ... \
  [--format json|jsonl] \
  [--timeout 5...900] \
  [--allow-partial] \
  [--output PATH]
```

La sorgente attualmente disponibile per l’estrazione canonica è `apple_health`. I file complementari nel formato nativo dei provider mantengono i propri contratti e non vengono convertiti in valori Apple Health sintetici.

## Iniziare con una richiesta circoscritta

```bash
# One category, one day, summary detail
healthmd extract --category Sleep --yesterday --output sleep.json

# One metric for the last 30 complete days
healthmd extract --metric resting_heart_rate --last 30 \
  --output resting-heart-rate.json

# Every selected source object for one exact range
healthmd extract --all-metrics \
  --from 2026-07-01 --to 2026-07-07 \
  --detail lossless --output health-week.json
```

I nomi delle metriche e delle categorie vengono convalidati rispetto al catalogo corrente prima che inizi qualsiasi operazione sull’iPhone. Ripeti i selettori per combinarli.

```bash
healthmd extract \
  --metric sleep_total \
  --metric resting_heart_rate \
  --category Workouts \
  --last 14 --output recovery-context.json
```

## La selezione precede la lettura di HealthKit

L’estrazione non recupera un’esportazione salvata con tutte le metriche per poi ridurla. La CLI risolve il selettore in una `CanonicalHealthDataSelection` immutabile e la invia all’iPhone. Health.md controlla e legge soltanto i normali tipi HealthKit sui quali si basano le metriche selezionate.

Questa distinzione è importante per la riservatezza, le prestazioni e la completezza:

- le metriche non selezionate non vengono acquisite;
- le preferenze per le metriche salvate sull’iPhone non cambiano;
- le richieste di riepilogo non creano un archivio di origine nascosto;
- le richieste senza perdita acquisiscono soltanto i tipi di origine necessari alla selezione;
- la selezione entra a far parte dell’impronta della richiesta persistente.

I selettori per oggetti e puntatori JSON restringono i dati emessi dopo l’acquisizione. I selettori per metrica, categoria, origine e dettaglio restringono invece l’acquisizione stessa sull’iPhone.

## Dettaglio riepilogativo e senza perdita

Il riepilogo è l’impostazione predefinita:

```bash
healthmd extract --category Activity --last 7 --detail summary
```

L’output riepilogativo può includere riepiloghi giornalieri tipizzati, dati diagnostici delle query e `raw_capture_status: not_requested`. Quest’ultimo stato è esplicito: il comando non ha acquisito i record canonici di origine.

Richiedi il dettaglio senza perdita quando sono importanti oggetti di origine, UUID, orari esatti, provenienza o dati diagnostici dell’archivio:

```bash
healthmd extract --metric workouts --last 14 \
  --detail lossless --output workouts-lossless.json
```

Gli oggetti relativi all’archivio, come `records`, implicano il dettaglio senza perdita anche se `--detail` viene omesso.

## Selettori per gli oggetti

Usa `--object` per conservare una parte nota di ogni giornata selezionata. I nomi disponibili includono:

| Oggetto | Contenuto tipico |
|---|---|
| `sleep` | Campi del riepilogo giornaliero del sonno |
| `activity` | Passi, energia, distanza, esercizio e relativi riepiloghi delle attività |
| `heart` | Frequenza cardiaca, frequenza cardiaca a riposo, HRV e relativi riepiloghi |
| `vitals` | Pressione arteriosa, glicemia, temperatura, ossigeno e altri parametri vitali |
| `body` | Peso, composizione corporea, altezza e misure corporee |
| `nutrition` | Riepiloghi di nutrienti e idratazione |
| `mindfulness` | Sessioni di consapevolezza e riepiloghi sul benessere mentale |
| `mobility` | Campi relativi a cammino, andatura e mobilità |
| `hearing` | Campi relativi a esposizione sonora e udito |
| `reproductive-health` | Campi relativi a salute riproduttiva, gravidanza e ciclo |
| `cycling` | Riepiloghi delle attività in bicicletta |
| `vitamins` / `minerals` | Riepiloghi specifici per i nutrienti |
| `symptoms` | Dati sui sintomi |
| `medications` | Dati sui farmaci, quando disponibili e autorizzati |
| `workouts` | Oggetti canonici di riepilogo degli allenamenti |
| `archive` | Involucro canonico dell’archivio HealthKit |
| `records` | Record canonici di origine; implica il dettaglio senza perdita |
| `external-records` | Record esterni già presenti nella giornata pubblica |
| `query-results` | Esiti dell’acquisizione per ciascuna query |
| `warnings` | Avvisi relativi all’integrità |

Esempi:

```bash
healthmd extract --metric workouts --last 30 \
  --object workouts --output workout-summaries.json

healthmd extract --metric workouts --last 30 \
  --object records --detail lossless --output workout-records.json

healthmd extract --category Sleep --last 7 \
  --object sleep --object query-results --output sleep-with-status.json
```

## Proiezioni mediante puntatori JSON

Ripeti `--field` con puntatori JSON conformi a RFC 6901 per emettere valori esatti o voci di stato:

```bash
healthmd extract --category Sleep --last 7 \
  --field /sleep/totalDuration \
  --field /sleep/deepSleep \
  --field /raw_capture_status \
  --output selected-sleep-fields.json
```

I risultati dei puntatori sono proiezioni, non documenti giornalieri completi. Fanno riferimento allo schema e alla giornata di origine, ma non includono `schema: healthmd.health_data` in un modo che possa far apparire un sottoalbero come un’esportazione completa.

Se un percorso selezionato è assente, viene segnalato come completamente vuoto oppure con lo stato incompleto della giornata. Health.md non trasforma l’assenza in zero.

## Output JSON

L’output JSON predefinito contiene una delle raccolte seguenti:

- `health_data` per i documenti giornalieri canonici completi; oppure
- `projections` per i risultati relativi a oggetti o puntatori.

Contiene inoltre `healthmd.extract_receipt`, che registra:

- la selezione risolta e l’intervallo di date;
- la sorgente e il livello di dettaglio;
- gli esiti per ciascuna giornata;
- il numero di elementi conservati e di acquisizioni;
- le date mancanti;
- i dati diagnostici relativi a risultati parziali o non riusciti;
- lo stato di completamento dell’output.

La ricevuta è un metadato del protocollo. Non sostituisce lo schema di origine.

## Output JSONL

Usa JSONL per l’elaborazione in streaming:

```bash
healthmd extract --category Sleep --last 30 \
  --format jsonl --output sleep.jsonl
```

Ogni riga contiene un elemento di dati. La ricevuta non viene inserita nel flusso dei dati sanitari:

- con `--output`, viene scritta in `OUTPUT.receipt.json`;
- senza `--output`, viene scritta su stderr.

In questo modo le pipeline restano prevedibili:

```bash
healthmd extract --metric workouts --last 30 \
  --object workouts --format jsonl --output workouts.jsonl

jq -c 'select(.workouts != null)' workouts.jsonl
jq '{status, retained_item_count, missing_dates}' workouts.jsonl.receipt.json
```

Non reindirizzare stderr al parser JSONL: contiene la ricevuta e l’avanzamento privo di dati sanitari.

## Risultati completi, vuoti e parziali

Health.md distingue gli stati seguenti:

| Stato | Significato |
|---|---|
| `success` | Ogni ramo richiesto è stato completato, compresi quelli completi ma privi di dati |
| `complete_empty` | L’ambito richiesto è stato rappresentato e non conteneva osservazioni |
| `partial_success` | Alcuni dati richiesti sono stati conservati, ma almeno un ramo richiesto è incompleto |
| `failed` | Un ramo richiesto non è riuscito |
| `unsupported` | La piattaforma o HealthKit non supporta il ramo richiesto |
| `skipped` | Health.md ha intenzionalmente omesso la query per quel ramo |
| `cancelled` | L’iPhone ha confermato l’annullamento |
| `missing` | Una giornata o un ramo richiesto non è stato rappresentato |

Per impostazione predefinita, un’estrazione parziale non emette alcun dato conservato. Aggiungi `--allow-partial` soltanto se il sistema che riceve i dati è progettato per accettare e mantenere un ambito incompleto:

```bash
healthmd extract --category Sleep --last 30 \
  --allow-partial --output sleep-partial.json
```

L’opzione modifica il comportamento di emissione e il codice di uscita. Non rimuove i dati diagnostici e non trasforma dati parziali in dati completi.

## Backend dell’app per Mac e backend diretto

Il comando funziona con entrambi i backend:

```bash
# Bundled helper default: Mac app loopback and connected iPhone
healthmd extract --category Sleep --last 7 --output sleep.json

# Direct-capable helper: bypass the Mac app
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json
```

Entrambi i percorsi usano lo stesso schema giornaliero pubblico e la stessa convalida rigorosa. Cambiano il trasporto, l’abbinamento, l’archiviazione e i record delle attività. Entrambi i percorsi richiedono una sorgente iPhone; il backend diretto di Android non implementa l’estrazione canonica.

## Cronologie estese

`--all` non impone un limite fisso alle date:

```bash
healthmd extract --metric steps --all --output all-steps.json
```

L’iPhone individua il primo record selezionato disponibile, fissa ogni giornata secondo il calendario della sorgente fino a oggi e trasferisce partizioni di dimensioni limitate. La CLI assembla e convalida i dati su disco, invece di creare in memoria un’unica risposta senza limiti.

Per raccolte di grandi dimensioni, usa JSONL o una selezione più circoscritta. Lo spazio disponibile su disco e una singola giornata insolitamente densa restano limiti pratici.

## Promemoria sulla riservatezza

- Preferisci `--output` per qualsiasi risultato che contenga dati sanitari.
- Proteggi i file di output e le ricevute con la stessa attenzione riservata alla sorgente Apple Health.
- Non attivare la registrazione dei comandi della shell durante le operazioni sui dati sanitari.
- Evita di includere i payload nei registri CI e nelle trascrizioni degli agenti.
- Durante la risoluzione dei problemi, controlla soltanto ricevute, conteggi, stati, schema e campi relativi ai dati mancanti.
- Elimina le esportazioni temporanee dopo che il sistema destinatario le ha salvate in modo sicuro.

## Argomenti correlati

<div class="related">
  <a href="/it/docs/cli/"><span>CLI</span>CLI di Health.md: configurazione, scelta del backend, elenco dei comandi e regole per l’output.</a>
  <a href="/it/docs/agent-queries/"><span>Viste derivate</span>Ricettario delle query tipizzate: serie di metriche, sonno, allenamento, attività, confronti e dati di riscontro.</a>
  <a href="/it/docs/reference/daily-records/"><span>Schema</span>Record giornalieri: contratto completo dei documenti giornalieri con schema v8.</a>
  <a href="/it/docs/reference/canonical-healthkit-records/"><span>Archivio di origine</span>Record canonici di Apple Health: identità, provenienza, relazioni e payload.</a>
  <a href="/it/docs/reference/api-and-cli/"><span>Protocollo</span>Riferimento API e CLI: richieste di estrazione, ricevute, convalida rigorosa e codici di uscita.</a>
</div>
