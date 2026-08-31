---
title: Android-app
description: Stel Health.md in op Android, exporteer Health Connect-gegevens naar Markdown, Obsidian Bases, JSON en CSV, kies mappen via het Storage Access Framework, plan exports en automatiseer met Tasker of adb.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Van Health Connect naar privébestanden</p>
  <p>Health.md voor Android leest Health Connect op je apparaat en schrijft Markdown, Obsidian Bases, JSON of CSV naar mappen die je zelf kiest. Je hebt geen Health.md-account, cloud voor gezondheidsgegevens of abonnement nodig.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Download via Google Play</a>
    <a class="docs-button-secondary" href="/nl/docs/export/">Lees de exportdocumentatie</a>
  </div>
</div>

<div class="reference-stats">
<div><strong>106</strong><span>selecteerbare Health Connect-meetwaarden</span></div>
<div><strong>4</strong><span>exportformaten</span></div>
<div><strong>10</strong><span>gratis handmatige exportacties</span></div>
<div><strong>0</strong><span>vereiste Health.md-cloudaccounts</span></div>
</div>

## Wat de Android-app doet

Health.md voor Android maakt van Health Connect een gezondheidsdagboek met lokale verwerking. Kies de meetwaarden die je belangrijk vindt, bekijk een voorbeeld en exporteer overzichtelijke bestanden naar een lokale map, Obsidian-kluis, gesynchroniseerde providermap of een andere Android-documentprovider die schrijftoegang verleent.

<div class="options">
  <div class="option"><strong>Health Connect als bron</strong><p>Leest via de Health Connect-API's op het Android-apparaat gegevens over onder meer activiteit, slaap, hart, vitale functies, lichaamsmetingen, voeding en work-outs.</p></div>
  <div class="option"><strong>Uitvoer voor Obsidian</strong><p>Schrijft dagelijkse notities, YAML-frontmatter, notities voor Obsidian Bases, individuele vermeldingen en JSON die compatibel is met de Health.md-plugin voor Obsidian.</p></div>
  <div class="option"><strong>Opslag via Android</strong><p>Gebruikt het Storage Access Framework. Daarmee kun je mappen kiezen die beschikbaar zijn via lokale opslag, Obsidian, Google Drive, OneDrive, Syncthing of een andere provider.</p></div>
</div>

## Vereisten

- Android 9 / API 28 of nieuwer.
- Een apparaat of emulator die Health Connect ondersteunt.
- Health Connect-gegevens van Android-apps, wearables of diensten die naar Health Connect schrijven.
- Een map of documentprovider die Health.md schrijftoegang geeft voor exports.

## Eerste export

1. Installeer Health.md via Google Play.
2. Open de instellingen van **Health Connect** en geef alleen toegang tot de categorieën die Health.md mag exporteren.
3. Kies de exportbestemming met de mapkiezer van Android.
4. Kies Markdown, Obsidian Bases, JSON, CSV of een combinatie daarvan.
5. Selecteer meetwaarden en een datumbereik.
6. Bekijk een voorbeeld van de uitvoer.
7. Tik op exporteren en controleer de gemaakte bestanden in je map of kluis.

Met het gratis aanbod kun je 10 handmatige exportacties uitvoeren. Zo kun je machtigingen, maptoegang, formaten en je Obsidian-workflow testen voordat je onbeperkte exports ontgrendelt.

## Bestemmingen op Android

Android gebruikt niet de lokale-netwerkbestemming van iPhone naar Mac. De app gebruikt in plaats daarvan het Storage Access Framework van Android.

| Bestemming | Status op Android |
|---|---|
| Lokale map op het apparaat | Ondersteund via de mapkiezer |
| Obsidian-kluis | Ondersteund als de kluismap beschikbaar is in de Android-mapkiezer |
| Google Drive, OneDrive, Syncthing, Obsidian Sync en vergelijkbare providers | Ondersteund als de provider schrijfbare mappen beschikbaar stelt |
| Lokale-netwerkbestemming voor iPhone/Mac | Alleen voor Apple-platforms; Android gebruikt deze niet |

Als een provider geen schrijfbare mappen aanbiedt via de mapkiezer van Android, kan Health.md daar niet veilig rechtstreeks naartoe schrijven. Kies een providermap met blijvende schrijftoegang of exporteer lokaal en synchroniseer de bestanden met je voorkeursprogramma.

## Formaten

De Android-app hanteert voor gewone bestanden dezelfde uitgangspunten als de Apple-app:

| Formaat | Geschikt voor |
|---|---|
| Markdown | Leesbare dagelijkse gezondheidsoverzichten, sjablonen en notities |
| Obsidian Bases | Notities waarin frontmatter centraal staat en die je kunt opvragen in databaseweergaven van Obsidian |
| JSON | Gestructureerde dagelijkse gegevens voor scripts, dashboards, notebooks en de Health.md-plugin voor Obsidian |
| CSV | Spreadsheets en gegevensanalyse |

JSON-exports van Android zijn ontworpen voor compatibiliteit met de Obsidian-visualisaties van Health.md. Exports in Markdown en Obsidian Bases volgen dezelfde frontmattergerichte werkwijze als in de [gids over formaten](/nl/docs/format/).

## Planning en automatisering

Geplande exports vereisen de eenmalige aankoop voor levenslange toegang. Geplande exports gebruiken een eenmalig exact alarm als je Android toegang geeft tot Alarmen en herinneringen. Een blijvende WorkManager-taak dient als reserve. Zonder toegang voor exacte alarmen is WorkManager de primaire planner. De gekozen tijd is dan een richttijd en geen harde garantie. Health.md houdt de exportgeschiedenis bij, kan gemiste geplande datums herstellen en laat je mislukte uitvoeringen opnieuw proberen.

Voor Tasker, adb en andere automatiseringsprogramma's biedt Health.md uitsluitend expliciete broadcast-intents. Externe aanroepers moeten de receivercomponent rechtstreeks adresseren:

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

Automatisering gebruikt standaard het actieve profiel met de bevroren bestemming, formaten, meetwaarden, tegoed en geschiedenis. Een meegegeven extra `PROFILE` kan een stabiel profiel via ID of naam selecteren; een onbekende verwijzing stopt veilig in plaats van actuele instellingen te gebruiken. Geplande uitvoeringen blijven ook aan hun profiel gebonden. Zie [Exportprofielen](/nl/docs/export-profiles/).

### Achtergrondvereisten en geplande annulering

- Sta Health Connect-lezingen op de achtergrond toe voor onbeheerde exports; open anders Health.md om de lezing af te ronden.
- Houd meldingen aan voor actief werk, de vereiste voorgrondservice en herstelberichten.
- Geef alleen toegang tot Alarmen en herinneringen voor exacte alarmen. Zonder die toegang blijft werk persistent maar is de tijd bij benadering.
- Een geplande uitvoering annuleren stopt alleen die poging. Voltooide datums blijven behouden, andere zijn herhaalbaar en het schema blijft actief.

## Gezondheidsbronnen

Health Connect is het standaardpad voor lokale exports. De Android-app bevat ook instellingen voor ecosystemen zoals Samsung Health, Huawei Health, Fitbit, Garmin, Withings, Oura, Polar en WHOOP. Als die ecosystemen gegevens naar Health Connect schrijven, kan Health.md de bijbehorende Health Connect-records exporteren. Voor rechtstreekse imports van cloudproviders is toestemming van de provider nodig. Er kunnen daarnaast extra configuratie- of beschikbaarheidsbeperkingen gelden.

Google Fit staat bewust niet in de lijst met ondersteunde providers, omdat Health Connect de voorkeurslaag van Android voor gezondheidsgegevens is.

### Exacte lokale dagstappen

Dagtotalen gebruiken exacte lokale daggrenzen met tijdzone. Health.md knipt en splitst Health Connect-intervallen bij lokale middernacht vóór aggregatie, zodat reizen en zomertijd geen stappen verschuiven.

## Prijzen en aankopen herstellen

- De Android-app bevat 10 gratis handmatige exportacties.
- Met een eenmalige aankoop voor levenslange toegang via Google Play Billing ontgrendel je onbeperkte exports en geplande automatisering.
- Er is geen abonnement of terugkerende betaling.
- Google Play toont vóór de aankoop de actuele lokale prijs.
- Gebruik Aankoop herstellen met het Google-account waarmee Premium is gekocht.

Na een tijdelijke verbreking van Google Play Billing maakt Health.md opnieuw verbinding en vernieuwt het recht automatisch. Premium verdwijnt niet permanent; gebruik Aankoop herstellen alleen als het account na netwerkherstel onopgelost blijft.

## Privacymodel

Health.md voor Android verwerkt gegevens lokaal:

- Health Connect-records worden op je Android-apparaat gelezen.
- Exports worden rechtstreeks naar de mappen geschreven die je kiest.
- Health.md beheert geen cloud voor gezondheidsgegevens.
- Instellingen en exportgeschiedenis blijven op het apparaat.
- Google Play verwerkt de betaling.
- Mappen van externe providers worden gesynchroniseerd volgens de voorwaarden van die provider.

Wil je alles zo veel mogelijk lokaal houden, voer dan handmatige exports uit naar een lokale map op het apparaat en schakel geplande exports en synchronisatie via providers uit.

## Gerelateerde documentatie

<div class="related">
  <a href="/nl/docs/export-profiles/"><span>Profielen</span>Bewaar onafhankelijke bestemmingen, uitvoerinstellingen, planningen en stabiele automatiserings-ID’s.</a>
  <a href="/nl/docs/export/"><span>Export</span>Handmatige exports, datumbereiken, voorbeelden, geschiedenis en bestandsuitvoer.</a>
  <a href="/nl/docs/metrics/"><span>Meetwaarden</span>Hoe selectie en categorieën van meetwaarden in Health.md werken.</a>
  <a href="/nl/docs/format/"><span>Formaten</span>Markdown, Bases, JSON, CSV, eenheden, bestandsnamen en frontmatter.</a>
  <a href="/nl/docs/visualizations-roadmap/"><span>Obsidian</span>Hoe geëxporteerde JSON en Markdown de Health.md-visualisaties aansturen.</a>
</div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">Laatst bijgewerkt op 31 augustus 2026</p>
