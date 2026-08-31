---
title: Inizia con Health.md.
description: Esporta i dati di Apple Health o Health Connect, collega l’helper firmato per Mac a un agente locale e sviluppa utilizzando i contratti versionati di Health.md.
---

<div class="docs-hero" data-strand-stage>
  <canvas class="docs-dna" data-three-strand aria-hidden="true"></canvas>
  <div class="docs-hero-copy">
    <p class="docs-eyebrow">Disponibile ora · helper firmato per Mac</p>
    <p>Esporta i dati sanitari dal telefono, collega un agente locale tramite gli helper firmati per Mac oppure sviluppa utilizzando contratti versionati. Le letture di HealthKit restano sull’iPhone e quelle di Health Connect restano su Android.</p>
    <div class="docs-command" aria-label="Comando incluso per verificare che Health.md sia pronto"><span aria-hidden="true">$</span> "/Applications/Health.md.app/Contents/Helpers/healthmd" doctor</div>
    <p class="docs-command-note">Installato altrove? Copia il percorso dell’helper incluso da <strong>Health.md per Mac → CLI</strong>.</p>
    <div class="docs-actions">
      <a class="docs-button" href="/it/docs/iphone-first-export/">Prima esportazione da iPhone</a>
      <a class="docs-button-secondary" href="/it/docs/configuration/">Collega un agente</a>
      <a class="docs-button-secondary" href="/it/docs/reference/">Esplora i contratti</a>
    </div>
  </div>
</div>

<div class="agent-path" aria-label="Scegli un obiettivo di Health.md">
  <a href="/it/docs/iphone-first-export/"><span>01 · Esporta</span><strong>Inizia su iPhone</strong>Autorizza Apple Health, scegli una cartella, visualizza l’anteprima del risultato ed esegui la prima esportazione.</a>
  <a href="/it/docs/configuration/"><span>02 · Chiedi</span><strong>Collega un agente locale</strong>Usa l’helper MCP firmato per Mac con Codex, Claude o un altro client stdio.</a>
  <a href="/it/docs/reference/"><span>03 · Sviluppa</span><strong>Usa contratti stabili</strong>Integra schemi, record, evidenze, fixture generate e involucri esatti.</a>
</div>

<div class="reference-stats">
<div><strong>21</strong><span>strumenti MCP inclusi per Mac</span></div>
<div><strong>4</strong><span>formati di esportazione</span></div>
<div><strong>v8</strong><span>schema pubblico di esportazione Apple</span></div>
<div><strong>0</strong><span>passaggi obbligatori attraverso il cloud di Health.md</span></div>
</div>

<p class="docs-section-kicker">Disponibile ora · macOS</p>

## Avvio rapido in cinque minuti con un agente locale

Apri Health.md sul Mac, quindi apri Health.md sull’iPhone abbinato e attendi che venga stabilita la connessione. L’helper incluso verifica che tutto sia pronto senza restituire valori sanitari, elenca le metriche del sonno ed esegue una query relativa a un giorno:

```bash
HMD="/Applications/Health.md.app/Contents/Helpers/healthmd"
"$HMD" doctor
"$HMD" metrics list --category Sleep
"$HMD" query --category Sleep --yesterday
```

Quando tutto è pronto, il risultato di `doctor` usa lo schema `healthmd.cli_doctor` e include le azioni successive se la configurazione è incompleta. Per Codex o Claude, prosegui con [Configura il tuo agente](/it/docs/configuration/) e configura il client affinché utilizzi l’helper firmato separato `healthmd-mcp`.

<p class="docs-section-kicker">Scegli in base all’obiettivo</p>

## Configurazione e connessione

<div class="related">
  <a href="/it/docs/configuration/"><span>Disponibile ora · Mac</span>Configurazione — collega Codex, Claude o un altro client stdio all’helper MCP firmato.</a>
  <a href="/it/docs/mcp/"><span>Disponibile ora · Mac</span>Server MCP e app — scopri 21 strumenti inclusi, genera visualizzazioni private e scopri l’anteprima multipiattaforma.</a>
  <a href="/it/docs/cli/"><span>Disponibile ora · Mac</span>CLI di Health.md — installa l’helper incluso, verifica che tutto sia pronto, interroga i dati e distingui l’anteprima multipiattaforma.</a>
  <a href="/it/docs/agents/"><span>Architettura</span>Contesto dell’agente — scopri l’ambito delle richieste, l’attendibilità locale, il contesto crittografato, le evidenze, la conservazione e la privacy.</a>
</div>

<p class="docs-section-kicker">Operazioni quotidiane</p>

## Interrogazione, estrazione e automazione

<div class="related">
  <a href="/it/docs/agent-queries/"><span>Query tipizzate</span>Richiedi metriche, sessioni di sonno, allenamenti, confronti, copertura ed evidenze fattuali.</a>
  <a href="/it/docs/cli-direct/"><span>Anteprima · CLI multipiattaforma</span>Accesso diretto al telefono — consulta l’abbinamento tramite IP manuale o Tailscale e l’attuale matrice di compatibilità iPhone/Android non qualificata.</a>
  <a href="/it/docs/cli-extract/"><span>Dati di origine</span>Estrazione canonica — acquisisci giorni selezionati dello schema v8, record di origine, proiezioni o JSONL.</a>
  <a href="/it/docs/cli-jobs/"><span>Esecuzioni affidabili</span>Attività persistenti — gestisci in modo sicuro timeout, esiti sconosciuti, ripresa, annullamento e risultati parziali.</a>
  <a href="/it/docs/agent-api/"><span>Basso livello</span>API di loopback — usa route esatte per query, evidenze, cursori, aggiornamenti e attività persistenti.</a>
  <a href="/it/docs/reference/integration-recipes/"><span>Modelli</span>Ricette di integrazione — analizza e convalida i risultati di Health.md senza indebolirne i contratti.</a>
</div>

<p class="docs-section-kicker">Interfacce stabili</p>

## Contratti e strutture dei dati

<div class="related">
  <a href="/it/docs/reference/"><span>Mappa dei contratti</span>Riferimento per l’esportazione — consulta schemi, metriche, formati, record e fixture di interoperabilità.</a>
  <a href="/it/docs/reference/api-and-cli/"><span>Automazione</span>Contratti API e CLI — esamina involucri, route, comportamento di uscita ed esempi generati.</a>
  <a href="/it/docs/reference/evidence-packets/"><span>Risultati dell’agente</span>Query ed evidenze — valori tipizzati, copertura, dati mancanti, operazioni e identità deterministiche.</a>
  <a href="/it/docs/reference/daily-records/"><span>Schema v8</span>Record giornalieri — comprendi il documento di origine pubblico e le relative regole di titolarità.</a>
  <a href="/it/docs/shared-metric-registry/"><span>Vocabolario</span>Registro delle metriche — usa ID, categorie, unità e metadati del profilo stabili e multipiattaforma.</a>
  <a href="/it/docs/reference/generated/"><span>Leggibile dalle macchine</span>Artefatti generati — consulta campi canonici, fixture, inventari dei messaggi e contratti CLI.</a>
</div>

<p class="docs-section-kicker">Flussi di lavoro del prodotto</p>

## App ed esportazioni

### Esportazioni affidabili basate sui profili

- Scegli Riepilogo o Serie temporale dettagliata condivisa; l’archivio canonico senza perdita è solo Apple.
- Salva impostazioni, destinazioni e pianificazioni indipendenti in profili locali su iPhone o Android.
- Interrompere o annullare riguarda solo il tentativo attivo: le date completate restano, le altre sono riprovabili e le pianificazioni attive.

Inizia da [Profili di esportazione](/it/docs/export-profiles/) per ID stabili, automazione, cronologia delle destinazioni e fallimenti sicuri.

<div class="related">
  <a href="/it/docs/export-profiles/"><span>Flussi riutilizzabili</span>Profili di esportazione — fissa destinazione, formati, metriche, pianificazione e ID di automazione.</a>
  <a href="/it/docs/iphone-first-export/"><span>Inizia qui · iPhone</span>Prima esportazione — autorizza Apple Health, scegli una cartella, visualizza l’anteprima del risultato e verifica i file scritti.</a>
  <a href="/it/docs/android/"><span>Android</span>Health Connect — scegli una cartella tramite un provider di documenti e configura l’automazione della piattaforma.</a>
  <a href="/it/docs/export/"><span>File</span>Esportazione — esegui intervalli di date espliciti in Markdown, CSV, JSON o Obsidian Bases.</a>
  <a href="/it/docs/format/"><span>Struttura</span>Personalizzazione del formato — controlla unità, date, frontmatter, nomi dei file e comportamento di scrittura.</a>
  <a href="/it/docs/scheduling/"><span>In background</span>Programmazione — comprendi le cadenze ricorrenti, il recupero e i limiti temporali della piattaforma.</a>
  <a href="/it/docs/shortcuts/"><span>Automazione</span>Comandi rapidi e App Intents — avvia esportazioni, riepiloghi e controlli dello stato dai flussi di lavoro Apple.</a>
</div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:12px; font-family:var(--sl-font-mono);">Struttura della documentazione aggiornata il 2026-08-31</p>
