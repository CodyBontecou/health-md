---
title: "API-eindpunt"
description: "Stuur geselecteerde Apple Health-gegevens als JSON rechtstreeks vanaf de iPhone naar je eigen HTTP(S)-eindpunt."
---

<p>API-eindpunt is een exportbestemming waarmee je gegevens van Health.md naar je eigen server, webhook, database, dashboard of automatisering stuurt. De iPhone blijft Apple Health uitlezen. In plaats van bestanden te schrijven, stuurt de app JSON met een POST-verzoek naar het eindpunt dat je configureert.</p>

<div class="callout">
<strong>Let op je privacy.</strong>
<p style="margin-top:6px;">Deze bestemming stuurt de geselecteerde gezondheidsgegevens bewust naar de URL die je invoert. Gebruik een eindpunt dat je beheert of vertrouwt, kies bij voorkeur HTTPS en beperk de meetwaarden tot wat je dienst werkelijk nodig heeft.</p>
</div>

## De bestemming instellen

<ol>
<li>Open Health.md op de iPhone.</li>
<li>Ga naar <strong>Exporteren</strong>.</li>
<li>Kies bij <strong>Exportbestemming</strong> de optie <strong>API-eindpunt</strong>.</li>
<li>Voer een URL in, bijvoorbeeld <code>https://api.example.com/healthmd/ingest</code>.</li>
<li>Optioneel: voer een bearer-token in. Health.md bewaart dit in de sleutelhanger.</li>
<li>Tik op <strong>Gereed</strong>, kies het datumbereik en de meetwaarden en tik daarna op <strong>Exporteren</strong>.</li>
</ol>

<p>Voer je een token zonder voorvoegsel in, dan verstuurt Health.md dit als <code>Authorization: Bearer &lt;token&gt;</code>. Begint de waarde al met <code>Bearer </code> of <code>Basic </code>, dan verstuurt Health.md de waarde ongewijzigd.</p>

## Structuur van de payload

<p>Health.md verstuurt één POST-verzoek per exportactie. De hoofdtekst is een afzonderlijk van versies voorziene <code>healthmd.api_export</code>-envelop met dagelijkse records volgens het openbare schema v8 <code>healthmd.health_data</code>. Versie 1 van de API-envelop bevat de dagelijkse records. Versie 2 kan daarnaast provider-sidecars bevatten zonder het schema van de dagelijkse records te wijzigen.</p>

<div class="options">
<div class="option"><strong><code>records</code></strong><p>Volledige dagelijkse objecten volgens schema v8 die voor het gevraagde bereik zijn behouden. Dit omvat volledig lege records waarvan het querymanifest als bewijs dient.</p></div>
<div class="option"><strong><code>failed_date_details</code></strong><p>Datums die zijn mislukt voordat er een dagelijks document kon worden behouden.</p></div>
<div class="option"><strong><code>daily_record_schema_version</code></strong><p>De versie van het dagelijkse schema in <code>records</code>. Deze versie ontwikkelt zich onafhankelijk van de versie van de API-envelop.</p></div>
<div class="option"><strong>Provider-sidecars</strong><p>Optionele externe records in v2 met een eigen schema en eigen identiteitsregels wanneer een verbonden provider is ingeschakeld.</p></div>
</div>

<p>Bekijk de volledig vanuit productie gegenereerde <a href="/docs/reference/generated/automation/api-export-v1.json">API v1-envelop</a> en <a href="/docs/reference/generated/automation/api-export-v2-provider-sidecar.json">API v2-envelop met provider-sidecar</a>. Het <a href="/nl/docs/reference/api-and-cli/">API- en CLI-contract</a> beschrijft elk veld, elke versiegrens en elke acceptatieregel.</p>

## Vereisten voor het eindpunt

<div class="options">
<div class="option"><strong>Methode</strong><p>Accepteer <code>POST</code>.</p></div>
<div class="option"><strong>Contenttype</strong><p>Accepteer <code>application/json</code>.</p></div>
<div class="option"><strong>Geslaagd</strong><p>Geef een willekeurige <code>2xx</code>-status terug nadat de payload veilig is geaccepteerd.</p></div>
<div class="option"><strong>Mislukt</strong><p>Geef <code>4xx</code> of <code>5xx</code> terug voor afgewezen verzoeken. Health.md toont waar mogelijk een kort voorbeeld van het antwoord.</p></div>
</div>

<p>Maak het eindpunt voor betrouwbare verwerking idempotent per datum. Iemand kan hetzelfde exportbereik opnieuw uitvoeren na een wijziging van de meetwaarden of nadat een serverfout is opgelost.</p>

## Tips

<ul>
<li>Test met één dag voordat je een lange historische aanvulling uploadt.</li>
<li>Laat Gezondheidsgegevens zonder verlies ingeschakeld als volledigheid van de bron belangrijk is. Verklein het datumbereik voor omvangrijke routes, klinische documenten, ECG's of bijlagen.</li>
<li>Valideer het token op de server voordat je een payload opslaat.</li>
<li>Gebruik <code>records[].date</code> als primaire sleutel per dag.</li>
<li>Geef een beknopte fouttekst terug; Health.md toont slechts een kort voorbeeld.</li>
</ul>

## Problemen oplossen

| Probleem | Betekent meestal | Oplossing |
|---|---|---|
| API-bestemming is niet gereed | URL is leeg of ongeldig | Open de instellingen voor API-eindpunt opnieuw en voer een geldige HTTP(S)-URL in. |
| HTTP 401 of 403 | Token ontbreekt of is afgewezen | Werk het token of de autorisatieregels op de server bij. |
| HTTP 404 | URL-pad is onjuist | Controleer de route op je server. |
| HTTP 413 | Payload is te groot | Exporteer minder dagen. Gebruik alleen een uitvoer met samenvattingen als de ontvanger geen canonieke bronrecords nodig heeft. |
| Sommige datums ontbreken | Geen ingeschakelde HealthKit-gegevens voor die datums | Controleer <code>failed_date_details</code> en je selectie van meetwaarden. |

## Gerelateerde documentatie

<div class="related">
  <a href="/nl/docs/export/"><span>Bron</span>Exporteren: kies bestemmingen en datumbereiken en voer handmatige exports uit.</a>
  <a href="/nl/docs/reference/api-and-cli/"><span>Schema</span>API- en CLI-referentie: exacte enveloppen, versies, foutgedrag en gegenereerde voorbeelden.</a>
  <a href="/nl/docs/format/"><span>Uitvoer</span>Formaataanpassing: JSON, CSV, Markdown, eenheden en velden.</a>
</div>
