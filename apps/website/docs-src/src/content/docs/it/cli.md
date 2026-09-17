---
title: "CLI di Health.md"
description: "Installa la CLI healthmd autonoma su macOS, Linux o Windows, abbinala direttamente a un iPhone o a un dispositivo Android, verifica la disponibilità, esporta dati, esegui query e gestisci attività persistenti. Nessuna app per Mac richiesta."
---

La CLI `healthmd` autonoma funziona su macOS, Linux e Windows e si abbina direttamente a un’app Health.md aperta su iPhone (protocollo v1) o Android (protocollo v2). Non richiede mai l’app Health.md per Mac, non prevede alcuna scelta di backend e non legge mai Apple Health o Health Connect dal computer.

<div class="callout">
<strong>I dati sanitari restano sul tuo telefono.</strong>
<p style="margin-top:6px;">La CLI non legge mai Apple Health o Health Connect dal computer. Per ogni nuova lettura dei dati sanitari della piattaforma serve una versione aggiornata e aperta dell’app Health.md su iPhone o Android. La CLI riceve risultati o file convalidati.</p>
</div>

## Installare la CLI autonoma

<div class="availability preview">
<strong>Anteprima pubblica · versione stabile qualificata non ancora disponibile</strong>
<p>La CLI Rust multipiattaforma è distribuita pubblicamente, ma la sua matrice mobile esatta attende ancora la qualifica fisica di rilascio.</p>
</div>

Su macOS o Linux, installa l’anteprima con <code>brew install CodyBontecou/tap/healthmd</code>. Usa la build mobile esatta indicata dalle evidenze di rilascio; la pubblicazione del pacchetto non dimostra la compatibilità mobile.

La CLI Rust autonoma funziona su macOS, Linux e Windows, usa connessioni dirette Manual IP o Tailscale e non richiede l’app per Mac. Si abbina alle sorgenti iPhone tramite il protocollo v1 e alle sorgenti Android tramite il protocollo v2, con controlli automatici di compatibilità Swift↔Rust e Kotlin↔Rust. La compatibilità dei protocolli è implementata; la QA di rilascio su dispositivi fisici deve concludersi prima della prima versione stabile qualificata. Archivi con somma di controllo, un installatore PowerShell e `cargo install healthmd-cli --locked` accompagnano ogni rilascio.

Il client multipiattaforma supporta abbinamento, stato, esportazione raw, destinazioni di file generati, ripresa e annullamento sulle tre piattaforme desktop per iPhone e Android. L’estrazione canonica e le query MCP tipizzate sono funzionalità di iPhone. Gli snapshot raw di Android conservano il contratto Health Connect nativo del fornitore invece di essere convertiti in dati in formato HealthKit. Le query tipizzate di Android non sono implementate. Per l’esportazione di file generati, il telefono tratta la destinazione come un’etichetta opaca; la CLI ricevente la convalida e la vincola in modo durevole al file system dell’host. Il protocollo Android v2 conferma le destinazioni dei file su ogni sistema operativo della CLI e limita ogni attività generata a 4.096 file.

## Elenco dei comandi

| Comando | Scopo |
|---|---|
| `healthmd status` | Ispezionare la disponibilità in tempo reale o un’attività locale persistente |
| `healthmd export` | Scrivere file generati o restituire JSON raw rigoroso |
| `healthmd extract` | Acquisire oggetti canonici `healthmd.health_data` selezionati (iPhone) |
| `healthmd query` | Eseguire operazioni di query tipizzate fisse (iPhone) |
| `healthmd resume` | Riprendere un’attività di esportazione persistente immutabile |
| `healthmd cancel` | Richiedere un annullamento esplicito |
| `healthmd direct ...` | Abbinare, elencare e rimuovere la fiducia diretta del telefono |
| `healthmd mcp ...` | Servire o ispezionare la superficie fissa degli strumenti MCP |
| `healthmd setup codex` | Configurare Codex e abbinare un iPhone in un unico flusso |

I comandi diretti si abbinano a sorgenti iPhone (protocollo v1) o Android (protocollo v2). L’`extract` canonico e ogni comando di query tipizzata sono funzionalità di iPhone; le sorgenti dirette di Android restituiscono snapshot raw Health Connect nativi del fornitore e file generati.

```bash
# Disponibilità e fiducia locale
healthmd status
healthmd direct devices

# Esportazione raw nativa della piattaforma; ometti --output per trasmettere JSON/NDJSON convalidato su stdout
healthmd export --yesterday --raw --output yesterday.json
healthmd export --last 7 --raw --output week.json

# Query tipizzata tramite lo stesso registro di operazioni di MCP (iPhone)
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'

# Estrazione canonica mirata (iPhone)
healthmd extract --category Sleep --last 7 --output sleep.json

# File generati in produzione su ogni sistema operativo della CLI
mkdir -p "$HOME/Documents/HealthVault"
healthmd export --yesterday --destination "$HOME/Documents/HealthVault"

# Operazioni persistenti
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --output resumed.json
healthmd cancel JOB_UUID
```

### Esportazione portatile di file basata su profilo

La CLI diretta autonoma può risolvere un profilo salvato su entrambe le piattaforme telefoniche supportate tramite il suo ID stabile. Il profilo fornisce le impostazioni di output congelate; la destinazione del computer resta esplicita:

```bash
mkdir -p "$HOME/Documents/HealthVault"
healthmd export --last 7 \
  --profile 11111111-2222-4333-8444-555555555555 \
  --destination "$HOME/Documents/HealthVault"
```

`--profile PROFILE_ID` non può essere combinato con `--use-device-settings` né con selettori di metriche/categorie, e un ID sconosciuto fallisce in modo sicuro invece di usare le impostazioni attuali. Copia l’ID da **Impostazioni → Profili di esportazione → ID profilo** su iPhone o Android. Consulta [Profili di esportazione](/it/docs/export-profiles/) per automazione e comportamento delle destinazioni.

Il client diretto multipiattaforma può richiamare qualsiasi operazione tipizzata di iPhone supportata senza involucro MCP:

```bash
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'
```

## Helper per Mac incluso

Health.md per Mac include i propri helper Swift firmati `healthmd` e `healthmd-mcp` dentro l’app. Quell’helper è una funzione dell’app per Mac, non un backend della CLI autonoma: per impostazione predefinita si rivolge al server loopback dell’app per Mac in esecuzione per query locali crittografate, strumenti MCP e la cartella di destinazione già selezionata in Health.md per Mac; offre inoltre una modalità diretta per iPhone compatibile, selezionata con `--backend direct`. I due client non cambiano mai modalità automaticamente.

<div class="availability available">
<strong>Disponibile ora · Health.md per Mac</strong>
<p>Gli helper Swift firmati per CLI e MCP sono inclusi nell’app per Mac pubblicata.</p>
</div>

Apri l’app per Mac e seleziona **CLI** per vedere i percorsi della tua copia installata, i comandi di configurazione, i prompt degli agenti e il programma di installazione opzionale delle skill degli agenti.

I percorsi normali del bundle dell’app sono:

```text
/Applications/Health.md.app/Contents/Helpers/healthmd
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

Usa alias per una sessione della shell:

```bash
alias healthmd="/Applications/Health.md.app/Contents/Helpers/healthmd"
alias healthmd-mcp="/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
```

Oppure crea collegamenti simbolici persistenti in una directory bin di proprietà dell’utente:

```bash
mkdir -p ~/.local/bin
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd" ~/.local/bin/healthmd
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp" ~/.local/bin/healthmd-mcp
```

Aggiungi `~/.local/bin` al `PATH` se la tua shell non lo include già:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Verifica l’helper senza avviare il ciclo stdio di MCP:

```bash
healthmd --help
healthmd doctor
```

`healthmd doctor` restituisce JSON `healthmd.cli_doctor` con la disponibilità di Mac, contesto crittografato e iPhone. Non stampa valori sanitari.

### Comandi dell’helper incluso

| Comando | Scopo |
|---|---|
| `healthmd export --iphone ...` | Scrivere file generati o restituire JSON raw rigoroso tramite l’app per Mac |
| `healthmd status` | Ispezionare la disponibilità Mac/iPhone o un’attività persistente |
| `healthmd doctor` | Illustrare la disponibilità di Mac, contesto crittografato e iPhone |
| `healthmd metrics list` | Restituire il catalogo canonico delle metriche interrogabili |
| `healthmd query` | Acquisire e interrogare metriche tipizzate selezionate |
| `healthmd sleep sessions` | Restituire sessioni di sonno di prima classe e finestre fisse |
| `healthmd training align` | Allineare gli allenamenti al sonno precedente e successivo |
| `healthmd workouts` | Elencare allenamenti tipizzati con evidenze |
| `healthmd coverage` | Ispezionare la copertura di date e metriche o i dati mancanti |
| `healthmd compare` | Confrontare periodi esatti con aggregazione scelta dal chiamante |
| `healthmd evidence training` | Costruire un pacchetto di evidenze di allenamento fattuale |
| `healthmd resume` / `healthmd cancel` | Gestire attività persistenti |
| `healthmd agent ...` | Chiamare l’API loopback di basso livello per query e attività |
| `healthmd --backend direct ...` | La modalità diretta per iPhone compatibile dell’helper |

Nella modalità diretta dell’helper, i sottocomandi di query, evidenza, doctor, metriche e aggiornamento del contesto Mac restituiscono `backend_unsupported` invece di passare all’app per Mac.

### Primo flusso di lavoro con l’app per Mac

1. Apri Health.md su Mac e seleziona una cartella di destinazione se prevedi di scrivere file.
2. Apri Health.md sull’iPhone abbinato e attendi la connettività con il Mac.
3. Verifica la disponibilità.
4. Esegui un comando ridotto prima di richiedere uno storico esteso.

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --metric sleep_total --yesterday
```

Le nuove query acquisiscono solo le metriche, le sorgenti, le date e il dettaglio di riepilogo o senza perdita forniti. Non modificano le impostazioni di esportazione salvate sull’iPhone.

### Esportazioni di file e dati grezzi dell’helper incluso

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
```

Attualmente non esiste un limite di giorni di calendario. `--all` chiede all’iPhone di individuare il record selezionato più antico disponibile, fissa l’intervallo risolto e lo elabora in partizioni limitate. Lo spazio di archiviazione disponibile e una giornata insolitamente densa restano limiti pratici.

`--raw` richiede temporaneamente record canonici senza perdita senza modificare la preferenza dell’iPhone. Non scrive file generati e non include gli allegati dei fornitori collegati.

## Estrazione canonica o query derivata?

Usa `extract` quando ti servono dati con la forma della sorgente:

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

Usa un comando di query quando ti serve una vista tipizzata collegata alle evidenze. La CLI autonoma espone operazioni tipizzate fisse; l’helper per Mac incluso offre in più i comandi di alto livello seguenti:

```bash
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"exact","range":{"start_date":"2026-07-22","end_date":"2026-07-28"}},"all_pages":true}'
healthmd compare --metric steps:sum \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

`healthmd.health_data` v8 è il contratto pubblico della sorgente Apple. Gli schemi di query, evidenza, attività e ricevuta descrivono viste di trasporto o derivate. Non sostituiscono lo schema della sorgente. L’estrazione canonica è una funzionalità di iPhone; le sorgenti dirette di Android espongono snapshot Health Connect nativi del fornitore tramite l’esportazione raw.

## Comportamento leggibile dalle macchine

I comandi usano per impostazione predefinita JSON con versione su stdout o nel percorso `--output` esplicito. L’estrazione canonica può emettere JSONL e le query di alto livello possono optare per una tabella deliberatamente con perdita. L’avanzamento senza dati sanitari può usare stderr. `--help` è testo semplice. Gli errori di argomento prima dell’avvio di un comando sono testo semplice su stderr con codice di uscita 2.

Un’uscita di processo riuscita non basta a dimostrare dati sanitari completi. Verifica:

- lo stato esterno;
- lo stato dell’ambito richiesto;
- gli esiti per giorno e per query;
- gli intervalli mancanti;
- `next_cursor` o la ricevuta di attraversamento;
- schema e versione della sorgente;
- limitazioni e avvisi.

Un risultato completamente vuoto significa che Health.md ha rappresentato l’ambito richiesto e non ha trovato osservazioni. Non equivale a zero, mancante, non riuscito, saltato o non supportato.

## Automazione sicura

Usa il timeout di processo del tuo host di automazione e mantieni stdin chiuso per i comandi che non devono richiedere input. Sui sistemi con `timeout` GNU:

```bash
NO_COLOR=1 TERM=dumb timeout 30 healthmd status </dev/null
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output sleep.json </dev/null
```

Timeout, Ctrl-C, la fine del processo, la perdita di rete e il tempo di background iOS esaurito non annullano un’attività persistente. Ispeziona l’ID dell’attività e riprendila invece di avviare un duplicato.

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
healthmd cancel JOB_UUID
```

Solo il riconoscimento dell’iPhone rende definitivo l’annullamento.

## Regole sulla riservatezza

L’output raw e senza perdita può contenere timestamp esatti, percorsi, cartelle cliniche, farmaci, voci di umore, valori ECG, provenienze e allegati. Preferisci un file di output all’output su terminale. Non incollare i payload in segnalazioni, trascrizioni di agenti, log CI o tracce della shell.

L’API di query locale dell’helper per Mac incluso non ha token bearer, registrazione, profilo di accesso né database di concessioni. La raggiungibilità in loopback è il suo intero confine di accesso. Qualsiasi processo locale può usarla mentre l’app per Mac è aperta; non fare mai proxy né esporre la porta `17645` a un’altra macchina.

## Guide successive

<div class="related">
  <a href="/it/docs/cli-direct/"><span>Senza app per Mac</span>CLI diretta dal telefono: abbinamento con iPhone o Android, trasporti, esportazioni raw e di file, comportamento in background e supporto delle piattaforme.</a>
  <a href="/it/docs/cli-extract/"><span>Dati sorgente</span>Estrazione canonica: selezionare metriche, oggetti, dettaglio, puntatori JSON, JSONL e ricevute.</a>
  <a href="/it/docs/cli-jobs/"><span>Automazione</span>Attività persistenti: timeout, ripresa, annullamento, risultati parziali e script sicuri.</a>
  <a href="/it/docs/agents/"><span>Agenti</span>Flussi di agenti locali: contesto crittografato, ambito diretto, comandi tipizzati ed evidenze.</a>
  <a href="/it/docs/mcp/"><span>MCP</span>Configura l’helper stdio isolato ed esamina il suo confine degli strumenti.</a>
  <a href="/it/docs/reference/api-and-cli/"><span>Contratto</span>Riferimento API e CLI: route esatte, schemi, risposte e fixture generati.</a>
</div>
