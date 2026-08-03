---
title: "Endpoint API"
description: "Invia direttamente dall'iPhone al tuo endpoint HTTP(S) i dati JSON selezionati di Apple Health."
---

<p>Endpoint API è una destinazione di esportazione per chi vuole inviare i dati di Health.md al proprio server, webhook, database, dashboard o sistema di automazione. L'iPhone continua a leggere Apple Health ma, anziché scrivere file, invia tramite POST il JSON all'endpoint configurato.</p>

<div class="callout">
<strong>Promemoria sulla privacy.</strong>
<p style="margin-top:6px;">Questa destinazione invia intenzionalmente i dati sanitari selezionati all'URL inserito. Usa un endpoint che controlli o consideri attendibile, preferisci HTTPS e limita le metriche a quelle effettivamente necessarie al servizio.</p>
</div>

## Configurare la destinazione

<ol>
<li>Apri Health.md sull'iPhone.</li>
<li>Vai a <strong>Esporta</strong>.</li>
<li>In <strong>Destinazione di esportazione</strong>, scegli <strong>Endpoint API</strong>.</li>
<li>Inserisci un URL, ad esempio <code>https://api.example.com/healthmd/ingest</code>.</li>
<li>Facoltativo: inserisci un token bearer. Health.md lo archivia nel Portachiavi.</li>
<li>Tocca <strong>Fatto</strong>, scegli l'intervallo di date e le metriche, quindi tocca <strong>Esporta</strong>.</li>
</ol>

<p>Se inserisci un token semplice, Health.md lo invia come <code>Authorization: Bearer &lt;token&gt;</code>. Se il valore inizia già con <code>Bearer </code> o <code>Basic </code>, Health.md lo invia senza modificarlo.</p>

## Struttura del payload

<p>Health.md invia una richiesta POST per ogni azione di esportazione. Il corpo è un involucro <code>healthmd.api_export</code> con versione indipendente, contenente record giornalieri pubblici <code>healthmd.health_data</code> dello schema v7. L'involucro API v1 contiene i record giornalieri; la versione v2 può includere anche sidecar dei provider senza modificare lo schema dei record giornalieri.</p>

<div class="options">
<div class="option"><strong><code>records</code></strong><p>Oggetti giornalieri completi dello schema v7 conservati per l'intervallo richiesto, inclusi i record completamente vuoti il cui manifesto delle query costituisce un'evidenza.</p></div>
<div class="option"><strong><code>failed_date_details</code></strong><p>Date per le quali si è verificato un errore prima che fosse possibile conservare un documento giornaliero.</p></div>
<div class="option"><strong><code>daily_record_schema_version</code></strong><p>Versione dello schema giornaliero usata in <code>records</code>. Avanza indipendentemente dalla versione dell'involucro API.</p></div>
<div class="option"><strong>Sidecar dei provider</strong><p>Record esterni facoltativi della versione v2, con schema e regole di identità propri, presenti quando è abilitato un provider connesso.</p></div>
</div>

<p>Consulta l'<a href="/docs/reference/generated/automation/api-export-v1.json">involucro API v1</a> completo generato in produzione e l'<a href="/docs/reference/generated/automation/api-export-v2-provider-sidecar.json">involucro API v2 con sidecar del provider</a>. Il <a href="/it/docs/reference/api-and-cli/">contratto API e CLI</a> descrive ogni campo, confine di versione e regola di accettazione.</p>

## Requisiti dell'endpoint

<div class="options">
<div class="option"><strong>Metodo</strong><p>Deve accettare <code>POST</code>.</p></div>
<div class="option"><strong>Tipo di contenuto</strong><p>Deve accettare <code>application/json</code>.</p></div>
<div class="option"><strong>Esito positivo</strong><p>Dopo aver accettato il payload in modo sicuro, deve restituire uno stato <code>2xx</code>.</p></div>
<div class="option"><strong>Errori</strong><p>Per le richieste rifiutate deve restituire <code>4xx</code> o <code>5xx</code>. Quando disponibile, Health.md mostra una breve anteprima della risposta.</p></div>
</div>

<p>Per un'acquisizione affidabile, rendi l'endpoint idempotente per data. L'utente potrebbe ripetere lo stesso intervallo di esportazione dopo aver modificato le metriche o corretto un errore del server.</p>

## Suggerimenti

<ul>
<li>Esegui una prova con un solo giorno prima di caricare una cronologia estesa.</li>
<li>Mantieni abilitata l'opzione Dati sanitari senza perdita quando è importante conservare tutte le informazioni della fonte; riduci l'intervallo di date per percorsi densi, documenti clinici, ECG o allegati.</li>
<li>Convalida il token sul server prima di archiviare qualsiasi payload.</li>
<li>Usa <code>records[].date</code> come chiave principale di ogni giorno.</li>
<li>Restituisci un corpo di errore conciso: Health.md ne mostra soltanto una breve anteprima.</li>
</ul>

## Risoluzione dei problemi

| Problema | Significato probabile | Soluzione |
|---|---|---|
| La destinazione API non è pronta | L'URL è vuoto o non valido | Riapri le impostazioni di Endpoint API e inserisci un URL HTTP(S) valido. |
| HTTP 401 o 403 | Il token manca o è stato rifiutato | Aggiorna il token o le regole di autenticazione del server. |
| HTTP 404 | Il percorso dell'URL è errato | Controlla l'endpoint sul server. |
| HTTP 413 | Il payload è troppo grande | Esporta meno giorni; usa l'output di solo riepilogo esclusivamente se il destinatario non richiede i record sorgente canonici. |
| Mancano alcune date | Per quelle date non esistono dati HealthKit abilitati | Controlla <code>failed_date_details</code> e la selezione delle metriche. |

## Contenuti correlati

<div class="related">
  <a href="/it/docs/export/"><span>Origine</span>Esportazione: scegli la destinazione e l'intervallo di date ed esegui esportazioni manuali.</a>
  <a href="/it/docs/reference/api-and-cli/"><span>Schema</span>Riferimento API e CLI: involucri esatti, versioni, comportamento in caso di errore ed esempi generati.</a>
  <a href="/it/docs/format/"><span>Output</span>Personalizzazione del formato: JSON, CSV, Markdown, unità e campi.</a>
</div>
