---
title: "Individuele vermeldingen bijhouden"
description: "Schrijf optioneel één bestand per vermelding met tijdstempel. Elke work-out, bloeddrukmeting en stemmingsregistratie krijgt een eigen Markdown-bestand met de tijdstempel in de bestandsnaam."
---

## Wanneer je dit gebruikt
<p>Dagelijkse exports geven je één bestand per dag met samenvattingen. Met <em>individueel bijhouden</em> kun je naar één gebeurtenis verwijzen, bijvoorbeeld naar een specifieke work-out vanuit een dagboeknotitie of met een backlink van een stemmingsregistratie naar een weekoverzicht.</p>

<p>Deze bestanden komen naast de dagelijkse export en vervangen deze niet. Als beide functies zijn ingeschakeld, krijg je beide soorten bestanden.</p>

## Configuratie in twee stappen
<p>De instellingen bestaan bewust uit twee stappen:</p>
<ol>
<li><strong>Hoofdschakelaar.</strong> Schakel de functie voor de hele app in.</li>
<li><strong>Selectie per meetwaarde.</strong> Kies <em>welke</em> meetwaarden een afzonderlijk bestand krijgen. De meeste mensen willen geen bestand voor elke hartslagmeting (10,000 / day), maar wel één voor elke work-out (~1 / day).</li>
</ol>

## Snelacties
<div class="options">
<div class="option"><strong>Voorgestelde meetwaarden inschakelen</strong><p>Praktische standaardkeuzes: stemming, symptomen, work-outs, bloeddruk en bloedglucose. Bij deze meetwaarden is één bestand per vermelding doorgaans zinvol.</p></div>
<div class="option"><strong>Alle meetwaarden inschakelen</strong><p>Schakelt alles in. Let op: dit kan duizenden bestanden per dag opleveren.</p></div>
<div class="option"><strong>Alle meetwaarden uitschakelen</strong><p>Wist de selectie per meetwaarde zonder de hoofdschakelaar uit te zetten.</p></div>
</div>

## Mapstructuur
<div class="options">
<div class="option"><strong>Map met vermeldingen</strong><p>Het pad waar afzonderlijke bestanden terechtkomen, relatief aan de kluis. Standaard: <code>entries</code>.</p></div>
<div class="option"><strong>Ordenen op categorie</strong><p>Als deze optie aanstaat, worden vermeldingen in submappen per categorie geplaatst, zoals <code>entries/workouts/</code> en <code>entries/symptoms/</code>. Staat de optie uit, dan komen alle vermeldingen in één platte map.</p></div>
</div>

## Sjabloon voor bestandsnamen
<p>Standaard: <code>{date}_{time}_{metric}</code>. Beschikbare plaatshouders: <code>{date}</code>, <code>{time}</code>, <code>{metric}</code> en <code>{category}</code>. Voorbeelduitvoer:</p>

<div class="doc-diagram folder-tree" aria-label="Voorbeeld van de bestandsstructuur voor individuele vermeldingen">
<span>{vault}/entries/</span>
<span>├─ workouts/2026_07_14_0920_workouts_workouts_71000000-0000-0000-0000-000000000008.md</span>
<span>├─ symptoms/2026_07_14_0916_symptom_headache_symptom_headache_71000000-0000-0000-0000-000000000002.md</span>
<span>└─ vitals/2026_07_14_0918_blood_pressure_blood_pressure_71000000-0000-0000-0000-000000000004.md</span>
</div>

<p>Bij vermeldingen met een canoniek bronrecord voegt Health.md na de ingestelde bestandsnaam de geselecteerde meetwaarde en de HealthKit-UUID in kleine letters toe. Zo blijft hetzelfde bronrecord bij herhaalde exports stabiel en ontstaan er geen conflicten binnen dezelfde minuut. Compatibiliteitsvermeldingen zonder UUID behouden het kortere oude bestandsnaamgedrag.</p>

<div class="callout">
<strong>Let op.</strong>
<p style="margin-top:6px;">Hier verschijnen alleen categorieën waarvoor je ten minste één meetwaarde hebt ingeschakeld bij <em>Gezondheidsmeetwaarden</em>. Schakel daar eerst een meetwaarde in en kies daarna hier of deze afzonderlijk moet worden bijgehouden. Lees het <a href="/nl/docs/reference/individual-entry-tracking/">identiteitscontract voor bronrecords</a> en de gegenereerde <a href="/nl/docs/reference/generated/individual/filename-path-matrix/">bestandsnaammatrix</a> voordat je automatisering op deze paden baseert.</p>
</div>

## Gerelateerde documentatie

<div class="related">
  <a href="/nl/docs/metrics/"><span>Voorwaarde</span>Gezondheidsmeetwaarden: schakel eerst meetwaarden in.</a>
  <a href="/nl/docs/format/"><span>Uitvoer</span>Formaat: geldt ook voor bestanden met afzonderlijke vermeldingen.</a>
  <a href="/nl/docs/daily-notes/"><span>Alternatief</span>Invoegen in dagelijkse notities: een andere manier om meetwaarden aan notities te koppelen.</a>
  <a href="/nl/docs/reference/individual-entry-tracking/"><span>Contract</span>Referentie voor individuele vermeldingen: UUID-identiteit, frontmatter, gespecialiseerde vermeldingen en compatibiliteitsalternatieven.</a>
</div>
