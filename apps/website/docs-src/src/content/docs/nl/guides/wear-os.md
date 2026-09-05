---
title: Wear OS-compagnon
description: Health.md voor Wear OS voegt activiteits- en hersteltiles toe aan je horloge, plus tien gezondheidscomplicaties, terwijl de telefoon het Health Connect-gezag blijft.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Android · Wear OS</p>
  <p>Health.md levert een Wear OS-compagnon onder dezelfde Google Play-vermelding als de telefoonapp. Voeg in één oogopslag leesbare gezondheidsoppervlakken toe aan je horloge, terwijl je telefoon het enige Health Connect-gezag blijft.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Download via Google Play</a>
    <a class="docs-button-secondary" href="/nl/docs/android/">Android-app-handleiding</a>
  </div>
</div>

## Wat het horloge laat zien

| Oppervlak | Wat je krijgt |
|---|---|
| Tile Dagelijkse activiteit | Het activiteitsoverzicht van vandaag als tile op de wijzerplaat |
| Tile Herstel | Het hersteloverzicht van vandaag als tile op de wijzerplaat |
| Complicaties (10) | Activiteit, Herstel, Stappen, Bewegen, Training, Slaap, Rusthartslag, Gemiddelde hartslag, HRV en Bloedzuurstof als complicaties op de wijzerplaat |

Complicaties kun je bij de meeste wijzerplatten toevoegen via de wijzerplaat-editor, en tiles verschijnen in de tilecarrousel van het horloge.

## Hoe het werkt

- De horlogeapp wordt geleverd via dezelfde Play-vermelding en ondertekeningsidentiteit als de telefoonapp.
- Gezondheidsgegevens stromen van telefoon naar horloge over de Wear OS-datalaag als een privé-samengevoegde snapshot. Het horloge heeft **geen directe Health Connect- of Health Services-sensing**; de telefoon blijft gezaghebbend voor elke meetwaarde.
- Horlogeoppervlakken verversen vanuit de nieuwste snapshot die de telefoonapp doorstuurt — geen accounts, geen cloud, en geen gezondheidsgegevens verlaten je apparaten.

## Vereisten

- Een Android-telefoon met Health.md geïnstalleerd en gekoppeld aan een Wear OS-horloge.
- Health Connect-gegevens op de telefoon voor de meetwaarden die je wilt zien.
- Installeer Health.md op het horloge via de Play Store op het horloge, of via de Play Store-vermelding van de telefoon.

## Instellen

1. Open de Play Store op je horloge (of het horlogegedeelte van de Play Store op de telefoon) en installeer Health.md.
2. Open de telefoonapp één keer zodat een snapshot kan synchroniseren.
3. Houd je wijzerplaat lang ingedrukt → **Aanpassen** → voeg een Health.md-complicatie toe, of veeg naar de tilecarrousel en zet een Health.md-tile vast.

## Privacy en validatie

De compagnon gebruikt een zuiver privé, samengevoegd transportcontract, zodat er geen ruwe records naar het horloge worden verzonden. De releasekwaliteit wordt gegate op emulatorsuites plus batterij- en OEM-QA-bewijs van fysiek gekoppelde apparaten voordat Wear OS-artefacten verschijnen. Zie de [Wear OS-implementatiechecklist](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/features/wear-os-implementation.md) voor het volledige stappenplan.
