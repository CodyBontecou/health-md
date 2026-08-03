---
title: "CLI rechtstreeks naar de iPhone"
description: "Koppel healthmd via Manual IP, Tailscale of ondersteund Nearby-transport aan een iPhone en exporteer zonder Health.md voor Mac uit te voeren."
---

De rechtstreekse backend verbindt `healthmd` met een geopende Health.md-app op de iPhone zonder de opdracht via Health.md voor Mac te sturen. De iPhone leest HealthKit, zet het resultaat klaar in beveiligde opslag en draagt gevalideerde partities over aan de CLI.

```text
healthmd on the computer
  <-> authenticated encrypted Manual IP, Tailscale, or supported Nearby channel
Health.md on iPhone -> HealthKit -> protected bounded spool / typed query evaluator
  -> canonical JSON, production-generated files, or bounded MCP query pages
```

<div class="availability preview">
<strong>Preview · platformonafhankelijke directe CLI</strong>
<p>De gebundelde rechtstreekse Swift-backend is beschikbaar op macOS. De platformonafhankelijke Rust-client is een alpha die wacht op release-QA met een fysieke iPhone en het eerste openbare pakket. De opdrachten voor Linux en Windows beschrijven de voorbereide workflow.</p>
</div>

## Ondersteuning in de directe modus

- eenmalige koppeling en opnieuw verbinden met een vertrouwd apparaat;
- lokale inspectie en ontkoppeling van vertrouwde apparaten;
- actuele gereedheid van de iPhone;
- strikte onbewerkte export volgens schema v7;
- geselecteerde canonieke extractie;
- export van bestanden met de productie-exporters;
- status en hervatting van persistente lokale taken;
- expliciete annulering;
- de stdio-server `healthmd mcp serve` in hetzelfde uitvoerbare bestand, met rechtstreekse getypeerde queries, de meetwaardecatalogus, bewijs, de MCP Apps-interface en een PNG-alternatief.

De rechtstreekse backend van de opdracht `healthmd` bootst de HTTP-routes voor versleutelde context van de Mac-app niet na. Subopdrachten voor de Mac, zoals `doctor`, queries, bewijs en verversing, geven daarom nog steeds `backend_unsupported` terug in plaats van van backend te wisselen. Gebruik `healthmd mcp serve` voor nieuwe getypeerde analyse rechtstreeks op de iPhone. Je kunt ook `healthmd setup codex` uitvoeren om Codex automatisch te configureren en te koppelen. `healthmd mcp schema [TOOL]` toont lokaal het exacte geneste MCP-invoerschema en voorbeelden. Gebruik voor slaap rechtstreeks `healthmd_sleep_sessions` en behandel canonieke `extract`-uitvoer niet als de getypeerde query-API.

## Vereisten

- Een versie van `healthmd` die rechtstreekse toegang ondersteunt en een bijpassende versie van Health.md op de iPhone.
- Health.md op de voorgrond van een iPhone voor koppeling en nieuwe opdrachten.
- **Instellingen > Mac-synchronisatie > Direct CLI-toegang** ingeschakeld op de iPhone.
- Beschikbare HealthKit-toestemming, beveiligde gegevens, toestemming voor het lokale netwerk en exporttegoed.
- Een bereikbaar computeradres en TCP-poort `17647` voor Manual IP. Een Tailscale-adres werkt ook.
- Een bestaande absolute bestemming voor de modus met gegenereerde bestanden.

De CLI luistert. De iPhone maakt verbinding met het computeradres dat bij Direct CLI-toegang is ingevoerd.

## Ondersteunde transporten

| Transport | Gebundeld Swift-hulpprogramma op macOS | Platformonafhankelijke Rust-client |
|---|---:|---:|
| Manual IP op een LAN | Ja | macOS, Linux, Windows |
| Tailscale-adres | Ja | macOS, Linux, Windows |
| Nearby / MultipeerConnectivity | Ja | Nee |

Nearby gebruikt de versleutelde Multipeer-sessie van Apple en dezelfde authenticatie en versleuteling op Health.md-applicatieniveau als Manual IP. De platformonafhankelijke client geeft voor Nearby `transport_unsupported` terug.

## Eenmalig koppelen via Manual IP

Start de listener op de computer:

```bash
healthmd direct pair --transport manual-ip
```

De opdracht schrijft een zescijferige code, mogelijke computeradressen en de listenerpoort naar stderr. Stdout blijft gereserveerd voor het uiteindelijke JSON-resultaat.

Op de iPhone:

1. Open **Health.md > Instellingen > Mac-synchronisatie > Direct CLI-toegang**.
2. Schakel Direct CLI-toegang in.
3. Selecteer **Manual IP**.
4. Voer het LAN- of Tailscale-adres van de computer in.
5. Voer poort `17647` in, tenzij de CLI een andere algemene `--port` gebruikt.
6. Voer de koppelingscode in en tik op Koppelen.
7. Houd de app geopend totdat beide kanten melden dat de koppeling is geslaagd.

Koppelingscodes verlopen na 10 minuten. Ze worden nooit via het netwerk verstuurd of blijvend opgeslagen.

Gebruik zo nodig een andere poort:

```bash
healthmd --port 18000 direct pair --transport manual-ip
healthmd --backend direct --port 18000 status
```

Blijf dezelfde expliciete poort gebruiken voor latere opdrachten voor status, export, hervatten en annuleren.

## Koppelen via Nearby

Nearby is alleen beschikbaar in het gebundelde Swift-hulpprogramma:

```bash
healthmd direct pair --transport nearby
```

Selecteer Nearby bij Direct CLI-toegang op de iPhone, voer de weergegeven code in en houd beide apparaten geopend totdat de koppeling is voltooid. Een mislukte Nearby-bewerking schakelt niet over op Manual IP.

## Vertrouwde apparaten

De koppeling maakt een vertrouwensrelatie die losstaat van de synchronisatierelatie met de Health.md-app op de Mac.

```bash
healthmd direct devices
healthmd direct unpair DEVICE_UUID
```

Deze opdrachten lezen of wijzigen het lokale vertrouwen en maken geen verbinding met de iPhone. Gebruik op de iPhone **Gekoppelde CLI vergeten** om de andere kant te verwijderen.

Als meer dan één iPhone wordt vertrouwd, selecteer je de bedoelde installatie expliciet:

```bash
healthmd --backend direct --device DEVICE_UUID status
```

Gebruik `healthmd direct reset-trust --confirm` alleen als het lokale vertrouwen beschadigd is of bij een vervangen installatie hoort. De opdracht verwijdert alle lokale rechtstreekse koppelingen. Vergeet die koppelingen ook op de iPhone voordat je opnieuw begint.

## Actuele gereedheid controleren

```bash
healthmd --backend direct --transport manual-ip status
```

Een rechtstreeks statusantwoord meldt de verbindings- en veiligheidsstatus zonder gezondheidswaarden. Controleer deze velden voordat je begint:

| Veld | Gereedheidsstatus |
|---|---|
| `backend` | `direct` |
| `mac_app` | `bypassed` |
| `direct_cli.paired` | `true` |
| `iphone.connected` | `true` |
| `iphone.app_active` | `true` voor nieuw werk |
| `iphone.protected_data_available` | `true` |
| `iphone.can_trigger_raw_exports` | `true` voor onbewerkte export en extractie |
| `iphone.can_trigger_exports` | `true` voor gegenereerde bestanden |

In de rechtstreekse status blijft de bestemming ongeselecteerd. De bestandsmodus gebruikt uitsluitend de expliciete `--destination` die aan de opdracht is meegegeven.

## Strikte onbewerkte export

Kies één bereikselectie:

```bash
healthmd --backend direct export --yesterday --raw --output yesterday.json
healthmd --backend direct export --last 7 --raw --output week.json
healthmd --backend direct export \
  --from 2026-07-01 --to 2026-07-07 --raw --output range.json
healthmd --backend direct export --all --raw --output complete-health-corpus.json
```

Laat `--output` weg om gevalideerde JSON naar stdout te streamen. Een uitvoerbestand is veiliger voor gevoelige of omvangrijke antwoorden.

Strikte onbewerkte export geeft `healthmd.raw_result` v1 terug met gewone dagen volgens schema v7 `healthmd.health_data` en de bijbehorende canonieke bronarchieven. De export vraagt tijdelijk verliesvrij detail op zonder opgeslagen iPhone-instellingen te wijzigen. Voordat het resultaat beschikbaar komt, valideert de CLI de exacte datums, het profiel, schema, archief, de manifesten, digestketen, uiteindelijke digest van de hoofdtekst en voltooiingsstatus.

Een volledig lege dag geldt als geslaagd. Ontbrekende, gedeeltelijke, mislukte, geannuleerde, niet-ondersteunde of overgeslagen gevraagde gegevens leveren `partial_success` en een afsluitcode anders dan nul op, tenzij `--allow-partial` expliciet is opgegeven.

## Canonieke extractie

Rechtstreekse extractie gebruikt hetzelfde persistente onbewerkte transport, maar geeft geselecteerde gegevens in de vorm van de bron terug in plaats van de transportwrapper:

```bash
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json

healthmd --backend direct extract \
  --metric workouts --last 14 --object records \
  --detail lossless --output workout-records.json
```

De selectie van meetwaarden, categorieën, bronnen en het detailniveau bereikt de iPhone voordat HealthKit wordt uitgelezen. Lees [Canonieke extractie](/nl/docs/cli-extract/) voor objectselecties, JSON Pointers, JSONL en ontvangstbewijzen.

## Bestanden uit de productie-exporters

In de rechtstreekse bestandsmodus voert de iPhone de productie-exporters van Health.md uit en draagt daarna de gemaakte bestanden over naar een expliciete bestemming op de computer.

```bash
mkdir -p "$HOME/Documents/HealthVault"

healthmd --backend direct export --yesterday \
  --destination "$HOME/Documents/HealthVault"

healthmd --backend direct export --last 7 \
  --category Sleep --detail summary \
  --destination "$HOME/Documents/HealthVault"

healthmd --backend direct export --yesterday --use-iphone-settings \
  --destination "$HOME/Documents/HealthVault"
```

De bestemming moet al bestaan, absoluut zijn en mag niet via een symbolische koppeling worden herleid. De rechtstreekse modus raadt nooit een bestemming en gebruikt geen bladwijzer van de Mac-app. `--output` is bestemd voor onbewerkte uitvoer of extractie; `--destination` is bestemd voor gegenereerde bestanden.

Standaard behoudt een verzoek de opgeslagen formaten, Health-submap, bestandsnamen, sjablonen, schrijfmodus, Invoegen in dagelijkse notities en Alleen dagelijkse notities. Voor die taak worden periodeoverzichten en de modus met alleen samenvattingen onderdrukt. Herhaalbare opties `--metric` of `--category` en `--detail` vervangen alleen het bereik van meetwaarden en details van de taak. `--use-iphone-settings` neemt alle opgeslagen instellingen over en kan niet met selecties worden gecombineerd.

De iPhone kan JSON, CSV, Markdown, ZIP, gegevenswoordenboeken, periodeoverzichten, individuele records, dagelijkse notities en provider-sidecars klaarzetten. Voordat bestanden worden vastgelegd, valideert de CLI elk relatief pad, byteaantal, elke digest, het bestandsmanifest, de bestemmingsidentiteit en de vingerafdruk van het verzoek. De CLI wijst directory traversal, symbolische koppelingen in bovenliggende mappen, wijzigingen aan de hoofdmap, padconflicten en gewijzigde digests af. Overschrijven is atomair. Toevoegen en samenvoegen van Markdown gebruiken opgeslagen plannen, zodat opnieuw afspelen geen dubbele inhoud oplevert.

Bestemmingen voor gegenereerde bestanden werken op macOS en Linux. Protocol v1 wijst ze af op Windows. Gebruikers van de rechtstreekse modus op Windows kunnen onbewerkte export en extractie gebruiken.

## Gedrag op de voorgrond en achtergrond

Voor koppeling en nieuw werk moet de iPhone-app op de voorgrond staan. Direct CLI-toegang maakt van iOS geen headless exportserver en kan de app niet op verzoek activeren.

Als een export al verbonden is wanneer de app naar de achtergrond gaat, vraagt Health.md een beperkte hoeveelheid iOS-achtergrondtijd aan. De export kan binnen die periode worden voltooid. Verstrijkt de toegewezen tijd, dan sluit de verbinding en pauzeert de persistente taak. Open Health.md opnieuw en hervat dezelfde taak.

Tijdens rechtstreeks werk toont de iPhone een algemene activiteitsbanner. Deze vermeldt de vastleggings- en overdrachtsfase, voltooide dagen, bytevoortgang en de gepauzeerde of voltooide status zonder gezondheidswaarden te tonen.

## Persistente taken hervatten en annuleren

Rechtstreekse taken verlopen zeven dagen nadat ze zijn aangemaakt. Een time-out, Ctrl-C, beëindigd proces, verbroken verbinding of verstreken achtergrondtijd annuleert ze niet.

```bash
healthmd --backend direct status --job JOB_UUID
healthmd --backend direct resume JOB_UUID --timeout 300 --output recovered.json
healthmd --backend direct cancel JOB_UUID
```

Bij hervatten blijven de oorspronkelijke datums, instellingen, bestemming, vingerafdruk van het verzoek, het apparaat en het partitievoortgangspunt behouden. Je kunt een bestandstaak tijdens het hervatten niet naar een andere bestemming laten schrijven.

Annuleren legt een blijvend verzoek vast, maar de annulering is pas definitief nadat de iPhone deze heeft bevestigd. Als de iPhone niet beschikbaar is, blijft de status `cancellation_pending`. Open dezelfde iPhone opnieuw en probeer de annulering nogmaals.

## Beveiligingsmodel

- De koppeling gebruikt tijdelijke Curve25519-sleuteluitwisseling en transcriptbewijzen die aan de zescijferige code zijn gebonden.
- Bij opnieuw verbinden worden een willekeurig opgeslagen geheim en beide installatie-identiteiten bewezen.
- Elke verbinding leidt nieuwe sleutels en nonces af.
- Berichten en binaire frames gebruiken ChaCha20-Poly1305 met controles op oplopende volgnummers.
- Partities gebruiken SHA-256-manifesten en een gekoppeld digestvoortgangspunt.
- Vertrouwen op de iPhone wordt in de sleutelhanger bewaard.
- Platformonafhankelijk vertrouwen gebruikt de sleutelhanger, Secret Service of Windows Credential Manager en valt nooit terug op platte tekst.
- Spools en journalen gebruiken privéopslag van de app en worden uitgesloten van reservekopieën waar het platform dit ondersteunt.

Manual IP blijft versleuteld op een lokaal netwerk of via Tailscale. Tailscale beschermt ook het netwerkpad, maar vervangt de authenticatie van de Health.md-app niet.

## Veelvoorkomende fouten

| Fout | Actie |
|---|---|
| `direct_not_paired` | Koppel deze CLI-installatie met de iPhone. |
| `direct_device_selection_required` | Geef met `--device` het bedoelde vertrouwde apparaat door. |
| `direct_trust_invalid` | Bewaar de diagnostiek. Stel vertrouwen alleen opnieuw in als herstel onmogelijk is. |
| `direct_iphone_unavailable` | Controleer of de app op de voorgrond staat, de toegangsschakelaar, het adres, de poort, toestemming en bereikbaarheid via LAN of Tailscale. |
| `direct_export_paused` | Bekijk de taak, open de iPhone opnieuw en hervat de taak. |
| `direct_cancellation_pending` | Open de gekoppelde iPhone opnieuw en probeer de annulering nogmaals. |
| `transport_unsupported` | Gebruik Manual IP of Tailscale in de platformonafhankelijke client. |
| `backend_unsupported` | Gebruik de backend van de Mac-app voor query's, bewijs, doctor, meetwaarden of MCP. |
| `invalid_direct_raw_response` | Gebruik de uitvoer niet. Bewaar de validatiediagnostiek. |
| `invalid_direct_file_receipt` | Herstel bestanden niet handmatig. Bekijk en hervat de taak. |
| `job_expired` | De levensduur van de status van zeven dagen is verstreken. Vraag om bevestiging voordat je nieuw werk start. |

## Gerelateerde documentatie

<div class="related">
  <a href="/nl/docs/cli/"><span>Overzicht</span>Health.md-CLI: installeer de gebundelde hulpprogramma's en kies de juiste backend.</a>
  <a href="/nl/docs/cli-extract/"><span>Gegevens</span>Canonieke extractie: selecteer Health.md-gegevens en voer ze uit in de vorm van de bron.</a>
  <a href="/nl/docs/cli-jobs/"><span>Betrouwbaarheid</span>Persistente taken en automatisering: hervatten, annuleren, gedeeltelijke resultaten en scripts.</a>
  <a href="/nl/docs/reference/connected-mac-iphone-protocol/"><span>Protocol</span>Referentie voor verbonden Mac en iPhone: mogelijkheden, afgebakende overdracht en resultaatstatussen.</a>
</div>
