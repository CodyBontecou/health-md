---
title: "Opdrachten en App Intents"
description: "Gebruik zeven Health.md-acties in Opdrachten en Siri. Mac-contextvernieuwing is voorgesteld, niet beschikbaar."
---

<div class="availability preview"><strong>Zeven acties geregistreerd in de broncode</strong><p>Refresh Mac Health Context en Get Mac Context Refresh Status zijn voorgesteld, niet geïmplementeerd of beschikbaar in ontwikkeling. Volg <a href="https://github.com/CodyBontecou/health-md/issues/173">issue #173</a>; beschikbaarheid vereist implementatie, kwalificatie en de notities van een exacte Apple-release.</p></div>

## Acties

- gisteren, één datum, een bereik of de laatste N dagen exporteren;
- gezondheidssamenvatting of laatste exportstatus ophalen;
- planning in- of uitschakelen.

### Voorgestelde Mac-contextacties (niet beschikbaar)

De gevraagde actie **Refresh Mac Health Context** zou een expliciet profiel-/datumbereik, geauthenticeerde compatibele apparaten en duurzame contextverwerving gebruiken zonder exportbestanden of verbruik van het bestandsexportquotum. **Get Mac Context Refresh Status** zou de status wachtend/voltooid/mislukt melden met een herstelbare taakidentiteit. Dit zijn vereisten, geen ondersteunde actienamen, parameters of resultaten in de huidige app.

MCP-vernieuwing vanaf de computer voldoet niet aan een persoonlijke iOS-automatisering. Gebruik gewone export-Opdrachten niet als vervanging: ze behouden de iPhone-map als bestemming. Geen automatisering kan beloven een slapende Mac te wekken of beschermde HealthKit-gegevens te omzeilen. Testen van de automatisering na ontwaken op een fysieke iPhone blijft vereist voordat deze functie kan worden gekwalificeerd.

De vier exportacties accepteren optioneel een **Profiel**. Een onbekende naam faalt zonder terugval. Gewone Opdrachten schrijven naar de iPhone-map en schakelen niet stil over naar API Endpoint of Connected Mac.

Uitvoeren bij vergrendeling ontgrendelt HealthKit niet. Health.md bewaart de aanvraag en toont **Health Export Needs Attention**.

### Ochtendautomatisering

1. Maak een tijdautomatisering.
2. Voeg **Export Yesterday's Health Data** toe.
3. Voeg **Get Last Export Status** en een melding toe.

Gisteren bevat de slaap die gisteravond begon. Zie [Slaapdatums](/nl/docs/sleep-date-attribution/).

<div class="related"><a href="/nl/docs/export-profiles/"><span>Profielen</span>Stabiele identiteiten.</a><a href="/nl/docs/release-status/"><span>Compatibiliteit</span>Versies controleren.</a></div>
