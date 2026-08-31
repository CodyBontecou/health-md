---
title: "Agenti locali e contesto sanitario"
description: "Collega gli agenti locali a Health.md tramite comandi CLI con ambito definito o MCP diretto per iPhone, conservando evidenze, copertura e dati mancanti."
---

Health.md offre agli agenti locali di sviluppo e automazione due modi per lavorare con i dati di Apple Health:

- la CLI `healthmd` per comandi espliciti da terminale ed estrazione canonica;
- `healthmd mcp serve` e la relativa app MCP per strumenti tipizzati, visualizzazioni native ed esportazioni approvate di file generati.

Il server MCP multipiattaforma comunica direttamente con l'iPhone in primo piano e non richiede Health.md per Mac. La CLI può usare lo stesso canale diretto per esportazioni grezze o canoniche, oppure l'API di loopback dell'app per Mac per i flussi di lavoro basati sull'indice del Mac. Le letture HealthKit avvengono sempre sull'iPhone e `healthmd.health_data` v8 resta il contratto pubblico dei dati di origine.

```text
local agent -> healthmd mcp serve -> authenticated encrypted port 17647 -> foreground iPhone
local agent -> healthmd CLI -> direct iPhone or optional Mac loopback workflow
```

## Operazioni disponibili per un agente

- verificare l'abbinamento diretto e lo stato operativo dell'iPhone in primo piano senza leggere valori sanitari;
- elencare ID metrica canonici e categorie;
- acquisire dall'iPhone un ambito esatto di metriche, fonti, date e dettagli;
- estrarre documenti giornalieri canonici o record sorgente;
- interrogare serie di metriche tipizzate con evidenze e copertura;
- ricostruire sessioni di sonno stabili e finestre di sonno fisse;
- allineare gli allenamenti con il sonno precedente e successivo;
- elencare gli allenamenti ed esaminare la copertura;
- confrontare periodi esatti con un'aggregazione esplicita;
- creare pacchetti di evidenze fattuali sull'allenamento;
- consultare un corpus logico senza limiti complessivi tramite richieste limitate;
- mostrare viste di metriche, sonno, allenamenti, confronti, copertura ed evidenze nelle app MCP;
- eseguire esportazioni approvate di file generati in una destinazione esistente ed esplicita sul computer;
- esaminare, riprendere o annullare attività persistenti di esportazione.

Health.md non formula diagnosi, non consiglia trattamenti, non deduce rapporti causali e non definisce un risultato sano, dannoso, migliore o peggiore.

## Configurare gli helper locali

<div class="availability preview">
<strong>Anteprima pubblica · non ancora una versione stabile qualificata</strong>
<p>Il pacchetto multipiattaforma è pubblicato come anteprima esplicitamente non qualificata. Usa la build mobile esatta indicata dalle prove di rilascio; l'helper firmato per Mac resta disponibile in <a href="/it/docs/configuration/">Configura il tuo agente</a>.</p>
</div>

1. Su macOS o Linux, esegui `brew install CodyBontecou/tap/healthmd`, quindi verifica `healthmd --version`.
2. Esegui `healthmd setup codex`: il comando configura Codex e avvia l'abbinamento se l'iPhone non è ancora attendibile.
3. Completa l'abbinamento in Accesso CLI diretto nell'app Health.md per iPhone e mantieni l'app in primo piano.
4. Per Claude o una configurazione manuale dell'host, indica il percorso assoluto di `healthmd` con gli argomenti `mcp serve`, come descritto in [Server e app MCP di Health.md](/it/docs/mcp/).
5. Se la configurazione è cambiata, riavvia l'host e chiama `healthmd_doctor`.

## Installare una skill per agenti

Per chi usa un Mac, l'app Health.md per Mac resta un metodo facoltativo di installazione e distribuzione della skill, non una dipendenza dell'MCP multipiattaforma.

La maggior parte degli utenti dovrebbe installare soltanto la [skill Health.md CLI per utenti su skills.sh](https://skills.sh/CodyBontecou/health-md/healthmd-cli):

```bash
npx skills add CodyBontecou/health-md@healthmd-cli
```

Il repository pubblico offre quattro skill specifiche per attività:

| Skill | Uso previsto |
|---|---|
| `healthmd-cli` | Query ed esportazioni CLI e MCP limitate e autorizzate dall'utente |
| `healthmd-cli-operator` | Operazioni dirette con iPhone e recupero dei job persistenti |
| `healthmd-cli-development` | Sviluppo di CLI, MCP, protocollo e servizio iPhone |
| `healthmd-cli-qa` | Validazione automatizzata e su dispositivi fisici |

Per installare una skill per collaboratori, sostituisci il nome dopo `@`; non installare istruzioni di sviluppo o QA per normali richieste di dati sanitari. Usa `npx skills add CodyBontecou/health-md --list` per esaminare il repository senza installare una skill e `npx skills update healthmd-cli --project --yes` per aggiornare la skill utente del progetto. La [guida all'installazione del repository](https://github.com/CodyBontecou/health-md/blob/main/docs/agents/skills.md) documenta tutti i comandi e il contratto di pubblicazione.

Una skill è un insieme di istruzioni. Non installa `healthmd` o `healthmd-mcp`, non configura MCP, non abbina un telefono, non concede accesso ai dati sanitari e non si aggiorna automaticamente. Esamina il codice sorgente prima dell'installazione.

Il programma di installazione della skill crea `healthmd-cli/SKILL.md` nella cartella approvata. Sostituisce soltanto la cartella della skill di Health.md. La skill illustra comandi con limiti espliciti, gestione dei risultati strutturati, regole di privacy, limiti di divulgazione relativi al fornitore del modello e recupero sicuro dopo esiti sconosciuti.

Se vuoi che un agente crei i collegamenti simbolici, usa il prompt di configurazione nell'app per Mac. Health.md non modifica silenziosamente i file di avvio della shell né `/usr/local/bin`.

## Verificare prima lo stato operativo

Nei client MCP multipiattaforma, chiama `healthmd_doctor`. Il comando verifica la relazione di fiducia diretta locale e l'iPhone connesso e in primo piano senza leggere valori sanitari, quindi restituisce errori operativi che non contengono dati sanitari. Ogni query MCP tipizzata costituisce poi una nuova richiesta esplicita a quell'iPhone: acquisisce soltanto l'ambito richiesto, valuta la query tipizzata sul dispositivo e restituisce pagine limitate.

Chi usa la CLI tramite loopback sul Mac può comunque eseguire `healthmd doctor` per ottenere lo stato operativo `healthmd.cli_doctor` v1, la copertura del contesto crittografato e le azioni successive.

## Ogni richiesta definisce il proprio ambito

Health.md non usa profili di accesso salvati, registrazioni dei chiamanti, registri delle autorizzazioni o credenziali CLI. Ogni richiesta specifica l'intero ambito dei dati necessario:

- ID metrica o categorie;
- selettori delle fonti Apple Health e degli eventuali provider;
- date esatte oppure tutte le date disponibili;
- dettagli di riepilogo o senza perdita;
- operazione di query;
- controlli limitati delle pagine.

La nuova acquisizione convalida l'ambito rispetto ai cataloghi correnti, lo conserva con l'attività persistente e lo applica sull'iPhone senza modificare le preferenze di esportazione salvate.

Una richiesta priva di una selezione di acquisizione esplicita viene rifiutata, anziché ereditare le normali impostazioni di esportazione dell'utente.

## Perimetri di autorizzazione

L'MCP multipiattaforma usa il protocollo diretto abbinato: archiviazione nativa delle credenziali, autenticazione reciproca della trascrizione, pacchetti crittografati, protezione dagli attacchi di replay e connessione dell'iPhone in primo piano all'indirizzo esplicito del computer. L'API di query facoltativa per Mac resta invece in ascolto soltanto sul loopback IPv4 e IPv6 e convalida che il peer appartenga al loopback.

Nella modalità facoltativa tramite loopback sul Mac, qualsiasi processo locale in grado di raggiungere la porta `17645` mentre l’app Health.md è aperta può inviare le stesse richieste di query. Considera l'accesso locale al computer come un'autorizzazione a eseguire query:

- non esporre la porta su un'interfaccia LAN e non usarla tramite proxy;
- non creare un tunnel verso un altro computer;
- non anteporre un reverse proxy HTTP;
- non configurare MCP con un URL esterno al loopback;
- controlla quali agenti locali possono eseguire l'helper.

Per compatibilità, i precedenti endpoint dei profili e delle attività restituiscono `410 removed_endpoint`.

## Dati canonici e viste derivate

Usa `healthmd extract` quando l'agente necessita di dati nella struttura della fonte o di un corpo grezzo o canonico esteso e convalidato:

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

Usa i comandi di query o gli strumenti MCP per viste derivate e visualizzazioni all'interno dell'host:

```bash
healthmd query --metric resting_heart_rate --last 30 --all-pages
healthmd sleep sessions --last-nights 14 --window first:4h
healthmd training align --last 14 --workout running --sleep-window first:4h
```

La distinzione è intenzionale:

| Superficie | Ruolo contrattuale |
|---|---|
| `healthmd.health_data` v8 | Documento sorgente giornaliero pubblico |
| `healthmd.healthkit_records` v1 | Archivio canonico dei record sorgente nei documenti giornalieri senza perdita |
| `healthmd.extract_receipt` | Metadati dell'ambito e del completamento dell'estrazione |
| `healthmd.query_context_day` v1 | Record temporaneo dell'indice crittografato |
| `healthmd.query_response` v1 | Risultato derivato, tipizzato e paginato |
| `healthmd.evidence_packet` v1 | Pacchetto fattuale collegato alle evidenze della fonte |
| Ricevute delle attività e della consultazione | Metadati di trasporto, persistenza e completamento |

Una proiezione o un risultato tipizzato non viene mai presentato come un documento sorgente giornaliero completo.

## Acquisizione di dati nuovi

Le query di alto livello acquisiscono dati nuovi per impostazione predefinita:

```bash
healthmd query --category Sleep --last 14
```

Health.md crea una richiesta dedicata per il contesto crittografato. Non scrive file di esportazione e non consuma la quota per l'esportazione di file. L'iPhone legge l'ambito esplicito, crea giorni compatti e deterministici associati al titolare e invia partizioni limitate e ripristinabili. Il Mac conferma ogni giorno crittografato prima di inviarne la conferma.

Il controllo del completamento verifica ogni metrica, fonte o provider e ogni giorno richiesti rispetto ai blob sostituiti dopo l'inizio dell'aggiornamento. I valori meno recenti nella cache e i dati di un altro provider non possono nascondere un'acquisizione non riuscita.

Le richieste che riguardano soltanto provider possono evitare HealthKit. La consultazione della cronologia del provider segue i cursori nativi del provider, senza imporre un limite fisso al numero complessivo di risultati.

## Contesto crittografato del Mac

Il Mac archivia una generazione crittografata in modo indipendente per ogni giorno associato al titolare. Una chiave casuale a 256 bit viene conservata nel Portachiavi come elemento accessibile soltanto su questo dispositivo e quando è sbloccato.

- i blob giornalieri e il manifesto usano AES-256-GCM;
- i nomi dei file sono UUID casuali, non date o nomi di metriche;
- le date associate al titolare e le voci dell'indice sono crittografate;
- i file hanno autorizzazioni riservate al titolare e sono esclusi dal backup;
- ogni conferma scrive una nuova generazione immutabile prima di sostituire il manifesto crittografato;
- la lettura si interrompe in sicurezza se mancano le chiavi, l'autenticazione non riesce, le date non sono valide o il manifesto non corrisponde.

L'archivio non prevede un limite complessivo configurato per metriche, giorni, cronologia o risultati. I comandi restano limitati perché decifrano un giorno alla volta e impaginano i risultati.

L'indice è temporaneo. Le esportazioni canoniche restano la fonte attendibile.

## Conservazione ed eliminazione

Health.md non elimina il contesto delle query secondo un periodo di conservazione implicito. Sul Mac, Impostazioni mostra il numero di giorni archiviati associati al titolare e l'intervallo di date.

Usa:

- **Elimina contesto meno recente** per rimuovere le date associate al titolare strettamente precedenti al limite selezionato;
- **Elimina tutto il contesto crittografato** per rimuovere ogni generazione crittografata e la chiave dedicata del Portachiavi.

L'eliminazione completa resta disponibile anche se la chiave o il testo cifrato sono danneggiati. La rimozione della chiave garantisce la cancellazione crittografica degli eventuali frammenti di testo cifrato non eliminati.

L'eliminazione del contesto delle query non elimina file di esportazione, credenziali dei provider connessi o dati di Apple Health.

## Valori tipizzati e dati mancanti

I valori delle query sono contrassegnati dal tipo. Un risultato può contenere una quantità e la relativa unità canonica, una durata, un conteggio con segno, una stringa, una categoria, un valore booleano, un timestamp UTC, una data di calendario, un array annidato o un futuro payload tipizzato non ancora noto.

I dati mancanti restano espliciti:

- `complete_empty` indica che nell'ambito rappresentato non esistono osservazioni corrispondenti;
- `partial` indica che è stata completata soltanto una parte dell'ambito richiesto;
- `failed`, `unsupported`, `skipped` e `cancelled` conservano significati distinti;
- `not_requested`, `legacy_unavailable`, `redacted` e `not_synchronized` restano distinti.

Health.md non converte mai un valore assente nello zero numerico. Uno zero reale viene codificato come valore tipizzato disponibile.

## Evidenze e linguaggio neutro

I risultati collegano i fatti a evidenze delle fonti quali:

- chiavi dei riepiloghi giornalieri;
- UUID canonici di HealthKit;
- identità esterne;
- esiti dei manifesti delle query;
- avvisi di integrità;
- errori parziali.

La risoluzione delle evidenze controlla insieme ID dell'evidenza, riferimento, schema della fonte, versione della fonte e digest della fonte.

La direzione del confronto tra periodi è limitata a `increased`, `decreased`, `unchanged` o `not_comparable`. L'allineamento degli allenamenti indica timestamp e intervalli, non effetti causali. I pacchetti di evidenze riportano osservazioni archiviate e copertura, non conclusioni mediche.

Un agente dovrebbe rispettare gli stessi limiti nella propria risposta: segnalare i dati mancanti, evitare di trasformare una correlazione in una causa e indirizzare le domande mediche a un professionista sanitario qualificato.

## Pagine limitate, accesso logico completo

Le pagine delle query usano `max_items`, `max_bytes` e un `next_cursor` opaco. Il contratto non impone un limite complessivo al numero di giorni, allenamenti, metriche o elementi dei risultati archiviati.

Un cursore è protetto da controlli di integrità e associato alla query semantica e alla revisione del corpus crittografato. Health.md rifiuta:

- un cursore modificato;
- un cursore usato con un'altra query;
- un cursore emesso prima di una modifica del corpus;
- un cursore ripetuto durante la consultazione automatica.

Usa `--all-pages` o `all_pages: true` di MCP per una consultazione automatica con limiti. Restringi l'ambito o avanza manualmente tra le pagine se una singola esecuzione raggiunge il limite di sicurezza complessivo.

## Lista di controllo per le risposte degli agenti

Quando riepiloga un risultato, l'agente deve indicare:

- il comando o lo strumento usato;
- date, metriche, fonte e livello di dettaglio richiesti esattamente;
- la modalità con dati nuovi, dalla cache o con riuso della copertura;
- separatamente, lo stato dell'ambito richiesto e quello del corpus;
- il completamento della pagina o dell'intera consultazione;
- unità ed evidenze delle fonti per ogni valore citato;
- intervalli mancanti, limitazioni ed elementi non pertinenti ignorati;
- l'ID dell'attività quando il lavoro è in pausa o può essere ripreso.

Non includere record grezzi, percorsi, testo clinico, dettagli sui farmaci, registrazioni dello stato d'animo o allegati, a meno che l'utente non richieda esplicitamente questi valori e ne comprenda la divulgazione.

## Scegliere un'integrazione

<div class="related">
  <a href="/it/docs/agent-queries/"><span>Guida CLI</span>Query tipizzate per agenti: metriche, sessioni di sonno, allineamento degli allenamenti, allenamenti, copertura, confronto ed evidenze.</a>
  <a href="/it/docs/mcp/"><span>Protocollo degli strumenti</span>Configurazione di Codex e Claude, 21 strumenti Mac pubblicati, 19 strumenti multipiattaforma in anteprima, grafici dell'app MCP, esportazioni, paginazione e limiti dell’ambiente isolato.</a>
  <a href="/it/docs/agent-api/"><span>Basso livello</span>API di query su loopback: endpoint, richieste JSON dirette, cursori e attività persistenti di acquisizione.</a>
  <a href="/it/docs/cli-extract/"><span>Oggetti sorgente</span>Estrazione canonica: documenti schema v8, record, proiezioni e ricevute selezionati.</a>
  <a href="/it/docs/reference/evidence-packets/"><span>Contratti</span>Query compatte e pacchetti di evidenze: valori tipizzati, copertura, operazioni e ID deterministici.</a>
</div>
