---
title: "Health.md-CLI"
description: "Kies de backend van de Mac-app of de rechtstreekse iPhone-backend, installeer healthmd, controleer de gereedheid, exporteer bestanden, extraheer canonieke Apple Health-gegevens, voer getypeerde queries uit en automatiseer persistente taken."
---

De opdracht `healthmd` heeft twee werkmodi. Gebruik de backend van de Mac-app voor versleutelde lokale queries, MCP-tools of de bestemmingsmap die al in Health.md voor Mac is geselecteerd. Gebruik de rechtstreekse iPhone-backend voor onbewerkte gegevens of gegenereerde bestanden zonder de Mac-app uit te voeren.

<div class="callout">
<strong>HealthKit blijft op de iPhone.</strong>
<p style="margin-top:6px;">Geen van beide CLI-backends leest Apple Health uit op de computer. Voor elke nieuwe HealthKit-uitlezing moet de huidige Health.md-app op de iPhone geopend zijn. De CLI ontvangt gevalideerde resultaten of bestanden.</p>
</div>

## Een backend kiezen

| Mogelijkheid | Backend van de Mac-app | Rechtstreekse iPhone-backend |
|---|---|---|
| Standaard in het gebundelde Mac-hulpprogramma | Ja | Nee, selecteer met `--backend direct` |
| Vereist dat Health.md voor Mac geopend is | Ja | Nee |
| Vereist dat Health.md op de iPhone geopend is voor nieuwe gegevens | Ja | Ja |
| Bestandsbestemming | Map die in de Mac-app is geselecteerd | Bestaande absolute `--destination` |
| Strikte onbewerkte export | Ja | Ja |
| Canonieke `healthmd extract` | Ja | Ja |
| Versleutelde context, getypeerde queries en bewijs | Ja | Nee |
| `healthmd-mcp` | Ja | Nee |
| Manual IP of Tailscale | Mac-synchronisatie of expliciete directe modus | Ja |
| Rechtstreeks Nearby-transport | Alleen gebundeld Swift-hulpprogramma | Niet in de platformonafhankelijke Rust-client |

Keuzes voor backend en transport schakelen nooit ongemerkt over op een alternatief. Een rechtstreekse opdracht kan niet naar de Mac-app overschakelen om een query uit te voeren. Een mislukte Nearby-verbinding kan evenmin overschakelen op Manual IP.

## De gebundelde Mac-hulpprogramma's installeren

<div class="availability available">
<strong>Nu beschikbaar · Health.md voor Mac</strong>
<p>De ondertekende Swift-hulpprogramma's voor CLI en MCP worden met de uitgebrachte Mac-app meegeleverd.</p>
</div>

Health.md voor Mac bevat ondertekende hulpprogramma's `healthmd` en `healthmd-mcp`. Open de Mac-app en kies **CLI** om de paden voor jouw installatie, configuratieopdrachten, agentprompts en het optionele installatieprogramma voor de agentskill te bekijken.

De gebruikelijke paden in de appbundel zijn:

```text
/Applications/Health.md.app/Contents/Helpers/healthmd
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

Gebruik aliassen voor één shellsessie:

```bash
alias healthmd="/Applications/Health.md.app/Contents/Helpers/healthmd"
alias healthmd-mcp="/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
```

Of maak blijvende symbolische koppelingen in een bin-map waarvan je zelf eigenaar bent:

```bash
mkdir -p ~/.local/bin
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd" ~/.local/bin/healthmd
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp" ~/.local/bin/healthmd-mcp
```

Voeg `~/.local/bin` toe aan `PATH` als je shell deze map nog niet bevat:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Controleer de CLI zonder de stdio-lus van MCP te starten:

```bash
healthmd --help
healthmd doctor
```

`healthmd doctor` geeft JSON volgens `healthmd.cli_doctor` terug met de gereedheid van de Mac, de versleutelde context en de iPhone. De opdracht toont geen gezondheidswaarden.

## Status van de platformonafhankelijke CLI

<div class="availability preview">
<strong>Preview · nog niet openbaar uitgebracht</strong>
<p>De platformonafhankelijke Rust-CLI wacht op release-QA met een fysieke iPhone en op het eerste gekwalificeerde pakket.</p>
</div>

Een zelfstandige Rust-CLI is in ontwikkeling als `0.1.0-alpha.1`. De CLI werkt op macOS, Linux en Windows, gebruikt standaard rechtstreekse verbindingen via Manual IP of Tailscale en heeft de Mac-app niet nodig. Protocolcompatibiliteit en meertalige fixtures zijn geïmplementeerd. De release-QA met een fysieke iPhone en de publicatie van het pakket moeten nog worden afgerond voor de eerste openbare release.

Gebruik tot die release het gebundelde Mac-hulpprogramma. Vertrouw niet op ongepubliceerde URL's voor Homebrew, crates.io, GitHub-installatieprogramma's of downloads.

De platformonafhankelijke client ondersteunt op alle drie de platforms onbewerkte exports, canonieke extractie, koppeling, status, hervatten, annuleren en bestemmingen voor gegenereerde bestanden. Bij bestandsexports via protocol-v1 behandelt de iPhone de bestemming als een ondoorzichtig doellabel. De ontvangende CLI valideert het doel en bindt het blijvend aan het bestandssysteem van de host.

## Overzicht van opdrachten

| Opdracht | Doel | Backend |
|---|---|---|
| `healthmd status` | Actuele gereedheid of één lokale persistente taak bekijken | Beide |
| `healthmd doctor` | De gereedheid van de Mac, versleutelde context en iPhone toelichten | Mac-app |
| `healthmd metrics list` | De canonieke catalogus met opvraagbare meetwaarden teruggeven | Mac-app |
| `healthmd extract` | Geselecteerde canonieke `healthmd.health_data`-objecten ophalen | Beide |
| `healthmd query` | Geselecteerde getypeerde meetwaarden ophalen en opvragen | Mac-app |
| `healthmd sleep sessions` | Volwaardige slaapsessies en vaste vensters teruggeven | Mac-app |
| `healthmd training align` | Work-outs afstemmen op de slaap ervoor en erna | Mac-app |
| `healthmd workouts` | Getypeerde work-outs met bewijs weergeven | Mac-app |
| `healthmd coverage` | Dekking of ontbrekende gegevens per datum en meetwaarde bekijken | Mac-app |
| `healthmd compare` | Exacte perioden vergelijken met een door de aanroeper gekozen aggregatie | Mac-app |
| `healthmd evidence training` | Een feitelijke bewijsbundel voor training maken | Mac-app |
| `healthmd export` | Gegenereerde bestanden schrijven of strikte onbewerkte JSON teruggeven | Beide |
| `healthmd resume` | Een onveranderlijke persistente exporttaak hervatten | Beide |
| `healthmd cancel` | Expliciete annulering aanvragen | Beide |
| `healthmd agent ...` | De laag-niveau-API voor loopback-query's en taken aanroepen | Mac-app |
| `healthmd direct ...` | Rechtstreeks vertrouwen met een iPhone koppelen, weergeven en verwijderen | Rechtstreeks |

## Eerste workflow met de Mac-app

1. Open Health.md op de Mac en selecteer een bestemmingsmap als je bestanden wilt schrijven.
2. Open Health.md op de gekoppelde iPhone en wacht op verbinding met de Mac.
3. Controleer de gereedheid.
4. Voer een kleine opdracht uit voordat je een omvangrijke geschiedenis opvraagt.

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --metric sleep_total --yesterday
```

Nieuwe queries halen alleen de opgegeven meetwaarden, bronnen en datums op, met samenvattings- of verliesvrij detailniveau. Ze wijzigen de opgeslagen exportinstellingen op de iPhone niet.

## Bestands- en onbewerkte exports

```bash
# Use the Mac app's selected destination
healthmd export --iphone --yesterday
healthmd export --iphone --last 7
healthmd export --iphone --from 2026-07-01 --to 2026-07-07
healthmd export --iphone --all

# Return strict lossless canonical JSON without writing export files
healthmd export --iphone --yesterday --raw --output yesterday.json
healthmd export --iphone --all --raw --output complete-health-corpus.json

# Replace saved metric scope for this one file job
healthmd export --iphone --last 7 --category Sleep --detail summary

# Mirror saved iPhone settings, including roll-ups
healthmd export --iphone --yesterday --use-iphone-settings
```

Er geldt momenteel geen limiet voor het aantal kalenderdagen. Met `--all` vraagt de CLI de iPhone om het oudste beschikbare geselecteerde bronrecord te zoeken, het gevonden bereik vast te zetten en dit via afgebakende partities te verwerken. De beschikbare opslag en één uitzonderlijk gegevensrijke dag blijven praktische beperkingen.

`--raw` vraagt tijdelijk canonieke verliesvrije bronrecords op zonder de iPhone-voorkeur te wijzigen. De opdracht schrijft geen gegenereerde bestanden en bevat geen sidecars van verbonden providers.

## Canonieke extractie of afgeleide query?

Gebruik `extract` als je gegevens in de vorm van de bron nodig hebt:

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

Gebruik een queryopdracht als je een getypeerde weergave met gekoppeld bewijs nodig hebt:

```bash
healthmd sleep sessions --last-nights 14 --window first:4h
healthmd compare --metric steps:sum \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

`healthmd.health_data` v7 is het openbare broncontract. Schema's voor queries, bewijs, taken en ontvangstbewijzen beschrijven transport of afgeleide weergaven. Ze vervangen het bronschema niet.

## Machineleesbaar gedrag

Opdrachten schrijven standaard JSON met versiebeheer naar stdout of naar het expliciete pad bij `--output`. Canonieke extractie kan optioneel JSONL leveren. Query's op hoog niveau kunnen optioneel een bewust onvolledige tabel leveren. Voortgang zonder gezondheidsgegevens kan via stderr lopen. `--help` is gewone tekst. Argumentfouten voordat een opdracht start, zijn gewone tekst op stderr met afsluitcode 2.

Een geslaagd proces bewijst niet dat de gezondheidsgegevens compleet zijn. Controleer:

- de buitenste status;
- de status van het gevraagde bereik;
- de resultaten per dag en per query;
- ontbrekende intervallen;
- `next_cursor` of het doorloopbewijs;
- het bronschema en de versie;
- beperkingen en waarschuwingen.

Een volledig leeg resultaat betekent dat Health.md het gevraagde bereik heeft weergegeven en geen waarnemingen heeft gevonden. Dit is niet hetzelfde als nul, ontbrekend, mislukt, overgeslagen of niet ondersteund.

## Veilige automatisering

Gebruik de procestime-out van je automatiseringshost en houd stdin gesloten voor opdrachten die niet om invoer horen te vragen. Op systemen met GNU `timeout`:

```bash
NO_COLOR=1 TERM=dumb timeout 30 healthmd doctor </dev/null
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output sleep.json </dev/null
```

Een time-out, Ctrl-C, beëindigd proces, netwerkverlies of verstreken iOS-achtergrondtijd annuleert een persistente taak niet. Controleer de taak-ID en hervat de taak in plaats van een duplicaat te starten.

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
healthmd cancel JOB_UUID
```

Alleen een bevestiging van de iPhone maakt een annulering definitief.

## Privacyregels

Onbewerkte en verliesvrije uitvoer kan exacte tijdstempels, routes, klinische records, medicatie, stemmingsregistraties, ecg-waarden, herkomst en bijlagen bevatten. Schrijf bij voorkeur naar een uitvoerbestand in plaats van naar de terminal. Plak payloads niet in probleemmeldingen, agenttranscripten, CI-logboeken of shelltraces.

De lokale query-API heeft geen bearer-token, registratie, toegangsprofiel of toestemmingsdatabase. Bereikbaarheid via loopback is de volledige toegangsgrens. Elk lokaal proces kan de API gebruiken terwijl de Mac-app geopend is. Proxy of publiceer poort `17645` daarom nooit naar een andere computer.

## Volgende gidsen

<div class="related">
  <a href="/nl/docs/cli-direct/"><span>Zonder Mac-app</span>CLI rechtstreeks naar de iPhone: koppeling, transporten, onbewerkte en bestandsexports, achtergrondgedrag en platformondersteuning.</a>
  <a href="/nl/docs/cli-extract/"><span>Brongegevens</span>Canonieke extractie: selecteer meetwaarden, objecten, details, JSON Pointers, JSONL en ontvangstbewijzen.</a>
  <a href="/nl/docs/cli-jobs/"><span>Automatisering</span>Persistente taken: time-outs, hervatten, annuleren, gedeeltelijke resultaten en veilige scripts.</a>
  <a href="/nl/docs/agents/"><span>Agents</span>Workflows voor lokale agents: versleutelde context, rechtstreeks bereik, getypeerde opdrachten en bewijs.</a>
  <a href="/nl/docs/mcp/"><span>MCP</span>Configureer het gesandboxte stdio-hulpprogramma en bekijk de toolgrens.</a>
  <a href="/nl/docs/reference/api-and-cli/"><span>Contract</span>API- en CLI-referentie: exacte routes, schema's, antwoorden en gegenereerde fixtures.</a>
</div>
