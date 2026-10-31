---
title: "Android-app"
description: "Stel Health.md in voor Android. Exporteer Health Connect gegevens, selecteer Storage Access Framework-mappen, plan exports en automatiseer met Tasker of adb."
---

<div class="docs-hero">
 <p class="docs-eyebrow"> Health Connect naar privébestanden </p>
 <p> Health.md voor Android leest Health Connect op het apparaat en schrijft Markdown , Obsidian Bases, JSON of CSV naar mappen die u kiest. Voor deze workflow voor het exporteren van mappen is geen Health.md account vereist. De toegangsopties voor Google Play en de inbegrepen toegang voor F-Droid worden hieronder beschreven. </p>
 <div class="docs-actions">
 <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener"> Aan de slag Google Play </a>
 <a class="docs-button-secondary" href="#distribution-status"> F-Droid publicatiestatus </a>
 <a class="docs-button-secondary" href="/nl/docs/export/"> Lees exportdocumenten </a>
 </div>
 <p id="distribution-status"> F-Droid cataloguspublicatie is in behandeling. Download de huidige Android-release op Google Play . </p>
 </div>

<div class="reference-stats">
 <div> <strong> 106 </strong> <span> selecteerbaar Health Connect statistieken </span> </div>
 <div> <strong> 4 </strong> <span> exportformaten </span> </div>
 <div> <strong> 2 </strong> <span> Android-distributiekanalen </span> </div>
 <div> <strong> 0 </strong> <span> Health.md cloudaccounts vereist </span> </div>
 </div>

## Wat de Android-app doet

Health.md voor Android verandert Health Connect in een lokaal gezondheidstijdschrift. Kies de statistieken die u nodig heeft en bekijk een voorbeeld van de uitvoer. Exporteer vervolgens de bestanden naar een lokale map, Obsidian kluis, gesynchroniseerde providermap of beschrijfbare Android-documentprovider.

<div class="options">
 <div class="option"> <strong> Health Connect bron </strong> <p> Leest activiteit, slaap, hart, vitale waarden, lichaamsafmetingen, voeding, trainingen en andere categorieën via de Health Connect API's van Android op het apparaat. </p> </div>
 <div class="option"> <strong> Obsidian -native uitvoer </strong> <p> Schrijft dagelijkse notities, YAML/frontmatter, Obsidian Bases-vriendelijke notities, individuele vermeldingen en JSON compatibel met de Health.md Obsidian plug-in. </p> </div>
 <div class="option"> <strong> Android-native opslag </strong> <p> Gebruikt het Storage Access Framework, zodat u mappen kunt kiezen die beschikbaar zijn via lokale opslag, Obsidian , Google Drive, OneDrive, Syncthing of een andere provider. </p> </div>
 </div>

## Vereisten

- Android 9 / API 28 of nieuwer.
- Een apparaat of emulator dat geschikt is voor Health Connect .
- Health Connect gegevens van Android-apps, wearables of services die naar Health Connect schrijven.
- Een map- of documentprovider die schrijftoegang voor exports toestaat.

## Eerste export

1. Installeer de huidige Health.md release van Google Play .
2. Open de ** Health Connect ** instellingen en geef alleen de categorieën vrij die u met Health.md wilt exporteren.
3. Kies de exportbestemming via de Android-mapkiezer.
4. Kies formaten: Markdown , Obsidian Bases, JSON, CSV of een combinatie ervan.
5. Selecteer statistieken en datumbereik.
6. Bekijk een voorbeeld van de uitvoer.
7. Tik op exporteren en verifieer de gegenereerde bestanden in uw map of kluis.

Voor de telefoonversie met abonnement Google Play is een actief proefabonnement, abonnement, levenslange of behouden permanente toegang vereist voor handmatige export. In aanmerking komende abonnementen omvatten een proefperiode van zeven dagen; Levenslang kent geen proces. De F-Droid build omvat onbeperkte toegang zonder aankoop- of herstelstroom.

## Bestemmingen op Android

Android gebruikt de bestemming iPhone → Mac lokaal netwerk niet. In plaats daarvan vertrouwt het op het Storage Access Framework van Android.

| Bestemming | Android-status |
| --- | --- |
| Lokale apparaatmap | Ondersteund via de mapkiezer |
| Obsidian kluis | Ondersteund wanneer de kluismap wordt blootgesteld aan de kiezer van Android |
| Google Drive, OneDrive, Syncthing, Obsidian Sync en vergelijkbare providers | Ondersteund wanneer de provider beschrijfbare mappen beschikbaar stelt |
| iPhone /Mac lokale netwerkbestemming | Apple-platformspecifiek; niet gebruikt door Android |

Als een provider geen beschrijfbare mappen beschikbaar stelt via de kiezer van Android, kan Health.md daar niet veilig rechtstreeks naartoe schrijven. Kies een providermap die permanente schrijftoegang verleent of exporteer lokaal en synchroniseer met uw favoriete tool.

## Formaten

De Android-app deelt dezelfde doelstellingen voor gewone bestanden als de Apple-app:

| Formaat | Gebruik het voor |
| --- | --- |
| Markdown | Leesbare dagelijkse gezondheidssamenvattingen, sjablonen en notities |
| Obsidian Bases | Frontmatter-eerste notities die kunnen worden opgevraagd in Obsidian databaseweergaven |
| JSON | Gestructureerde dagelijkse payloads voor scripts, dashboards, notebooks en de plug-in Health.md Obsidian |
| CSV | Spreadsheet- en analyseworkflows |

Android JSON-exports zijn ontworpen om compatibel te zijn met de Obsidian visualisaties van Health.md . Markdown en Bases-exports gebruiken dezelfde frontmatter-gerichte workflow die is gedocumenteerd in de [format guide](/nl/docs/format/).

## Planning en automatisering

In de Google Play telefoonversie met abonnement vereist geplande export een actieve proefversie, abonnement, levenslange of behouden permanente toegang; ze zijn opgenomen in de F-Droid build. Ze gebruiken een eenmalig exact alarm wanneer u de alarmen en herinneringen van Android toegang verleent, met duurzaam WorkManager als back-up. Zonder exacte alarmtoegang wordt WorkManager de primaire planner, dus de geselecteerde tijd is eerder een doel dan een harde garantie. Health.md registreert de exportgeschiedenis, kan gemiste geplande datums herstellen en laat u mislukte runs opnieuw proberen.

Voor Tasker, adb of andere automatiseringstools geeft Health.md uitsluitend expliciete uitzendintenties weer. Externe bellers moeten de ontvangercomponent rechtstreeks aanspreken:

```text
com.healthmd.android/com.healthmd.automation.AutomationReceiver
```

Voorbeelden:

```bash
adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_YESTERDAY

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_LAST_DAYS \
  --ei com.healthmd.android.extra.DAYS 7

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_RANGE \
  --es com.healthmd.android.extra.START_DATE 2026-03-01 \
  --es com.healthmd.android.extra.END_DATE 2026-03-07
```

Automatisering gebruikt standaard het actieve profiel, inclusief de bevroren bestemming, indelingen, statistieken, boekhouding en geschiedenis. Een meegeleverde `PROFILE` extra kan een stabiele profiel-ID of naam selecteren. Een onbekende referentie mislukt. Het sluiten mislukt in plaats van de huidige instellingen te gebruiken. Geplande runs blijven ook gebonden aan hun profiel. Zie [Profielen exporteren](/nl/docs/export-profiles/).

### Achtergrondgereedheid en geplande annulering

- Sta toe dat Health Connect achtergrondlezen voor onbeheerde exports uitvoert. Open anders Health.md om het lezen van de gezondheidsgegevens te voltooien.
- Houd meldingen ingeschakeld, zodat Android actief werk, de status van de voorgrondservice, resultaten en herstelacties kan weergeven.
- Verleen alleen alarmen en herinneringen als u een exacte alarmplanning wilt. Zonder dit blijft duurzaam WorkManager werk beschikbaar, maar de gekozen tijd is bij benadering.
- Het annuleren van een geplande run stopt alleen die poging. Voltooide datums blijven compleet, onopgeloste datums kunnen opnieuw worden geprobeerd en het terugkerende schema blijft ingeschakeld.

## Gezondheidsbronnen

Health Connect is het lokale exportpad in beide kanalen. De Google Play build bevat ook een configuratiegebied voor gezondheidsbronnen voor ecosystemen zoals Samsung Health, Huawei Health, Fitbit, Garmin, Withings, Oura, Polar en WHOOP. Waar deze ecosystemen in Health Connect schrijven, kan elke build de resulterende Health Connect records exporteren. Directe import van cloudproviders en OAuth-callbacks zijn alleen voor afspelen. De F-Droid providercatalogus bevat alleen Health Connect .

Google Fit is opzettelijk uitgesloten van de ondersteunde providerpagina omdat Health Connect de voorkeurslaag voor gezondheidsgegevens van Android is.

### Exacte stappen per lokale dag

Dagelijkse stappentotalen gebruiken exacte gezoneerde lokale daggrenzen. Vóór de aggregatie knipt en splitst Health.md overlappende Health Connect intervallen om lokale middernacht. Reizen en veranderingen in de zomertijd zorgen er dus niet voor dat er stappen op de verkeerde dag terechtkomen.

## Distributie, prijzen en omschakeling

- ** Google Play :** de telefoonversie met abonnement biedt individuele wekelijkse/jaarlijkse abonnementen en levenslang. In aanmerking komende nieuwe abonnees ontvangen een proefperiode van zeven dagen en verlengen vervolgens automatisch tegen de weergegeven prijs totdat ze worden opgezegd via Google Play . De levensduur wordt één keer onmiddellijk in rekening gebracht, zonder proefperiode. Er blijft geen lokale vrije-exportvergoeding over. Bestaande permanente toegang blijft behouden. Aankoop herstellen maakt gebruik van het Google-aankoopaccount; het verwijderen van de app of het kopen van Lifetime annuleert een abonnement niet. Oudere vrijgegeven builds kunnen de vorige toeslag tonen. De huidige release is alleen voor telefoons. De Wear OS-metgezel wordt uitgesteld naar een latere kwalificatiecyclus.
- ** F-Droid :** onbeperkte toegang is inbegrepen. Er is geen gratis teller, factureringsafhankelijkheid, betaalmuur, aankoop of herstelactie.
- ** F-Droid bereik:** alleen Health Connect , zonder Wear OS-integratie, directe OAuth van de cloudprovider, Play-beoordeling, attributie of Health.md onboarding-telemetrie.
- **Gedeeld resultaat:** beide kanalen gebruiken dezelfde Health Connect capture, exporters, schema's, automatiseringsacties en direct-device protocol.
- **Overstappen:** Google Play en F-Droid gebruiken verschillende ondertekeningssleutels, dus als u van kanaal wilt wisselen, moet u eerst de app verwijderen.

Een kanaalwisseling migreert geen aankopen, instellingen, geschiedenis, inloggegevens of privéoverdrachtsstatus. Geëxporteerde bestanden blijven op de door u gekozen bestemming staan.

Als Google Play Facturering tijdelijk wordt verbroken, wordt de Play-build opnieuw verbonden en wordt de rechtenstatus automatisch vernieuwd. Bij tijdelijk serviceverlies wordt Premium niet permanent verwijderd. Gebruik Aankoop herstellen alleen als het account onopgelost blijft nadat de verbinding is hersteld.

## Privacymodel

Health.md voor Android is eerst lokaal:

- Health Connect records worden gelezen op uw Android-apparaat.
- Exporten worden rechtstreeks naar de door u gekozen mappen geschreven.
- Bij het exporteren van kernmappen en directe apparaatquery's wordt standaard geen Health.md serverkopie gemaakt.
- Instellingen en exportgeschiedenis blijven op het apparaat staan.
- Facturering wordt afgehandeld door Google Play in de Play-build. F-Droid omvat onbeperkte toegang zonder facturering en bevat geen Health.md telemetriecode of telemetrie-identiteit/status.
- Door de provider ondersteunde mappen worden gesynchroniseerd volgens de eigen voorwaarden van die provider.

Als u de strengste lokale instellingen wilt, voert u handmatige exports uit naar een lokale apparaatmap en laat u geplande exports en door de provider ondersteunde synchronisatie uitgeschakeld.

De afzonderlijke, optionele Health.md Cloud-pilot is uitsluitend voor één eigenaar en bewaart alleen bewust geüploade API-exports. Er is geen openbare registratie of automatische apparaatsynchronisatie; deze mapworkflow uploadt niets naar de pilot. Het [privacybeleid](/privacy-policy.html) beschrijft bewaartermijnen, verwijdering, opslagquota en verliesrisico’s zonder back-up.

## Gerelateerde documenten

<div class="related">
 <a href="/nl/docs/export-profiles/"> <span> Profielen </span> Bewaar onafhankelijke bestemmingen, uitvoerinstellingen, schema's en stabiele automatiserings-ID's. </a>
 <a href="/nl/docs/export/"> <span> Exporteren </span> Handmatige exportstroom, datumbereiken, voorbeelden, geschiedenis en bestandsuitvoer. </a>
 <a href="/nl/docs/metrics/"> <span> Statistieken </span> Hoe statistische selectie en categorieën werken in Health.md . </a>
 <a href="/nl/docs/format/"> <span> Formaten </span> Markdown , Bases, JSON, CSV, eenheden, bestandsnamen en frontmatter. </a>
 <a href="/nl/docs/visualizations-roadmap/"> <span> Obsidian </span> Hoe geëxporteerde JSON en Markdown Health.md visualisaties ondersteunen. </a>
 </div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;"> Laatst bijgewerkt 04-10-2026 </p>
