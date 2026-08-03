---
title: "Gezondheidsmeetwaarden"
description: "Kies uit de huidige catalogus met Apple Health-meetwaarden van Health.md. Zoek, schakel hele categorieën tegelijk in of uit of beheer elke meetwaarde afzonderlijk."
---

<div class="callout">
<strong>Opmerking voor Android.</strong>
<p style="margin-top:6px;">Deze pagina beschrijft de keuzelijst voor Apple Health-meetwaarden en de gegenereerde HealthKit-gegevensreferentie. De Android-app biedt 106 Health Connect-meetwaarden. Lees de <a href="/nl/docs/android/">Android-gids</a> voor de configuratie van Health Connect en platformspecifiek gedrag.</p>
</div>

## Indeling
<div class="options">
<div class="option"><strong>Teller bovenaan</strong><p>Toont live hoeveel meetwaarden en categorieën zijn ingeschakeld. Houd ingedrukt om de exacte selectiestatus naar het klembord te kopiëren.</p></div>
<div class="option"><strong>Alle meetwaarden ingeschakeld</strong><p>Met deze hoofdschakelaar zet je elke categorie aan of uit. Als beginpunt kun je alles inschakelen en daarna uitschakelen wat je niet nodig hebt.</p></div>
<div class="option"><strong>Zoeken</strong><p>Filtert direct op namen en ID's van meetwaarden. Probeer 'hart', 'slaap' of 'vo2'.</p></div>
</div>

## Categorieën
<p>De keuzelijst groepeert gewone samenvattingen en bronrecorddefinities in categorieën zoals Slaap, Activiteit, Hart, Ademhaling, Vitale functies, Lichaamsmetingen, Mobiliteit, Fietsen, Voeding, Mindfulness, Reproductieve gezondheid, Symptomen, Medicatie, gespecialiseerde records en Work-outs. Elke rij toont de aan-uitstatus en het actuele aantal ingeschakelde definities. De vanuit productie gegenereerde <a href="/nl/docs/reference/generated/core/metric-catalog/">meetwaardecatalogus</a> is de gezaghebbende actuele inventaris.</p>

<p>Tik op een categorie om de bijbehorende meetwaarden te bekijken. Elke meetwaarde heeft een eigen schakelaar en HealthKit-ID. De kleur van de stip geeft aan of HealthKit op dit apparaat momenteel gegevens voor die meetwaarde bevat.</p>

## Bereik van de selectie
<p>Je selectie van meetwaarden bepaalt <em>alles</em>:</p>
<ul>
<li>Dagelijkse exports: alleen ingeschakelde meetwaarden verschijnen in het bestand</li>
<li>Individueel bijhouden: alleen ingeschakelde meetwaarden krijgen een bestand per vermelding</li>
<li>Invoegen in dagelijkse notities: alleen ingeschakelde meetwaarden worden met de frontmatter samengevoegd</li>
<li>Shortcuts: exports van een datumbereik gebruiken dezelfde selectie</li>
</ul>

<div class="callout">
<strong>Praktische tip.</strong>
<p style="margin-top:6px;">Begin klein. Schakel Slaap, Activiteit en Hart in en voer een export uit. Bekijk het bestand en voeg daarna meer categorieën toe. Dat werkt sneller dan een bestand van 50 regels doorzoeken op meetwaarden die je niet nodig hebt.</p>
</div>

## Gerelateerde documentatie

<div class="related">
  <a href="/nl/docs/reference/"><span>Referentie</span>Exportreferentie: elke Apple-meetwaarde, sleutel, eenheid, bronrecorddefinitie en exportstructuur.</a>
  <a href="/nl/docs/android/"><span>Android</span>Android-app: configuratie van Health Connect, meetwaarden, bestemmingen en automatisering.</a>
  <a href="/nl/docs/format/"><span>Opmaak</span>Formaat: bepaal hoe de geselecteerde meetwaarden worden geschreven.</a>
  <a href="/nl/docs/individual-tracking/"><span>Details</span>Individueel bijhouden: schrijf daarnaast één bestand per vermelding met tijdstempel.</a>
  <a href="/nl/docs/daily-notes/"><span>Obsidian</span>Invoegen in dagelijkse notities: voeg deze meetwaarden toe aan je dagelijkse notities.</a>
</div>
