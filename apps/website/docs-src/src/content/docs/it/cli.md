---
title: "CLI di Health.md"
description: "Scegli il backend dell’app per Mac o quello diretto per iPhone, installa healthmd, verifica la disponibilità, esporta file, estrai dati canonici di Apple Health, esegui query tipizzate e automatizza attività persistenti."
---

Il comando `healthmd` offre due modalità operative. Usa il backend dell’app per Mac per eseguire query locali crittografate, usare gli strumenti MCP o scrivere nella cartella di destinazione già selezionata in Health.md per Mac. Usa il backend diretto per iPhone per ottenere dati grezzi o file generati senza avviare l’app per Mac.

<div class="callout">
<strong>HealthKit resta sull’iPhone.</strong>
<p style="margin-top:6px;">Nessun backend della CLI legge Apple Health dal computer. Per ogni nuova lettura di HealthKit serve una versione aggiornata e aperta dell’app Health.md per iPhone. La CLI riceve risultati o file convalidati.</p>
</div>

## Scegliere un backend

| Funzionalità | Backend dell’app per Mac | Backend diretto per iPhone |
|---|---|---|
| Impostazione predefinita nell’helper per Mac incluso | Sì | No, selezionalo con `--backend direct` |
| Richiede Health.md per Mac aperta | Sì | No |
| Richiede Health.md aperta sull’iPhone per acquisire nuovi dati | Sì | Sì |
| Destinazione dei file | Cartella selezionata nell’app per Mac | Percorso assoluto esistente indicato con `--destination` |
| Esportazione rigorosa dei dati grezzi | Sì | Sì |
| `healthmd extract` canonico | Sì | Sì |
| Contesto crittografato, query tipizzate e dati di riscontro | Sì | No |
| `healthmd-mcp` | Sì | No |
| IP manuale o Tailscale | Sincronizzazione Mac o modalità diretta esplicita | Sì |
| Trasporto diretto Nearby | Solo helper Swift incluso | Non disponibile nel client Rust multipiattaforma |

Le scelte di backend e trasporto non prevedono passaggi automatici e silenziosi. Un comando diretto non può passare all’app per Mac per soddisfare una query e, se una connessione Nearby non riesce, non può passare a IP manuale.

## Installare gli helper per Mac inclusi

<div class="availability available">
<strong>Disponibile ora · Health.md per Mac</strong>
<p>L’app per Mac distribuita include gli helper Swift firmati per la CLI e MCP.</p>
</div>

Health.md per Mac include gli helper firmati `healthmd` e `healthmd-mcp`. Apri l’app per Mac e seleziona **CLI** per consultare i percorsi dell’installazione corrente, i comandi di configurazione, i prompt per gli agenti e il programma facoltativo per installare la skill dell’agente.

I normali percorsi nel pacchetto dell’app sono:

```text
/Applications/Health.md.app/Contents/Helpers/healthmd
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

Per una singola sessione della shell, usa gli alias:

```bash
alias healthmd="/Applications/Health.md.app/Contents/Helpers/healthmd"
alias healthmd-mcp="/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
```

In alternativa, crea collegamenti simbolici permanenti in una directory di eseguibili di proprietà dell’utente:

```bash
mkdir -p ~/.local/bin
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd" ~/.local/bin/healthmd
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp" ~/.local/bin/healthmd-mcp
```

Aggiungi `~/.local/bin` a `PATH` se non è già incluso nella configurazione della shell:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Verifica la CLI senza avviare il ciclo stdio di MCP:

```bash
healthmd --help
healthmd doctor
```

`healthmd doctor` restituisce un documento JSON `healthmd.cli_doctor` con la disponibilità del Mac, del contesto crittografato e dell’iPhone. Non mostra valori sanitari.

## Stato della CLI multipiattaforma

<div class="availability preview">
<strong>Anteprima · non ancora disponibile come pacchetto pubblico</strong>
<p>La CLI Rust multipiattaforma è in attesa dei test di rilascio su un iPhone fisico e del primo pacchetto qualificato.</p>
</div>

È in fase di sviluppo una CLI Rust autonoma, versione `0.1.0-alpha.1`. Funziona su macOS, Linux e Windows, usa per impostazione predefinita connessioni dirette tramite IP manuale o Tailscale e non richiede l’app per Mac. La compatibilità del protocollo e le fixture tra i diversi linguaggi sono già implementate, ma prima del rilascio pubblico restano da completare i test su un iPhone fisico e la preparazione dei pacchetti.

Fino al rilascio, usa l’helper incluso per Mac. Non fare affidamento su Homebrew, crates.io, programmi di installazione GitHub o URL di download non pubblicati.

Il client multipiattaforma supporta esportazione dei dati grezzi, estrazione canonica, abbinamento, stato, ripresa, annullamento e destinazioni dei file generati su tutti e tre i sistemi operativi. Nell’esportazione di file con il protocollo v1, l’iPhone considera la destinazione un’etichetta opaca, mentre la CLI ricevente la convalida e la vincola in modo persistente nel file system del computer.

## Elenco dei comandi

| Comando | Scopo | Backend |
|---|---|---|
| `healthmd status` | Controlla la disponibilità in tempo reale o una singola attività persistente locale | Entrambi |
| `healthmd doctor` | Spiega la disponibilità del Mac, del contesto crittografato e dell’iPhone | App per Mac |
| `healthmd metrics list` | Restituisce il catalogo canonico delle metriche interrogabili | App per Mac |
| `healthmd extract` | Acquisisce gli oggetti canonici `healthmd.health_data` selezionati | Entrambi |
| `healthmd query` | Acquisisce e interroga metriche tipizzate selezionate | App per Mac |
| `healthmd sleep sessions` | Restituisce sessioni di sonno complete e finestre temporali fisse | App per Mac |
| `healthmd training align` | Correla gli allenamenti con il sonno precedente e successivo | App per Mac |
| `healthmd workouts` | Elenca allenamenti tipizzati con i dati di riscontro | App per Mac |
| `healthmd coverage` | Controlla copertura o dati mancanti per date e metriche | App per Mac |
| `healthmd compare` | Confronta periodi esatti con l’aggregazione scelta dal chiamante | App per Mac |
| `healthmd evidence training` | Crea un pacchetto di dati di riscontro fattuali sull’allenamento | App per Mac |
| `healthmd export` | Scrive file generati o restituisce JSON grezzo sottoposto a convalida rigorosa | Entrambi |
| `healthmd resume` | Riprende un’attività di esportazione persistente e immutabile | Entrambi |
| `healthmd cancel` | Richiede un annullamento esplicito | Entrambi |
| `healthmd agent ...` | Chiama l’API di basso livello in loopback per query e attività | App per Mac |
| `healthmd direct ...` | Abbina, elenca e rimuove i rapporti di attendibilità diretti con l’iPhone | Diretto |

## Primo flusso di lavoro con l’app per Mac

1. Apri Health.md sul Mac e seleziona una cartella di destinazione se intendi scrivere file.
2. Apri Health.md sull’iPhone abbinato e attendi la connessione al Mac.
3. Controlla la disponibilità.
4. Esegui un comando circoscritto prima di richiedere una cronologia estesa.

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --metric sleep_total --yesterday
```

Le nuove query acquisiscono soltanto metriche, sorgenti e date indicate, con il livello di dettaglio riepilogativo o senza perdita richiesto. Non modificano le impostazioni di esportazione salvate sull’iPhone.

## Esportazioni di file e dati grezzi

```bash
# Use the Mac app's selected destination
healthmd export --iphone --yesterday
healthmd export --iphone --last 7
healthmd export --iphone --from 2026-07-01 --to 2026-07-07
healthmd export --iphone --all

# Return strict lossless canonical JSON without writing export files
healthmd export --iphone --yesterday --raw --output yesterday.json
healthmd export --iphone --all --raw --output complete-health-corpus.json

# Replace saved metric scope for this one file job
healthmd export --iphone --last 7 --category Sleep --detail summary

# Mirror saved iPhone settings, including roll-ups
healthmd export --iphone --yesterday --use-iphone-settings

# Run a saved export profile by UUID (frozen settings + destination)
healthmd export --iphone --last 7 --profile 11111111-2222-4333-8444-555555555555
```

`--profile PROFILE_ID` risolve un profilo di esportazione salvato sull'iPhone tramite il suo UUID stabile: l'esecuzione usa la selezione delle metriche, i formati e la destinazione congelati di quel profilo anziché le impostazioni attive dell'app. Non può essere combinato con `--use-iphone-settings` né con i selettori di metrica/categoria (il profilo possiede l'ambito delle impostazioni), e un UUID sconosciuto fallisce con un errore tipizzato `profile_not_found` invece di ripiegare sulle impostazioni attive. Leggi l'UUID dal selettore dei profili nella scheda Esporta dell'app.

Non esiste un limite predefinito al numero di giornate. `--all` chiede all’iPhone di individuare il primo record disponibile tra le sorgenti selezionate, fissa l’intervallo risultante e lo elabora in partizioni di dimensioni limitate. Lo spazio disponibile e una singola giornata insolitamente densa restano limiti pratici.

`--raw` richiede temporaneamente i record canonici di origine senza perdita, senza modificare le preferenze dell’iPhone. Non scrive file generati e non include i file complementari dei provider connessi.

## Estrazione canonica o query derivata?

Usa `extract` quando ti servono dati nella forma della sorgente:

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

Usa un comando di query quando ti serve una vista tipizzata collegata ai dati di riscontro:

```bash
healthmd sleep sessions --last-nights 14 --window first:4h
healthmd compare --metric steps:sum \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

`healthmd.health_data` v7 è il contratto pubblico dei dati di origine. Gli schemi relativi a query, dati di riscontro, attività e ricevute descrivono il trasporto o le viste derivate. Non sostituiscono lo schema di origine.

## Comportamento leggibile dalle macchine

Per impostazione predefinita, i comandi usano JSON con versione su stdout o nel percorso indicato esplicitamente con `--output`. L’estrazione canonica può usare JSONL, mentre le query di alto livello possono produrre intenzionalmente una tabella con informazioni ridotte. L’avanzamento privo di dati sanitari può essere scritto su stderr. `--help` restituisce testo semplice. Gli errori negli argomenti rilevati prima dell’avvio del comando sono scritti come testo semplice su stderr con codice di uscita 2.

Il codice di uscita zero del processo non basta a dimostrare che i dati sanitari siano completi. Controlla:

- lo stato esterno;
- lo stato dell’ambito richiesto;
- gli esiti per ogni giornata e query;
- gli intervalli mancanti;
- `next_cursor` o la ricevuta dell’esplorazione;
- lo schema e la versione della sorgente;
- limiti e avvisi.

Un risultato completo ma vuoto indica che Health.md ha rappresentato l’ambito richiesto senza trovare osservazioni. Non equivale a zero, mancante, non riuscito, ignorato o non supportato.

## Automazione sicura

Usa il timeout del processo fornito dal sistema di automazione e chiudi stdin per i comandi che non devono richiedere input. Nei sistemi che dispongono di GNU `timeout`:

```bash
NO_COLOR=1 TERM=dumb timeout 30 healthmd doctor </dev/null
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output sleep.json </dev/null
```

Timeout, Ctrl-C, chiusura del processo, perdita della rete e termine del periodo di esecuzione in background concesso da iOS non annullano un’attività persistente. Controlla l’ID dell’attività e riprendila, invece di avviarne una copia.

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
healthmd cancel JOB_UUID
```

L’annullamento diventa definitivo soltanto dopo la conferma dell’iPhone.

## Regole sulla riservatezza

L’output grezzo e senza perdita può contenere orari esatti, percorsi, record clinici, farmaci, stati d’animo, valori ECG, provenienza e allegati. Preferisci un file di output al terminale. Non incollare i payload in segnalazioni di problemi, trascrizioni degli agenti, registri CI o tracciamenti della shell.

L’API locale per le query non usa token bearer, registrazione, profili di accesso o un database di autorizzazioni. La raggiungibilità in loopback costituisce l’intero confine di accesso. Qualsiasi processo locale può usarla mentre l’app per Mac è aperta: non inoltrare né esporre mai la porta `17645` a un’altra macchina.

## Guide successive

<div class="related">
  <a href="/it/docs/cli-direct/"><span>Senza app per Mac</span>CLI diretta per iPhone: abbinamento, trasporti, esportazioni di dati grezzi e file, comportamento in background e compatibilità con le piattaforme.</a>
  <a href="/it/docs/cli-extract/"><span>Dati di origine</span>Estrazione canonica: seleziona metriche, oggetti, dettaglio, puntatori JSON, JSONL e ricevute.</a>
  <a href="/it/docs/cli-jobs/"><span>Automazione</span>Attività persistenti: timeout, ripresa, annullamento, risultati parziali e script sicuri.</a>
  <a href="/it/docs/agents/"><span>Agenti</span>Flussi di lavoro per agenti locali: contesto crittografato, ambito diretto, comandi tipizzati e dati di riscontro.</a>
  <a href="/it/docs/mcp/"><span>MCP</span>Configura l’helper stdio isolato e controlla i limiti dei suoi strumenti.</a>
  <a href="/it/docs/reference/api-and-cli/"><span>Contratto</span>Riferimento API e CLI: route esatte, schemi, risposte e fixture generate.</a>
</div>
