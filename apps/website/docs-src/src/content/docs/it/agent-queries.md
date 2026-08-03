---
title: "Guida pratica alle query tipizzate"
description: "Esegui query nuove o dalla cache di Health.md per metriche, sonno, allenamento, copertura, confronto tra periodi ed evidenze, con paginazione e dati mancanti espliciti."
---

I comandi CLI di alto livello trasformano le domande comuni sui dati sanitari in operazioni di query fisse e tipizzate. Per impostazione predefinita acquisiscono dall'iPhone i dati richiesti, interrogano il contesto crittografato del Mac e restituiscono JSON versionato con evidenze e copertura.

Se ti servono giorni completi `healthmd.health_data` o record sorgente, usa invece l'[estrazione canonica](/it/docs/cli-extract/).

## Verificare lo stato operativo e trovare le metriche

```bash
healthmd doctor
healthmd metrics list
healthmd metrics list --category Sleep
```

Il catalogo delle metriche restituisce ID canonici, nomi visualizzati, categorie, unità e requisiti di disponibilità. Non indica che l'autorizzazione HealthKit sia stata concessa per una determinata metrica.

Copia gli ID dal catalogo anziché provare a indovinarli.

## Interrogare le serie di metriche

```bash
healthmd query \
  --metric sleep_total \
  --metric sleep_deep \
  --from 2026-07-01 --to 2026-07-14 \
  --all-pages
```

Le categorie vengono espanse in base al catalogo corrente:

```bash
healthmd query --category Sleep --yesterday
healthmd query --category Heart --last 30 --all-pages
```

Puoi combinare più flag per metriche e categorie. La nuova acquisizione invia all'iPhone la selezione espansa senza modificare le impostazioni di esportazione salvate.

La risposta usa un involucro `healthmd.cli_metric_query` v1. Mantiene la diagnostica dell'acquisizione accanto alla risposta tipizzata annidata.

## Dati nuovi, cache e riuso della copertura

Per impostazione predefinita vengono richiesti dati nuovi:

```bash
healthmd query --metric resting_heart_rate --last 30
```

Il comando richiede l'ambito esatto all'iPhone connesso, conferma i giorni crittografati aggiornati associati al titolare e infine li interroga.

La modalità cache non contatta l'iPhone:

```bash
healthmd query --metric resting_heart_rate --last 30 --cached
```

Usa la modalità cache per l'analisi offline soltanto se l'ora di acquisizione e la copertura archiviate sono adeguate.

`--reuse-covered` controlla prima la copertura del riepilogo crittografato:

```bash
healthmd query --metric resting_heart_rate --last 30 --reuse-covered
```

Health.md salta l'acquisizione soltanto quando ogni metrica e ogni giorno richiesti hanno una copertura di riepilogo completa e compatibile. Le richieste senza perdita e le nuove operazioni che ricostruiscono le sessioni di sonno non usano questa scorciatoia.

## Comprendere i campi di completamento

Le risposte alle query con dati nuovi distinguono tre concetti:

| Campo | Domanda a cui risponde |
|---|---|
| `requested_scope_status` | Sono state completate tutte le metriche, le fonti, i provider e le giornate richiesti per questa acquisizione? |
| `corpus_status` | Altri rami del corpus acquisito hanno segnalato avvisi, elementi ignorati o errori? |
| `unrelated_skips` | Quali rami ignorati o non supportati non facevano parte dell'ambito richiesto? |

Un ambito richiesto completo può coesistere con elementi non pertinenti ignorati nel corpus. Health.md conserva entrambe le informazioni, senza declassare erroneamente il risultato richiesto né nascondere la diagnostica del corpus.

Per le acquisizioni nuove, il completamento conta soltanto i blob sostituiti dopo l'inizio dell'aggiornamento. I valori obsoleti nella cache non possono far risultare riuscita una richiesta non completata.

## Consultare tutte le pagine dei risultati

Senza `--all-pages`, il comando restituisce una sola pagina limitata. Controlla `next_cursor`:

```bash
healthmd query --category Activity --last 365 --output activity-page-1.json
jq '.query.next_cursor' activity-page-1.json
```

Un cursore non nullo indica che esistono altri risultati. Lo stato esterno di alto livello resta `partial_success` finché la consultazione non è completa.

La consultazione automatica segue cursori opachi e verifica che non si ripetano:

```bash
healthmd query --category Activity --last 365 \
  --all-pages --output activity-all-pages.json
```

La risposta conserva il primo `healthmd.query_response` in `query`, le risposte versionate successive in `pages` e una ricevuta `healthmd.cli_query_receipt` v1 con il numero di pagine, elementi, fatti ed evidenze, oltre allo stato finale della consultazione.

La consultazione automatica applica un limite complessivo di pagine e byte. Se lo raggiungi, restringi l'intervallo di date o la selezione delle metriche oppure usa l'[API di basso livello](/it/docs/agent-api/) per avanzare manualmente tra le pagine.

## Avanzamento e output tabellare

Scrivi su stderr, in formato JSONL e senza dati sanitari, l'avanzamento delle fasi e delle pagine:

```bash
healthmd query --category Sleep --last 90 \
  --all-pages --progress-json --output sleep.json \
  2> sleep-progress.jsonl
```

Il JSON costituisce l'output completo. La modalità tabellare è una vista TSV con perdita di informazioni, da attivare esplicitamente per la consultazione nel terminale:

```bash
healthmd query --metric resting_heart_rate --last 30 --format table
```

Il piè di pagina conserva le note su copertura, fonte, limitazioni, completamento ed elementi non pertinenti ignorati. Non usare l'output tabellare se uno script richiede valori tipizzati esatti o evidenze.

## Sessioni di sonno

Le fasi del sonno di Apple Health possono superare la mezzanotte e sovrapporsi tra fonti. Il comando per il sonno ricostruisce sessioni stabili, anziché trattare ogni giorno associato al titolare come un unico totale numerico.

```bash
healthmd sleep sessions --last-nights 14
healthmd sleep sessions --last-nights 14 --include-naps
healthmd sleep sessions --last-nights 14 \
  --window first:4h --physiology-metric heart_rate
```

Sono disponibili anche date esatte e l'intera cronologia:

```bash
healthmd sleep sessions \
  --from 2026-07-01 --to 2026-07-14 \
  --window first:3h --all-pages

healthmd sleep sessions --all --all-pages
```

Ogni sessione può indicare:

- un'identità stabile della sessione;
- la data associata al titolare e il fuso orario locale;
- i timestamp esatti di inizio e fine, locali e UTC;
- la classificazione come sonno notturno o pisolino;
- i totali delle fasi selezionate;
- la durata osservata e quella non monitorata;
- completezza ed esclusioni;
- una finestra fissa relativa alla sessione;
- la copertura fisiologica nei giorni adiacenti;
- le evidenze delle fonti.

L'acquisizione delle sessioni richiede gli intervalli canonici senza perdita delle fasi del sonno e l'insieme completo delle metriche canoniche delle fasi. Health.md legge al massimo un giorno tecnico adiacente per stabilire i confini, quindi esclude dal risultato le date non pertinenti.

Le fasi sovrapposte provenienti da fonti diverse vengono deduplicate nel calcolo della durata totale del sonno. Il contesto nella cache che contiene soltanto dati aggregati è contrassegnato come `aggregated` e non dichiara una copertura osservata degli intervalli. Una finestra fissa `first:4h` non ripartisce mai su quattro ore un valore aggregato giornaliero.

## Allineare allenamenti e sonno

```bash
healthmd training align --last 14
healthmd training align --last 14 --workout running
healthmd training align --last 14 --workout running \
  --sleep-window first:4h \
  --physiology-metric heart_rate \
  --all-pages
```

Per ogni allenamento selezionato, Health.md individua entro 36 ore le sessioni di sonno idonee più vicine, precedente e successiva. Indica:

- ID stabili dell'allenamento e delle sessioni;
- intervalli temporali esatti;
- finestre di sonno richieste;
- numero di campioni fisiologici;
- copertura delle fasi e delle sessioni;
- evidenze ed esclusioni.

L'operazione esegue un allineamento temporale deterministico. Non sostiene che un allenamento abbia causato un determinato sonno, né che il sonno abbia causato una determinata prestazione. Legge al massimo due giorni tecnici adiacenti e non restituisce dati non pertinenti.

## Elencare gli allenamenti

```bash
healthmd workouts --yesterday
healthmd workouts --last 14 --all-pages
healthmd workouts \
  --from 2026-07-01 --to 2026-07-31 \
  --format table
```

L'elenco conserva identità stabili, timestamp esatti, dettagli tipizzati, evidenze e dati mancanti. I risultati sono ordinati per timestamp di inizio e identità stabile dell'allenamento. Non esiste un limite complessivo fisso al numero di allenamenti; i controlli delle pagine limitano ogni risposta.

## Copertura

Usa la copertura quando la domanda è "Quali dati sono disponibili?" anziché "Qual è il valore?".

```bash
healthmd coverage --category Sleep --last 30
healthmd coverage \
  --metric steps --metric resting_heart_rate \
  --from 2026-01-01 --to 2026-06-30 \
  --all-pages
```

La copertura restituisce gli intervalli richiesti e disponibili, i giorni considerati, i giorni con valori e gli intervalli mancanti corredati dal relativo stato. Gli intervalli adiacenti con lo stesso stato e motivo possono essere compressi senza perdere informazioni.

Un giorno privo di osservazioni corrispondenti può essere `complete_empty`. Un giorno mai sincronizzato ha uno stato diverso. Nessuno dei due viene trasformato in zero.

## Confrontare periodi esatti

La CLI non presume mai che una metrica debba essere sommata, mediata, ridotta al minimo o al massimo, conteggiata oppure rappresentata dal valore più recente. Indica l'aggregazione accanto a ogni ID metrica:

```bash
healthmd compare \
  --metric steps:sum \
  --metric resting_heart_rate:average \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

Le aggregazioni supportate sono:

- `sum`
- `average`
- `minimum`
- `maximum`
- `latest`
- `count`
- `duration_sum`

Una mancata corrispondenza di unità o tipo genera un errore anziché essere combinata automaticamente. Un periodo mancante non ha un valore aggregato. Se il valore di riferimento del primo periodo è zero, è disponibile una variazione assoluta ma non percentuale e tra le limitazioni compare `zero_baseline`.

La direzione è puramente fattuale: `increased`, `decreased`, `unchanged` o `not_comparable`. Non indica mai che il risultato sia migliore o peggiore.

## Pacchetti di evidenze sull'allenamento

```bash
healthmd evidence training \
  --category Sleep \
  --metric resting_heart_rate \
  --last 14 \
  --all-pages
```

Richiedi dettagli specifici degli allenamenti soltanto quando servono:

```bash
healthmd evidence training \
  --category Sleep \
  --workout-detail distance \
  --workout-detail duration \
  --last 14 --all-pages
```

La selezione dei dettagli dell'allenamento richiede l'ambito senza perdita necessario per quella richiesta. Il pacchetto contiene valori fattuali, copertura, descrittori delle fonti, riferimenti alle evidenze e limitazioni.

Gli ID dei pacchetti sono digest SHA-256 deterministici del contenuto semantico. Se rigeneri lo stesso pacchetto in un altro momento, l'ID semantico non cambia, anche se possono cambiare i metadati di generazione.

I tipi di pacchetto previsti dal contratto v1 includono `daily_wellness`, `training` e `doctor_visit`. Il comando pratico di alto livello espone attualmente il pacchetto di allenamento. Per corpi di richiesta esatti, usa l'API di basso livello.

## Attribuzione delle date e fuso orario

Le date delle query sono valori `owner_date` del contesto compatto. Ogni giorno conserva anche l'intervallo UTC semiaperto esatto e il fuso orario di calendario IANA acquisito con cui è stato definito.

Le sessioni di sonno conservano timestamp locali e date che superano la mezzanotte. Le letture tecniche dei giorni adiacenti consentono a una sessione di attraversare il confine tra giorni associati al titolare senza spostare i dati in base al fuso orario corrente del Mac.

Quando rivolgi a un agente una domanda sensibile alle date, specifica le date desiderate associate al titolare e controlla il fuso orario restituito, anziché presumere che coincida con quello del computer.

## Non nascondere i dati mancanti nella risposta di un agente

Un riepilogo affidabile dovrebbe conservare:

- ID metrica e unità canonica;
- intervallo di date e fuso orario;
- modalità con dati nuovi, dalla cache o con riuso della copertura;
- stato dell'ambito richiesto e stato del corpus;
- completamento della consultazione delle pagine;
- riferimenti alle evidenze o digest della fonte;
- intervalli completamente vuoti e intervalli mancanti;
- avvisi, limitazioni ed elementi non pertinenti ignorati.

Non escludere i giorni non riusciti dal calcolo di una media, non trattare l'assenza come zero e non descrivere un allineamento temporale come un rapporto causale.

## Contenuti correlati

<div class="related">
  <a href="/it/docs/agents/"><span>Architettura</span>Agenti locali e contesto sanitario: configurazione, crittografia, ambito delle richieste, evidenze e conservazione.</a>
  <a href="/it/docs/mcp/"><span>MCP</span>Helper MCP locale: strumenti tipizzati equivalenti per query, sonno, allineamento, allenamenti, copertura, confronto ed evidenze.</a>
  <a href="/it/docs/agent-api/"><span>Contratti grezzi</span>API di query su loopback: richieste esatte, risposte di una pagina, aggiornamento ed endpoint delle attività.</a>
  <a href="/it/docs/reference/evidence-packets/"><span>Riferimento</span>Query compatte e pacchetti di evidenze: valori tipizzati, cursori, operazioni, copertura e ID.</a>
</div>
