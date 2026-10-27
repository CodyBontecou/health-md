---
title: "Ontbrekende gegevens bij Apple Health-export? Problemen oplossen"
description: "Los lege Apple Health- of Health Connect-exports, ontbrekende slaap, CSV-details, schrijffouten en vertraagde schema’s op. Controleer eerst één dag."
---

Ontbreken gegevens in een Apple Health- of Health Connect-export? Maak eerst onderscheid tussen een **leesprobleem** en een **probleem bij het opslaan**. Ontbrekende gegevens zijn geen gemeten nulwaarde.

## Begin met één controleerbare dag

1. Controleer een vastgelegde waarde en datum in Apple Health of Health Connect. Laat het horloge of de bronapp eerst synchroniseren.
2. Controleer in Health.md het actieve profiel, de meetwaarde, datums, indeling en bestemming. Begin met één ondersteunde meetwaarde van een voltooide dag.
3. Ontgrendel de telefoon, open Health.md en bekijk het voorbeeld indien beschikbaar. Exporteer daarna en controleer het echte resultaat en de bestemming. Een voorbeeld bewijst niet dat een bestand is opgeslagen.

Zie de [eerste iPhone-export](/nl/docs/iphone-first-export/) of [Android-installatie](/nl/docs/android/).

## De bron bevat gegevens, maar de export is leeg

Controleer op iPhone de categorieën die Health.md in Apple Health mag lezen. **HealthKit maakt niet bekend of leestoestemming is geweigerd**. Een leeg resultaat maakt dus geen onderscheid tussen beperkte toegang en ontbrekende passende records. Een geslaagde toestemmingsaanvraag bevestigt niet elke leescategorie. Zie [Apples documentatie](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).

Controleer op Android of de bronapp het record werkelijk in Health Connect heeft geschreven en of Health.md dat ondersteunde type mag lezen. Gegevens die alleen in een andere app staan, zijn mogelijk niet exporteerbaar. Zie [Googles controlelijst](https://support.google.com/android/answer/13770384).

Controleer na synchronisatie of gewijzigde rechten de meetwaarde en datum opnieuw. Vervang ontbrekende waarden niet door nul.

Meldt een gestructureerd resultaat `complete_empty`, onderscheid dit dan van niet-ondersteunde, gedeeltelijke, overgeslagen of mislukte uitvoer. Het bewijst geen gemeten nul en onthult geen beslissing over leestoestemming.

## De slaap van afgelopen nacht ontbreekt bij Vandaag

Health.md gebruikt op Apple en Android een lokaal slaapvenster **van middag tot middag**. Exporteer op dinsdagochtend **Gisteren** (maandag), ook voor slaap die na middernacht op dinsdag begon, of maandag en dinsdag voor slaap en activiteit. Herhaal bij late synchronisatie de dag van het dagboek. Zie [datumvoorbeelden](/nl/docs/sleep-date-attribution/#sleep-date-examples).

## Het voorbeeld toont gegevens, maar de map is leeg

Controleer op iPhone of het actieve profiel naar een lokale map, Connected Mac of API Endpoint schrijft. Controleer bij bestanden map, submap, bestandsnaam en resultaat: geschreven, overgeslagen of mislukt. Overslaan kan passen bij het gekozen schrijfgedrag. Selecteer een onbereikbare map opnieuw en controleer de bestandsprovider. Zie [mappen en vaults](/nl/docs/folder-vault/) en [profielen](/nl/docs/export-profiles/).

## De CSV bevat totalen, niet de verwachte metingen

Op iPhone bieden Summary en Detailed Time-Series verschillend detail. Controleer Data Detail en meetwaarden voordat je meer dagen kiest. Metadata zijn geen gezondheidsmetingen. Behoud eenheden en onderscheid dagtotalen van bronrecords. Lossless Health Records heeft een aparte vastleggingsstatus; een samenvatting bewijst geen volledige vastlegging. Zie de [referentie voor indeling en dekking](/nl/docs/reference/export-formats/).

## Een geplande export komt niet aan

iOS-achtergrondtaken en Android WorkManager gebruiken doeltijden zonder bezorggarantie. Ontgrendel het apparaat, open Health.md en controleer geschiedenis en wachtend herstel voordat je opnieuw begint. Een melding bewijst niet dat schrijven is gelukt. Zie [iPhone-planning](/nl/docs/scheduling/) of [Android-automatisering](/nl/docs/android/).

## CLI-time-out

Een time-out annuleert geen geaccepteerde job:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

Controleer status, ontbrekende dagen, dekking, `next_cursor`, versie en beperkingen voordat je volledigheid claimt. `--allow-partial` wijzigt alleen afsluitbeleid.

## Vraag hulp zonder gezondheidsgegevens te delen

Vermeld app- en systeemversie, platform, indeling en of gegevens leeg zijn, uitvoer is overgeslagen of schrijven mislukt. Maak privégegevens onleesbaar in schermafbeeldingen en logboeken. Publiceer geen gezondheidswaarden, routes, klinische documenten, tokens, koppelcodes of privépaden.

<div class="related"><a href="/nl/docs/cli-jobs/"><span>Jobs</span>Hervatten en annuleren.</a><a href="/nl/docs/release-status/"><span>Versies</span>Compatibiliteit.</a></div>
