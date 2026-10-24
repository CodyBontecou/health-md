---
title: "Comandi rapidi e App Intents"
description: "Usa sette azioni Health.md in Comandi rapidi e Siri. Le azioni di aggiornamento del contesto Mac sono proposte, non disponibili."
---

<div class="availability preview"><strong>Sette azioni registrate nel codice</strong><p>Refresh Mac Health Context e Get Mac Context Refresh Status sono proposte, non implementate né disponibili in sviluppo. Segui la <a href="https://github.com/CodyBontecou/health-md/issues/173">segnalazione #173</a>; la disponibilità richiede implementazione, qualificazione e note di una versione Apple esatta.</p></div>

## Azioni

- esportare ieri, una data, un intervallo o gli ultimi N giorni;
- ottenere riepilogo salute o ultimo stato;
- attivare o sospendere la pianificazione.

### Azioni di contesto Mac proposte (non disponibili)

L’azione richiesta **Refresh Mac Health Context** userebbe un ambito esplicito di profilo e date, dispositivi compatibili autenticati e acquisizione durevole del contesto senza file di esportazione né consumo della quota di esportazione file. **Get Mac Context Refresh Status** riporterebbe lo stato in attesa/completato/fallito con un’identità di lavoro recuperabile. Questi sono requisiti, non nomi di azioni, parametri o risultati supportati nell’app attuale.

L’aggiornamento MCP dal computer non soddisfa un’automazione personale iOS. Non usare i normali comandi di esportazione come sostituti: mantengono la semantica della cartella iPhone. Nessuna automazione può promettere di risvegliare un Mac in stop o aggirare i dati protetti di HealthKit. Prima di qualificare questa funzione resta necessaria la verifica dell’automazione su un iPhone fisico dopo il risveglio.

Le quattro azioni di esportazione accettano un **Profilo** facoltativo. Un nome sconosciuto fallisce senza ripiego. I comandi ordinari scrivono nella cartella iPhone e non passano silenziosamente a API Endpoint o Connected Mac.

Consentire l’esecuzione da bloccato non sblocca HealthKit. Health.md conserva la richiesta e mostra **Health Export Needs Attention**.

### Automazione mattutina

1. Crea un’automazione oraria.
2. Aggiungi **Export Yesterday's Health Data**.
3. Aggiungi **Get Last Export Status** e una notifica.

Ieri include il sonno iniziato ieri sera. Vedi [Date del sonno](/it/docs/sleep-date-attribution/).

<div class="related"><a href="/it/docs/export-profiles/"><span>Profili</span>Identità stabili.</a><a href="/it/docs/release-status/"><span>Compatibilità</span>Versioni qualificate.</a></div>
