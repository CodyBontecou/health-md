---
title: Compagno Wear OS
description: Health.md per Wear OS aggiunge al tuo orologio tile di attività e recupero più dieci complicazioni salute, mentre il telefono resta l’autorità Health Connect.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Android · Wear OS</p>
  <p>Health.md include un compagno Wear OS nella stessa scheda Google Play dell’app del telefono. Aggiungi superfici salute a colpo d’occhio al tuo orologio mentre il telefono resta l’unica autorità Health Connect.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Scarica da Google Play</a>
    <a class="docs-button-secondary" href="/it/docs/android/">Guida dell’app Android</a>
  </div>
</div>

## Cosa mostra l’orologio

| Superficie | Cosa ottieni |
|---|---|
| Tile Attività giornaliera | Il riepilogo dell’attività di oggi come tile del quadrante |
| Tile Recupero | Il riepilogo del recupero di oggi come tile del quadrante |
| Complicazioni (10) | Attività, Recupero, Passi, Movimento, Esercizio, Sonno, Frequenza cardiaca a riposo, Frequenza cardiaca media, VFC e Ossigeno nel sangue come complicazioni del quadrante |

Le complicazioni si possono aggiungere alla maggior parte dei quadranti dall’editor del quadrante, e le tile appaiono nel carosello delle tile dell’orologio.

## Come funziona

- L’app orologio viene distribuita con la stessa scheda Play e la stessa identità di firma dell’app telefono.
- I dati salute passano dal telefono all’orologio tramite il livello dati Wear OS come snapshot aggregato privato. L’orologio **non ha rilevamento diretto di Health Connect o di Health Services**; il telefono resta autorevole per ogni metrica.
- Le superfici dell’orologio si aggiornano dall’ultimo snapshot inviato dall’app del telefono: nessun account, nessun cloud e nessun dato salute lascia i tuoi dispositivi.

## Requisiti

- Uno smartphone Android con Health.md installato e abbinato a un orologio Wear OS.
- Dati Health Connect sul telefono per le metriche che vuoi vedere.
- Installa Health.md sull’orologio dal Play Store dell’orologio o dalla scheda Play Store del telefono compagno.

## Configurazione

1. Apri il Play Store sull’orologio (o sulla sezione orologi del Play Store del telefono) e installa Health.md.
2. Apri una volta l’app del telefono perché uno snapshot possa sincronizzarsi.
3. Tieni premuto il quadrante → **Personalizza** → aggiungi una complicazione Health.md, oppure scorri fino al carosello delle tile e fissa una tile Health.md.

## Privacy e validazione

Il compagno usa un contratto di trasporto privato puramente aggregato, quindi nessun record non elaborato viene trasmesso all’orologio. La qualità delle versioni è vincolata a suite di emulatore e a evidenze di batteria e QA OEM su dispositivi fisici abbinati prima della pubblicazione degli artefatti Wear OS. Vedi la [checklist di implementazione Wear OS](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/features/wear-os-implementation.md) per il runbook completo.
