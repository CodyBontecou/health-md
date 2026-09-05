---
title: Functies per platform
description: Wat Health.md biedt op iPhone, iPad, Mac, Android, Wear OS en in de CLI — gedeelde functies en de eerlijke platformverschillen.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Platformoverzicht</p>
  <p>Wat Health.md doet op iPhone, iPad, Mac, Android, Wear OS en in de CLI — gedeeld waar de platforms het toestaan, eerlijk waar ze verschillen.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://apps.apple.com/us/app/health-md/id6757763969" target="_blank" rel="noopener">iPhone en Mac</a>
    <a class="docs-button-secondary" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Android</a>
  </div>
</div>

Legenda: ✓ beschikbaar · ◐ beschikbaar met platformverschillen die per rij zijn benoemd · △ gepland of in QA · ? beschikbaarheid niet geclaimd · — niet beschikbaar op dat platform.

De CLI is geen aparte kolom voor een gezondheidsgegevensplatform: CLI-functies staan in de automatiseringsrijen en behouden de semantiek van hun iPhone- of Android-bron.

## Installatie en machtigingen

| Functie | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Machtigingen voor gezondheidsgegevens (kies precies wat er gelezen wordt) | ✓ Apple Health-typen | ◐ leest via de gekoppelde iPhone / Mac-bestemming | ✓ Health Connect-categorieën | — |
| Exportbestemming kiezen | ✓ Obsidian-kluis, iCloud Drive, Bestanden | ✓ lokale mappen | ✓ elke Android-mapprovider (Drive, OneDrive, Syncthing, Obsidian Sync…) | — |
| Installatie met voorbeeldweergave | ✓ | ✓ | ✓ | — |
| Share My Setup (voorkeuren tussen apparaten verplaatsen) | △ in QA | △ in QA | △ in QA | — |

## Lezen en exporteren

| Functie | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Dagelijkse exports naar Markdown, Obsidian Bases, JSON, CSV | ✓ | ✓ (bestanden komen binnen vanaf de iPhone) | ✓ | — |
| 225+ Apple Health-meetwaarden / 106 Health Connect-meetwaarden | ✓ | ✓ | ✓ | — |
| Voorbeeldweergave vóór het schrijven | ✓ | ✓ | ✓ | — |
| Opgeslagen exportprofielen met onafhankelijke instellingen | ✓ beheren op de iPhone; ? iPad-beheer niet geclaimd | ? beheer niet geclaimd | ✓ beheren op Android | — |
| Wekelijkse / maandelijkse / jaarlijkse overzichten | ✓ | ✓ | △ gepland; vereist een afzonderlijk beoordeeld Android-schemaprofiel (huidige v4/v5 blijven ongewijzigd) | — |
| Exportgeschiedenis en opnieuw proberen | ✓ | ✓ | ✓ | — |
| Actieve uitvoering stoppen of annuleren zonder het schema uit te schakelen | ✓ voltooide datums bewaard; onopgeloste datums opnieuw probeerbaar | ✓ | ✓ voltooide datums bewaard; onopgeloste datums opnieuw probeerbaar | — |
| ZIP-archief van één uitvoering | ✓ | ✓ | — | — |
| Samenvattingsdetail van gegevens | ✓ | ✓ | ✓ | — |
| Gedetailleerde tijdreeks voor geselecteerde meetwaarden | ✓ | ✓ | ✓ | — |
| Canoniek bronarchief van Verliesvrije gezondheidsrecords | ✓ `healthmd.healthkit_records` | ✓ | — alleen Apple; zie in plaats daarvan Ruwe API-snapshots | — |
| Export van ruwe API-snapshots (onveranderlijk JSON/NDJSON) | — | — | ✓ Health Connect + Fitbit, Oura, WHOOP, Withings | — |

## Geavanceerde gegevens

| Functie | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Tracking per afzonderlijk item (trainingen, slaapfasen, vitale waarden) | ✓ | ✓ | ✓ | — |
| Trainingsdetails met volledige grafieken en routes waar aangeboden | ✓ | ✓ | ✓ | — |
| Export van stemming / State of Mind | ✓ | ✓ | — (geen Health Connect-equivalent) | — |
| Gebeurtenissen van medicatiedoses | ✓ | ✓ | — (geen Health Connect-equivalent) | — |
| Metingen van bloeddruk, glucose, zuurstof en temperatuur | ✓ | ✓ | ✓ | — |
| Gegevens van externe providers | ◐ WHOOP-sectie in de export (bèta) | ◐ | ✓ natieve ruwe snapshots van de provider | — |

Sommige gegevens worden bewust **niet als gelijkwaardig behandeld** tussen platforms: hartslagvariabiliteit is SDNN op Apple en RMSSD op Android en WHOOP — Health.md houdt ze als afzonderlijke meetwaarden in plaats van ze te mengen. De polstemperatuur van de Apple Watch en de huidtemperatuur van Health Connect blijven ook gescheiden.

## Automatiseren en integreren

| Functie | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Geplande terugkerende exports | ✓ meldingen + APNs-fallback | ✓ | ✓ WorkManager (+ optioneel exact alarm), herstel na herstart | — |
| Systeemautomatisering | ✓ Shortcuts / Siri / App Intents | — | ✓ Tasker, adb, expliciete broadcast-intents | — |
| Exports naar je eigen HTTP(S)-API-endpoint sturen | ✓ | — | ✓ met versleutelde opslag van headers | — |
| Koppeling met de zelfstandige CLI (`healthmd`) | ✓ directe dienst op de voorgrond | ✓ gebundeld + zelfstandig | ✓ koppeling met code van 20 cijfers | — |
| Wake voor directe CLI-verzoeken | ✓ begrensd wachten + APNs op opt-in | ✓ CLI-initiator | ◐ begrensd wachten; FCM gepland | — |
| MCP-server voor AI-agenten | ◐ gebundeld via de Mac; de getypeerde draagbare directe MCP is uitsluitend voor de iPhone | ✓ gebundeld als `healthmd-mcp` | — getypeerde directe MCP niet ondersteund | — |

## Apparaten en vlakken in één oogopslag

| Functie | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Widgets op het startscherm | ✓ samenvatting, activiteitsringen, hartslagbereik, slaap | — | ✓ samenvatting, activiteit, hartslagbereik, slaap (stappen vervangen sta-uren) | — |
| Exportvoortgang via Live Activity | ✓ | — | — | — |
| Oppervlakken op het horloge | ✓ horloge-app + 10 complicaties | — | — | ✓ tiles + 10 complicaties |
| Mac als exportbestemming (versleutelde lokale overdracht) | ✓ iPhone verstuurt | ✓ ontvangt | — | — |

## Aankoop en privacy

| Functie | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Gratis laag | ✓ 10 handmatige of geplande exportacties | — | ✓ 10 handmatige exportacties | — |
| Ontgrendeling | ✓ eenmalige aankoop voor levenslang (individueel / gezin) | ◐ dezelfde Apple-ontgrendeling | ✓ eenmalige aankoop voor levenslang, planning inbegrepen | — |
| Privacy met lokale verwerking | ✓ geen Health.md-cloud voor gezondheidsgegevens | ✓ | ✓ | ✓ |
| Verslag voor de zorgverlener (één PDF voor afspraken) | ✓ | — | ✓ | — |

Health.md beheert geen cloud voor gezondheidsgegevens. Gezondheidsgegevens kunnen bestaan in bestemmingen die je zelf kiest, in versleutelde lokale context en in een afgebakende privé-overdrachtstoestand. Elke map, Mac, API-endpoint of CLI-bestemming wordt expliciet geconfigureerd. Profielen en planningen blijven lokaal op het apparaat waar ze zijn aangemaakt. Voor de workflow van elk platform: zie [Exportprofielen](/nl/docs/export-profiles/), de [Android-handleiding](/nl/docs/android/) en de [iPhone-exportgids](/nl/docs/export/).
