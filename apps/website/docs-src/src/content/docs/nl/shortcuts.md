---
title: "Shortcuts en App Intents"
description: "Met acht App Intents start je exports, haal je samenvattingen op en schakel je de planning via Siri, de app Shortcuts, focusfilters, automatiseringen en andere hosts met AppIntent-ondersteuning."
---

## Beschikbare intenties
<div class="options">
<div class="option"><strong>Gezondheidsgegevens van gisteren exporteren</strong><p>Snelkoppeling zonder parameters. De snelste manier om gewoon de gegevens van gisteren te exporteren zonder extra vragen. Gebruikt dezelfde engine als de handmatige export. Optionele parameter <em>Profiel</em> (zie <a href="#profiles">Exportprofielen</a>).</p></div>
<div class="option"><strong>Gezondheidsgegevens voor een datum exporteren</strong><p>Eén parameter <em>Datum</em>. Het tijdstip wordt genegeerd. Handig voor automatiseringen op basis van een kalender. Optionele parameter <em>Profiel</em>.</p></div>
<div class="option"><strong>Gezondheidsgegevens voor een datumbereik exporteren</strong><p>Parameters <em>Begindatum</em> en <em>Einddatum</em>, beide inclusief. Gebruik dit om historische gegevens aan te vullen. Optionele parameter <em>Profiel</em>.</p></div>
<div class="option"><strong>Gezondheidsgegevens van de laatste N dagen exporteren</strong><p>Parameter <em>Aantal dagen</em> (1–366). Het bereik eindigt gisteren en de standaardwaarde is 7. Geschikt voor automatiseringen zoals 'exporteer elke zondag de laatste 7 dagen'. Optionele parameter <em>Profiel</em>.</p></div>
<div class="option"><strong>Gezondheidssamenvatting voor een datum ophalen</strong><p>Geeft een gestructureerde momentopname terug van stappen, actieve calorieën, slaap en hartslag zonder iets naar de kluis te schrijven. Gebruik deze intentie in Shortcuts om waarden aan andere apps door te geven.</p></div>
<div class="option"><strong>Status van laatste export ophalen</strong><p>Geeft het tijdstempel, de successtatus, het aantal dagen en een eventuele foutreden van de meest recente vastgelegde export terug. Een verzoek op een vergrendeld apparaat blijft in behandeling tot een nieuwe poging en verschijnt in die tussentijd niet als huidige status.</p></div>
<div class="option"><strong>Geplande export in- of uitschakelen</strong><p>Booleaanse parameter. Gebruik deze om het schema te pauzeren, bijvoorbeeld tijdens de focus Vakantie, en later te hervatten.</p></div>
<div class="option"><strong>Gezondheidsgegevens exporteren</strong><p>Algemene export die het datumbereik uit de laatst gebruikte status van het exportvenster in de app overneemt. Deze is minder gebruikelijk; de varianten met een expliciet datumbereik zijn meestal duidelijker. Optionele parameter <em>Profiel</em>.</p></div>
</div>

<a id="profiles"></a>
## Exportprofielen
<p>Alle vijf exportintents accepteren een optionele parameter <em>Profiel</em>. Laat hem leeg om met je huidige in-app exportinstellingen te draaien; geef de naam van een opgeslagen profiel door om de bevroren configuratie van dat profiel — metrieselectie, formaten en bestemming — uit te voeren, ongeacht wat de app op dat moment toont.</p>
<div class="callout">
<strong>Let op voor bestaande sneltoetsen zonder parameter.</strong>
<p style="margin-top:6px;">Zodra je je eerste exportprofiel in de app aanmaakt, exporteert een sneltoets zonder ingesteld <em>Profiel</em> met de opgeslagen instellingen van het <em>actieve</em> profiel in plaats van de actuele app-instellingen. Vertrouw je op het oude gedrag, pin de sneltoets dan op een specifiek profiel (of houd nul profielen) om expliciet te blijven. Een profielnaam die niet meer bestaat faalt met een duidelijke fout in plaats van het verkeerde te exporteren.</p>
</div>
## Waar je ze vindt
<p>Open de app Shortcuts op iOS of macOS. Tik op <em>+</em> om een nieuwe snelkoppeling te maken en zoek naar 'Health.md' of een van de bovenstaande namen. De intenties staan in de categorie <em>Gezondheid</em>.</p>
<p>De meeste intenties hebben <code>openAppWhenRun = false</code>. Ze worden dus zonder zichtbare app uitgevoerd: de app opent niet en de interface flitst niet in beeld. Je kunt ze gebruiken vanuit automatiseringen en focusfilters, via Hé Siri en met de actieknop.</p>

<div class="callout">
<strong>Uitvoeren bij vergrendeling ontgrendelt HealthKit niet.</strong>
<p style="margin-top:6px;">Apple beschermt HealthKit-gegevens wanneer de iPhone is vergrendeld en <a href="https://support.apple.com/guide/security/protecting-access-to-users-health-data-sec88be9900f/web">trekt app-toegang ongeveer tien minuten na het vergrendelen in</a>. Met <em>Uitvoeren bij vergrendeling toestaan</em> kan Shortcuts de actie starten, maar deze instelling omzeilt de gegevensbescherming van HealthKit niet. De toestemming voor Health.md-appinhoud in Shortcuts doet dat evenmin.</p>
<p>Als HealthKit niet beschikbaar is, bewaart Health.md de gevraagde datums als openstaand en plaatst het de melding <em>Gezondheidsexport vereist aandacht</em>. Ontgrendel de iPhone en tik daarna op de melding of open Health.md om het opnieuw te proberen. Een volledig automatische export zonder toezicht kan niet worden gegarandeerd zolang de telefoon vergrendeld blijft.</p>
</div>

<a id="recipe-nightly-export-with-confirmation"></a>
## Recept: dagelijkse export met bevestiging
<ol>
<li><strong>Persoonlijke automatisering</strong> → <em>Tijdstip</em> → kies een moment waarop je de ontgrendelde iPhone meestal gebruikt, bijvoorbeeld 8:00 AM.</li>
<li>Intentie <em>Gezondheidsgegevens van gisteren exporteren</em>.</li>
<li>Intentie <em>Status van laatste export ophalen</em>.</li>
<li><em>Toon melding</em> met het resultaat.</li>
</ol>
<p><strong>Opmerking over een openstaande status:</strong> <em>Status van laatste export ophalen</em> leest het meest recente item in de exportgeschiedenis. Als HealthKit tijdens deze uitvoering door vergrendeling niet beschikbaar was, kan de intentie nog de vorige export tonen totdat je het openstaande verzoek opnieuw uitvoert. De herstelmelding van Health.md zelf is het gezaghebbende signaal voor openstaand werk.</p>

## Recept: eenmalig historische gegevens aanvullen
<ol>
<li>Maak een snelkoppeling.</li>
<li>Gebruik <em>Gezondheidsgegevens voor een datumbereik exporteren</em> met begin = 2024-01-01 en einde = 2024-12-31.</li>
<li>Voer de snelkoppeling uit. Health.md doorloopt het jaar en schrijft één bestand per dag. Voor een heel jaar kan dit enkele minuten duren.</li>
</ol>

## Recept: planning pauzeren tijdens vakantie
<ol>
<li><strong>Focusfilter</strong>: voer bij het inschakelen van de focus <em>Vakantie</em> de intentie <em>Geplande export in- of uitschakelen</em> uit met Enabled = false.</li>
<li>Voer de intentie bij het uitschakelen van de focus opnieuw uit met Enabled = true.</li>
</ol>

<div class="callout">
<strong>Toestemming vereist.</strong>
<p style="margin-top:6px;">Intenties nemen je HealthKit-toestemming en kluisselectie uit de app over. Ze geven een duidelijke fout als de app niet ten minste eenmaal op dit apparaat is geopend en geconfigureerd.</p>
</div>

## Gerelateerde documentatie

<div class="related">
  <a href="/nl/docs/scheduling/"><span>Bron</span>Planning: het equivalent in de app van de intentie om het schema te schakelen.</a>
  <a href="/nl/docs/export/"><span>Bron</span>Exporteren: het equivalent in de app van de intenties voor datumbereiken.</a>
</div>
