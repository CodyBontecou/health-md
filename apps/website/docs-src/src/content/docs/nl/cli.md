---
title: "Health.md-CLI"
description: "Installeer de zelfstandige healthmd-CLI op macOS, Linux of Windows, koppel deze rechtstreeks aan een iPhone of Android-apparaat, controleer de gereedheid, exporteer gegevens, voer queries uit en beheer persistente taken. Geen Mac-app nodig."
---

De zelfstandige `healthmd`-CLI draait op macOS, Linux en Windows en koppelt rechtstreeks met een geopende Health.md-app op de iPhone (protocol v1) of op Android (protocol v2). De CLI heeft Health.md voor Mac nooit nodig, kent geen backendselectie en leest Apple Health of Health Connect nooit vanaf de computer.

<div class="callout">
<strong>Gezondheidsgegevens blijven op je telefoon.</strong>
<p style="margin-top:6px;">De CLI leest Apple Health of Health Connect nooit vanaf de computer. Een actuele, geopende Health.md-app op iPhone of Android voert elke nieuwe gezondheidslezing van het platform uit. De CLI ontvangt gevalideerde resultaten of bestanden.</p>
</div>

## De zelfstandige CLI installeren

<div class="availability preview">
<strong>Openbare preview · nog geen gekwalificeerde stabiele versie</strong>
<p>De platformonafhankelijke Rust-CLI is openbaar verpakt, maar de exacte mobiele matrix wacht nog op fysieke releasekwalificatie.</p>
</div>

Installeer de preview op macOS of Linux met <code>brew install CodyBontecou/tap/healthmd</code>. Gebruik de exacte mobiele build die de releasebewijzen noemen; pakketpublicatie bewijst geen mobiele compatibiliteit.

De zelfstandige Rust-CLI draait op macOS, Linux en Windows, gebruikt rechtstreekse Manual IP- of Tailscale-verbindingen en heeft de Mac-app niet nodig. De CLI koppelt met iPhone-bronnen via protocol v1 en met Android-bronnen via protocol v2, met geautomatiseerde Swift↔Rust- en Kotlin↔Rust-compatibiliteitscontroles. De protocolcompatibiliteit is geïmplementeerd; fysieke release-QA moet nog worden afgerond vóór de eerste gekwalificeerde stabiele versie. Archieven met controlesom, een PowerShell-installatieprogramma en `cargo install healthmd-cli --locked` horen bij elke release.

De draagbare client ondersteunt koppeling, status, onbewerkte export, bestemmingen voor gegenereerde bestanden, hervatting en annulering op alle drie de desktopplatforms voor iPhone en Android. Canonieke extractie en getypeerde MCP-queries zijn iPhone-mogelijkheden. Onbewerkte Android-snapshots behouden hun providerspecifieke Health Connect-contract in plaats van conversie naar HealthKit-vormige gegevens. Getypeerde Android-queries zijn niet geïmplementeerd. Bij de export van gegenereerde bestanden behandelt de telefoon de bestemming als een ondoorzichtig label; de ontvangende CLI valideert deze en bindt deze duurzaam aan het bestandssysteem van de host. Android-protocol v2 bevestigt bestandsbestemmingen op elk CLI-besturingssysteem en beperkt elke gegenereerde taak tot 4.096 bestanden.

## Overzicht van opdrachten

| Opdracht | Doel |
|---|---|
| `healthmd status` | Live gereedheid of een lokale persistente taak controleren |
| `healthmd export` | Gegenereerde bestanden schrijven of strikte onbewerkte JSON teruggeven |
| `healthmd extract` | Geselecteerde canonieke `healthmd.health_data`-objecten ophalen (iPhone) |
| `healthmd query` | Vaste getypeerde querybewerkingen uitvoeren (iPhone) |
| `healthmd resume` | Een onveranderlijke persistente exporttaak hervatten |
| `healthmd cancel` | Expliciete annulering aanvragen |
| `healthmd direct ...` | Rechtstreekse telefoonvertrouwensrelaties koppelen, tonen en verwijderen |
| `healthmd mcp ...` | Het vaste MCP-tooloppervlak bedienen of inspecteren |
| `healthmd setup codex` | Codex configureren en een iPhone koppelen in één flow |

Rechtstreekse opdrachten koppelen met iPhone-bronnen (protocol v1) of Android-bronnen (protocol v2). Canonieke `extract` en elke getypeerde queryopdracht zijn iPhone-mogelijkheden; rechtstreekse Android-bronnen geven providerspecifieke onbewerkte Health Connect-snapshots en gegenereerde bestanden terug.

```bash
# Gereedheid en lokaal vertrouwen
healthmd status
healthmd direct devices

# Platform-eigen onbewerkte export; laat --output weg om gevalideerde JSON/NDJSON naar stdout te streamen
healthmd export --yesterday --raw --output yesterday.json
healthmd export --last 7 --raw --output week.json

# Getypeerde query via hetzelfde bewerkingsregister als MCP (iPhone)
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'

# Canonieke extractie met bereik (iPhone)
healthmd extract --category Sleep --last 7 --output sleep.json

# Productiegegenereerde bestanden op elk CLI-besturingssysteem
mkdir -p "$HOME/Documents/HealthVault"
healthmd export --yesterday --destination "$HOME/Documents/HealthVault"

# Persistente bewerkingen
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --output resumed.json
healthmd cancel JOB_UUID
```

### Draagbare profielgebaseerde bestandsexport

De zelfstandige rechtstreekse CLI kan een opgeslagen profiel op beide ondersteunde telefoonplatforms via zijn stabiele ID oplossen. Het profiel levert de bevroren uitvoerinstellingen; de computerbestemming blijft expliciet:

```bash
mkdir -p "$HOME/Documents/HealthVault"
healthmd export --last 7 \
  --profile 11111111-2222-4333-8444-555555555555 \
  --destination "$HOME/Documents/HealthVault"
```

`--profile PROFILE_ID` kan niet worden gecombineerd met `--use-device-settings` of metriek/categorie-selectors, en een onbekend ID faalt veilig in plaats van live instellingen te gebruiken. Kopieer het ID op iPhone of Android via **Instellingen → Exportprofielen → Profiel-ID**. Zie [Exportprofielen](/nl/docs/export-profiles/) voor automatisering en bestemmingsgedrag.

De draagbare rechtstreekse client kan elke ondersteunde getypeerde iPhone-bewerking aanroepen zonder MCP-envelop:

```bash
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'
```

## Gebundeld Mac-hulpprogramma

Health.md voor Mac levert zijn eigen ondertekende Swift-hulpprogramma's `healthmd` en `healthmd-mcp` binnen de app. Dat hulpprogramma is een functie van de Mac-app, geen backend van de zelfstandige CLI: standaard spreekt het de loopbackserver van de actieve Mac-app aan voor versleutelde lokale queries, MCP-tools en de bestemmingsmap die al in Health.md voor Mac is geselecteerd; daarnaast biedt het een compatibele rechtstreekse iPhone-modus, gekozen met `--backend direct`. De twee clients wisselen nooit ongemerkt van modus.

<div class="availability available">
<strong>Nu beschikbaar · Health.md voor Mac</strong>
<p>De ondertekende Swift CLI- en MCP-hulpprogramma's worden meegeleverd met de uitgebrachte Mac-app.</p>
</div>

Open de Mac-app en kies **CLI** om de paden van je geïnstalleerde kopie, configuratieopdrachten, agentprompts en het optionele installatieprogramma voor agentvaardigheden te zien.

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

Of maak permanente symbolische koppelingen in een map met binaries die de gebruiker bezit:

```bash
mkdir -p ~/.local/bin
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd" ~/.local/bin/healthmd
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp" ~/.local/bin/healthmd-mcp
```

Voeg `~/.local/bin` toe aan `PATH` als je shell dat nog niet doet:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Controleer het hulpprogramma zonder de MCP-stdio-lus te starten:

```bash
healthmd --help
healthmd doctor
```

`healthmd doctor` geeft `healthmd.cli_doctor`-JSON met de gereedheid van Mac, versleutelde context en iPhone. Het print geen gezondheidswaarden.

### Opdrachten van het gebundelde hulpprogramma

| Opdracht | Doel |
|---|---|
| `healthmd export --iphone ...` | Gegenereerde bestanden schrijven of strikte onbewerkte JSON teruggeven via de Mac-app |
| `healthmd status` | Mac/iPhone-gereedheid of een persistente taak controleren |
| `healthmd doctor` | Gereedheid van Mac, versleutelde context en iPhone toelichten |
| `healthmd metrics list` | De canonieke catalogus met te bevragen metrieken teruggeven |
| `healthmd query` | Geselecteerde getypeerde metrieken ophalen en bevragen |
| `healthmd sleep sessions` | Slaapsessies van de eerste klasse en vaste vensters teruggeven |
| `healthmd training align` | Trainingen aan voorafgaande en volgende slaap koppelen |
| `healthmd workouts` | Getypeerde trainingen met bewijs tonen |
| `healthmd coverage` | Datum- en metriekdekking of ontbrekende gegevens controleren |
| `healthmd compare` | Exacte perioden vergelijken met door de aanroeper gekozen aggregatie |
| `healthmd evidence training` | Een feitelelijk trainingsbewijspakket opbouwen |
| `healthmd resume` / `healthmd cancel` | Persistente taken beheren |
| `healthmd agent ...` | De low-level loopback-API voor queries en taken aanroepen |
| `healthmd --backend direct ...` | De compatibele rechtstreekse iPhone-modus van het hulpprogramma |

In de rechtstreekse modus van het hulpprogramma geven subopdrachten voor query, bewijs, doctor, metrieken en verversing van Mac-context `backend_unsupported` terug in plaats van over te schakelen naar de Mac-app.

### Eerste workflow met de Mac-app

1. Open Health.md op de Mac en selecteer een bestemmingsmap als je bestanden wilt schrijven.
2. Open Health.md op de gekoppelde iPhone en wacht op Mac-connectiviteit.
3. Controleer de gereedheid.
4. Voer een kleine opdracht uit voordat je een lange geschiedenis aanvraagt.

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --metric sleep_total --yesterday
```

Nieuwe queries vragen alleen de opgegeven metrieken, bronnen, datums en samenvattings- of verliesvrije details op. Ze wijzigen de opgeslagen iPhone-exportinstellingen niet.

### Bestands- en onbewerkte exports van het gebundelde hulpprogramma

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

Er is momenteel geen kalenderdaglimiet. `--all` laat de iPhone het oudst beschikbare geselecteerde record opzoeken, het opgeloste bereik vastleggen en het verwerken in begrensde partities. Beschikbare opslag en één ongebruikelijk dichte dag blijven praktische limieten.

`--raw` vraagt tijdelijk canonieke verliesvrije bronrecords op zonder de iPhone-voorkeur te wijzigen. Het schrijft geen gegenereerde bestanden en bevat geen sidecars van verbonden providers.

## Canonieke extractie of afgeleide query?

Gebruik `extract` wanneer je gegevens in de vorm van de bron nodig hebt:

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

Gebruik een queryopdracht wanneer je een getypeerde, aan bewijs gekoppelde weergave nodig hebt. De zelfstandige CLI biedt vaste getypeerde bewerkingen; het gebundelde Mac-hulpprogramma biedt daarnaast de volgende shells op hoog niveau:

```bash
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"exact","range":{"start_date":"2026-07-22","end_date":"2026-07-28"}},"all_pages":true}'
healthmd compare --metric steps:sum \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

`healthmd.health_data` v8 is het openbare Apple-broncontract. Query-, bewijs-, taak- en ontvangstschema's beschrijven transport- of afgeleide weergaven. Ze vervangen het bronschema niet. Canonieke extractie is een iPhone-mogelijkheid; rechtstreekse Android-bronnen bieden via onbewerkte export providerspecifieke Health Connect-snapshots aan.

## Machineleesbaar gedrag

Opdrachten gebruiken standaard geversioneerde JSON op stdout of op het expliciete `--output`-pad. Canonieke extractie kan JSONL uitvoeren en queries op hoog niveau kunnen kiezen voor een bewust verliesvolle tabel. Voortgang zonder gezondheidswaarden mag stderr gebruiken. `--help` is platte tekst. Argumentfouten vóór het starten van een opdracht zijn platte tekst op stderr met afsluitcode 2.

Een geslaagde procesafsluiting bewijst geen volledige gezondheidsgegevens. Controleer:

- de buitenste status;
- de status van het gevraagde bereik;
- resultaten per dag en per query;
- ontbrekende intervallen;
- `next_cursor` of de traverseerontvangst;
- bronschema en -versie;
- beperkingen en waarschuwingen.

Een volledig leeg resultaat betekent dat Health.md het gevraagde bereik heeft weergegeven en geen waarnemingen vond. Het is niet hetzelfde als nul, ontbrekend, mislukt, overgeslagen of niet ondersteund.

## Veilige automatisering

Gebruik de procestimeout van je automatiseringshost en houd stdin gesloten voor opdrachten die niet om invoer mogen vragen. Op systemen met GNU `timeout`:

```bash
NO_COLOR=1 TERM=dumb timeout 30 healthmd status </dev/null
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output sleep.json </dev/null
```

Timeout, Ctrl-C, proceseinde, netwerkverlies en uitgeputte iOS-achtergrondtijd annuleren een persistente taak niet. Controleer de taak-ID en hervat deze in plaats van een duplicaat te starten.

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
healthmd cancel JOB_UUID
```

Alleen een bevestiging van de iPhone maakt annulering definitief.

## Privacyregels

Onbewerkte en verliesvrije uitvoer kan exacte tijdstempels, routes, klinische dossiers, medicijnen, stemmingsitems, ECG-waarden, herkomst en bijlagen bevatten. Gebruik bij voorkeur een uitvoerbestand in plaats van terminaluitvoer. Plak payloads niet in probleemrapporten, agenttranscripties, CI-logboeken of shell-traces.

De lokale query-API van het gebundelde Mac-hulpprogramma heeft geen bearer-token, registratie, toegangsprofiel of rechtendatabase. Loopback-bereikbaarheid is de volledige toegangsgrens. Elk lokaal proces kan deze gebruiken zolang de Mac-app open is; proxy of exposeer poort `17645` nooit naar een andere machine.

## Volgende handleidingen

<div class="related">
  <a href="/nl/docs/cli-direct/"><span>Zonder Mac-app</span>Rechtstreekse telefoon-CLI: koppel met iPhone of Android, bekijk transports, onbewerkte en bestandsexports, achtergrondgedrag en platformondersteuning.</a>
  <a href="/nl/docs/cli-extract/"><span>Brongegevens</span>Canonieke extractie: metrieken, objecten, detail, JSON-pointers, JSONL en ontvangsten kiezen.</a>
  <a href="/nl/docs/cli-jobs/"><span>Automatisering</span>Persistente taken: timeouts, hervatting, annulering, deelresultaten en veilig scripten.</a>
  <a href="/nl/docs/agents/"><span>Agents</span>Lokale agentworkflows: versleutelde context, rechtstreeks bereik, getypeerde opdrachten en bewijs.</a>
  <a href="/nl/docs/mcp/"><span>MCP</span>Configureer het geïsoleerde stdio-hulpprogramma en bekijk zijn toolgrens.</a>
  <a href="/nl/docs/reference/api-and-cli/"><span>Contract</span>API- en CLI-referentie: exacte routes, schema's, antwoorden en gegenereerde fixtures.</a>
</div>
