---
title: "API di query su loopback"
description: "Chiama tramite HTTP o il comando di basso livello healthmd agent gli endpoint locali e versionati di Health.md per query, evidenze, aggiornamento, verifica, metriche e attività persistenti."
---

Health.md per Mac espone un'API locale versionata in `/v1/agent/`. L'API gestisce query sul contesto crittografato, pacchetti di evidenze, acquisizioni dall'iPhone con ambito limitato alla richiesta, verifica dello stato operativo e attività persistenti di acquisizione.

L'API resta in ascolto sul loopback alla porta `17645`. Accetta soltanto peer loopback IPv4 o IPv6 convalidati.

<div class="callout">
<strong>Non esporre questa porta.</strong>
<p style="margin-top:6px;">Non sono previsti token bearer, registrazioni dei chiamanti, profili di accesso o database delle autorizzazioni. La raggiungibilità tramite loopback costituisce l'intero perimetro di autorizzazione. Qualsiasi processo locale può inviare richieste mentre l’app Health.md è aperta.</p>
</div>

## Endpoint

| Metodo | Endpoint | Scopo |
|---|---|---|
| `GET` | `/v1/agent/capabilities` | Elenca schemi versionati, ambiti supportati e limiti delle pagine |
| `GET` | `/v1/agent/metrics` | Restituisce ID metrica canonici interrogabili, categorie, unità e requisiti |
| `GET` | `/v1/agent/readiness` | Restituisce lo stato operativo del contesto crittografato e dell'iPhone per nuove letture, con le azioni successive |
| `POST` | `/v1/agent/query` | Esegue una pagina limitata di una query tipizzata |
| `POST` | `/v1/agent/evidence` | Ricava una pagina limitata di un pacchetto di evidenze fattuali |
| `POST` | `/v1/agent/refresh` | Acquisisce dall'iPhone un ambito esplicito nel contesto crittografato del Mac |
| `GET` | `/v1/agent/jobs/{id}` | Esamina un'attività persistente locale di acquisizione |
| `POST` | `/v1/agent/jobs/{id}/resume` | Riprende la richiesta immutabile di acquisizione |
| `POST` | `/v1/agent/jobs/{id}/cancel` | Richiede l'annullamento esplicito |

I precedenti endpoint `/v1/agent/profiles` e `/v1/agent/activity/query` restituiscono `410 removed_endpoint`.

Il backend diretto per iPhone non ospita questi endpoint HTTP. Il comando autonomo `healthmd` usa tale backend per l'estrazione canonica e l'esportazione, mentre `healthmd mcp serve` implementa direttamente, tramite il protocollo di query v3 dell'iPhone, strumenti per nuove query tipizzate, evidenze, catalogo delle metriche, verifica, visualizzazioni ed esportazioni persistenti. L'abbinamento e il server MCP usano la stessa identità dell'eseguibile; l'aggiornamento e il contesto crittografato del Mac restano specifici di questa API HTTP.

## Preferire l'adattatore CLI

La CLI di basso livello conserva esattamente i corpi delle richieste e gestisce gli errori del trasporto su loopback:

```bash
healthmd agent capabilities
healthmd agent query --input query-body.json
healthmd agent query --input - < query-body.json
healthmd agent evidence --input evidence-body.json
healthmd agent refresh --input refresh-body.json
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
healthmd agent job cancel JOB_UUID
```

Per un corpo breve, usa `--json JSON` al posto di `--input`. La CLI non amplia né restringe automaticamente il JSON fornito a questi comandi.

Per i flussi di lavoro comuni, usa comandi di alto livello come `healthmd query`, `healthmd sleep sessions` o `healthmd compare`. Convalidano i selettori e costruiscono l'operazione tipizzata.

## Corpo della query

`POST /v1/agent/query` accetta al livello principale soltanto `request` e il campo facoltativo `detail_level`:

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "metric_series"
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144
    }
  },
  "detail_level": "summary"
}
```

I campi wrapper sconosciuti vengono rifiutati. Il contratto della richiesta di query definisce metriche, fonti, date, operazione e controlli delle pagine. `detail_level` può essere `summary` o `lossless`.

La risposta è `healthmd.query_response` v1. Contiene elementi tipizzati, copertura, evidenze, descrittori delle fonti, limitazioni e l'eventuale `next_cursor`.

Consulta una risposta sintetica completa in [`agent-query-response.json`](/docs/reference/generated/automation/agent-query-response.json).

## Continuare da un cursore

Per richiedere la pagina successiva, invia la stessa richiesta semantica e inserisci il cursore restituito in `page.cursor`:

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "metric_series"
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144,
      "cursor": "OPAQUE_CURSOR_FROM_PRIOR_RESPONSE"
    }
  },
  "detail_level": "summary"
}
```

Segui `next_cursor` finché non è più presente. I cursori sono autenticati e associati alla richiesta e alla revisione del corpus crittografato. Health.md rifiuta i cursori modificati, non corrispondenti o obsoleti.

I limiti delle pagine proteggono ogni richiesta senza imporre un limite complessivo alla cronologia o ai risultati.

## Corpo delle evidenze

`POST /v1/agent/evidence` usa lo stesso wrapper. L'operazione è `derive_packet`, accompagnata dal tipo di pacchetto e dai dettagli selezionati esplicitamente.

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps", "resting_heart_rate"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "derive_packet",
      "kind": "doctor_visit",
      "detail_ids": []
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144
    }
  },
  "detail_level": "summary"
}
```

La risposta resta una risposta di query paginata e contiene un frammento `healthmd.evidence_packet` v1. I fatti includono valori tipizzati ed evidenze. Il pacchetto specifica che contiene soltanto osservazioni fattuali.

Consulta [`agent-evidence-response.json`](/docs/reference/generated/automation/agent-evidence-response.json) per una risposta sintetica completa.

## Corpo dell'aggiornamento

L'aggiornamento acquisisce soltanto un ambito esplicito. Il corpo accetta date, metriche, fonti, livello di dettaglio e un tempo di attesa finito:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-01",
      "end_date": "2026-07-07"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["sleep_total"]
  },
  "sources": {
    "type": "explicit",
    "source_ids": ["apple_health"],
    "provider_ids": []
  },
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

Il Mac convalida l'ambito rispetto ai cataloghi correnti e lo trasforma in una selezione canonica immutabile. L'iPhone legge soltanto i normali tipi HealthKit selezionati. Le impostazioni limitate alla richiesta non modificano le preferenze di esportazione salvate sull'iPhone.

L'aggiornamento usa una modalità di trasferimento dedicata `encrypted_context`:

- non scrive file di esportazione;
- non consuma la quota per l'esportazione di file;
- trasferisce partizioni limitate e ripristinabili;
- il Mac conferma ogni giorno compatto e deterministico associato al titolare prima di inviarne la conferma;
- la richiesta esatta viene conservata con l'attività persistente.

Un ambito che include soltanto provider non richiede una lettura di Apple Health. La cronologia nativa di ciascun provider resta un'evidenza nativa e non viene convertita in metriche sintetiche di Apple Health.

## Selezione di tutti i dati disponibili

I selettori di metriche e date possono usare `all_available`:

```json
{
  "dates": {"type": "all_available"},
  "metrics": {"type": "all_available"},
  "sources": {"type": "all_available"},
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

L'iPhone individua il primo record Apple Health disponibile tra quelli selezionati e include tutti i giorni di calendario delle fonti fino a oggi. L'acquisizione dai provider segue i cursori delle rispettive cronologie native. Gli identificatori risolti vengono fissati prima del trasferimento, così la ripresa non può modificare la richiesta.

Non esiste un limite fisso per date o risultati. Partizioni, pagine, decodifica di un solo giorno alla volta, spazio su disco e attese finite limitano l'uso delle risorse.

## Attività persistenti di acquisizione

L'attesa di un aggiornamento può scadere mentre l'attività continua. La risposta include l'ID dell'attività e informazioni sicure sull'avanzamento.

```bash
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
healthmd agent job cancel JOB_UUID
```

L'attività scade sette giorni dopo la creazione. La ripresa riutilizza la stessa richiesta, lo stesso Mac, lo stesso iPhone, lo stesso ambito delle fonti e lo stesso punto già confermato.

L'annullamento diventa definitivo soltanto dopo la conferma dell'iPhone. Se l'iPhone non è disponibile, l'attività può restare in attesa di annullamento.

## Chiamate HTTP dirette

È preferibile usare la CLI, ma il software locale può chiamare direttamente l'API HTTP:

```bash
curl --fail-with-body --max-time 5 \
  http://127.0.0.1:17645/v1/agent/readiness

curl --fail-with-body --max-time 30 \
  -H 'Content-Type: application/json' \
  --data @query-body.json \
  http://127.0.0.1:17645/v1/agent/query
```

Il listener impone limiti alle intestazioni e ai corpi JSON, richiede metodo e tipo di contenuto espliciti, applica scadenze alla ricezione e garantisce che le richieste abbiano durata finita.

Mantieni i client HTTP diretti sullo stesso Mac. Non aggiungere un binding alla rete LAN, un proxy, un tunnel o un wrapper MCP HTTP remoto.

## Valori tipizzati e dati mancanti

I risultati delle query conservano tipo e unità. I valori possono rappresentare quantità, durate, conteggi, stringhe, categorie, valori booleani, timestamp, date di calendario, array annidati o futuri valori tipizzati non ancora noti.

Gli stati dei dati mancanti includono vuoto completo, parziale, non riuscito, non supportato, ignorato, annullato, non richiesto, non disponibile nei dati legacy, oscurato e non sincronizzato. I consumer non devono convertirli in zero.

La copertura include gli intervalli richiesti e disponibili, i giorni considerati, i giorni con valori e gli intervalli mancanti compressi che mantengono il relativo stato.

## Gestione degli errori

Gli errori usano `healthmd.query_error` v1 con codice stabile, messaggio, possibilità di riprovare e dettagli tipizzati. Errori distinti riguardano:

- controlli delle pagine non validi;
- cursori non validi o manomessi;
- mancata corrispondenza tra cursore e query;
- revisione obsoleta del corpus;
- intervallo di date non valido;
- convalida di metriche o fonti;
- mancata corrispondenza di unità o aggregazione;
- operazione non supportata;
- violazione dell'ambito delle evidenze;
- stato operativo dell'iPhone o dell'archivio crittografato;
- stato dell'attività persistente.

Dopo un esito sconosciuto, non riprovare automaticamente un aggiornamento. Controlla prima lo stato dell'attività.

## Contenuti correlati

<div class="related">
  <a href="/it/docs/agents/"><span>Panoramica</span>Agenti locali e contesto sanitario: configurazione, archiviazione crittografata, ambito e regole di presentazione.</a>
  <a href="/it/docs/agent-queries/"><span>Alto livello</span>Guida pratica alle query tipizzate: comandi convalidati per le domande comuni su metriche, sonno, allenamenti ed evidenze.</a>
  <a href="/it/docs/mcp/"><span>Strumenti</span>Server MCP locale: configurazione stdio, strumenti tipizzati, paginazione e limiti della sandbox.</a>
  <a href="/it/docs/reference/api-and-cli/"><span>Riferimento</span>Contratto API e CLI: esportazione, estrazione, query, backend diretto e limiti operativi.</a>
  <a href="/it/docs/reference/evidence-packets/"><span>Contratti dei dati</span>Query compatte e pacchetti di evidenze: tipi, cursori, operazioni e ID deterministici dei pacchetti.</a>
</div>
