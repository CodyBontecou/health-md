---
title: "Formaataanpassing"
description: "Bepaal de opmaak van de uitvoer zonder te wijzigen welke gegevens worden verzameld. Kies een bestandsformaat, stel datum-, tijd- en eenheidsnotaties in, pas de YAML-frontmatter aan en kies een Markdown-sjabloon."
---

## Uitvoerformaten
<div class="options">
<div class="option"><strong>Markdown (.md)</strong><p>Het standaardformaat. Eén bestand per dag, met optionele YAML-frontmatter en secties met een kop voor elke categorie.</p></div>
<div class="option"><strong>Obsidian Bases</strong><p>Markdown met gestructureerde frontmatter die is geoptimaliseerd voor de plugin <a href="https://help.obsidian.md/Plugins/Bases">Bases</a> van Obsidian. Getallen blijven getallen en datums blijven datums.</p></div>
<div class="option"><strong>JSON</strong><p>Eén JSON-bestand per dag. Dagelijkse samenvattingen volgens schema v7 kunnen het gezaghebbende archief <code>healthmd.healthkit_records</code> v1 bevatten als Gezondheidsgegevens zonder verlies is ingeschakeld.</p></div>
<div class="option"><strong>CSV</strong><p>Eén CSV-bestand per dag met de kopregel <code>Date,Category,Metric,Value,Unit,Timestamp</code>. Compatibiliteitsrijen met samenvattingen bevatten vijf velden en laten de tijdstempelkolom weg. Rijen met een tijdstempel en canonieke recordrijen bevatten alle zes velden.</p></div>
</div>

<div class="callout">
<strong>Het exacte contract nodig?</strong>
<p style="margin-top:6px;">Bekijk de op productie gebaseerde <a href="/nl/docs/reference/export-formats/">formaatreferentie</a>, de <a href="/nl/docs/reference/generated/core/csv-row-contracts/">CSV-rijcontracten</a> en de volledige downloadbare fixtures.</p>
</div>

## Datum en tijd
<p>Kies een datumnotatie, bijvoorbeeld <code>YYYY-MM-DD</code> of <code>MMM d, yyyy</code>, en een 12-uurs- of 24-uursnotatie voor tijden. Het voorbeeld onderaan het scherm verandert direct als je de instellingen aanpast.</p>

## Eenhedensysteem
<p>Schakel tussen <em>Metrisch</em> en <em>Imperiaal</em>. Dit beïnvloedt onder meer afstand (m/km tegenover ft/mi), gewicht (kg tegenover lb) en temperatuur (°C tegenover °F). HealthKit bewaart gegevens altijd in canonieke eenheden; Health.md rekent ze tijdens de export om.</p>

## Frontmattervelden
<p>Als je op <em>Frontmattervelden</em> tikt, wordt een afzonderlijke editor geopend:</p>
<ul>
<li>Schakel ingebouwde velden afzonderlijk in of uit (date, weekday, totalSteps enzovoort)</li>
<li>Wijzig een veldnaam als je Obsidian-configuratie andere sleutels verwacht</li>
<li>Voeg aangepaste velden met statische waarden toe, bijvoorbeeld <code>type: health</code></li>
<li>Voeg velden met plaatshouders toe die tijdens de export worden ingevuld, bijvoorbeeld <code>weather: {weather}</code></li>
</ul>

## Markdown-sjabloon
<p>Als je op <em>Markdown-sjabloon</em> tikt, wordt een sjablooneditor geopend met verschillende ingebouwde stijlen (Compact, Secties en Gedetailleerd) en een volledig aangepaste modus. Het voorbeeld toont het resultaat voor de gegevens van vandaag.</p>

## Voorbeeld
<p>Onderaan het scherm Formaat staat een livevoorbeeld van de gegevens van vandaag met je huidige instellingen. Zo kun je snel bijstellen: wijzig een optie, bekijk het voorbeeld en herhaal dit waar nodig.</p>

## Gerelateerde documentatie

<div class="related">
  <a href="/nl/docs/metrics/"><span>Gegevens</span>Gezondheidsmeetwaarden: kies eerst welke gegevens je wilt opnemen.</a>
  <a href="/nl/docs/individual-tracking/"><span>Details</span>Individueel bijhouden: een geheel andere uitvoer met één bestand per vermelding.</a>
  <a href="/nl/docs/daily-notes/"><span>Obsidian</span>Invoegen in dagelijkse notities: gebruikt dezelfde frontmattervelden.</a>
  <a href="/nl/docs/reference/export-formats/"><span>Contract</span>Exportformaten: het exacte gedrag van JSON, CSV, Markdown en Bases.</a>
</div>
