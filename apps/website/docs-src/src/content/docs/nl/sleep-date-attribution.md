---
title: "Slaapdatums en dagelijkse notities"
description: "Waarom nachtslaap bij de startdatum hoort en welk bereik je 's ochtends exporteert."
---

Health.md kent een slaapsessie toe aan de datum waarop ze **begon**. Slaap van maandag 23:45 tot dinsdag 7:30 hoort bij maandag. Apple en Android delen deze regel, ook als Health Connect de wekdatum toont.

| Doel | Exporteer |
|---|---|
| Afgelopen nacht op dinsdagochtend | **Gisteren** (maandag) |
| Activiteit van dinsdag | **Vandaag** |
| Beide | Maandag en dinsdag |

Dagoverzichten houden de nacht bijeen. Canonieke bronrecords bewaren oorspronkelijke start en einde en horen bij de startdag; Health.md bedenkt geen helften. Gebruik `healthmd_sleep_sessions` voor sessiesemantiek.

Daily Note Injection en API Endpoint volgen dezelfde toewijzing. Synchroniseerde de bron laat, exporteer de startdag opnieuw. Er is nu geen optie om samenvattingen naar de wekdatum te verplaatsen.

<div class="related"><a href="/nl/docs/scheduling/"><span>Automatisering</span>Neem Gisteren mee.</a><a href="/nl/docs/troubleshooting/"><span>Hulp</span>Lege of late data.</a></div>
