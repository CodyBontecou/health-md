---
title: "Opdrachten en App Intents"
description: "Gebruik zeven gepubliceerde acties en twee Mac-contextacties uit de ontwikkelbron in Opdrachten en Siri."
---

<div class="availability preview"><strong>Zeven gepubliceerde acties · negen in huidige bron</strong><p>De twee Mac-contextacties vereisen compatibele iPhone- en Mac-builds. Controleer de notities van de exacte release.</p></div>

## Acties

- gisteren, één datum, een bereik of de laatste N dagen exporteren;
- gezondheidssamenvatting of laatste exportstatus ophalen;
- planning in- of uitschakelen;
- **Refresh Mac Health Context** (ontwikkeling): duurzame versleutelde vernieuwing gekoppeld aan een profiel;
- **Get Mac Context Refresh Status** (ontwikkeling): status en job-ID.

De vier exportacties accepteren optioneel een **Profiel**. Een onbekende naam faalt zonder terugval. Gewone Opdrachten schrijven naar de iPhone-map en schakelen niet stil over naar API Endpoint of Connected Mac.

Uitvoeren bij vergrendeling ontgrendelt HealthKit niet. Health.md bewaart de aanvraag en toont **Health Export Needs Attention**.

### Ochtendautomatisering

1. Maak een tijdautomatisering.
2. Voeg **Export Yesterday's Health Data** toe.
3. Voeg **Get Last Export Status** en een melding toe.

Gisteren bevat de slaap die gisteravond begon. Zie [Slaapdatums](/nl/docs/sleep-date-attribution/).

<div class="related"><a href="/nl/docs/export-profiles/"><span>Profielen</span>Stabiele identiteiten.</a><a href="/nl/docs/release-status/"><span>Compatibiliteit</span>Versies controleren.</a></div>
