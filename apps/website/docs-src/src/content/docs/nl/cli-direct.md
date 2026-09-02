---
title: "CLI rechtstreeks naar de telefoon"
description: "Koppel healthmd via Manual IP of Tailscale aan een iPhone of Android-telefoon en exporteer zonder Health.md voor Mac uit te voeren."
---

De rechtstreekse backend verbindt `healthmd` met een geopende Health.md-app op een iPhone of Android-telefoon zonder de opdracht via Health.md voor Mac te sturen. De telefoon leest het gezondheidsarchief van het platform — HealthKit op de iPhone, Health Connect op Android —, zet het resultaat klaar in beveiligde opslag en draagt gevalideerde partities over aan de CLI.

```text
healthmd on the computer
  <-> authenticated encrypted Manual IP, Tailscale, or supported Nearby channel
Health.md on iPhone or Android -> HealthKit / Health Connect -> protected bounded spool
  -> raw snapshots, production-generated files, or (iPhone) canonical and typed query data
```

<div class="availability preview">
<strong>Preview · platformonafhankelijke directe CLI</strong>
<p>De gebundelde rechtstreekse Swift-backend is beschikbaar op macOS en koppelt met de iPhone. Android met applicatieprotocol v2 maakt deel uit van de openbaar verpakte preview van de platformonafhankelijke Rust-client. Huidige iOS- en Android-versies gebruiken dezelfde selector 3 en dezelfde universele QR voor nieuwe platformonafhankelijke koppelingen. Release-QA met fysieke iPhones en Android-toestellen is nog niet voltooid; de opdrachten voor Linux en Windows beschrijven een expliciet ongekwalificeerde workflow.</p>
</div>

## Mobiele compatibiliteit voor 0.1.0-alpha.3

Deze zelfstandige tabel is de toepasbare matrix voor de uitdrukkelijk ongekwalificeerde preview. Er is nog geen openbare CLI/mobiele combinatie gekwalificeerd.

| Mobiele bron | Protocol | Exacte tag-SHA-tegenhanger / ongekwalificeerde ondergrens | Platformonafhankelijke Rust-bewerkingen | Openbare status |
|---|---|---|---|---|
| iPhone met export | huidige selector 3 (oude 1) / applicatie v1 | iOS 3.2.1 (build 202608300209) / iOS 3.0.3 | Status, onbewerkt, extractie, bestanden, hervatten, annuleren | Fysieke kwalificatie in afwachting |
| iPhone met queries | huidige selector 3 (oude 1) / applicatie v1 + query v3 | iOS 3.2.1 (build 202608300209) / iOS 3.0.3 | V1 plus lokale MCP/query met 19 tools | Fysieke kwalificatie in afwachting |
| Android | huidige selector 3 (oude 2) / applicatie v2 | Android 1.8.1 (`versionCode 30`) / Android 1.5.4 (`versionCode 25`) | Status, systeemeigen onbewerkt, bestanden, hervatten, annuleren | Fysieke kwalificatie in afwachting |
| Getypeerde Android-MCP-query | Niet beschikbaar | Niet geïmplementeerd | Querytools vereisen iPhone v3 | Niet ondersteund |

## Ondersteuning in de directe modus

- eenmalige koppeling via gedeelde selector 3 en opnieuw verbinden met een vertrouwd apparaat bij bronnen op de iPhone (applicatieprotocol v1) of op Android (applicatieprotocol v2);
- lokale inspectie en ontkoppeling van vertrouwde apparaten;
- actuele gereedheid van de telefoon;
- strikte onbewerkte export — schema v8 `healthmd.health_data` op de iPhone, systeemeigen Health Connect-momentopnames op Android;
- geselecteerde canonieke extractie (alleen iPhone);
- export van bestanden met de productie-exporters op beide telefoonplatforms;
- status en hervatting van persistente lokale taken;
- expliciete annulering;
- de stdio-server `healthmd mcp serve` in hetzelfde uitvoerbare bestand, met rechtstreekse getypeerde queries, de meetwaardecatalogus, bewijs, de MCP Apps-interface en een PNG-alternatief (alleen iPhone).

De rechtstreekse backend van de opdracht `healthmd` bootst de HTTP-routes voor versleutelde context van de Mac-app niet na. Subopdrachten voor de Mac, zoals `doctor`, queries, bewijs en verversing, geven daarom nog steeds `backend_unsupported` terug in plaats van van backend te wisselen. Gebruik `healthmd mcp serve` voor nieuwe getypeerde analyse rechtstreeks op de iPhone. Je kunt ook `healthmd setup codex` uitvoeren om Codex automatisch te configureren en te koppelen. `healthmd mcp schema [TOOL]` toont lokaal het exacte geneste MCP-invoerschema en voorbeelden. Gebruik voor slaap rechtstreeks `healthmd_sleep_sessions` en behandel canonieke `extract`-uitvoer niet als de getypeerde query-API.

## Vereisten

- Een versie van `healthmd` die rechtstreekse toegang ondersteunt en een bijpassende Health.md-build: iPhone (applicatieprotocol v1) of Android (applicatieprotocol v2). Android-koppeling vereist de platformonafhankelijke Rust-client; het gebundelde macOS-hulpprogramma koppelt alleen met de iPhone.
- Health.md op de voorgrond van de telefoon voor koppeling en nieuwe opdrachten.
- **Instellingen > Mac-synchronisatie > Direct CLI-toegang** ingeschakeld op de iPhone, of **Instellingen → Direct CLI** op Android.
- Beschikbare gezondheidstoestemming van het platform (HealthKit of Health Connect), beveiligde gegevens, toestemming voor het lokale netwerk en exporttegoed.
- Een bereikbaar computeradres en TCP-poort `17647` voor Manual IP. Een Tailscale-adres werkt ook.
- Een bestaande absolute bestemming voor de modus met gegenereerde bestanden.

De CLI luistert. De telefoon maakt verbinding met het computeradres dat bij Direct CLI-toegang is ingevoerd.

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

De platformonafhankelijke Rust-client toont één universele QR-code voor iOS en Android en schrijft de gedeelde code van twintig cijfers, mogelijke computeradressen, de listenerpoort en een zescijferige reservecode voor oudere iOS-versies naar stderr. Het gebundelde macOS-hulpprogramma toont nog steeds alleen de oude zescijferige iPhone-code. Stdout blijft gereserveerd voor het uiteindelijke JSON-resultaat.

Op de iPhone:

1. Open **Health.md > Instellingen > Mac-synchronisatie > Direct CLI-toegang** en schakel de toegang in.
2. Tik op **QR-code voor koppelen scannen** en scan de universele QR; de koppeling start direct na deze expliciete scan.
3. Als scannen niet beschikbaar is, selecteer je **Manual IP** en voer je adres, poort en de gedeelde twintigcijferige code in. Bij een oudere CLI blijft de zescijferige code bruikbaar.
4. Houd de app geopend totdat beide kanten melden dat de koppeling is geslaagd.

## Een Android-telefoon koppelen

1. Open **Health.md > Instellingen → Direct CLI** op de Android-telefoon.
2. Tik op **QR-code voor koppelen scannen** en scan de universele QR; de koppeling start direct na deze expliciete scan.
3. Zonder camera of toestemming kun je adres, poort en dezelfde gedeelde twintigcijferige code handmatig invoeren.
4. Houd de app geopend; voor een actieve rechtstreekse sessie draait Android een zichtbare, door de gebruiker gestarte voorgronddienst voor gegevenssynchronisatie.

De eenmalige codes worden nooit via het netwerk verstuurd of blijvend opgeslagen. Na het koppelen beschermt Keychain of Android Keystore het vertrouwen voor opnieuw verbinden.

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

Deze opdrachten lezen of wijzigen het lokale vertrouwen en maken geen verbinding met de telefoon. Gebruik op de iPhone **Gekoppelde CLI vergeten** om de andere kant te verwijderen; verwijder op Android de koppeling via **Instellingen → Direct CLI**.

Als meer dan één telefoon wordt vertrouwd, selecteer je de bedoelde installatie expliciet:

```bash
healthmd --backend direct --device DEVICE_UUID status
```

Gebruik `healthmd direct reset-trust --confirm` alleen als het lokale vertrouwen beschadigd is of bij een vervangen installatie hoort. De opdracht verwijdert alle lokale rechtstreekse koppelingen. Vergeet die koppelingen ook op de telefoon voordat je opnieuw begint.

## Actuele gereedheid controleren

```bash
healthmd --backend direct --transport manual-ip status
```

Een rechtstreeks statusantwoord meldt de verbindings- en veiligheidsstatus zonder gezondheidswaarden. De platformonafhankelijke client meldt de bron onder `source` met een `platform` van `ios` of `android`; het gebundelde hulpprogramma toont de onderstaande velden van `iphone`. Controleer deze velden voordat je begint (iPhone-bron getoond):

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

Een Android-bron meldt `platform: "android"` met `app_active`, `protected_data_available`, `export_in_progress` en de beschikbare onbewerkte producten, in plaats van de triggermarkeringen van de iPhone.

## Strikte onbewerkte export (iPhone)

Kies één bereikselectie:

```bash
healthmd --backend direct export --yesterday --raw --output yesterday.json
healthmd --backend direct export --last 7 --raw --output week.json
healthmd --backend direct export \
  --from 2026-07-01 --to 2026-07-07 --raw --output range.json
healthmd --backend direct export --all --raw --output complete-health-corpus.json
```

Laat `--output` weg om gevalideerde JSON naar stdout te streamen. Een uitvoerbestand is veiliger voor gevoelige of omvangrijke antwoorden.

Strikte onbewerkte export op de iPhone geeft `healthmd.raw_result` v1 terug met gewone dagen volgens schema v8 `healthmd.health_data` en de bijbehorende canonieke bronarchieven. De export vraagt tijdelijk verliesvrij detail op zonder opgeslagen iPhone-instellingen te wijzigen. Voordat het resultaat beschikbaar komt, valideert de CLI de exacte datums, het profiel, schema, archief, de manifesten, digestketen, uiteindelijke digest van de hoofdtekst en voltooiingsstatus.

Een volledig lege dag geldt als geslaagd. Ontbrekende, gedeeltelijke, mislukte, geannuleerde, niet-ondersteunde of overgeslagen gevraagde gegevens leveren `partial_success` en een afsluitcode anders dan nul op, tenzij `--allow-partial` expliciet is opgegeven.

## Systeemeigen onbewerkte provider-export (Android)

De platformonafhankelijke Rust-client is standaard rechtstreeks, dus onbewerkte Android-opdrachten laten de vlag `--backend` weg:

```bash
healthmd export --last 7 --raw --provider health_connect \
  --raw-format ndjson --output health-connect.ndjson
```

`--provider` benoemt één expliciete provider en staat standaard op `health_connect`. `--raw-format` staat standaard op NDJSON, de aanbevolen vorm voor omvangrijke momentopnames; validatie van JSON in het geheugen is begrensd op 64 MiB. Meetwaardeselectie ondersteunt `--metric` en `--all-metrics`, maar geen canonieke selectors of selectors voor gegenereerde bestanden — dat blijven iPhone-mogelijkheden.

Onbewerkte Android-momentopnames houden hun systeemeigen Health Connect-contract. Ze worden nooit omgezet in `healthmd.health_data`-dagen in HealthKit-vorm, en verwante maar verschillende statistieken behouden hun eigen identiteiten.

## Canonieke extractie

Rechtstreekse extractie gebruikt hetzelfde persistente onbewerkte transport, maar geeft geselecteerde gegevens in de vorm van de bron terug in plaats van de transportwrapper. Dit is een iPhone-mogelijkheid:

```bash
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json

healthmd --backend direct extract \
  --metric workouts --last 14 --object records \
  --detail lossless --output workout-records.json
```

De selectie van meetwaarden, categorieën, bronnen en het detailniveau bereikt de iPhone voordat HealthKit wordt uitgelezen. Lees [Canonieke extractie](/nl/docs/cli-extract/) voor objectselecties, JSON Pointers, JSONL en ontvangstbewijzen.

Zolang de telefoonapp op de voorgrond blijft, kan een vertrouwde rechtstreekse sessie na een tijdelijke verbreking automatisch opnieuw verbinden, met begrensde pogingen en wachttijden. Dit wekt geen achtergrondapp en belooft er geen toegang toe; open Health.md opnieuw vóór hervatten.

## Bestanden uit de productie-exporters

In de rechtstreekse bestandsmodus voert de telefoon de productie-exporters van Health.md uit en draagt daarna de gemaakte bestanden over naar een expliciete bestemming op de computer.

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

Bestemmingen voor gegenereerde bestanden werken voor zowel iPhone protocol v1 als Android protocol v2 op elk CLI-besturingssysteem — macOS, Linux en Windows. Android beperkt elke gegenereerde taak tot 4,096 bestanden.

Bestandstaken van Android protocol v2 halen hun uitvoerinstellingen uit de opgeslagen exportselecties op het apparaat of uit `--profile PROFILE_ID`; metriek-, categorie- en detailkiezers van de CLI worden afgewezen. Op beide telefoonplatforms zoekt `--profile` bevroren uitvoerinstellingen op, terwijl het verplichte `--destination` de expliciete computermap blijft aanwijzen.
Voor stabiele ID’s en veilig profielgedrag, zie [Exportprofielen](/nl/docs/export-profiles/).

## Gedrag op de voorgrond en achtergrond

Voor koppeling en nieuw werk moet de telefoon-app op de voorgrond staan. Direct CLI-toegang maakt van de telefoon geen headless exportserver en kan de app niet op verzoek activeren.

Op de iPhone geldt: als een export al verbonden is wanneer de app naar de achtergrond gaat, vraagt Health.md een beperkte hoeveelheid iOS-achtergrondtijd aan. De export kan binnen die periode worden voltooid. Verstrijkt de toegewezen tijd, dan sluit de verbinding en pauzeert de persistente taak. Open Health.md opnieuw en hervat dezelfde taak.

Op Android draait een actieve rechtstreekse sessie als zichtbare, door de gebruiker gestarte voorgronddienst voor gegevenssynchronisatie. Houd de app op de voorgrond voor koppeling en nieuw werk.

Op de iPhone toont een algemene activiteitsbanner tijdens rechtstreeks werk de vastleggings- en overdrachtsfase, voltooide dagen, bytevoortgang en de gepauzeerde of voltooide status zonder gezondheidswaarden te tonen.

Zolang de telefoon-app op de voorgrond blijft, kan een vertrouwde rechtstreekse sessie na een tijdelijke onderbreking automatisch opnieuw verbinden. Nieuwe pogingen gebruiken oplopende vertragingen met een korte bovengrens. Dit activeert een app op de achtergrond niet en belooft daar geen toegang toe; open Health.md opnieuw voordat je hervat als de app niet meer op de voorgrond staat.

Het begrensde wachtvenster van 120 seconden houdt hetzelfde verzoek open terwijl de gebruiker de telefoon ontgrendelt en Health.md opent. Pas het aan met `--wake-timeout SECONDS`; `0` schakelt het uit. MCP gebruikt `HEALTHMD_WAKE_TIMEOUT`. Deze eerste fase verzendt nog geen pushmelding en omzeilt ontgrendeling of machtigingen niet.

## Persistente taken hervatten en annuleren

Rechtstreekse taken verlopen zeven dagen nadat ze zijn aangemaakt. Een time-out, Ctrl-C, beëindigd proces, verbroken verbinding of verstreken achtergrondtijd annuleert ze niet.

```bash
healthmd --backend direct status --job JOB_UUID
healthmd --backend direct resume JOB_UUID --timeout 300 --output recovered.json
healthmd --backend direct cancel JOB_UUID
```

Bij hervatten blijven de oorspronkelijke datums, instellingen, bestemming, vingerafdruk van het verzoek, het apparaat en het partitievoortgangspunt behouden. Je kunt een bestandstaak tijdens het hervatten niet naar een andere bestemming laten schrijven.

Annuleren legt een blijvend verzoek vast, maar de annulering is pas definitief nadat de gekoppelde telefoon deze heeft bevestigd. Als de telefoon niet beschikbaar is, blijft de status `cancellation_pending`. Open dezelfde telefoon opnieuw en probeer de annulering nogmaals.

## Beveiligingsmodel

- Huidige platformonafhankelijke koppelingen gebruiken tijdelijke sleuteluitwisseling en transcriptbewijzen van selector 3 die zijn gebonden aan één gedeelde iOS-/Android-code van twintig cijfers (~66 bits) met hoge entropie. De oude Apple-selector-1- en Android-selector-2-stromen blijven bytecompatibel.
- QR-overdrachten worden alleen geaccepteerd door expliciete scanners in de app voor canonieke privé-LAN-/Tailscale-adressen; een externe aangepaste URL kan koppeling niet autoriseren.
- Bij opnieuw verbinden worden een willekeurig opgeslagen geheim en beide installatie-identiteiten bewezen.
- Elke verbinding leidt nieuwe sleutels en nonces af.
- Berichten en binaire frames gebruiken ChaCha20-Poly1305 met controles op oplopende volgnummers.
- Partities gebruiken SHA-256-manifesten en een gekoppeld digestvoortgangspunt.
- Vertrouwen op de iPhone wordt in de sleutelhanger bewaard; vertrouwen voor opnieuw verbinden op Android is gebaseerd op de Keystore.
- Platformonafhankelijk vertrouwen gebruikt de sleutelhanger, Secret Service of Windows Credential Manager en valt nooit terug op platte tekst.
- Spools en journalen gebruiken privéopslag van de app en worden uitgesloten van reservekopieën waar het platform dit ondersteunt.

Manual IP blijft versleuteld op een lokaal netwerk of via Tailscale. Tailscale beschermt ook het netwerkpad, maar vervangt de authenticatie van de Health.md-app niet.

## Veelvoorkomende fouten

| Fout | Actie |
|---|---|
| `direct_not_paired` | Koppel deze CLI-installatie met de bedoelde mobiele bron. |
| `direct_device_selection_required` | Geef met `--device` het bedoelde vertrouwde apparaat door. |
| `direct_trust_invalid` | Bewaar de diagnostiek. Stel vertrouwen alleen opnieuw in als herstel onmogelijk is. |
| `direct_iphone_unavailable` | Controleer of de app op de voorgrond staat, de toegangsschakelaar, het adres, de poort, toestemming en bereikbaarheid via LAN of Tailscale. |
| `direct_export_paused` | Bekijk de taak, open de gekoppelde telefoon opnieuw en hervat de taak. |
| `direct_cancellation_pending` | Open de gekoppelde telefoon opnieuw en probeer de annulering nogmaals. |
| `transport_unsupported` | Gebruik Manual IP of Tailscale in de platformonafhankelijke client. |
| `backend_unsupported` | Gebruik de backend van de Mac-app voor query's, bewijs, doctor, meetwaarden of MCP. |
| `invalid_direct_raw_response` | Gebruik de uitvoer niet. Bewaar de validatiediagnostiek. |
| `invalid_direct_file_receipt` | Herstel bestanden niet handmatig. Bekijk en hervat de taak. |
| `job_expired` | De levensduur van de status van zeven dagen is verstreken. Vraag om bevestiging voordat je nieuw werk start. |

## Gerelateerde documentatie

<div class="related">
  <a href="/nl/docs/cli/"><span>Overzicht</span>Health.md-CLI: installeer de gebundelde hulpprogramma's en kies de juiste backend.</a>
  <a href="/nl/docs/android/"><span>Android</span>Health.md voor Android: Health Connect-bronnen, mapbestemmingen en automatisering op het apparaat.</a>
  <a href="/nl/docs/cli-extract/"><span>Gegevens</span>Canonieke extractie: selecteer Health.md-gegevens en voer ze uit in de vorm van de bron (iPhone).</a>
  <a href="/nl/docs/cli-jobs/"><span>Betrouwbaarheid</span>Persistente taken en automatisering: hervatten, annuleren, gedeeltelijke resultaten en scripts.</a>
  <a href="/nl/docs/reference/connected-mac-iphone-protocol/"><span>Protocol</span>Referentie voor verbonden Mac en iPhone: mogelijkheden, afgebakende overdracht en resultaatstatussen.</a>
</div>
