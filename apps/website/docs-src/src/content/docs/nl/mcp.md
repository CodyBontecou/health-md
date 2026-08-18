---
title: "Health.md MCP-server en App"
description: "Gebruik Codex of Claude voor afgebakende analyse van Apple Health, systeemeigen grafieken en persistente Health.md-exports via een lokale gesandboxte MCP App."
---

Health.md voor Mac bevat een ondertekend stdio-hulpprogramma `healthmd-mcp`. Daarmee kunnen Codex, Claude en andere MCP-hosts feitelijke Apple Health-gegevens opvragen, visualisaties tonen, versleutelde lokale context verversen en goedgekeurde persistente exports uitvoeren via de geopende Mac-app.

```text
Codex / Claude / another local MCP host
  <-> MCP JSON-RPC over stdio
  <-> signed healthmd-mcp helper
  <-> Health.md Mac loopback API on 127.0.0.1:17645
  <-> connected iPhone for fresh HealthKit reads and exports
```

<div class="availability available">
<strong>Nu beschikbaar · Health.md voor Mac</strong>
<p>De gebundelde server biedt 21 vaste tools. Het hulpprogramma leest zelf geen HealthKit, exportmappen, security-scoped bladwijzers of willekeurige bestanden.</p>
</div>

<div class="availability preview">
<strong>Preview · platformonafhankelijke directe MCP</strong>
<p>De afzonderlijke opzet met 19 tools via <code>healthmd mcp serve</code> voor macOS, Linux en Windows is geïmplementeerd, maar nog niet openbaar uitgebracht. Het cloudvrije beginpunt <code>serve-read-only</code> biedt na lokale koppeling alleen de 13 tools voor gereedheid en queries. Opdrachten op deze pagina die uitsluitend voor de platformonafhankelijke versie gelden, zijn als preview gemarkeerd.</p>
</div>

## Vereisten

- Health.md voor Mac is geïnstalleerd en geopend.
- Health.md is geopend op de verbonden iPhone wanneer de vernieuwingstool of een export nieuw HealthKit-werk start.
- Een lokale MCP-host met ondersteuning voor stdio.
- Het pad van het ondertekende hulpprogramma onder **Health.md voor Mac → CLI**.

Het gebruikelijke pad is `/Applications/Health.md.app/Contents/Helpers/healthmd-mcp`. Ondersteunde kernversies van het MCP-protocol zijn `2024-11-05`, `2025-03-26`, `2025-06-18` en `2025-11-25`. Start `healthmd-mcp` niet als een gewone interactieve opdracht. De MCP-host beheert stdin en de levenscyclus van het proces.

## Codex configureren

Voeg het gebundelde hulpprogramma toe aan `~/.codex/config.toml`:

```toml
[mcp_servers.healthmd]
command = "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
args = []
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_files]
approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_job_resume]
approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_job_cancel]
approval_mode = "prompt"
```

Start Codex opnieuw, roep `healthmd_doctor` aan, zoek ID's op met `healthmd_metrics`, haal met de vernieuwingstool expliciet een klein exact bereik op en vraag dat bereik daarna op met `healthmd_metric_chart`. Hosts zonder interactieve MCP Apps ontvangen nog steeds exacte JSON en een standaardgrafiek in PNG-formaat.

## Claude configureren

Gebruik dit lokale stdio-item in de MCP-configuratie van Claude Desktop of in een vertrouwd Claude Code-bestand `.mcp.json`:

```json
{
  "mcpServers": {
    "healthmd": {
      "command": "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp",
      "args": []
    }
  }
}
```

Start Claude Desktop opnieuw nadat je de configuratie hebt gewijzigd. Voor Claude-configuraties op projectniveau moet je de werkruimte vertrouwen en de server expliciet goedkeuren.

Versies van Claude Desktop die de stabiele MCP Apps-extensie aankondigen, tonen de interactieve Health.md-weergave in de interface. Claude Code en andere tekstgerichte clients behouden de JSON- en afbeeldingsalternatieven.

## Preview van platformonafhankelijke directe MCP

Na de zelfstandige release koppelt `healthmd setup codex` een iPhone-app op de voorgrond en maakt de opdracht veilig een item voor `healthmd mcp serve` in hetzelfde uitvoerbare bestand. Deze opzet gebruikt geauthenticeerd, versleuteld transport via Manual IP of Tailscale op poort `17647`, systeemeigen opslag voor inloggegevens en expliciete iPhone-uitlezingen per verzoek. Linux vereist daarnaast een ontgrendelde Secret Service-provider; Windows gebruikt Credential Manager.

Vertrouw niet op ongepubliceerde pakket- of installatie-URL's totdat er een release `healthmd-cli/v<version>` bestaat. Lees [CLI rechtstreeks naar de iPhone](/nl/docs/cli-direct/) voor het voorbereide koppelings- en transportcontract.

## Systeemeigen visualisaties in MCP App

Health.md implementeert stabiele onderhandeling voor `io.modelcontextprotocol/ui` met `text/html;profile=mcp-app`.

Nadat een host dat MIME-type aankondigt, biedt de server:

- `ui://healthmd/query-visualization-v1`;
- de standaardmethoden `resources/list` en `resources/read`;
- `_meta.ui.resourceUri` voor tools met analyseresultaten en exportontvangstbewijzen;
- gevalideerde `structuredContent` naast exacte JSON-tekst.

De weergave is een zelfstandige HTML5-resource zonder netwerk, externe scripts, externe lettertypen, opslag of geneste frames. Het opgegeven CSP bevat lege lijsten voor connect-, resource-, frame- en basedomeinen. De resource volgt de standaardlevenscyclus voor initialisatie, toolresultaten, thema, formaatwijzigingen, annulering en afbouw.

De resource kan het volgende tonen:

- lijngrafieken van meetwaarden met eenheden en expliciete hiaten voor ontbrekende gegevens;
- periodevergelijkingen met de door de aanroeper gekozen aggregatie;
- slaapsessies en samenvattingen van de duur per slaapfase;
- work-outs en feitelijke timing tussen work-out en slaap;
- dekking, ontbrekende intervallen, bewijs en beperkingen;
- doorloopbewijzen voor alle pagina's;
- voortgang, bestemmingen en taakbewijzen van persistente exports.

De tools blijven werken als de host MCP Apps niet ondersteunt. `healthmd_metric_chart` voegt inhoud als `image/png` toe voor hosts die afbeeldingen ondersteunen en behoudt tegelijk de volledige JSON als tekst.

## Beschikbare tools

De gebundelde Mac-server biedt 21 vaste tools: 13 voor gereedheid en query's, vier voor taken met gegenereerde bestanden en vier voor vernieuwingstaken van versleutelde context. De platformonafhankelijke preview met 19 tools behoudt de 13 gereedheids-/querytools en vier exporttools, vervangt Mac-vernieuwingstaken door twee tools voor rechtstreekse koppeling en voert getypeerde query's rechtstreeks uit op de iPhone op de voorgrond.

### Gereedheid en ontdekking

| Tool | Doel |
|---|---|
| `healthmd_status` | Gereedheid van de Mac-app, context, iPhone en export controleren |
| `healthmd_doctor` | Problemen met het gebundelde hulpprogramma en de Mac-loopbackopzet vaststellen |
| `healthmd_capabilities` | Mogelijkheden voor rechtstreekse queries, bewijs, exports, schema's en paginering weergeven |
| `healthmd_metrics` | Canonieke meetwaarde-ID's, categorieën, eenheden en vereisten weergeven |

### Analyse en visualisatie

| Tool | Doel |
|---|---|
| `healthmd_metric_chart` | Meetwaardereeksen opvragen en systeemeigen grafieken met dekking en eenheden tonen |
| `healthmd_sleep_sessions` | Stabiele slaapsessies en dekking van fysiologische gegevens weergeven en visualiseren |
| `healthmd_training_alignment` | Feitelijke timing van work-outs ten opzichte van de slaap ervoor en erna tonen |
| `healthmd_workouts` | Work-outs weergeven en visualiseren |
| `healthmd_coverage` | Dekking en ontbrekende gegevens per meetwaarde en datum bekijken |
| `healthmd_compare_periods` | Exacte perioden vergelijken met expliciete aggregatiesemantiek |
| `healthmd_training_evidence` | Een feitelijke bewijsbundel voor training maken |
| `healthmd_query` | Een exacte `healthmd.query_request` versturen en eventueel pagina's doorlopen |
| `healthmd_evidence_packet` | Een exact bewijsverzoek versturen en eventueel pagina's doorlopen |

### Exports van gegenereerde bestanden

| Tool | Doel |
|---|---|
| `healthmd_export_files` | Een persistente export via de Mac-app naar de geselecteerde map uitvoeren |
| `healthmd_export_job_status` | De exportvoortgang en het bestemmingsbewijs bekijken |
| `healthmd_export_job_resume` | De exacte onveranderlijke persistente exporttaak hervatten |
| `healthmd_export_job_cancel` | De exporttaak expliciet annuleren |

De tools voor exporteren, hervatten en annuleren zijn gemarkeerd als mogelijk destructieve schrijfbewerkingen. Huidige Claude-hosts vereisen daarvoor expliciete interactie, omdat ingestelde exportmodi gegenereerde bestanden kunnen bijwerken of overschrijven. De bovenstaande Codex-configuratie vraagt bij deze tools om extra bescherming.

### Taken voor versleutelde context · alleen gebundelde Mac

| Tool | Doel |
|---|---|
| `healthmd_refresh` | Een goedgekeurd bereik van de iPhone ophalen en in wegwerpbare versleutelde Mac-context plaatsen |
| `healthmd_job_status` | De voortgang van de verversing bekijken zonder gezondheidswaarden te lezen |
| `healthmd_job_resume` | De exact geaccepteerde verversingstaak hervatten |
| `healthmd_job_cancel` | Een geaccepteerde verversingstaak expliciet annuleren |

### De volledige querystructuur bekijken

MCP `tools/list` bevat het volledige geneste JSON Schema voor datums, meetwaarden, bronnen, paginering, perioden, aggregaties en de geavanceerde `healthmd.query_request`. Getypeerde tools bevatten ook concrete voorbeelden. Een agent hoort de bijpassende getypeerde tool rechtstreeks aan te roepen in plaats van algemene shellhelp te bekijken. Gebruik voor vragen over slaap in het bijzonder `healthmd_sleep_sessions`; `healthmd extract` levert een andere canonieke projectie van brongegevens.

In de platformonafhankelijke preview kun je hetzelfde schema lokaal bekijken zonder een netwerklistener te openen of verbinding te maken met de iPhone. Gebruik voor het uitgebrachte Mac-hulpprogramma MCP tools/list.

```bash
healthmd mcp schema healthmd_sleep_sessions
healthmd mcp schema healthmd_metric_chart
healthmd mcp schema # complete fixed catalog
```

Een minimale aanroep voor slaap heeft deze structuur. Bepaal voor het werkelijke verzoek de inclusieve datums:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-22",
      "end_date": "2026-07-28"
    }
  },
  "all_pages": true
}
```

Canonieke slaapmeetwaarden en verliesvrije sessiedetails worden automatisch door `healthmd_sleep_sessions` aangeleverd.

## Gegevens analyseren en in een grafiek tonen

Roep eerst `healthmd_doctor` aan en zoek meetwaarde-ID's op met `healthmd_metrics`. In de uitgebrachte Mac-topologie lezen getypeerde querytools de versleutelde Mac-context; ze maken niet impliciet verbinding met de iPhone. Roep voor actuele gegevens de vernieuwingstool aan met expliciete datums, meetwaarden en bronnen, wacht tot de persistente taak is voltooid en maak daarna een grafiek van hetzelfde bereik:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-01",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps", "resting_heart_rate"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "all_pages": true
}
```

Geef dit object door aan `healthmd_metric_chart`. De interactieve weergave gebruikt compacte deelgrafieken met veilige eenheden. Een ontbrekend of gedeeltelijk punt onderbreekt de lijn en wordt niet nul.

De uitgebrachte getypeerde Mac-tools verwerken versleutelde lokale context en geven afgebakende pagina's terug met dekking, ontbrekende gegevens, bewijs en beperkingen. Alleen een expliciete vernieuwing maakt verbinding met de verbonden iPhone op de voorgrond en vervangt het gevraagde contextbereik. De platformonafhankelijke preview verwerkt elke getypeerde aanvraag rechtstreeks op de gekoppelde iPhone op de voorgrond.

## Een export met gegenereerde bestanden uitvoeren

Selecteer en bewaar eerst een beschrijfbare bestemmingsmap in Health.md voor Mac. Nadat de host alle argumenten heeft getoond en de gebruiker ze heeft goedgekeurd, roep je `healthmd_export_files` aan:

```json
{
  "date_selection": "explicit_range",
  "date_range": {
    "start": "2026-07-01",
    "end": "2026-07-07"
  },
  "settings_policy": "requested_dates_only",
  "categories": ["Sleep"],
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

Gebruik `date_selection: "all_available"` zonder `date_range` voor de volledige geschiedenis. Optionele `metric_ids`, `categories` of `all_metrics` beperken de gegevensophaling op de iPhone zonder opgeslagen instellingen te wijzigen. `detail_level` geldt alleen als een van die selecties aanwezig is. `all_metrics` kan niet worden gecombineerd met expliciete lijsten van meetwaarden of categorieën.

Om in plaats daarvan een opgeslagen exportprofiel uit te voeren, zet je `settings_policy` op `"profile"` en geef je `profile_reference` mee met de stabiele UUID van het profiel (een optionele weergavenaam `name` wordt alleen voor fouten vastgelegd):

```json
{
  "date_selection": "explicit_range",
  "date_range": { "start": "2026-07-01", "end": "2026-07-07" },
  "settings_policy": "profile",
  "profile_reference": { "profileID": "11111111-2222-4333-8444-555555555555" }
}
```

Het profiel bepaalt het instellingenbereik: `profile_reference` kan niet worden gecombineerd met `metric_ids`, `categories`, `all_metrics` of het beleid voor opgeslagen instellingen, en een onbekende UUID faalt met een getypeerde fout in plaats van terug te vallen op actuele instellingen.

Controleer:

- `status` en de persistente `state`;
- `job_id`;
- verwerkte en totale dagen en voortgang;
- geschreven bestanden of dagelijkse notities;
- de gevalideerde bestemming op de computer;
- vastgelegde partities en bytes;
- de reden voor pauzeren of mislukken en de vervaldatum.

Een time-out of gesloten MCP-wachter annuleert de persistente taak niet. Controleer `healthmd_export_job_status` voordat je een taak na een onbekende uitkomst hervat. Alleen expliciete annulering beëindigt de taak.

Onbewerkt en canoniek brontransport kan gigabytes aan routes, klinische tekst, bijlagen en bronrecords bevatten. Health.md plaatst deze hoofdteksten bewust niet in een MCP-gesprek. Gebruik de gevalideerde streaming-CLI voor uitvoer in de vorm van de bron:

```bash
healthmd extract --metric workouts --last 30 --detail lossless --output workouts.json
healthmd export --iphone --all --raw --output health-corpus.json
```

MCP-analyse blijft een afgeleide feitelijke weergave. Exports van gegenereerde bestanden blijven via de productie-exporters het openbare contract `healthmd.health_data` gebruiken.

## Paginering en volledigheid

Query- en bewijstools bieden waar ondersteund `all_pages: true`. Het hulpprogramma volgt ondoorzichtige cursors met cyclusdetectie en totale grenzen voor bytes en pagina's. Elk antwoord met versiebeheer blijft behouden onder `healthmd.mcp_query_pages` v1. Als de grens voor automatische doorloop wordt bereikt, zet de geslaagde gedeeltelijke wrapper `receipt.traversal_complete` op `false` en geeft deze de exacte `receipt.next_cursor` terug om zonder gegevensverlies verder te gaan. De iPhone bewaart een gepagineerde compacte momentopname gedurende tien minuten inactiviteit op de voorgrond en wist deze na definitieve doorloop of wanneer de app naar de achtergrond gaat. Eén verzoek heeft een grens van 366,000 dagen en 64 MiB voor de gecodeerde compacte context. `query_scope_too_large` betekent dat je datums of meetwaarde-ID's over meerdere aanroepen moet verdelen, niet dat de logische geschiedenis niet beschikbaar is. Pagina's begrenzen lijsten met ontbrekende intervallen en bronbeschrijvingen met expliciete velden voor aantallen en afkapping, plus beperkingen.

Geslaagd transport betekent niet dat de gegevens compleet zijn. Controleer altijd:

- de status van het gevraagde bereik en de corpusstatus;
- dekking en ontbrekende intervallen;
- beperkingen en bewijs;
- `next_cursor` of het doorloopbewijs;
- niet-gerelateerde overgeslagen onderdelen;
- het bronschema en de versie.

De MCP App toont deze velden in plaats van ze te verbergen. Verklein het bereik of ga handmatig verder als de automatische doorloop de veiligheidsgrens bereikt.

## Beveiligings- en privacygrenzen

Het hulpprogramma heeft geen prompts, rootmappen, sampling, shell, SQL, willekeurige bestandslezingen, willekeurige URL-ophaalacties, HealthKit-schrijfbewerkingen, loopback-HTTP-dienst of extern MCP-eindpunt. De enige MCP-resource is het gebundelde App-document. Schrijven van gegenereerde bestanden is één vaste bewerking waarvoor goedkeuring nodig is. Het uitgebrachte Mac-hulpprogramma gebruikt de map die in Health.md voor Mac is geselecteerd; de platformonafhankelijke preview vereist een expliciete bestaande bestemming die vóór de overdracht wordt gevalideerd en blijvend gebonden.

Rechtstreeks vertrouwen wordt opgeslagen in de sleutelhanger, Secret Service of Windows Credential Manager. De koppeling gebruikt het bestaande geauthenticeerde, versleutelde protocol. De iPhone moet op de voorgrond staan en expliciet verbonden zijn met het LAN- of Tailscale-adres van de computer. Querypagina's zijn begrensd op de overeengekomen limieten voor bytes en items. Automatische samenvoeging van alle pagina's heeft aanvullende grenzen voor bytes en pagina's. Onbegrensde onbewerkte hoofdteksten blijven op het gevalideerde streamingpad van de CLI.

Health.md meldt feitelijke waarnemingen met eenheden, herkomst, dekking en ontbrekende gegevens. Het stelt geen diagnose, beveelt geen behandeling aan, leidt geen oorzakelijk verband af en noemt een richting niet beter of slechter.

## Problemen oplossen

| Symptoom | Actie |
|---|---|
| Host kan het hulpprogramma niet starten | Gebruik het absolute geïnstalleerde pad naar `healthmd` of `.exe` met de argumenten `mcp serve` |
| Hulpprogramma wacht wanneer het in Terminal wordt uitgevoerd | Dit is normaal; een MCP-host moet JSON-RPC via stdin versturen |
| `healthmd_not_paired` | Voer `healthmd direct pair` uit en rond de koppeling op de iPhone af |
| `healthmd_unavailable` | Ontgrendel Health.md op de iPhone en breng de app naar de voorgrond, schakel Direct CLI-toegang in en maak verbinding met de computer |
| `query_scope_too_large` | Verdeel datums of meetwaarde-ID's over meerdere aanroepen; het logische corpus blijft tussen verzoeken beschikbaar |
| Geen interactieve grafiek | Werk de host bij; de server geeft nog steeds exacte JSON en een PNG-alternatief voor meetwaardegrafieken terug |
| Exportbestemming niet beschikbaar | Mac: selecteer de opgeslagen map opnieuw in Health.md. Platformonafhankelijke preview: maak een bestaande absolute map op de computer die geen symbolische koppeling is en geef deze door. |
| Wachter voor export verloopt | Bekijk de persistente exporttaak aan de hand van de ID voordat je hervat |
| Resultaat bevat `next_cursor` | Stel `all_pages: true` in of ga handmatig verder met de cursor |

## Gerelateerde documentatie

<div class="related">
  <a href="/nl/docs/agents/"><span>Architectuur</span>Lokale agents, versleutelde context, verzoekbereik en bewijs.</a>
  <a href="/nl/docs/agent-queries/"><span>Analyse</span>Recepten voor getypeerde queries over meetwaarden, slaap, work-outs, vergelijkingen en dekking.</a>
  <a href="/nl/docs/cli-extract/"><span>Brongegevens</span>Gevalideerde canonieke extractie voor omvangrijke resultaten in de vorm van de bron.</a>
  <a href="/nl/docs/reference/evidence-packets/"><span>Contracten</span>Getypeerde waarden, ontbrekende gegevens, bewijs en bundelidentiteiten.</a>
</div>
