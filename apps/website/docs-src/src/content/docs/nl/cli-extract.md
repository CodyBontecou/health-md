---
title: "Canonieke gezondheidsgegevens extraheren"
description: "Gebruik healthmd extract om geselecteerde Apple Health-meetwaarden op te halen en canonieke documenten volgens schema v7, bronrecords, JSON Pointer-projecties of JSONL met expliciete ontvangstbewijzen uit te voeren."
---

`healthmd extract` is de opdracht voor brongegevens in scripts en agents. De opdracht laat de iPhone alleen de geselecteerde meetwaarden en het gekozen detailniveau ophalen, valideert de persistente overdracht, verwijdert de transport-envelop en voert canonieke documenten volgens `healthmd.health_data` v7 of duidelijk gelabelde projecties uit.

Gebruik extractie als je de oorspronkelijke Health.md-gegevens nodig hebt. Gebruik [getypeerde queries](/nl/docs/agent-queries/) voor sessies, vergelijkingen, afstemming van work-outs, dekking of bewijsbundels.

## Basisstructuur

Voor een extractie heb je nodig:

1. ten minste één selectie met een meetwaarde, categorie, object of `--all-metrics`;
2. één datumselectie;
3. optionele keuzes voor detailniveau, object, veld, formaat, uitvoer, time-out en gedeeltelijke resultaten.

```bash
healthmd extract \
  (--metric ID | --category NAME | --object NAME | --all-metrics) ... \
  (--from DATE --to DATE | --last N | --yesterday | --all) \
  [--detail summary|lossless] \
  [--source apple_health] \
  [--field /JSON/POINTER] ... \
  [--format json|jsonl] \
  [--timeout 5...900] \
  [--allow-partial] \
  [--output PATH]
```

De huidige canonieke extractiebron is `apple_health`. Systeemeigen provider-sidecars blijven in hun eigen contracten en worden niet omgezet in synthetische Apple Health-waarden.

## Begin met een klein verzoek

```bash
# One category, one day, summary detail
healthmd extract --category Sleep --yesterday --output sleep.json

# One metric for the last 30 complete days
healthmd extract --metric resting_heart_rate --last 30 \
  --output resting-heart-rate.json

# Every selected source object for one exact range
healthmd extract --all-metrics \
  --from 2026-07-01 --to 2026-07-07 \
  --detail lossless --output health-week.json
```

Namen van meetwaarden en categorieën worden aan de hand van de huidige catalogus gevalideerd voordat de iPhone aan het werk gaat. Herhaal selecties om ze te combineren.

```bash
healthmd extract \
  --metric sleep_total \
  --metric resting_heart_rate \
  --category Workouts \
  --last 14 --output recovery-context.json
```

## Selectie vindt plaats voordat HealthKit wordt uitgelezen

Extractie haalt niet eerst een opgeslagen export met alle meetwaarden op om die daarna bij te snijden. De CLI zet je selectie om in een onveranderlijke `CanonicalHealthDataSelection` en stuurt deze naar de iPhone. Health.md controleert en leest alleen de gewone HealthKit-typen die de geselecteerde meetwaarden ondersteunen.

Dit onderscheid is belangrijk voor privacy, prestaties en volledigheid:

- niet-geselecteerde meetwaarden worden niet opgehaald;
- opgeslagen voorkeuren voor meetwaarden op de iPhone veranderen niet;
- verzoeken om samenvattingen maken geen verborgen bronarchief;
- verliesvrije verzoeken halen alleen de brontypen op die de selectie nodig heeft;
- de selectie wordt onderdeel van de vingerafdruk van het persistente verzoek.

Selecties met objecten en JSON Pointers beperken de uitgevoerde gegevens na de vastlegging. Selecties met meetwaarden, categorieën, bronnen en detailniveau beperken de gegevensophaling op de iPhone zelf.

## Samenvattings- en verliesvrij detailniveau

Samenvatting is de standaard:

```bash
healthmd extract --category Activity --last 7 --detail summary
```

Samenvattingsuitvoer kan getypeerde dagsamenvattingen, querydiagnostiek en `raw_capture_status: not_requested` bevatten. Die status is eerlijk: de opdracht heeft geen canonieke bronrecords opgehaald.

Vraag verliesvrij detail aan als bronobjecten, UUID's, exacte tijdstempels, herkomst of archiefdiagnostiek belangrijk zijn:

```bash
healthmd extract --metric workouts --last 14 \
  --detail lossless --output workouts-lossless.json
```

Archiefgerichte objecten zoals `records` impliceren verliesvrij detail, ook als `--detail` is weggelaten.

## Objectselecties

Gebruik `--object` om een bekend deel van elke geselecteerde dag te behouden. De huidige namen zijn:

| Object | Gebruikelijke inhoud |
|---|---|
| `sleep` | Velden uit de dagelijkse slaapsamenvatting |
| `activity` | Stappen, energie, afstand, beweging en verwante activiteitssamenvattingen |
| `heart` | Hartslag, hartslag in rust, HRV en verwante samenvattingen |
| `vitals` | Bloeddruk, glucose, temperatuur, zuurstof en andere samenvattingen van vitale functies |
| `body` | Gewicht, lichaamssamenstelling, lengte en lichaamsmetingen |
| `nutrition` | Samenvattingen van voedingsstoffen en hydratatie |
| `mindfulness` | Mindfulness-sessies en samenvattingen over mentaal welzijn |
| `mobility` | Velden voor lopen, looppatroon en mobiliteit |
| `hearing` | Geluidsblootstelling en gehoorgegevens |
| `reproductive-health` | Gegevens over voortplanting, zwangerschap en cyclus |
| `cycling` | Fietssamenvattingen |
| `vitamins` / `minerals` | Samenvattingen per voedingsstof |
| `symptoms` | Symptoomgegevens |
| `medications` | Medicatiegegevens als deze beschikbaar en toegestaan zijn |
| `workouts` | Canonieke samenvattingsobjecten voor work-outs |
| `archive` | Canonieke HealthKit-archiefenvelop |
| `records` | Canonieke bronrecords; impliceert verliesvrij detail |
| `external-records` | Externe records die al in de openbare dag aanwezig zijn |
| `query-results` | Vastleggingsresultaten per query |
| `warnings` | Integriteitswaarschuwingen |

Voorbeelden:

```bash
healthmd extract --metric workouts --last 30 \
  --object workouts --output workout-summaries.json

healthmd extract --metric workouts --last 30 \
  --object records --detail lossless --output workout-records.json

healthmd extract --category Sleep --last 7 \
  --object sleep --object query-results --output sleep-with-status.json
```

## Projectie met JSON Pointer

Herhaal `--field` met JSON Pointers volgens RFC 6901 om exacte waarden of statusitems uit te voeren:

```bash
healthmd extract --category Sleep --last 7 \
  --field /sleep/totalDuration \
  --field /sleep/deepSleep \
  --field /raw_capture_status \
  --output selected-sleep-fields.json
```

Pointerresultaten zijn projecties, geen volledige dagdocumenten. Ze verwijzen naar het bronschema en de dag, maar bevatten `schema: healthmd.health_data` niet op een manier waardoor een subboom op een volledige export kan lijken.

Een geselecteerd pad dat ontbreekt, wordt gemeld als volledig leeg of met de onvolledige status van de dag. Health.md zet afwezigheid niet om in nul.

## JSON-uitvoer

De standaard-JSON-uitvoer bevat een van deze gegevensverzamelingen:

- `health_data` voor volledige canonieke dagdocumenten; of
- `projections` voor resultaten van object- of pointerselecties.

De uitvoer bevat ook `healthmd.extract_receipt`, waarin het volgende staat:

- de opgeloste selectie en het datumbereik;
- de bron en het detailniveau;
- resultaten per dag;
- aantallen behouden items en vastleggingen;
- ontbrekende datums;
- diagnostiek voor gedeeltelijke resultaten of fouten;
- de voltooiingsstatus van de uitvoer.

Het ontvangstbewijs is protocolmetadata. Het vervangt het bronschema niet.

## JSONL-uitvoer

Gebruik JSONL voor streamverwerking:

```bash
healthmd extract --category Sleep --last 30 \
  --format jsonl --output sleep.jsonl
```

Elke regel bevat één gegevensitem. Het ontvangstbewijs wordt niet met de stroom gezondheidsgegevens vermengd:

- met `--output` wordt het naar `OUTPUT.receipt.json` geschreven;
- zonder `--output` wordt het naar stderr geschreven.

Hierdoor gedragen pipelines zich voorspelbaar:

```bash
healthmd extract --metric workouts --last 30 \
  --object workouts --format jsonl --output workouts.jsonl

jq -c 'select(.workouts != null)' workouts.jsonl
jq '{status, retained_item_count, missing_dates}' workouts.jsonl.receipt.json
```

Stuur stderr niet naar de JSONL-parser. Stderr bevat het ontvangstbewijs en voortgang zonder gezondheidsgegevens.

## Volledige, lege en gedeeltelijke resultaten

Health.md houdt deze statussen afzonderlijk:

| Status | Betekenis |
|---|---|
| `success` | Elke gevraagde vertakking is voltooid, inclusief volledig lege vertakkingen |
| `complete_empty` | Het gevraagde bereik is weergegeven en bevatte geen waarnemingen |
| `partial_success` | Sommige gevraagde gegevens zijn behouden, maar ten minste één gevraagde vertakking is onvolledig |
| `failed` | Een gevraagde vertakking is mislukt |
| `unsupported` | Het platform of HealthKit ondersteunt de gevraagde vertakking niet |
| `skipped` | Health.md heeft die vertakking bewust niet opgevraagd |
| `cancelled` | De iPhone heeft de annulering bevestigd |
| `missing` | Een gevraagde dag of vertakking is niet weergegeven |

Een gedeeltelijke extractie voert standaard geen behouden gegevens uit. Voeg `--allow-partial` alleen toe als de ontvanger onvolledige bereiken kan accepteren en behouden:

```bash
healthmd extract --category Sleep --last 30 \
  --allow-partial --output sleep-partial.json
```

De flag wijzigt de uitvoer en afsluitcode. Diagnostiek blijft behouden en gedeeltelijke gegevens worden niet als volledig aangemerkt.

## Backends van de Mac-app en rechtstreekse verbinding

De opdracht werkt via beide backends:

```bash
# Bundled helper default: Mac app loopback and connected iPhone
healthmd extract --category Sleep --last 7 --output sleep.json

# Direct-capable helper: bypass the Mac app
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json
```

Beide routes gebruiken hetzelfde openbare dagschema en dezelfde strikte validatie. Transport, koppeling, opslag en taakrecords verschillen.

## Omvangrijke geschiedenis

`--all` heeft geen vaste datumlimiet:

```bash
healthmd extract --metric steps --all --output all-steps.json
```

De iPhone bepaalt het oudste beschikbare geselecteerde record, zet elke kalenderdag van de bron tot en met vandaag vast en draagt afgebakende partities over. De CLI stelt gegevens op schijf samen en valideert ze daar, in plaats van één onbegrensd antwoord in het geheugen op te bouwen.

Gebruik JSONL of een beperktere selectie voor een groot corpus. De beschikbare schijfruimte en één uitzonderlijk gegevensrijke dag blijven praktische grenzen.

## Privacychecklist

- Gebruik bij voorkeur `--output` voor elk resultaat dat gezondheidsgegevens bevat.
- Bescherm uitvoer- en ontvangstbestanden even zorgvuldig als de Apple Health-bron.
- Gebruik geen shelltracing rond gezondheidsopdrachten.
- Houd payloads uit CI-logboeken en agenttranscripten.
- Bekijk bij probleemoplossing alleen velden voor het ontvangstbewijs, aantallen, status, schema en ontbrekende gegevens.
- Verwijder tijdelijke exports nadat de bedoelde ontvanger ze veilig heeft vastgelegd.

## Gerelateerde documentatie

<div class="related">
  <a href="/nl/docs/cli/"><span>CLI</span>Health.md-CLI: configuratie, backendselectie, opdrachtoverzicht en uitvoerregels.</a>
  <a href="/nl/docs/agent-queries/"><span>Afgeleide weergaven</span>Recepten voor getypeerde queries: meetwaardereeksen, slaap, training, work-outs, vergelijkingen en bewijs.</a>
  <a href="/nl/docs/reference/daily-records/"><span>Schema</span>Dagrecords: het volledige contract voor dagdocumenten volgens schema v7.</a>
  <a href="/nl/docs/reference/canonical-healthkit-records/"><span>Bronarchief</span>Canonieke Apple Health-records: identiteit, herkomst, relaties en payloads.</a>
  <a href="/nl/docs/reference/api-and-cli/"><span>Protocol</span>API- en CLI-referentie: extractieverzoeken, ontvangstbewijzen, strikte validatie en afsluitgedrag.</a>
</div>
