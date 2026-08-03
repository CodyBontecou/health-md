---
title: Configureer je agent
description: Kies de MCP- of CLI-interface van Health.md, configureer Codex, Claude of een andere lokale client en verbind een gekoppelde iPhone zonder HealthKit-gegevens via een cloudservice te sturen.
---

De uitgebrachte Mac-app bevat twee ondertekende lokale hulpprogramma's: `healthmd-mcp` voor getypeerde agenttools en `healthmd` voor expliciete CLI-workflows. Daarnaast bestaat er een platformonafhankelijke CLI met rechtstreekse MCP-toegang tot de iPhone. Die staat als preview beschreven totdat het eerste openbare pakket de release-QA op fysieke apparaten heeft doorlopen.

<div class="callout">
<strong>HealthKit blijft op de iPhone.</strong>
<p style="margin-top:6px;">Met de configuratie krijgt een lokale client toegang tot de afgebakende interfaces van Health.md. De computer of agent krijgt geen rechtstreekse toegang tot HealthKit en je bronbibliotheek wordt niet naar een Health.md-cloud geüpload.</p>
</div>

## Kies een interface

| Doel | Begin met | Lees verder |
|---|---|---|
| Laat Codex of Claude gezondheidsgegevens op de Mac opvragen en visualiseren | Gebundelde `healthmd-mcp` via stdio | [MCP-server en -tools](/nl/docs/mcp/) |
| Exporteer canonieke JSON of gegenereerde bestanden vanuit een Mac-script | Gebundelde `healthmd`-CLI | [CLI](/nl/docs/cli/) |
| Maak rechtstreeks verbinding met een geopende iPhone zonder de Mac-app | Platformonafhankelijke directe CLI (**preview**) | [Rechtstreekse iPhone-toegang](/nl/docs/cli-direct/) |
| Ontwikkel met exacte API-enveloppen voor verzoeken en antwoorden | Loopback-API of openbare contracten | [Loopback-API](/nl/docs/agent-api/) |
| Verwerk schema's, records, bewijs of gegenereerde fixtures | Referentie met versiebeheer | [Datacontracten](/nl/docs/reference/) |

Je kiest de backend en het transport expliciet. Health.md schakelt niet ongemerkt van rechtstreekse iPhone-toegang over op de Mac-app.

## Codex met de Mac-app

<div class="availability available">
<strong>Nu beschikbaar · ondertekend Mac-hulpprogramma</strong>
<p>Installeer Health.md voor Mac, open het scherm <strong>CLI</strong> en kopieer het weergegeven pad van de gebundelde MCP-server als de app niet in <code>/Applications</code> staat.</p>
</div>

Voeg het afzonderlijk ondertekende hulpprogramma `healthmd-mcp` toe aan `~/.codex/config.toml`:

```toml
[mcp_servers.healthmd]
command = "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
args = []
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"
```

Start Codex opnieuw, roep `healthmd_doctor` aan en gebruik daarna `healthmd_metrics` en een kleine getypeerde tool, bijvoorbeeld `healthmd_metric_chart`. De gebundelde server biedt 21 tools, waaronder gereedheidscontrole voor de Mac, verversingstaken voor versleutelde context, bewijs en visualisaties.

## Claude Desktop of Claude Code op de Mac

Voeg het gebundelde hulpprogramma toe aan de MCP-configuratie van Claude Desktop of aan een vertrouwd Claude Code-bestand `.mcp.json`:

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

Start de client opnieuw nadat je de configuratie hebt gewijzigd. Voor configuraties op projectniveau moet je de werkruimte nog steeds vertrouwen en de server expliciet goedkeuren. Houd de Mac- en iPhone-app geopend als een tool actuele HealthKit-gegevens nodig heeft.

## Andere stdio-MCP-clients op de Mac

Configureer één lokaal proces:

```text
command: /Applications/Health.md.app/Contents/Helpers/healthmd-mcp
arguments: none
transport: stdio
```

De host beheert stdin en de levenscyclus van het proces. Start het hulpprogramma niet als een gewone interactieve opdracht en plaats er geen shell omheen die de JSON-RPC-uitvoer wijzigt. Gebruik MCP `tools/list` om de exacte schema's op te vragen die de geïnstalleerde app aanbiedt.

## Platformonafhankelijke directe configuratie

<div class="availability preview">
<strong>Preview · nog niet openbaar uitgebracht</strong>
<p>De platformonafhankelijke Rust-CLI, <code>healthmd setup codex</code>, de MCP-server <code>healthmd mcp serve</code> in hetzelfde uitvoerbare bestand en rechtstreekse koppeling op Linux en Windows zijn geïmplementeerd. Ze wachten nog op hun eerste gekwalificeerde openbare release.</p>
</div>

Na publicatie configureert `healthmd setup codex` Codex idempotent en start de opdracht de rechtstreekse koppeling met de iPhone. Vertrouw tot die tijd niet op ongepubliceerde URL's voor Homebrew, crates.io, installatieprogramma's of GitHub-releases. De pagina [Rechtstreekse iPhone-toegang](/nl/docs/cli-direct/) beschrijft het voorbereide transport- en protocolgedrag.

## Expliciete CLI-workflows

Roep voor canonieke extractie of bestandsgerichte automatisering rechtstreeks `healthmd` aan. Laat een MCP-host geen omvangrijke brontekst vervoeren:

```bash
healthmd status
healthmd extract --category Sleep --last 7 --output sleep.json
healthmd export --last 7 --destination "$HOME/Documents/HealthVault"
```

De gebundelde Mac-helper en de zelfstandige platformonafhankelijke CLI verschillen in beschikbaarheid en syntaxis. Lees [Health.md-CLI](/nl/docs/cli/) voordat je opdrachten in onbeheerde automatisering overneemt.

## Koppeling en gereedheid voor de directe CLI

<div class="availability preview">
<strong>Preview · platformonafhankelijke directe workflows</strong>
<p>Deze stappen gelden voor het komende platformonafhankelijke pakket. De uitgebrachte gebundelde MCP-server voor de Mac gebruikt de bestaande iPhone-verbinding van de Mac-app.</p>
</div>

Voor rechtstreekse MCP- en CLI-workflows moet je Health.md op de iPhone eenmalig als vertrouwd apparaat koppelen. De koppeling gebruikt een geverifieerd, versleuteld kanaal en de ingebouwde opslag voor inloggegevens van macOS, Linux of Windows.

1. Schakel **Direct CLI-toegang** in Health.md op de iPhone in.
2. Start de koppeling met `healthmd setup codex` of `healthmd direct pair`.
3. Keur het afgebakende koppelingsverzoek op de iPhone goed.
4. Houd Health.md op de voorgrond wanneer je een query of export start.
5. Roep vóór grotere taken `healthmd_doctor` aan via MCP of `healthmd status` via de platformonafhankelijke CLI.

Lees [Rechtstreekse iPhone-toegang](/nl/docs/cli-direct/) voor informatie over Manual IP, Tailscale, de poort, vertrouwde apparaten, gebruik op de voorgrond en herstel.

## Grenzen van de configuratie

Een lokale agentconfiguratie geeft **geen** toestemming voor:

- willekeurige lees- of schrijfbewerkingen in HealthKit;
- willekeurige toegang tot het bestandssysteem;
- willekeurige URL's, shell-opdrachten, prompts, rootmappen of sampling via MCP;
- het verbergen van ontbrekende gegevens, dekking, eenheden, bewijs of beperkingen;
- het zonder de vereiste goedkeuring hervatten, annuleren of overschrijven van gegenereerde bestanden.

Controleer voor een volledig resultaat niet alleen of het proces is geslaagd, maar ook het gevraagde bereik, de dekking, de doorloopstatus, de beperkingen en het bronschema.

## Lees verder

<div class="related">
  <a href="/nl/docs/mcp/"><span>Toolinterface</span>Bekijk de 21 beschikbare Mac-tools, de platformonafhankelijke preview met 17 tools, MCP Apps, schema's, paginering, exports en sandboxgrenzen.</a>
  <a href="/nl/docs/agent-queries/"><span>Eerste vragen</span>Voer getypeerde workflows uit voor meetwaarden, slaap, work-outs, vergelijkingen, dekking en bewijs.</a>
  <a href="/nl/docs/cli-extract/"><span>Canonieke gegevens</span>Extraheer geselecteerde documenten en bronrecords uit schema v7 zonder grote gegevensblokken in een chat te plaatsen.</a>
  <a href="/nl/docs/reference/"><span>Contracten</span>Bekijk gegevensstructuren met versiebeheer, veldinventarissen, gegenereerde fixtures en integratierecepten.</a>
</div>
