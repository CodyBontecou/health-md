---
title: "Server e app MCP di Health.md"
description: "Usa Codex o Claude per eseguire analisi mirate dei dati di Apple Health, generare grafici nativi e avviare esportazioni persistenti di Health.md tramite un'app MCP locale isolata."
---

Health.md per Mac include l'helper stdio firmato `healthmd-mcp`. Codex, Claude e altri host MCP possono usarlo per interrogare dati fattuali di Apple Health, generare visualizzazioni, aggiornare il contesto locale crittografato ed eseguire esportazioni persistenti approvate tramite l'app per Mac aperta.

```text
Codex / Claude / another local MCP host
  <-> MCP JSON-RPC over stdio
  <-> signed healthmd-mcp helper
  <-> Health.md Mac loopback API on 127.0.0.1:17645
  <-> connected iPhone for fresh HealthKit reads and exports
```

<div class="availability available">
<strong>Disponibile ora · Health.md per Mac</strong>
<p>Il server incluso espone 21 strumenti fissi. Non accede direttamente a HealthKit, alle cartelle di esportazione, ai segnalibri con ambito di sicurezza o a file arbitrari.</p>
</div>

<div class="availability preview">
<strong>Anteprima · MCP diretto multipiattaforma</strong>
<p>La topologia separata con 19 strumenti <code>healthmd mcp serve</code> per macOS, Linux e Windows è distribuita pubblicamente come anteprima esplicitamente non qualificata. Il comando senza cloud <code>serve-read-only</code> espone soltanto i 13 strumenti di verifica e query dopo l'abbinamento locale. Installa su macOS o Linux con <code>brew install CodyBontecou/tap/healthmd</code>.</p>
</div>

## Requisiti della versione integrata per Mac

- Health.md per Mac installata e aperta.
- Health.md aperta sull'iPhone connesso quando lo strumento di aggiornamento o un'esportazione avvia un nuovo lavoro HealthKit.
- Un host MCP locale che supporti stdio.
- Il percorso dell'helper firmato indicato in **Health.md per Mac → CLI**.

Il percorso abituale dell'helper è `/Applications/Health.md.app/Contents/Helpers/healthmd-mcp`. Le versioni supportate del protocollo MCP di base sono `2024-11-05`, `2025-03-26`, `2025-06-18` e `2025-11-25`. Non avviare `healthmd-mcp` come un normale comando interattivo: l'host MCP gestisce stdin e il ciclo di vita del processo.

## Requisiti della modalità diretta portatile

- Installa l’anteprima autonoma su macOS, Linux o Windows; l’app per Mac e il relativo servizio di loopback non sono necessari.
- Abbina una volta un iPhone con query e mantieni Health.md in primo piano per ogni nuova richiesta tipizzata. Android non supporta MCP tipizzato.
- Usa Manual IP o Tailscale e l’archivio credenziali nativo; Linux richiede un provider Secret Service sbloccato.
- Configura il launcher di compatibilità installato o il server stdio nello stesso binario. Entrambi usano il backend diretto abbinato.

## Configurazione di Codex

Aggiungi l'helper incluso a `~/.codex/config.toml`:

```toml
[mcp_servers.healthmd]
command = "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
args = []
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_files]
approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_job_resume]
approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_job_cancel]
approval_mode = "prompt"
```

Riavvia Codex, chiama `healthmd_doctor`, risolvi gli ID con `healthmd_metrics`, acquisisci esplicitamente un ambito piccolo ed esatto con lo strumento di aggiornamento, quindi interroga quell'ambito con `healthmd_metric_chart`. Gli host che non supportano app MCP interattive ricevono comunque il JSON esatto e un grafico PNG standard.

## Configurazione di Claude

Usa questa voce stdio locale nella configurazione MCP di Claude Desktop o in un file `.mcp.json` attendibile di Claude Code:

```json
{
  "mcpServers": {
    "healthmd": {
      "command": "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp",
      "args": []
    }
  }
}
```

Riavvia Claude Desktop dopo aver modificato la configurazione. Le configurazioni dei progetti Claude richiedono che l'area di lavoro sia considerata attendibile e che il server venga approvato esplicitamente.

Le versioni di Claude Desktop che dichiarano il supporto per l'estensione stabile MCP Apps mostrano la vista interattiva di Health.md direttamente nell'interfaccia. Claude Code e gli altri client basati soprattutto sul testo mantengono le alternative in formato JSON e immagine.

## Anteprima dell'MCP diretto multipiattaforma

Nell'anteprima pubblica autonoma, `healthmd setup codex` abbina un iPhone in primo piano e crea in modo sicuro una voce `healthmd mcp serve` eseguita dallo stesso binario. Questa topologia usa il trasporto IP manuale o Tailscale autenticato e crittografato sulla porta `17647`, l'archiviazione nativa delle credenziali e letture esplicite dall'iPhone per ogni richiesta. Su Linux è inoltre necessario un provider Secret Service sbloccato; Windows usa Credential Manager.

Usa la prerelease esatta `healthmd-cli/v<version>` invece del puntatore all'ultima release dell'intero repository. Consulta [CLI diretta per iPhone](/it/docs/cli-direct/) per il contratto di abbinamento e trasporto esplicitamente non qualificato.

## Visualizzazioni native dell'app MCP

Health.md implementa la negoziazione stabile `io.modelcontextprotocol/ui` con `text/html;profile=mcp-app`.

Quando un host dichiara questo tipo MIME, il server espone:

- `ui://healthmd/query-visualization-v1`;
- i metodi standard `resources/list` e `resources/read`;
- `_meta.ui.resourceUri` negli strumenti di analisi e nelle ricevute di esportazione;
- `structuredContent` convalidato insieme al testo JSON esatto.

La vista è una risorsa HTML5 autonoma senza rete, script remoti, font remoti, archiviazione o frame annidati. La CSP dichiarata contiene elenchi vuoti per i domini di connessione, risorse, frame e base. La vista segue il ciclo di vita standard di inizializzazione, risultato dello strumento, tema, ridimensionamento, annullamento e chiusura.

Può mostrare:

- grafici delle metriche con unità e intervalli di dati mancanti indicati esplicitamente;
- confronti tra periodi con l'aggregazione scelta dal chiamante;
- sessioni di sonno e riepiloghi della durata delle fasi;
- allenamenti e relazione temporale fattuale tra allenamento e sonno;
- copertura, intervalli mancanti, evidenze e limitazioni;
- ricevute della consultazione di tutte le pagine;
- avanzamento, destinazioni e ricevute delle esportazioni persistenti.

Gli strumenti funzionano anche se l'host non supporta MCP Apps. `healthmd_metric_chart` aggiunge contenuto `image/png` per gli host in grado di gestire immagini, conservando al contempo il JSON completo come testo.

## Strumenti disponibili

Il server incluso per Mac espone 21 strumenti fissi: 13 per verifica e query, quattro per le attività dei file generati e quattro per le attività di aggiornamento del contesto crittografato. L'anteprima multipiattaforma con 19 strumenti mantiene i 13 strumenti di verifica/query e i quattro di esportazione, sostituisce le attività di aggiornamento Mac con due strumenti di abbinamento diretto ed esegue le query tipizzate direttamente sull'iPhone in primo piano.

### Verifica e rilevamento

| Strumento | Scopo |
|---|---|
| `healthmd_status` | Verifica che l'app per Mac, il contesto, l'iPhone e l'esportazione siano pronti |
| `healthmd_doctor` | Diagnostica l'helper incluso e la topologia di loopback sul Mac |
| `healthmd_capabilities` | Elenca le funzionalità di query diretta, evidenze, esportazione, schema e paginazione |
| `healthmd_metrics` | Elenca ID metrica canonici, categorie, unità e requisiti |

### Analisi e visualizzazione

| Strumento | Scopo |
|---|---|
| `healthmd_metric_chart` | Interroga serie di metriche e genera grafici nativi con copertura e unità |
| `healthmd_sleep_sessions` | Elenca e visualizza sessioni di sonno stabili e copertura fisiologica |
| `healthmd_training_alignment` | Mostra la relazione temporale fattuale tra gli allenamenti e il sonno precedente o successivo |
| `healthmd_workouts` | Elenca e visualizza gli allenamenti |
| `healthmd_coverage` | Esamina la copertura per metrica e data e i dati mancanti |
| `healthmd_compare_periods` | Confronta periodi esatti con una semantica di aggregazione esplicita |
| `healthmd_training_evidence` | Crea un pacchetto di evidenze fattuali sull'allenamento |
| `healthmd_query` | Invia una richiesta `healthmd.query_request` esatta e, facoltativamente, consulta più pagine |
| `healthmd_evidence_packet` | Invia una richiesta di evidenze esatta e, facoltativamente, consulta più pagine |

### Esportazioni di file generati

| Strumento | Scopo |
|---|---|
| `healthmd_export_files` | Esegue un’esportazione persistente di file; il Mac integrato usa la cartella selezionata, mentre MCP diretto portatile richiede una destinazione esplicita sul computer |
| `healthmd_export_job_status` | Esamina l'avanzamento dell'esportazione e la ricevuta della destinazione |
| `healthmd_export_job_resume` | Riprende esattamente l'attività persistente e immutabile di esportazione |
| `healthmd_export_job_cancel` | Annulla esplicitamente l'attività di esportazione |

Gli strumenti di esportazione, ripresa e annullamento sono contrassegnati come scritture potenzialmente distruttive e richiedono un'interazione esplicita negli host Claude attuali, perché le modalità di esportazione configurate possono aggiornare o sovrascrivere i file generati. La configurazione di Codex riportata sopra richiede una conferma per questi strumenti come ulteriore misura di sicurezza.

### Attività di acquisizione del contesto crittografato · solo nella versione inclusa per Mac

| Strumento | Scopo |
|---|---|
| `healthmd_refresh` | Acquisisce dall'iPhone un ambito approvato e lo inserisce nel contesto crittografato temporaneo del Mac |
| `healthmd_job_status` | Esamina l'avanzamento dell'aggiornamento senza leggere valori sanitari |
| `healthmd_job_resume` | Riprende esattamente l'attività persistente di aggiornamento già accettata |
| `healthmd_job_cancel` | Annulla esplicitamente un'attività persistente di aggiornamento già accettata |

### Scoprire la struttura completa delle query

MCP `tools/list` include lo schema JSON annidato completo per date, metriche, fonti, paginazione, intervalli temporali, aggregazioni e la richiesta avanzata `healthmd.query_request`. Gli strumenti tipizzati includono anche esempi concreti. Un agente dovrebbe chiamare direttamente lo strumento tipizzato adatto, anziché consultare la guida generica della shell. In particolare, per le domande sul sonno va usato `healthmd_sleep_sessions`; `healthmd extract` produce una proiezione diversa dei dati di origine canonici.

L'anteprima multipiattaforma consente di esaminare lo stesso schema in locale senza aprire una porta di rete né contattare l'iPhone. Per l'helper Mac pubblicato, usa tools/list di MCP.

```bash
healthmd mcp schema healthmd_sleep_sessions
healthmd mcp schema healthmd_metric_chart
healthmd mcp schema # complete fixed catalog
```

Una chiamata minima per il sonno ha questa struttura (sostituisci le date inclusive con quelle della richiesta effettiva):

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-22",
      "end_date": "2026-07-28"
    }
  },
  "all_pages": true
}
```

Le metriche canoniche del sonno e i dettagli senza perdita delle sessioni vengono forniti automaticamente da `healthmd_sleep_sessions`.

## Analizzare e rappresentare i dati

Chiama prima `healthmd_doctor` e ricava gli ID metrica con `healthmd_metrics`. Nella topologia Mac pubblicata, gli strumenti di query tipizzati leggono il contesto Mac crittografato e non contattano implicitamente l'iPhone. Per dati aggiornati, chiama lo strumento di aggiornamento con date, metriche e fonti esplicite, attendi il completamento dell'attività persistente, quindi genera il grafico dello stesso ambito:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-01",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps", "resting_heart_rate"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "all_pages": true
}
```

Passa questo oggetto a `healthmd_metric_chart`. La vista interattiva usa piccoli multipli che rispettano le unità. Un punto mancante o parziale interrompe la linea anziché essere trasformato in zero.

Gli strumenti tipizzati Mac pubblicati valutano il contesto locale crittografato e restituiscono pagine limitate con copertura, dati mancanti, evidenze e limitazioni. Solo un aggiornamento esplicito contatta l'iPhone connesso in primo piano e sostituisce l'ambito di contesto richiesto. L'anteprima multipiattaforma valuta invece ogni richiesta tipizzata direttamente sul proprio iPhone abbinato in primo piano.

## Eseguire un'esportazione di file generati

Prima seleziona e conserva una cartella di destinazione scrivibile in Health.md per Mac. Dopo che l'host ha mostrato tutti gli argomenti e l'utente li ha approvati, chiama `healthmd_export_files`:

```json
{
  "date_selection": "explicit_range",
  "date_range": {
    "start": "2026-07-01",
    "end": "2026-07-07"
  },
  "settings_policy": "requested_dates_only",
  "categories": ["Sleep"],
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

Usa `date_selection: "all_available"` senza `date_range` per l'intera cronologia. I campi facoltativi `metric_ids`, `categories` o `all_metrics` limitano l'acquisizione dall'iPhone senza modificare le impostazioni salvate. `detail_level` si applica soltanto quando è presente una di queste selezioni. `all_metrics` non può essere combinato con elenchi espliciti di metriche o categorie.

Per eseguire invece un profilo salvato, imposta `settings_policy` su `"profile"` e passa `profile_reference` con l’UUID stabile. Nel protocollo pubblico, il `name` facoltativo fornisce contesto di visualizzazione e di errore. Le implementazioni attuali del telefono possono consultarlo se la ricerca dell’ID non riesce, ma tale comportamento non resiste alle rinomine; l’automazione deve trattare l’UUID come identità stabile:

```json
{
  "date_selection": "explicit_range",
  "date_range": { "start": "2026-07-01", "end": "2026-07-07" },
  "settings_policy": "profile",
  "profile_reference": { "profileID": "11111111-2222-4333-8444-555555555555" }
}
```

Il profilo possiede l'ambito delle impostazioni: `profile_reference` non può essere combinato con `metric_ids`, `categories`, `all_metrics` né con la politica delle impostazioni salvate, e un riferimento non risolvibile fallisce con un errore tipizzato invece di ripiegare sulle impostazioni attive.

Gli esempi precedenti usano la destinazione del Mac integrato. Con MCP diretto portatile, ogni richiesta di file richiede anche una cartella assoluta esistente sul computer in `destination`; il profilo del telefono fornisce le impostazioni di output, non quel percorso host:

```json
{
  "date_selection": "explicit_range",
  "date_range": { "start": "2026-07-01", "end": "2026-07-07" },
  "settings_policy": "profile",
  "profile_reference": { "profileID": "11111111-2222-4333-8444-555555555555" },
  "destination": "/absolute/existing/HealthVault",
  "wait_timeout_seconds": 300
}
```

La modalità diretta portatile rifiuta una destinazione assente, relativa, inesistente o simbolica prima di avviare l’attività sul telefono.

Controlla:

- `status` e lo `state` persistente;
- `job_id`;
- giorni elaborati e totali, oltre all'avanzamento;
- file o note giornaliere scritti;
- destinazione sul computer convalidata;
- partizioni confermate e byte;
- motivo della pausa o dell'errore e scadenza.

La scadenza dell'attesa MCP o la chiusura del client in attesa non annulla l'attività persistente. Controlla `healthmd_export_job_status` prima di riprendere dopo un esito sconosciuto. Soltanto un annullamento esplicito termina l'attività.

Il trasporto dei dati grezzi e canonici può contenere gigabyte di percorsi, testo clinico, allegati e record sorgente. Health.md evita intenzionalmente di inserire questi contenuti in una conversazione MCP. Usa la CLI di streaming convalidata per un output nella struttura dei dati di origine:

```bash
healthmd extract --metric workouts --last 30 --detail lossless --output workouts.json
healthmd export --iphone --all --raw --output health-corpus.json
```

L'analisi MCP rimane una vista fattuale derivata; le esportazioni di file generati continuano a usare il contratto pubblico `healthmd.health_data` tramite gli strumenti di esportazione di produzione.

## Paginazione e completezza

Gli strumenti di query e di evidenza espongono `all_pages: true` dove supportato. L'helper segue cursori opachi, rileva i cicli e applica limiti complessivi di byte e pagine, conservando ogni risposta versionata in `healthmd.mcp_query_pages` v1. Se viene raggiunto un limite della consultazione automatica, il wrapper parziale riuscito imposta `receipt.traversal_complete` su `false` e restituisce il valore esatto di `receipt.next_cursor` per continuare senza perdite. L'iPhone conserva un'istantanea compatta paginata per dieci minuti di inattività in primo piano e la elimina al termine della consultazione o quando passa in background. Ogni richiesta ha un limite di 366.000 giorni e 64 MiB per il contesto compatto codificato; `query_scope_too_large` indica che devi suddividere le date o gli ID metrica tra più chiamate, non che la cronologia logica non sia disponibile. Le pagine limitano gli elenchi degli intervalli mancanti e dei descrittori delle fonti tramite campi espliciti di conteggio e troncamento e relative limitazioni.

Il successo del trasporto non garantisce la completezza. Controlla sempre:

- ambito richiesto e stato del corpus;
- copertura e intervalli mancanti;
- limitazioni ed evidenze;
- `next_cursor` o ricevuta della consultazione;
- elementi ignorati non pertinenti;
- schema e versione della fonte.

L'app MCP mostra questi campi anziché nasconderli. Se la consultazione automatica raggiunge il limite di sicurezza, restringi l'ambito o continua manualmente.

## Perimetro di sicurezza e privacy

L'helper non offre prompt, radici, campionamento, shell, SQL, letture di file arbitrari, recupero di URL arbitrari, scritture HealthKit, servizi HTTP di loopback o endpoint MCP remoti. La sua unica risorsa MCP è il documento dell'app incluso. La scrittura di file generati è una singola operazione fissa soggetta ad approvazione. L'helper Mac pubblicato usa la cartella selezionata in Health.md per Mac; l'anteprima multipiattaforma richiede una destinazione esistente esplicita, che convalida e associa in modo persistente prima del trasferimento.

La relazione di fiducia diretta viene archiviata in Portachiavi, Secret Service o Windows Credential Manager. L'abbinamento usa il protocollo autenticato e crittografato esistente; l'iPhone deve essere in primo piano e connesso esplicitamente all'indirizzo LAN o Tailscale del computer. Le pagine delle query rispettano i limiti negoziati di byte ed elementi, mentre l'aggregazione automatica di tutte le pagine applica ulteriori limiti complessivi di byte e pagine. I contenuti grezzi senza limiti restano nel percorso CLI di streaming convalidato.

Health.md segnala osservazioni fattuali con unità, provenienza, copertura e dati mancanti. Non formula diagnosi, non consiglia trattamenti, non deduce rapporti causali e non definisce un andamento migliore o peggiore.

## Risoluzione dei problemi

| Sintomo | Azione |
|---|---|
| L'host non riesce ad avviare l'helper | Usa il percorso assoluto dell'eseguibile `healthmd` o `.exe` installato con gli argomenti `mcp serve` |
| L'helper rimane in attesa quando viene eseguito nel Terminale | È il comportamento previsto: un host MCP deve inviare JSON-RPC su stdin |
| `healthmd_not_paired` | Esegui `healthmd direct pair` e completa l'abbinamento sull'iPhone |
| `healthmd_unavailable` | Sblocca e porta Health.md in primo piano sull'iPhone, abilita Accesso CLI diretto e connettiti al computer |
| `query_scope_too_large` | Suddividi le date o gli ID metrica tra più chiamate; il corpus logico resta disponibile tra le richieste |
| Nessun grafico interattivo | Aggiorna l'host; il server restituisce comunque il JSON esatto e un grafico PNG alternativo |
| Destinazione di esportazione non disponibile | Mac: seleziona di nuovo la cartella salvata in Health.md. Anteprima multipiattaforma: crea e indica una cartella assoluta esistente sul computer che non sia un collegamento simbolico. |
| L'attesa dell'esportazione scade | Controlla l'attività persistente di esportazione tramite ID prima di riprenderla |
| Il risultato contiene `next_cursor` | Imposta `all_pages: true` oppure continua manualmente dal cursore |

## Contenuti correlati

<div class="related">
  <a href="/it/docs/agents/"><span>Architettura</span>Agenti locali, contesto crittografato, ambito delle richieste ed evidenze.</a>
  <a href="/it/docs/agent-queries/"><span>Analisi</span>Guida pratica alle query tipizzate per metriche, sonno, allenamenti, confronti e copertura.</a>
  <a href="/it/docs/cli-extract/"><span>Dati di origine</span>Estrazione canonica convalidata per risultati estesi nella struttura dei dati di origine.</a>
  <a href="/it/docs/reference/evidence-packets/"><span>Contratti</span>Valori tipizzati, dati mancanti, evidenze e identità dei pacchetti.</a>
</div>
