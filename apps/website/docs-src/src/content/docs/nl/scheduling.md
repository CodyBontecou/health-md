---
title: "Geplande exports"
description: "Voer exports automatisch uit, dagelijks of wekelijks en op een tijdstip dat je kiest. Health.md gebruikt iOS-achtergrondtaken en een geplande lokale melding als alternatief wanneer het apparaat is vergrendeld."
---

## Het tabblad Schema
<p>Dit is een statusscherm, geen instellingenpaneel. Je ziet in één oogopslag:</p>
<ul>
<li>of het schema aan- of uitstaat</li>
<li>wanneer de volgende geplande uitvoering plaatsvindt</li>
<li>wat het resultaat van de laatste uitvoering was</li>
</ul>
<p>Met één knop, <em>Schema instellen</em> of <em>Schema beheren</em>, open je de detailweergave.</p>

## Schema-instellingen
<div class="options">
<div class="option"><strong>Geplande exports inschakelen</strong><p>De hoofdschakelaar bovenaan. Staat deze uit, dan zijn er geen uitvoeringen op de achtergrond en geen meldingen.</p></div>
<div class="option"><strong>Frequentie</strong><p>Dagelijks, wekelijks of maandelijks. Een dagelijkse export omvat gisteren, een wekelijkse export de vorige 7 dagen en een maandelijkse export de vorige 30 dagen.</p></div>
<div class="option"><strong>Tijd</strong><p>Uur en minuut. iOS behandelt dit als richttijd, niet als garantie. Lees de toelichting over beperkingen hieronder.</p></div>
</div>

## Exportgeschiedenis
<p>De lijst onderaan het scherm Schema legt elke geplande uitvoering en het resultaat vast. Tik op een rij voor meer informatie. Bij een mislukte uitvoering staat een knop <em>Opnieuw proberen</em> waarmee je dat specifieke datumbereik opnieuw uitvoert.</p>

## Hoe planning in iOS werkelijk werkt
<div class="doc-diagram">
  <div class="flow-steps" aria-label="Alternatief verloop voor een geplande export">
    <span><strong>1. Richttijd</strong>Health.md vraagt iOS de app rond de gekozen tijd te activeren.</span>
    <span><strong>2. Poging op de achtergrond</strong>Als het apparaat beschikbaar is, voert iOS een taak voor achtergrondvernieuwing uit.</span>
    <span><strong>3. Alternatief bij vergrendeling</strong>Als HealthKit niet beschikbaar is, plaatst Health.md een melding.</span>
    <span><strong>4. Tik om te voltooien</strong>Open de melding, zodat de app HealthKit kan lezen en kan exporteren.</span>
  </div>
</div>

<div class="callout">
<strong>Belangrijke beperkingen van iOS.</strong>
<p style="margin-top:6px;">HealthKit-gegevens zijn niet leesbaar wanneer het apparaat is vergrendeld. Geplande exports gebruiken <code>BGAppRefreshTask</code>. iOS plant deze taak op basis van gebruikspatronen wanneer het systeem daar gelegenheid voor ziet. De ingestelde tijd is dus een richttijd, geen afspraak. Als alternatief plaatst de app op de geplande tijd een lokale melding wanneer het apparaat is vergrendeld. Tik daarop om de export uit te voeren.</p>
</div>
<ul>
<li>De geplande tijd is bij benadering. iOS kan de taak eerder of later uitvoeren of overslaan als het apparaat uitstaat of niet verbonden is.</li>
<li>Geplande exports werken het best als je telefoon regelmatig rond dezelfde tijd is aangesloten en ontgrendeld.</li>
<li>Mislukt de export omdat het apparaat was vergrendeld, tik dan op de melding. De app voert de export vervolgens met HealthKit-toegang uit.</li>
</ul>

## Programmatisch bedienen
<p>Je kunt het schema via Shortcuts in- of uitschakelen met de intentie <em>Geplande export in- of uitschakelen</em>. <a href="/nl/docs/shortcuts/">Bekijk Shortcuts</a> voor voorbeelden.</p>

## Gerelateerde documentatie

<div class="related">
  <a href="/nl/docs/export/"><span>Handmatig</span>Exporteren: voor eenmalige datumbereiken.</a>
  <a href="/nl/docs/shortcuts/"><span>Automatiseren</span>Shortcuts: schakel het schema vanuit automatiseringen.</a>
  <a href="/nl/docs/sync/"><span>Meerdere apparaten</span>Mac-synchronisatie: plan ook op de Mac.</a>
</div>
