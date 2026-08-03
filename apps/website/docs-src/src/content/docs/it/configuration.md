---
title: Configura il tuo agente
description: Scegli l'interfaccia MCP o CLI di Health.md, configura Codex, Claude o un altro client locale e connetti un iPhone abbinato senza instradare HealthKit attraverso un servizio cloud.
---

L'app per Mac distribuita include due helper locali firmati: `healthmd-mcp` per strumenti tipizzati destinati agli agenti e `healthmd` per flussi di lavoro CLI espliciti. Una CLI multipiattaforma separata con MCP diretto per iPhone è documentata come anteprima finché il suo primo pacchetto pubblico non avrà superato i test di rilascio su dispositivi fisici.

<div class="callout">
<strong>HealthKit rimane su iPhone.</strong>
<p style="margin-top:6px;">La configurazione consente a un client locale di accedere alle interfacce con ambito limitato di Health.md. Non concede al computer o all'agente l'accesso diretto a HealthKit e non carica la libreria di origine su un cloud di Health.md.</p>
</div>

## Scegli un'interfaccia

| Obiettivo | Inizia con | Prosegui con |
|---|---|---|
| Consentire a Codex o Claude di interrogare e rappresentare graficamente i dati sanitari su Mac | `healthmd-mcp` incluso tramite stdio | [Server e strumenti MCP](/it/docs/mcp/) |
| Esportare JSON canonico o file generati in uno script per Mac | CLI `healthmd` inclusa | [CLI](/it/docs/cli/) |
| Connettersi direttamente a un iPhone aperto senza l'app per Mac | CLI diretta multipiattaforma (**anteprima**) | [Accesso diretto a iPhone](/it/docs/cli-direct/) |
| Sviluppare usando le esatte strutture di richiesta e risposta | API loopback o contratti pubblici | [API loopback](/it/docs/agent-api/) |
| Analizzare schemi, record, evidenze o fixture generate | Riferimento con versionamento | [Contratti dei dati](/it/docs/reference/) |

Le scelte relative a backend e trasporto sono esplicite; Health.md non passa automaticamente dall'accesso diretto a iPhone all'app per Mac.

## Codex con l'app per Mac

<div class="availability available">
<strong>Disponibile ora · helper firmato per Mac</strong>
<p>Installa Health.md per Mac, apri la schermata <strong>CLI</strong> e copia il percorso MCP incluso visualizzato se l'app non si trova in <code>/Applications</code>.</p>
</div>

Aggiungi l'helper firmato separato `healthmd-mcp` a `~/.codex/config.toml`:

```toml
[mcp_servers.healthmd]
command = "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
args = []
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"
```

Riavvia Codex, chiama `healthmd_doctor`, quindi chiama `healthmd_metrics` e un piccolo strumento tipizzato come `healthmd_metric_chart`. Il server incluso espone 21 strumenti, tra cui verifica dell'idoneità del Mac, processi di aggiornamento del contesto crittografato, evidenze e visualizzazioni.

## Claude Desktop o Claude Code su Mac

Aggiungi l'helper incluso alla configurazione MCP di Claude Desktop o a un file `.mcp.json` attendibile di Claude Code:

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

Riavvia il client dopo averne modificato la configurazione. Le configurazioni definite a livello di progetto richiedono comunque che l'area di lavoro sia considerata attendibile e che il server venga approvato esplicitamente. Mantieni aperte le app per Mac e iPhone quando uno strumento richiede dati HealthKit aggiornati.

## Qualsiasi client MCP stdio su Mac

Configura un processo locale:

```text
command: /Applications/Health.md.app/Contents/Helpers/healthmd-mcp
arguments: none
transport: stdio
```

L'host gestisce stdin e il ciclo di vita del processo. Non avviare l'helper come un normale comando interattivo e non racchiuderlo in una shell che modifichi l'output JSON-RPC. Usa `tools/list` di MCP per individuare gli schemi esatti esposti dall'app installata.

## Configurazione diretta multipiattaforma

<div class="availability preview">
<strong>Anteprima · non ancora distribuita pubblicamente</strong>
<p>La CLI Rust multipiattaforma, <code>healthmd setup codex</code>, il comando <code>healthmd mcp serve</code> eseguito dallo stesso binario e l'abbinamento diretto su Linux/Windows sono implementati, ma attendono la prima versione pubblica qualificata.</p>
</div>

Dopo la pubblicazione, `healthmd setup codex` configurerà Codex in modo idempotente e avvierà l'abbinamento diretto con iPhone. Fino ad allora, non fare affidamento su URL non pubblicati di Homebrew, crates.io, programmi di installazione o versioni GitHub. La pagina [CLI diretta per iPhone](/it/docs/cli-direct/) documenta il trasporto in più fasi e il comportamento del protocollo.

## Flussi di lavoro CLI espliciti

Per l'estrazione canonica o l'automazione orientata ai file, invoca direttamente `healthmd` invece di chiedere a un host MCP di trasferire un corpo di origine di grandi dimensioni:

```bash
healthmd status
healthmd extract --category Sleep --last 7 --output sleep.json
healthmd export --last 7 --destination "$HOME/Documents/HealthVault"
```

La disponibilità e la sintassi differiscono tra l'helper incluso per Mac e la CLI multipiattaforma autonoma. Consulta [CLI di Health.md](/it/docs/cli/) prima di copiare i comandi in automazioni non presidiate.

## Abbinamento multipiattaforma e idoneità operativa

<div class="availability preview">
<strong>Anteprima · flussi di lavoro diretti multipiattaforma</strong>
<p>Questi passaggi descrivono il futuro pacchetto multipiattaforma. Il percorso MCP incluso nella versione per Mac distribuita usa invece la connessione esistente dell'app per Mac con iPhone.</p>
</div>

I flussi di lavoro MCP e CLI diretti richiedono un abbinamento attendibile, da eseguire una sola volta, con Health.md su iPhone. L'abbinamento usa un canale crittografato e autenticato e l'archiviazione nativa delle credenziali su macOS, Linux o Windows.

1. Abilita **Accesso CLI diretto** in Health.md su iPhone.
2. Avvia l'abbinamento da `healthmd setup codex` o `healthmd direct pair`.
3. Approva la richiesta di abbinamento con ambito limitato su iPhone.
4. Mantieni Health.md in primo piano mentre avvii una query o un'esportazione.
5. Chiama `healthmd_doctor` in MCP o `healthmd status` nella CLI multipiattaforma prima di operazioni più complesse.

Consulta [Accesso diretto a iPhone](/it/docs/cli-direct/) per informazioni su IP manuale, Tailscale, porta, dispositivo attendibile, esecuzione in primo piano e procedure di ripristino.

## Limiti della configurazione

La configurazione di un agente locale **non** concede:

- letture o scritture arbitrarie in HealthKit;
- accesso arbitrario al file system;
- URL, comandi shell, prompt, radici o campionamento arbitrari tramite MCP;
- l'autorizzazione a nascondere dati mancanti, copertura, unità, evidenze o limitazioni;
- l'autorizzazione a riprendere, annullare o sovrascrivere file generati senza l'approvazione applicabile.

Per ottenere un risultato completo, esamina l'ambito richiesto, la copertura, l'attraversamento, le limitazioni e lo schema di origine, non soltanto il completamento del processo.

## Continua

<div class="related">
  <a href="/it/docs/mcp/"><span>Interfaccia degli strumenti</span>Esamina i 21 strumenti disponibili per Mac, l'anteprima multipiattaforma con 17 strumenti, MCP Apps, gli schemi, la paginazione, le esportazioni e i limiti dell’ambiente isolato.</a>
  <a href="/it/docs/agent-queries/"><span>Prime domande</span>Esegui flussi di lavoro tipizzati per metriche, sonno, allenamenti, confronti, copertura ed evidenze.</a>
  <a href="/it/docs/cli-extract/"><span>Dati canonici</span>Estrai documenti schema-v7 selezionati e record di origine senza inserire corpi di grandi dimensioni nella chat.</a>
  <a href="/it/docs/reference/"><span>Contratti</span>Consulta strutture dati con versionamento, inventari dei campi, fixture generate e procedure di integrazione.</a>
</div>
