---
title: "Risoluzione dei problemi Health.md"
description: "Diagnostica esportazioni vuote, sonno assente, telefono non disponibile, pianificazioni, cartelle, risultati parziali e timeout."
---

Inizia con un dispositivo, un giorno, una categoria e una destinazione. Non pubblicare salute, percorsi, documenti clinici, token, codici di associazione o percorsi privati.

## Dati vuoti

Conferma il valore in Apple Health o Health Connect, controlla il permesso ed esporta una categoria per un giorno. Distingui `complete_empty`, permesso assente, non supportato, ignorato, parziale e fallito. Assente non significa zero.

## Sonno assente da Oggi

Il sonno appartiene al giorno di inizio della notte. Martedì mattina esporta **Ieri** oppure lunedì e martedì. Vedi [Date del sonno](/it/docs/sleep-date-attribution/).

## File e pianificazioni

Controlla vault, accesso cartella, sottocartella, modello e profilo. Il background iOS e WorkManager usano orari obiettivo, non garanzie universali. Sblocca e usa il recupero.

## Timeout CLI

Un timeout non annulla un job accettato:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

Prima di dichiarare completezza verifica stato, date mancanti, copertura, `next_cursor`, versione e limiti. `--allow-partial` cambia solo la politica d’uscita.

<div class="related"><a href="/it/docs/cli-jobs/"><span>Job</span>Riprendi e annulla.</a><a href="/it/docs/release-status/"><span>Versioni</span>Compatibilità.</a></div>
