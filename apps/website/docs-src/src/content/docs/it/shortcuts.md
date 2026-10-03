---
title: "Comandi rapidi e App Intents"
description: "Usa sette azioni pubblicate e due azioni di contesto Mac del codice in sviluppo in Comandi rapidi e Siri."
---

<div class="availability preview"><strong>Sette azioni pubblicate · nove nel codice attuale</strong><p>Le due azioni di contesto Mac richiedono build iPhone/Mac compatibili. Controlla le note della versione esatta.</p></div>

## Azioni

- esportare ieri, una data, un intervallo o gli ultimi N giorni;
- ottenere riepilogo salute o ultimo stato;
- attivare o sospendere la pianificazione;
- **Refresh Mac Health Context** (sviluppo): aggiornamento crittografato durevole legato al profilo;
- **Get Mac Context Refresh Status** (sviluppo): stato e job ID.

Le quattro azioni di esportazione accettano un **Profilo** facoltativo. Un nome sconosciuto fallisce senza ripiego. I comandi ordinari scrivono nella cartella iPhone e non passano silenziosamente a API Endpoint o Connected Mac.

Consentire l’esecuzione da bloccato non sblocca HealthKit. Health.md conserva la richiesta e mostra **Health Export Needs Attention**.

### Automazione mattutina

1. Crea un’automazione oraria.
2. Aggiungi **Export Yesterday's Health Data**.
3. Aggiungi **Get Last Export Status** e una notifica.

Ieri include il sonno iniziato ieri sera. Vedi [Date del sonno](/it/docs/sleep-date-attribution/).

<div class="related"><a href="/it/docs/export-profiles/"><span>Profili</span>Identità stabili.</a><a href="/it/docs/release-status/"><span>Compatibilità</span>Versioni qualificate.</a></div>
