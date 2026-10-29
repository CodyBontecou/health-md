---
title: "Slaapdatums en dagelijkse notities"
description: "Kies de juiste slaapexportdatum: het venster van middag tot middag, bedtijd na middernacht, dutjes en lege resultaten."
---

Exporteer op dinsdagochtend **maandag**, meestal **Gisteren**, voor de afgelopen nacht. Het dagelijkse slaapoverzicht van Health.md gebruikt een lokaal venster van **12:00 tot 12:00**: maandagmiddag tot dinsdagmiddag, niet de middernachtgrens van activiteit.

<div id="sleep-journal-window"></div>

## Waarom slaap in de notitie van gisteren staat

Het venster houdt een gebruikelijke nacht bij elkaar, ook bij een bedtijd na middernacht. De eerste middaggrens telt mee, de volgende niet. Slaap over een middaggrens kan bijdragen aan twee aangrenzende dagoverzichten. Oorspronkelijke tijdstempels worden niet aan de notitiedatum aangepast.

Apple en Android delen dit venster voor compatibele overzichten. Meetwaarden, slaapfasen, bronrecords en aggregatie kunnen verschillen. Er is geen instelling om het overzicht naar de wekdatum te verplaatsen.

<div id="sleep-date-examples"></div>

## Welke datum exporteren?

Fictieve voorbeelden in lokale tijd, geen gezondheidsgegevens:

| Slaap of activiteit | Exportdatum |
| --- | --- |
| Maandag 23:45 tot dinsdag 07:30 | **Maandag** |
| Dinsdag 01:00 tot dinsdag 07:30 | **Maandag**, niet dinsdag |
| Dutje op dinsdag, 14:00 tot 14:30 | **Dinsdag** |
| Stappen en activiteit van dinsdag | **Dinsdag** |
| Maandagnacht en dinsdagsactiviteit | **Maandag en dinsdag** |

Controleer de lokale tijdzone van de export. De wekdatum in een andere app of de wijzigingstijd van het bestand bepaalt niet de dag van het dagboek.

<div id="sleep-empty-checks"></div>

## Als de verwachte notitie leeg is

1. Controleer de dag en de geselecteerde slaapmetingen.
2. Laat horloge of bronapp synchroniseren met Apple Health of Health Connect. Bekijk daarna de voorvertoning en exporteer die dag opnieuw.
3. Controleer de toegang. Op iPhone onthult een leeg HealthKit-resultaat niet of leestoegang is geweigerd. Op Android moet de bron het ondersteunde record werkelijk naar Health Connect hebben geschreven.
4. Controleer bestemming en geschreven, overgeslagen of mislukte resultaten. Een voorvertoning bewijst niet dat een bestand is opgeslagen. Ontbrekend is niet nul.

Daily Note Injection en API Endpoint-overzichten volgen hetzelfde venster. Herhaal bij late bronupdates de dag of controleer de terugblikperiode van het schema. Achtergrondwerk garandeert geen geslaagde schrijfactie op een exact tijdstip.

<div id="sleep-records-and-queries"></div>

## Overzichten, bronrecords en sessiequery’s

Ruwe of canonieke records behouden hun tijdstempels en eigen dagregels. Reconstrueer geen sessies uit een dagtotaal en tel bronintervallen niet als extra slaap daarbij op.

Op Apple deelt het ruwe archief records in op basis van hun oorspronkelijke begintijd binnen de lokale kalenderdag, van middernacht tot middernacht. Het slaapoverzicht knipt intervallen juist af op het dagboekvenster van middag tot middag. Een geslaagde ruwe Sleep Analysis-query kan daarom ochtendrecords bevatten terwijl het slaapoverzicht voor die datum leeg is. Exporteer de vorige dagboekdatum en controleer `time_context.calendar_timezone` voordat je een ontbrekend overzicht onderzoekt. Records van 22 september van 04:03–11:52 UTC horen bijvoorbeeld in UTC volledig bij het overzicht van 21 september; in Europe/Lisbon vallen de laatste 52 minuten na de lokale middag en tellen die mee voor 22 september.

Slaapfasen vereisen geen expliciet `inBed`-record: als dat ontbreekt, gebruiken Apple-overzichten de vereniging van de beschikbare intervallen waarin je sliep. Ontbrekende gegevens over tijd in bed leveren geen duur in bed op. Een mislukte overzichtsquery hoort in `diagnostics.partial_failures` te staan; een geslaagde query zonder geschikte intervallen is geldige afwezigheid van gegevens. De rusthartslag gebruikt een aparte kalenderdagquery en vereist een echte rusthartslagmeting; slaapfasen of alleen leestoestemming leveren die niet.

`healthmd_sleep_sessions` vereist een ondersteunde CLI/MCP-configuratie voor **Apple Health**. Getypeerde Android-MCP-query’s worden momenteel niet ondersteund. Zie [platformmogelijkheden](/nl/docs/guides/platform-features/) en [MCP](/nl/docs/mcp/).

Meer hulp: [planning](/nl/docs/scheduling/), [probleemoplossing](/nl/docs/troubleshooting/) en [formaten](/nl/docs/format/).
