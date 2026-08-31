---
title: "Lokale agents en gezondheidscontext"
description: "Verbind lokale agents met Health.md via afgebakende CLI-opdrachten of MCP rechtstreeks op de iPhone, met behoud van bewijs, dekking en ontbrekende gegevens."
---

Health.md biedt lokale programmeer- en automatiseringsagents twee manieren om met Apple Health-gegevens te werken:

- de `healthmd`-CLI voor expliciete terminalopdrachten en canonieke extractie;
- `healthmd mcp serve` en de bijbehorende MCP App voor getypeerde tools, systeemeigen visualisaties en goedgekeurde exports van gegenereerde bestanden.

De platformonafhankelijke MCP-server communiceert rechtstreeks met de iPhone-app op de voorgrond en vereist Health.md voor Mac niet. De CLI kan hetzelfde rechtstreekse kanaal gebruiken voor onbewerkte of canonieke exports. Voor workflows met de Mac-index kan de CLI ook de loopback-API van de Mac-app gebruiken. HealthKit wordt altijd op de iPhone uitgelezen en `healthmd.health_data` v8 blijft het openbare broncontract.

```text
local agent -> healthmd mcp serve -> authenticated encrypted port 17647 -> foreground iPhone
local agent -> healthmd CLI -> direct iPhone or optional Mac loopback workflow
```

## Wat een agent kan doen

- controleren of de rechtstreekse koppeling en de iPhone-app op de voorgrond gereed zijn zonder gezondheidswaarden te lezen;
- canonieke meetwaarde-ID's en categorieën weergeven;
- een exact bereik van meetwaarde, bron, datum en detailniveau op de iPhone ophalen;
- canonieke dagdocumenten of bronrecords extraheren;
- getypeerde meetwaardereeksen met bewijs en dekking opvragen;
- stabiele slaapsessies en vaste slaapvensters samenstellen;
- work-outs afstemmen op de slaap ervoor en erna;
- work-outs weergeven en de dekking controleren;
- exacte perioden vergelijken met een expliciete aggregatie;
- feitelijke bewijsbundels voor trainingen maken;
- met afgebakende verzoeken door een logisch onbegrensd corpus bladeren;
- weergaven van meetwaarden, slaap, work-outs, vergelijkingen, dekking en bewijs tonen in MCP Apps;
- goedgekeurde exports van gegenereerde bestanden uitvoeren naar een expliciete, bestaande bestemming op de computer;
- persistente exporttaken bekijken, hervatten of annuleren.

Health.md stelt geen diagnose, beveelt geen behandeling aan, leidt geen oorzakelijk verband af en noemt een resultaat niet gezond, schadelijk, beter of slechter.

## De lokale hulpprogramma's instellen

<div class="availability preview">
<strong>Openbare preview · nog geen gekwalificeerde stabiele versie</strong>
<p>Het platformonafhankelijke pakket is gepubliceerd als een expliciet niet-gekwalificeerde preview. Gebruik de exacte mobiele build uit het releasebewijs; het ondertekende Mac-hulpprogramma blijft beschikbaar via <a href="/nl/docs/configuration/">Configureer je agent</a>.</p>
</div>

1. Voer op macOS of Linux `brew install CodyBontecou/tap/healthmd` uit en controleer daarna `healthmd --version`.
2. Voer `healthmd setup codex` uit. De opdracht configureert Codex en start de koppeling als de iPhone nog niet wordt vertrouwd.
3. Rond de koppeling af onder Direct CLI-toegang in Health.md op de iPhone en houd de app op de voorgrond.
4. Configureer voor Claude of een handmatig ingestelde host het absolute pad naar `healthmd` met de argumenten `mcp serve`, zoals beschreven in [Health.md MCP-server en App](/nl/docs/mcp/).
5. Start de host opnieuw als de configuratie volgens de setup is gewijzigd en roep daarna `healthmd_doctor` aan.

## Een agentskill installeren

Voor Mac-gebruikers blijft de Health.md-app op de Mac een optionele installatie- en distributieroute voor de skill. De app is geen vereiste voor platformonafhankelijke MCP.

De meeste gebruikers installeren alleen de [Health.md CLI-consumentenskill op skills.sh](https://skills.sh/CodyBontecou/health-md/healthmd-cli):

```bash
npx skills add CodyBontecou/health-md@healthmd-cli
```

De openbare repository biedt vier taakspecifieke skills:

| Skill | Bedoeld gebruik |
|---|---|
| `healthmd-cli` | Afgebakende, door de gebruiker geautoriseerde CLI- en MCP-query's en exports |
| `healthmd-cli-operator` | Rechtstreekse iPhone-bewerkingen en herstel van persistente taken |
| `healthmd-cli-development` | Ontwikkeling van CLI, MCP, protocol en iPhone-service |
| `healthmd-cli-qa` | Geautomatiseerde validatie en tests op fysieke apparaten |

Installeer een bijdragersskill door de naam na `@` te vervangen; installeer geen ontwikkel- of QA-instructies voor gewone verzoeken om gezondheidsgegevens. Gebruik `npx skills add CodyBontecou/health-md --list` om de repository te bekijken zonder een skill te installeren en `npx skills update healthmd-cli --project --yes` om de projectgebonden consumentenskill bij te werken. De [installatiehandleiding in de repository](https://github.com/CodyBontecou/health-md/blob/main/docs/agents/skills.md) documenteert alle opdrachten en het publicatiecontract.

Een skill is een instructiebundel. Deze installeert geen `healthmd` of `healthmd-mcp`, configureert MCP niet, koppelt geen telefoon, verleent geen toegang tot gezondheidsgegevens en werkt zichzelf niet automatisch bij. Controleer voor installatie de broncode.

Het installatieprogramma voor skills maakt `healthmd-cli/SKILL.md` aan in de map die je goedkeurt. Het vervangt uitsluitend de eigen skillmap van Health.md. De skill beschrijft afgebakende opdrachten, verwerking van gestructureerde resultaten, privacyregels, grenzen voor openbaarmaking aan de modelprovider en veilig herstel na een onbekende uitkomst.

Gebruik de configuratieprompt in de Mac-app als je een agent de symbolische koppelingen wilt laten maken. Health.md wijzigt zelf nooit ongemerkt shell-opstartbestanden of `/usr/local/bin`.

## Controleer eerst de gereedheid

Roep voor platformonafhankelijke MCP-clients `healthmd_doctor` aan. De tool controleert het lokale vertrouwen voor de rechtstreekse verbinding en de verbonden iPhone-app op de voorgrond zonder gezondheidswaarden te lezen. Bij problemen geeft hij bruikbare fouten zonder gezondheidsgegevens terug. Elke getypeerde MCP-query is daarna een expliciet nieuw verzoek aan die iPhone: de app legt alleen het gevraagde bereik vast, voert de getypeerde query op het apparaat uit en geeft afgebakende pagina's terug.

Gebruikers van de CLI via Mac-loopback kunnen nog steeds `healthmd doctor` uitvoeren voor gereedheid volgens `healthmd.cli_doctor` v1, dekking van de versleutelde context en vervolgstappen.

## Elk verzoek bevat een eigen bereik

Health.md gebruikt geen opgeslagen toegangsprofielen, aanroeperregistraties, toestemmingsrecords of CLI-inloggegevens. Elk verzoek geeft het volledige benodigde gegevensbereik op:

- meetwaarde-ID's of categorieën;
- bronselecties voor Apple Health en optionele providers;
- exacte datums of alle beschikbare datums;
- samenvattings- of verliesvrij detailniveau;
- de querybewerking;
- afgebakende instellingen voor paginering.

Bij een nieuwe gegevensophaling valideert Health.md het bereik aan de hand van de huidige catalogi, bewaart het bereik bij de persistente taak en past het op de iPhone toe zonder opgeslagen exportvoorkeuren te wijzigen.

Een verzoek zonder expliciete selectie voor gegevensophaling wordt afgewezen. Health.md neemt dan niet stilzwijgend de gewone exportinstellingen over.

## Autorisatiegrenzen

Platformonafhankelijke MCP gebruikt het gekoppelde directe protocol: systeemeigen opslag voor inloggegevens, wederzijdse authenticatie van het transcript, versleutelde pakketten, bescherming tegen herhaling en een verbinding met de iPhone-app op de voorgrond via het expliciete adres van de computer. De optionele Mac-query-API luistert alleen op IPv4- en IPv6-loopback en controleert of de peer een loopbackadres gebruikt.

In de optionele Mac-loopbackmodus kan elk lokaal proces dat poort `17645` bereikt terwijl Health.md geopend is dezelfde queryverzoeken indienen. Behandel toegang tot de lokale computer daarom als bevoegdheid om queries uit te voeren:

- bind de poort niet aan en proxy hem niet via een LAN-interface;
- tunnel de poort niet naar een andere computer;
- plaats geen omgekeerde HTTP-proxy voor de poort;
- configureer MCP niet met een URL die geen loopbackadres gebruikt;
- controleer welke lokale agents het hulpprogramma kunnen uitvoeren.

Voormalige routes voor profielen en activiteiten geven voor compatibiliteit `410 removed_endpoint` terug.

## Canonieke gegevens en afgeleide weergaven

Gebruik `healthmd extract` als de agent gegevens in de vorm van de bron of een omvangrijke, gevalideerde onbewerkte of canonieke inhoud nodig heeft:

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

Gebruik queryopdrachten of MCP-tools voor afgeleide weergaven en visualisaties in de host:

```bash
healthmd query --metric resting_heart_rate --last 30 --all-pages
healthmd sleep sessions --last-nights 14 --window first:4h
healthmd training align --last 14 --workout running --sleep-window first:4h
```

Dit onderscheid is bewust aangebracht:

| Interface | Rol in het contract |
|---|---|
| `healthmd.health_data` v8 | Openbaar dagelijks brondocument |
| `healthmd.healthkit_records` v1 | Canoniek bronrecordarchief in verliesvrije dagdocumenten |
| `healthmd.extract_receipt` | Bereik en voltooiingsmetadata van de extractie |
| `healthmd.query_context_day` v1 | Wegwerpbaar versleuteld indexrecord |
| `healthmd.query_response` v1 | Getypeerd, gepagineerd afgeleid resultaat |
| `healthmd.evidence_packet` v1 | Feitelijke bundel die aan bronbewijs is gekoppeld |
| Taak- en doorloopontvangstbewijzen | Metadata over transport, duurzaamheid en voltooiing |

Een samenvattingsweergave of getypeerd resultaat doet zich nooit voor als een volledig dagelijks brondocument.

## Nieuwe gegevens ophalen

Query's op hoog niveau halen standaard nieuwe gegevens op:

```bash
healthmd query --category Sleep --last 14
```

Health.md maakt een afzonderlijk verzoek voor versleutelde context. Het schrijft geen exportbestanden en verbruikt geen tegoed voor bestandsexports. De iPhone leest het expliciete bereik, bouwt deterministische compacte eigenaarsdagen en verstuurt afgebakende partities die kunnen worden hervat. De Mac legt elke versleutelde dag vast voordat hij de ontvangst bevestigt.

Bij voltooiing controleert Health.md elke gevraagde meetwaarde, bron of provider en eigenaarsdag aan de hand van blobs die zijn vervangen nadat deze verversing begon. Oudere waarden uit de cache of gegevens van een andere provider kunnen een mislukte gegevensophaling niet verhullen.

Verzoeken die alleen een provider gebruiken, kunnen HealthKit overslaan. Het doorlopen van de providergeschiedenis volgt de systeemeigen cursors van de provider en legt geen vaste limiet op het totale aantal resultaten op.

## Versleutelde context op de Mac

De Mac bewaart één onafhankelijk versleutelde generatie per eigenaarsdag. Een willekeurige 256-bits sleutel staat in de sleutelhanger als item dat alleen op dit apparaat en alleen na ontgrendeling beschikbaar is.

- dagblobs en het manifest gebruiken AES-256-GCM;
- bestandsnamen zijn willekeurige UUID's en bevatten geen datums of namen van meetwaarden;
- eigenaarsdatums en indexitems zijn versleuteld;
- bestanden hebben alleen machtigingen voor de eigenaar en worden uitgesloten van reservekopieën;
- bij het vastleggen wordt eerst een nieuwe onveranderlijke generatie geschreven en pas daarna het versleutelde manifest vervangen;
- leesbewerkingen worden veilig geweigerd bij ontbrekende sleutels, mislukte authenticatie, ongeldige datums of een afwijkend manifest.

De opslag heeft geen ingestelde limiet voor het totale aantal meetwaarden, dagen, geschiedenisitems of resultaten. Opdrachten blijven afgebakend doordat ze één dag tegelijk ontsleutelen en resultaten pagineren.

De index is wegwerpbaar. Canonieke exports blijven de bron van waarheid.

## Bewaren en verwijderen

Health.md verwijdert querycontext niet automatisch volgens een stilzwijgend bewaarschema. Instellingen op de Mac toont het aantal opgeslagen eigenaarsdagen en het datumbereik.

Gebruik:

- **Oudere context verwijderen** om eigenaarsdatums van vóór een gekozen grens te verwijderen;
- **Alle versleutelde context verwijderen** om elke versleutelde generatie en de speciale sleutel in de sleutelhanger te verwijderen.

Volledig verwijderen blijft mogelijk als de sleutel of cijfertekst beschadigd is. Door de sleutel te verwijderen worden eventuele niet-verwijderde resten van de cijfertekst cryptografisch gewist.

Het verwijderen van querycontext verwijdert geen exportbestanden, inloggegevens van verbonden providers of Apple Health-gegevens.

## Getypeerde waarden en ontbrekende gegevens

Querywaarden hebben een typelabel. Een resultaat kan een hoeveelheid met canonieke eenheid, duur, telling met teken, tekenreeks, categorie, Booleaanse waarde, UTC-tijdstempel, kalenderdatum, geneste array of een onbekende toekomstige getypeerde payload bevatten.

Ontbrekende gegevens blijven expliciet:

- `complete_empty` betekent dat het weergegeven bereik geen overeenkomende waarnemingen bevatte;
- `partial` betekent dat slechts een deel van het gevraagde bereik is voltooid;
- `failed`, `unsupported`, `skipped` en `cancelled` behouden elk hun eigen betekenis;
- `not_requested`, `legacy_unavailable`, `redacted` en `not_synchronized` blijven afzonderlijke statussen.

Health.md zet een ontbrekende waarde nooit om in het getal nul. Een echte nul wordt gecodeerd als beschikbare getypeerde waarde.

## Bewijs en neutrale formulering

Resultaten koppelen feiten aan bronbewijs, zoals:

- sleutels uit dagelijkse samenvattingen;
- canonieke HealthKit-UUID's;
- externe identiteiten;
- uitkomsten uit het querymanifest;
- integriteitswaarschuwingen;
- gedeeltelijke fouten.

Bij het herleiden van bewijs controleert Health.md samen de bewijs-ID, locator, het bronschema, de bronversie en de digest van de bron.

De richting van een periodevergelijking is beperkt tot `increased`, `decreased`, `unchanged` of `not_comparable`. Bij trainingsafstemming rapporteert Health.md tijdstempels en tussenpozen, geen oorzakelijke effecten. Bewijsbundels melden opgeslagen waarnemingen en dekking, geen medische conclusies.

Een agent hoort die grenzen in zijn antwoord te behouden. Hij moet ontbrekende gegevens benoemen, correlatie niet als oorzaak presenteren en medische vragen doorverwijzen naar een bevoegde zorgverlener.

## Afgebakende pagina's, volledige logische toegang

Querypagina's gebruiken `max_items`, `max_bytes` en een ondoorzichtige `next_cursor`. Op contractniveau bestaat geen limiet voor het totale aantal opgeslagen dagen, work-outs, meetwaarden of resultaatitems.

Een cursor is tegen manipulatie beschermd en gebonden aan de semantische query en de revisie van het versleutelde corpus. Health.md wijst het volgende af:

- een gewijzigde cursor;
- een cursor die bij een andere query wordt gebruikt;
- een cursor die is uitgegeven voordat het corpus veranderde;
- een herhaalde cursor tijdens automatische doorloop.

Gebruik `--all-pages` of MCP `all_pages: true` voor een afgebakende automatische doorloop. Verklein het bereik of blader handmatig als één aanroep de totale veiligheidsgrens bereikt.

## Checklist voor rapportage door agents

Vermeld bij een samenvatting van een resultaat:

- welke opdracht of tool is gebruikt;
- de exact gevraagde datums, meetwaarden, bron en het detailniveau;
- of nieuwe gegevens, cachegegevens of hergebruikte dekking zijn gebruikt;
- afzonderlijk de status van het gevraagde bereik en de status van het corpus;
- of de pagina of volledige doorloop is voltooid;
- de eenheden en het bronbewijs voor elke genoemde waarde;
- ontbrekende intervallen, beperkingen en niet-gerelateerde overgeslagen onderdelen;
- de taak-ID als werk is gepauzeerd of kan worden hervat.

Neem geen onbewerkte records, routes, klinische tekst, medicatiegegevens, stemmingsregistraties of bijlagen op, tenzij de gebruiker expliciet om die waarden vraagt en begrijpt dat ze worden gedeeld.

## Kies een integratie

<div class="related">
  <a href="/nl/docs/agent-queries/"><span>CLI-recepten</span>Getypeerde agentquery's: meetwaarden, slaapsessies, trainingsafstemming, work-outs, dekking, vergelijkingen en bewijs.</a>
  <a href="/nl/docs/mcp/"><span>Toolprotocol</span>Configuratie voor Codex en Claude, 21 uitgebrachte Mac-tools, 19 platformonafhankelijke previewtools, grafieken in MCP App, exports, paginering en sandboxgrenzen.</a>
  <a href="/nl/docs/agent-api/"><span>Laag niveau</span>Loopback-query-API: routes, rechtstreekse JSON-verzoeken, cursors en persistente taken voor gegevensophaling.</a>
  <a href="/nl/docs/cli-extract/"><span>Bronobjecten</span>Canonieke extractie: geselecteerde documenten, records, samenvattingsweergaven en ontvangstbewijzen uit schema v8.</a>
  <a href="/nl/docs/reference/evidence-packets/"><span>Contracten</span>Compacte queries en bewijsbundels: getypeerde waarden, dekking, bewerkingen en deterministische ID's.</a>
</div>
