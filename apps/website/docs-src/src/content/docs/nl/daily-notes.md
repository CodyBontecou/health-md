---
title: "Invoegen in dagelijkse notities"
description: "Voeg geselecteerde gezondheidsmeetwaarden samen met de YAML-frontmatter en eventueel de hoofdtekst van je bestaande dagelijkse notities in Obsidian of een andere Markdown-app."
---

## Wat deze functie doet
<p>Houd je dagelijkse notities bij, bijvoorbeeld in <code>Daily/2026-04-28.md</code>, dan kun je deze functie inschakelen. Bij elke export voegt de app de geselecteerde meetwaarden samen met de YAML-frontmatter van die notities, zonder de rest van de inhoud te wijzigen.</p>

<div class="doc-diagram merge-preview" aria-label="Frontmatter van een dagelijkse notitie voor en na samenvoeging door Health.md">
<div class="merge-card">
<strong>Voor</strong>
<pre><code>---
title: Tuesday note
mood: focused
---

Wrote launch notes...</code></pre>
</div>
<div class="merge-card">
<strong>Na de export</strong>
<pre><code>---
title: Tuesday note
mood: focused
steps: 12642
sleep_total_hours: 7.31
workout_count: 1
---

Wrote launch notes...</code></pre>
</div>
</div>

<p>De app kan ook Markdown-secties zoals Slaap, Activiteit en Hart in de hoofdtekst invoegen. De app beheert deze secties en vervangt ze bij elke export. Koppen die je zelf schrijft, blijven ongewijzigd.</p>

## Locatie
<div class="options">
<div class="option"><strong>Map</strong><p>Het pad naar de map met dagelijkse notities, relatief aan de kluis. De standaardwaarde is <code>Daily</code>. Laat het veld leeg voor de hoofdmap van de kluis. Voorbeelden: <code>Daily</code> en <code>Journal/Daily</code>.</p></div>
<div class="option"><strong>Bestandsnaam</strong><p>Het patroon voor de bestandsnaam van de notitie, zonder extensie. De standaardwaarde <code>{date}</code> wordt bijvoorbeeld <code>2026-04-28</code>.</p></div>
</div>

## Plaatshouders voor bestandsnamen
<p>Je kunt de volgende plaatshouders combineren:</p>
<ul>
<li><code>{date}</code> — volledige ISO-datum (<code>2026-04-28</code>)</li>
<li><code>{year}</code>, <code>{month}</code>, <code>{day}</code></li>
<li><code>{weekday}</code> — korte naam (<code>Tue</code>)</li>
<li><code>{monthName}</code> — lange naam (<code>April</code>)</li>
<li><code>{quarter}</code> — Q1 / Q2 / Q3 / Q4</li>
</ul>
<p>Voorbeeld: <code>{year}/{monthName}/{date}-{weekday}</code> → <code>2026/April/2026-04-28-Tue.md</code>. Onder het veld zie je direct een voorbeeld van het uiteindelijke pad.</p>

## Opties
<div class="options">
<div class="option"><strong>Notitie aanmaken als deze ontbreekt</strong><p>Maak een nieuwe dagelijkse notitie als er voor een datum nog geen bestaat. Laat dit uit als je notities zelf aanmaakt, bijvoorbeeld met Obsidian Templater of een vergelijkbare plugin.</p></div>
<div class="option"><strong>Meetwaardesecties invoegen</strong><p>Schrijf ook koppen zoals Slaap, Activiteit en Hart in de hoofdtekst van de notitie. De app beheert deze secties en vervangt ze bij elke export. Deze optie staat standaard uit.</p></div>
</div>

## Welke meetwaarden worden ingevoegd
<p>De app gebruikt de meetwaarden die je bij <em>Gezondheidsmeetwaarden</em> hebt geselecteerd. Op dit scherm staat geen aparte keuzelijst. Wijzig je de selectie bij Gezondheidsmeetwaarden, dan neemt Invoegen in dagelijkse notities die selectie over.</p>

## Voorbeeld van de frontmatter
<p>Onderaan het scherm Invoegen in dagelijkse notities staat een livevoorbeeld van de frontmatter die wordt samengevoegd. Dit voorbeeld verandert als je andere meetwaarden kiest of de frontmattervelden bij de formaataanpassing wijzigt.</p>

<div class="callout">
<strong>Zo werkt het samenvoegen.</strong>
<p style="margin-top:6px;">Heeft je dagelijkse notitie al frontmatter, dan behoudt de app je eigen sleutels en voegt zij alleen beheerde sleutels toe of werkt ze die bij. Door de app beheerde secties in de hoofdtekst staan tussen HTML-opmerkingen. Daardoor levert elke herhaling hetzelfde resultaat op.</p>
</div>

## Gerelateerde documentatie

<div class="related">
  <a href="/nl/docs/metrics/"><span>Voorwaarde</span>Gezondheidsmeetwaarden: kies wat de app invoegt.</a>
  <a href="/nl/docs/format/"><span>Formaat</span>Frontmattervelden: wijzig sleutelnamen en voeg aangepaste velden toe.</a>
  <a href="/nl/docs/individual-tracking/"><span>Details</span>Individueel bijhouden: een alternatief om afzonderlijke gebeurtenissen bij te houden.</a>
</div>
