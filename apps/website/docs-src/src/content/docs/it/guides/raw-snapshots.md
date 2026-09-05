---
title: Snapshot API non elaborati
description: Esporta snapshot JSON o NDJSON immutabili e versionati di record Health Connect e di risposte dei provider Fitbit, Oura, WHOOP e Withings, con manifest per tipo e checksum.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Android · export di livello archivistico</p>
  <p>Raw API Snapshot è un prodotto di export separato di Health.md per Android, pensato per flussi di migrazione e archiviazione: un artefatto JSON o NDJSON immutabile e versionato per ciascun intervallo selezionato, che conserva i record nativi.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Scarica da Google Play</a>
    <a class="docs-button-secondary" href="/it/docs/android/">Guida dell’app Android</a>
  </div>
</div>

## Che cos’è uno snapshot non elaborato

Gli export di compatibilità convertono i record Health Connect in riepiloghi giornalieri leggibili di `HealthData`. Uno snapshot non elaborato salta del tutto questa conversione:

- **Gli snapshot Health Connect** conservano ogni campo esposto dall’API AndroidX bloccata, inclusi identità e metadati nativi, timestamp in nanosecondi, offset sorgente nullable, valori enum non elaborati, campioni annidati, fasi, percorsi e strutture di allenamenti pianificati.
- **Gli snapshot Fitbit, Oura, WHOOP e Withings** conservano i byte esatti delle risposte riuscite del provider e dichiarano la paginazione dell’endpoint e l’aggregazione lato server. I provider non supportati vengono segnalati invece di essere normalizzati o sostituiti in silenzio con dati Health Connect.
- Ogni artefatto termina con un **manifest** con stato, problemi, conteggi e checksum per tipo. Anche gli export in cartella ricevono un file aggiuntivo `.sha256`.

Uno snapshot non elaborato è completo rispetto all’API provider bloccata dell’app, ma non è un backup transazionale del database del provider. Non può recuperare record inaccessibili, unità originali che l’API non espone, record eliminati o campi sconosciuti all’SDK installato.

## Anteprima prima della destinazione

Gli snapshot non elaborati possono essere visualizzati in anteprima senza una destinazione configurata. L’anteprima esegue la lettura nativa completa del provider in una memoria privata senza backup, mantiene in memoria solo un testo iniziale e finale limitato ed elimina l’artefatto temporaneo senza caricare nulla.

## Regole di consegna

Gli upload di API non elaborata sono volutamente più severi degli export di API di compatibilità:

| Regola | Motivo |
|---|---|
| Solo HTTPS | L’artefatto in streaming non viaggia mai in chiaro |
| Reindirizzamenti rifiutati | L’artefatto e le credenziali non possono mai essere replicati verso un’altra origine |
| Intestazioni di schema, export e checksum | L’endpoint ricevente può verificare cosa ha accettato |
| Artefatto privato temporaneo eliminato dopo il tentativo | Nessuna copia resta sul dispositivo |

## Archivi incrementali

Il backend `healthmd.raw-changes`, con versionamento separato, usa token di modifica e marcatori di eliminazione di Health Connect per futuri flussi di archiviazione incrementale, così uno snapshot completo non deve essere l’unica strategia di archiviazione.

## Requisiti

- Health.md per Android con il prodotto Raw API Snapshot.
- Autorizzazioni Health Connect per i tipi di record selezionati, oppure un account Fitbit, Oura, WHOOP o Withings collegato per gli snapshot dei provider.
- Un endpoint HTTPS se carichi gli snapshot; l’esportazione in cartella locale non ha requisiti di trasporto.

## Dove approfondire

- [Contratto snapshot non elaborato v1](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-snapshot-v1.md)
- [Contratto record non elaborato v1](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-record-v1.md)
- [Contratto modifiche non elaborate v1](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-changes-v1.md)
