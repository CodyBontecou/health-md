---
title: Funzioni per piattaforma
description: Che cosa offre Health.md su iPhone, iPad, Mac, Android, Wear OS e con la CLI — funzioni condivise e differenze di piattaforma dichiarate con onestà.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Panoramica delle piattaforme</p>
  <p>Che cosa fa Health.md su iPhone, iPad, Mac, Android, Wear OS e con la CLI — condiviso dove le piattaforme lo consentono, onesto dove differiscono.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://apps.apple.com/us/app/health-md/id6757763969" target="_blank" rel="noopener">iPhone e Mac</a>
    <a class="docs-button-secondary" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Android</a>
  </div>
</div>

Legenda: ✓ disponibile · ◐ disponibile con differenze di piattaforma indicate nella riga · △ pianificato o in QA · ? disponibilità non dichiarata · — non disponibile su quella piattaforma.

La CLI non è una colonna separata di piattaforma dati sanitari: le funzioni della CLI compaiono nelle righe di automazione e conservano la semantica della loro origine iPhone o Android.

## Configurazione e permessi

| Funzione | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Permessi sui dati sanitari (scegli esattamente cosa leggere) | ✓ tipi di Apple Health | ◐ legge tramite l'iPhone abbinato / destinazione Mac | ✓ categorie di Health Connect | — |
| Scegliere la destinazione di esportazione | ✓ archivio Obsidian, iCloud Drive, File | ✓ cartelle locali | ✓ qualsiasi provider di cartelle Android (Drive, OneDrive, Syncthing, Obsidian Sync…) | — |
| Configurazione iniziale con anteprima di esempio | ✓ | ✓ | ✓ | — |
| Share My Setup (spostare le preferenze tra dispositivi) | △ in QA | △ in QA | △ in QA | — |

## Lettura ed esportazione

| Funzione | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Esportazioni giornaliere in Markdown, Obsidian Bases, JSON, CSV | ✓ | ✓ (i file arrivano dall'iPhone) | ✓ | — |
| 225+ metriche di Apple Health / 106 metriche di Health Connect | ✓ | ✓ | ✓ | — |
| Anteprima prima della scrittura | ✓ | ✓ | ✓ | — |
| Profili di esportazione salvati con impostazioni indipendenti | ✓ gestione su iPhone; ? gestione su iPad non dichiarata | ? gestione non dichiarata | ✓ gestione su Android | — |
| Riepiloghi settimanali / mensili / annuali | ✓ | ✓ | △ pianificato; richiede un profilo schema Android con revisione separata (le attuali v4/v5 restano invariate) | — |
| Cronologia delle esportazioni e riprova | ✓ | ✓ | ✓ | — |
| Fermare o annullare l'esecuzione attiva senza disattivarne la pianificazione | ✓ date completate conservate; date non risolte ripetibili | ✓ | ✓ date completate conservate; date non risolte ripetibili | — |
| Archivio ZIP di una singola esecuzione | ✓ | ✓ | — | — |
| Dettaglio dei dati di riepilogo | ✓ | ✓ | ✓ | — |
| Serie temporale dettagliata per le metriche selezionate | ✓ | ✓ | ✓ | — |
| Archivio canonico dei record di origine dei Dati sanitari senza perdita | ✓ `healthmd.healthkit_records` | ✓ | — solo Apple; vedi invece gli snapshot API non elaborati | — |
| Esportazione di snapshot API non elaborati (JSON/NDJSON immutabile) | — | — | ✓ Health Connect + Fitbit, Oura, WHOOP, Withings | — |

## Dati avanzati

| Funzione | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Tracciamento individuale delle voci (allenamenti, fasi del sonno, parametri vitali) | ✓ | ✓ | ✓ | — |
| Dettagli degli allenamenti con grafici completi e percorsi quando disponibili | ✓ | ✓ | ✓ | — |
| Esportazione di umore / State of Mind | ✓ | ✓ | — (nessun equivalente su Health Connect) | — |
| Eventi di dosi di farmaci | ✓ | ✓ | — (nessun equivalente su Health Connect) | — |
| Misure di pressione arteriosa, glicemia, ossigeno e temperatura | ✓ | ✓ | ✓ | — |
| Dati di provider di terze parti | ◐ sezione WHOOP nell'esportazione (beta) | ◐ | ✓ snapshot non elaborati nativi del provider | — |

Alcuni dati non vengono volutamente **trattati come equivalenti** tra piattaforme: la variabilità della frequenza cardiaca è SDNN su Apple e RMSSD su Android e WHOOP — Health.md li mantiene come metriche distinte invece di fonderle. La temperatura del polso dell'Apple Watch e la temperatura della pelle di Health Connect restano anch'esse separate.

## Automatizzare e integrare

| Funzione | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Esportazioni ricorrenti pianificate | ✓ notifiche + fallback APNs | ✓ | ✓ WorkManager (+ allarme esatto opzionale), ripristino dopo il riavvio | — |
| Automazione di sistema | ✓ Comandi rapidi / Siri / App Intents | — | ✓ Tasker, adb, intent di broadcast espliciti | — |
| Inviare le esportazioni al tuo endpoint API HTTP(S) | ✓ | — | ✓ con archiviazione cifrata degli header | — |
| Abbinamento con la CLI autonoma (`healthmd`) | ✓ servizio diretto in primo piano | ✓ inclusa + autonoma | ✓ abbinamento con codice a 20 cifre | — |
| Risveglio per richieste CLI dirette | ✓ attesa limitata + APNs su consenso | ✓ iniziatore CLI | ◐ attesa limitata; FCM pianificato | — |
| Server MCP per agenti IA | ◐ incluso tramite il Mac; il MCP diretto tipizzato e portabile è esclusivo di iPhone | ✓ incluso come `healthmd-mcp` | — MCP diretto tipizzato non supportato | — |

## Dispositivi e superfici a colpo d'occhio

| Funzione | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Widget nella schermata Home | ✓ riepilogo, anelli di attività, fascia cardiaca, sonno | — | ✓ riepilogo, attività, fascia cardiaca, sonno (i passi sostituiscono le ore in piedi) | — |
| Avanzamento dell'esportazione in Attività in tempo reale | ✓ | — | — | — |
| Superfici dell'orologio | ✓ app orologio + 10 complicazioni | — | — | ✓ tile + 10 complicazioni |
| Mac come destinazione di esportazione (trasferimento locale cifrato) | ✓ l'iPhone invia | ✓ riceve | — | — |

## Acquisto e privacy

| Funzione | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Livello gratuito | ✓ 10 azioni di esportazione manuali o pianificate | — | ✓ 10 azioni di esportazione manuali | — |
| Sblocco | ✓ acquisto a vita una tantum (individuale / famiglia) | ◐ stesso sblocco Apple | ✓ acquisto a vita una tantum, pianificazione inclusa | — |
| Privacy con elaborazione locale | ✓ nessun cloud di dati sanitari di Health.md | ✓ | ✓ | ✓ |
| Referto per il clinico (un PDF per gli appuntamenti) | ✓ | — | ✓ | — |

Health.md non gestisce alcun cloud di dati sanitari. I dati sanitari possono esistere nelle destinazioni che scegli, in contesto locale cifrato e in uno stato di trasferimento privato limitato. Ogni cartella, Mac, endpoint API o destinazione CLI viene configurata esplicitamente. I profili e le pianificazioni restano locali al dispositivo in cui sono stati creati. Per il flusso di lavoro di ciascuna piattaforma, vedi i [profili di esportazione](/it/docs/export-profiles/), la [guida Android](/it/docs/android/) e la [guida all'esportazione su iPhone](/it/docs/export/).
