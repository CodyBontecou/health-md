---
title: Begin met Health.md.
description: Exporteer gegevens uit Apple Health of Health Connect, verbind het ondertekende Mac-hulpprogramma met een lokale agent en ontwikkel met Health.md-contracten met versiebeheer.
---

<div class="docs-hero" data-strand-stage>
  <canvas class="docs-dna" data-three-strand aria-hidden="true"></canvas>
  <div class="docs-hero-copy">
    <p class="docs-eyebrow">Nu beschikbaar · ondertekend Mac-hulpprogramma</p>
    <p>Exporteer gezondheidsgegevens vanaf je telefoon, verbind een lokale agent via de ondertekende Mac-hulpprogramma's of ontwikkel met contracten met versiebeheer. HealthKit wordt alleen op de iPhone uitgelezen en Health Connect alleen op Android.</p>
    <div class="docs-command" aria-label="Gebundelde Health.md-opdracht voor gereedheidscontrole"><span aria-hidden="true">$</span> "/Applications/Health.md.app/Contents/Helpers/healthmd" doctor</div>
    <p class="docs-command-note">Staat de app ergens anders? Kopieer het pad van het gebundelde hulpprogramma via <strong>Health.md voor Mac → CLI</strong>.</p>
    <div class="docs-actions">
      <a class="docs-button" href="/nl/docs/iphone-first-export/">Eerste iPhone-export</a>
      <a class="docs-button-secondary" href="/nl/docs/configuration/">Verbind een agent</a>
      <a class="docs-button-secondary" href="/nl/docs/reference/">Bekijk de contracten</a>
    </div>
  </div>
</div>

<div class="agent-path" aria-label="Kies wat je met Health.md wilt doen">
  <a href="/nl/docs/iphone-first-export/"><span>01 · Exporteren</span><strong>Begin op de iPhone</strong>Geef Apple Health-toegang, kies een map, bekijk de uitvoer en voer je eerste export uit.</a>
  <a href="/nl/docs/configuration/"><span>02 · Vragen</span><strong>Verbind een lokale agent</strong>Gebruik het ondertekende MCP-hulpprogramma voor de Mac met Codex, Claude of een andere stdio-client.</a>
  <a href="/nl/docs/reference/"><span>03 · Ontwikkelen</span><strong>Gebruik stabiele contracten</strong>Integreer schema's, records, bewijs, gegenereerde fixtures en exacte enveloppen.</a>
</div>

<div class="reference-stats">
<div><strong>21</strong><span>gebundelde MCP-tools voor de Mac</span></div>
<div><strong>4</strong><span>exportformaten</span></div>
<div><strong>v7</strong><span>openbaar exportschema</span></div>
<div><strong>0</strong><span>vereiste overdrachten via een Health.md-cloud</span></div>
</div>

<p class="docs-section-kicker">Nu beschikbaar · macOS</p>

## Een lokale agent instellen in vijf minuten

Open Health.md op de Mac. Open daarna Health.md op de gekoppelde iPhone en wacht tot er verbinding is. Het gebundelde hulpprogramma controleert de gereedheid zonder gezondheidswaarden terug te geven, toont de slaapmeetwaarden en voert een query voor één dag uit:

```bash
HMD="/Applications/Health.md.app/Contents/Helpers/healthmd"
"$HMD" doctor
"$HMD" metrics list --category Sleep
"$HMD" query --category Sleep --yesterday
```

Een gereed resultaat van `doctor` gebruikt het schema `healthmd.cli_doctor` en bevat vervolgstappen als de configuratie nog niet compleet is. Ga voor Codex of Claude verder naar [Configureer je agent](/nl/docs/configuration/) en laat de client het afzonderlijk ondertekende hulpprogramma `healthmd-mcp` gebruiken.

<p class="docs-section-kicker">Kies op basis van je doel</p>

## Configureren en verbinden

<div class="related">
  <a href="/nl/docs/configuration/"><span>Nu beschikbaar · Mac</span>Configuratie: verbind Codex, Claude of een andere stdio-client met het ondertekende MCP-hulpprogramma.</a>
  <a href="/nl/docs/mcp/"><span>Nu beschikbaar · Mac</span>MCP-server &amp; App: ontdek 21 gebundelde tools, toon privévisualisaties en lees meer over de platformonafhankelijke preview.</a>
  <a href="/nl/docs/cli/"><span>Nu beschikbaar · Mac</span>Health.md-CLI: installeer het gebundelde hulpprogramma, controleer de gereedheid, vraag gegevens op en herken de platformonafhankelijke preview.</a>
  <a href="/nl/docs/agents/"><span>Architectuur</span>Agentcontext: lees over het verzoekbereik, lokaal vertrouwen, versleutelde context, bewijs, bewaartermijnen en privacy.</a>
</div>

<p class="docs-section-kicker">Dagelijks gebruik</p>

## Opvragen, extraheren en automatiseren

<div class="related">
  <a href="/nl/docs/agent-queries/"><span>Getypeerde queries</span>Vraag naar meetwaarden, slaapsessies, work-outs, vergelijkingen, dekking en feitelijk bewijs.</a>
  <a href="/nl/docs/cli-direct/"><span>Preview · platformonafhankelijke CLI</span>Rechtstreekse iPhone-toegang: begrijp koppeling via Manual IP of Tailscale voordat het zelfstandige pakket verschijnt.</a>
  <a href="/nl/docs/cli-extract/"><span>Brongegevens</span>Canonieke extractie: haal geselecteerde dagen uit schema v7, bronrecords, samenvattingsweergaven of JSONL op.</a>
  <a href="/nl/docs/cli-jobs/"><span>Betrouwbare uitvoering</span>Persistente taken: ga veilig om met time-outs, onbekende uitkomsten, hervatten, annuleren en gedeeltelijke resultaten.</a>
  <a href="/nl/docs/agent-api/"><span>Laag niveau</span>Loopback-API: gebruik exacte routes voor queries, bewijs, cursors, verversing en persistente taken.</a>
  <a href="/nl/docs/reference/integration-recipes/"><span>Patronen</span>Integratierecepten: verwerk en valideer Health.md-uitvoer zonder de contracten af te zwakken.</a>
</div>

<p class="docs-section-kicker">Stabiele interfaces</p>

## Datacontracten en -structuren

<div class="related">
  <a href="/nl/docs/reference/"><span>Contractoverzicht</span>Exportreferentie: bekijk schema's, meetwaarden, formaten, records en interoperabiliteitsfixtures.</a>
  <a href="/nl/docs/reference/api-and-cli/"><span>Automatisering</span>API- &amp; CLI-contracten: bekijk enveloppen, routes, afsluitgedrag en gegenereerde voorbeelden.</a>
  <a href="/nl/docs/reference/evidence-packets/"><span>Agentresultaten</span>Queries &amp; bewijs: getypeerde waarden, dekking, ontbrekende gegevens, bewerkingen en deterministische identiteiten.</a>
  <a href="/nl/docs/reference/daily-records/"><span>Schema v7</span>Dagrecords: begrijp het openbare brondocument en de eigendomsregels.</a>
  <a href="/nl/docs/shared-metric-registry/"><span>Terminologie</span>Meetwaarderegister: gebruik stabiele platformonafhankelijke meetwaarde-ID's, categorieën, eenheden en profielmetadata.</a>
  <a href="/nl/docs/reference/generated/"><span>Machineleesbaar</span>Gegenereerde artefacten: open canonieke velden, fixtures, berichtinventarissen en CLI-contracten.</a>
</div>

<p class="docs-section-kicker">Productworkflows</p>

## Apps en exports

<div class="related">
  <a href="/nl/docs/iphone-first-export/"><span>Begin hier · iPhone</span>Eerste export: geef Apple Health-toegang, kies een map, bekijk de uitvoer en controleer de geschreven bestanden.</a>
  <a href="/nl/docs/android/"><span>Android</span>Health Connect: kies een map van een documentprovider en configureer automatisering voor Android.</a>
  <a href="/nl/docs/export/"><span>Bestanden</span>Exporteren: voer expliciete datumbereiken uit in Markdown, CSV, JSON of Obsidian Bases.</a>
  <a href="/nl/docs/format/"><span>Structuur</span>Formaataanpassing: bepaal eenheden, datums, frontmatter, bestandsnamen en schrijfgedrag.</a>
  <a href="/nl/docs/scheduling/"><span>Achtergrond</span>Planning: begrijp het gedrag van dagelijkse en wekelijkse exports en de beperkingen van het platform.</a>
  <a href="/nl/docs/shortcuts/"><span>Automatisering</span>Shortcuts &amp; App Intents: start exports, samenvattingen en statuscontroles vanuit Apple-workflows.</a>
</div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:12px; font-family:var(--sl-font-mono);">Documentatiestructuur bijgewerkt op 2 augustus 2026</p>
