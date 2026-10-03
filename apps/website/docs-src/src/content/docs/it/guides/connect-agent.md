---
title: "Collega un agente in 10 minuti"
description: "Collega l'helper MCP per Mac di Health.md rilasciato a Codex o Claude, acquisisci un ambito esplicito dall'iPhone, esegui una query limitata e verifica la completezza in sicurezza."
---

<div class="availability available">
<strong>Disponibile ora · Health.md per Mac</strong>
<p>Questo percorso usa l'helper <code>healthmd-mcp</code> firmato incluso nell'app per Mac rilasciata. Non usa la preview portabile della CLI, Accesso CLI diretto, un codice QR di abbinamento né la porta 17647.</p>
</div>

Collegherai un host MCP locale, verificherai la preparazione senza leggere valori sanitari, aggiornerai esplicitamente un piccolo ambito dall'iPhone e interrogherai quel contesto Mac crittografato. Prevedi una decina di minuti quando entrambe le app sono già installate e sulla stessa rete locale.

## 1. Installa e apri Health.md

[Scarica Health.md dall'App Store](https://apps.apple.com/us/app/health-md/id6757763969) su Mac e iPhone. Apri entrambe le app.

HealthKit resta sull'iPhone. L'app per Mac ospita l'helper MCP firmato e un contesto di query crittografato e monouso; non legge HealthKit direttamente.

## 2. Collega iPhone e Mac

1. Sul Mac, lascia Health.md aperto.
2. Sull'iPhone, apri **Health.md → Sincronizzazione** e attiva la connettività con il Mac.
3. Mantieni entrambi i dispositivi sulla stessa rete locale raggiungibile e tieni Health.md in primo piano sull'iPhone mentre inizia un lavoro nuovo.
4. Conferma che l'app sul Mac mostri la connessione iPhone prevista. Altrimenti, riapri entrambe le app e consulta la [preparazione della sincronizzazione Mac](/it/docs/sync/).

Questa è la connessione Mac rilasciata. Non eseguire `healthmd direct pair`; quel comando appartiene alla preview portabile separata.

## 3. Copia il percorso dell'helper firmato

Apri **Health.md per Mac → CLI** e copia il percorso dell'helper MCP mostrato. Un'installazione normale in `/Applications` usa:

```text
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

Usa il percorso mostrato se l'app è installata altrove. Configura l'helper direttamente: non avvolgerlo in una shell e non avviarlo come comando interattivo.

## 4. Configura Codex o Claude

### Codex

Aggiungi questo a `~/.codex/config.toml`, sostituendo quando necessario il percorso dell'helper:

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

Riavvia Codex dopo aver salvato il file.

### Claude Desktop o Claude Code

Aggiungi questa voce stdio locale alla configurazione MCP di Claude Desktop o a un `.mcp.json` affidabile di Claude Code:

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

Riavvia Claude Desktop, oppure considera affidabile lo spazio di lavoro di Claude Code e approva il server. Mantieni attivi gli avvisi di approvazione per le operazioni di aggiornamento, esportazione, ripresa e annullamento.

## 5. Verifica la preparazione

Chiama `healthmd_doctor`. Legge solo la preparazione, senza valori sanitari.

Un risultato pronto contiene questi campi:

```json
{
  "schema": "healthmd.local_readiness",
  "schema_version": 1,
  "status": "ready"
}
```

Il risultato completo include anche controlli e azioni successive. Risolvi ogni controllo bloccante prima di continuare. Un helper connesso **non** dimostra che il contesto crittografato sia aggiornato.

Poi chiama `healthmd_metrics` e conferma l'ID metrica canonico e l'unità che intendi richiedere. Questa guida usa `steps` solo come esempio.

## 6. Aggiorna esplicitamente un piccolo ambito

Definisci le date che vuoi davvero, poi chiama `healthmd_refresh` con un intervallo esatto e inclusivo. L'esempio richiede un giorno di dati riepilogativi:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-14",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

Esamina gli argomenti, approva l'acquisizione e tieni entrambe le app aperte. L'aggiornamento non scrive file di esportazione e non modifica le impostazioni di esportazione salvate sull'iPhone. Conserva il `job_id` restituito finché l'attività non raggiunge uno stato terminale.

## 7. Esegui la prima query limitata

Al termine dell'aggiornamento, chiama `healthmd_metric_chart` con le stesse date, metrica, selezione delle fonti e livello di dettaglio:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-14",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "all_pages": true
}
```

`all_pages: true` percorre cursore opachi solo entro i massimi aggregati di pagine e byte dell'helper. Per il sonno, chiama `healthmd_sleep_sessions` invece di sostituire l'estrazione canonica.

## 8. Verifica la completezza prima di rispondere

Non considerare il successo di uno strumento come prova di una copertura sanitaria completa. Verifica tutto quanto segue:

- l'aggiornamento ha raggiunto uno stato terminale di successo per le stesse date esatte, metriche, fonti e livello di dettaglio;
- lo schema e la versione della risposta sono riconosciuti;
- l'intervallo richiesto e il fuso orario corrispondono alla domanda;
- ogni valore dichiarato conserva il proprio ID metrica canonico e l'unità;
- lo stato di copertura, i giorni considerati, i giorni con valori e ogni intervallo mancante vengono riportati;
- `complete_empty`, `partial`, `failed`, `unsupported`, `skipped` e `cancelled` non vengono convertiti in zero;
- il percorso è completato, oppure ogni cursore o massimo aggregato residuo viene dichiarato;
- i descrittori di evidenza e di fonte e le limitazioni restano allegati alla risposta;
- la direzione fattuale non diventa diagnosi, consiglio terapeutico, causalità o un linguaggio «meglio/peggio».

### Leggi i risultati parziali senza scartare dati utili

Una query tipizzata può restituire un `healthmd.query_response` valido mentre è completata solo una parte dell'ambito richiesto. Il [fixture generato di risposta parziale](/docs/reference/generated/automation/agent-query-response-partial.json) conserva un elemento Passi disponibile e riporta separatamente il giorno non riuscito:

```json
{
  "schema": "healthmd.query_response",
  "schema_version": 1,
  "coverage": {
    "status": "partial",
    "days_considered": 2,
    "days_with_values": 1,
    "missing": [
      {
        "status": "failed",
        "range": {
          "start_date": "2026-03-16",
          "end_date": "2026-03-16"
        }
      }
    ]
  },
  "items": ["one retained typed item"],
  "limitations": ["one or more requested days did not complete"]
}
```

Le stringhe dentro `items` e `limitations` sopra sono abbreviazioni esplicative; usa il fixture generato scaricabile per i campi e le evidenze esatti. Conserva insieme l'elemento mantenuto, l'intervallo non riuscito, i conteggi di copertura e la limitazione.

Non aggiungere `status: "partial_success"` a `healthmd.query_response`. Quello stato appartiene alle buste CLI e di esportazione di livello superiore quando acquisizione, percorso o generazione di file sono incompleti. Un timeout è un'altra cosa ancora: è un esito sconosciuto di un'attività persistente da ispezionare tramite ID attività.

I guasti strutturati usano `healthmd.query_error` v1 anziché una risposta parziale. Consulta [agent-query-error.json](/docs/reference/generated/automation/agent-query-error.json) per la forma di produzione generata, con codice stabile, messaggio, ritentabilità e dettagli tipizzati.

## 9. Recupera da un timeout in sicurezza

Un timeout, un host chiuso o un'attesa MCP annullata non annulla un aggiornamento accettato.

1. Conserva il `job_id` restituito.
2. Chiama `healthmd_job_status` con quell'ID.
3. Se l'attività immutabile è riprendibile, esamina e approva `healthmd_job_resume` con lo stesso ID e un timeout di attesa finito.
4. Avvia un nuovo aggiornamento solo dopo che lo stato dimostra che nessuna attività accettata può ancora completarsi.
5. Usa `healthmd_job_cancel` solo quando intendi terminare l'attività; l'annullamento è terminale solo dopo il riconoscimento dell'iPhone.

Non riprovare mai alla cieca dopo un esito sconosciuto. Le attività persistenti di aggiornamento conservano l'ambito accettato e il punto già confermato.

## Sei connesso

Il primo flusso di sola lettura è completo quando il doctor è pronto, l'aggiornamento esplicito è terminale, la query limitata ha un percorso completo e hai esaminato copertura, evidenze, unità e limitazioni.

Le esportazioni di file generati sono un flusso separato soggetto ad approvazione. Lo strumento Mac rilasciato scrive nella cartella già selezionata in Health.md per Mac; non accetta un argomento di destinazione arbitrario.

<div class="related">
  <a href="/it/docs/mcp/"><span>Catalogo degli strumenti</span>Rivedi tutti gli strumenti Mac rilasciati, gli schemi esatti, MCP Apps, la paginazione e i limiti di sicurezza.</a>
  <a href="/it/docs/configuration/"><span>Altri client</span>Scegli tra l'integrazione Mac rilasciata e la preview portabile chiaramente segnalata.</a>
  <a href="/it/docs/agent-queries/"><span>Prossime domande</span>Esegui flussi tipizzati per metriche, sonno, allenamenti, confronti, copertura ed evidenze.</a>
  <a href="/it/docs/agents/"><span>Modello di fiducia</span>Comprendi contesto crittografato, ambito delle richieste, conservazione, evidenze e regole di report.</a>
</div>
