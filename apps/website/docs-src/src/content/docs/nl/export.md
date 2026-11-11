---
title: "Exporteren"
description: "Exporteer Apple Health-gegevens nu of volgens een schema. Controleer in Archief of alles klaarstaat, kies een periode in Nu exporteren en stel per automatisering een bestemming in."
---

<p>Op de iPhone heeft Health.md drie tabbladen, <strong>Archief</strong>, <strong>Automatiseringen</strong> en <strong>Instellingen</strong>, plus een ronde knop <strong>Nu exporteren</strong>. Op de iPad staan de tabbladen in een navigatiekolom.</p>

## Controleer in Archief of alles klaarstaat
<p>De kalender in <strong>Archief</strong> laat zien welke gezondheidsdatums elke automatisering heeft gedekt. Als iets exports blokkeert, noemt de kaart <strong>Vraagt aandacht</strong> bovenaan de oorzaak:</p>
<div class="options">
<div class="option"><strong>Apple Health</strong><p>Health.md toont de configuratiestatus van de app, geen bevestigde leestoegang tot elke categorie. HealthKit verbergt geweigerde leestoestemmingen. Controleer de categorieën in Apple Health. Lege resultaten kunnen geweigerde toegang of ontbrekende gegevens betekenen. <a href="/nl/docs/troubleshooting/">Ontbrekende gegevens oplossen</a>.</p></div>
<div class="option"><strong>Map</strong><p>Kies de map, of kies hem opnieuw, via <strong>Instellingen → Map</strong>. Verliest iOS na het verplaatsen van een map de toegang, dan vraagt Health.md je hem opnieuw te kiezen; er wordt niets verwijderd.</p></div>
</div>

## Kies waar een automatisering naartoe exporteert
<p>Elke automatisering heeft een eigen bestemming. Open <strong>Automatiseringen</strong>, kies de automatisering en dan <strong>Uitvoer</strong>:</p>

<div class="options">
<div class="option"><strong>Lokale map</strong><p>Schrijft direct naar de map of Obsidian-kluis die je op dit apparaat hebt gekozen.</p></div>
<div class="option"><strong>Verbonden Mac</strong><p>Stuurt de vastgelegde dagelijkse gegevens en een exacte momentopname van de instellingen naar de Mac-app in de buurt. De iPhone leest HealthKit; de Mac maakt de gekozen formaten en schrijft de bestanden.</p></div>
<div class="option"><strong>API-eindpunt</strong><p>Stuurt een JSON-envelop met POST rechtstreeks van de iPhone naar een HTTP(S)-eindpunt dat je zelf instelt. <a href="/nl/docs/api-endpoint/">Zie API-eindpunt</a>.</p></div>
<div class="option"><strong>Agent Data-gateway</strong><p>Uploadt elk geëxporteerd bestand ongewijzigd naar het ingest-eindpunt van je gateway.</p></div>
</div>

## Kies een periode in Nu exporteren
<p>Tik op <strong>Nu exporteren</strong>, kies de automatisering als je er meerdere hebt, en daarna een periode:</p>

<div class="options">
<div class="option"><strong>Gisteren</strong><p>De veiligste keuze voor dagelijkse exports, omdat de dag voorbij is.</p></div>
<div class="option"><strong>7 dagen / 30 dagen</strong><p>De afgelopen week of maand, tot en met gisteren. Vanaf 30 dagen vraagt Health.md eerst om bevestiging.</p></div>
<div class="option"><strong>Aangepast</strong><p>Kies een begin- en einddatum voor een bepaalde periode.</p></div>
</div>
<p><strong>Wordt geschreven</strong> toont de bestemming en ongeveer hoeveel bestanden en dagen de export omvat. <strong>Alleen samenvatting van het datumbereik</strong> schrijft één samenvattingsbestand in plaats van dagbestanden. Vandaag en Alles blijven beschikbaar via <strong>Automatiseringen → Alle exportinstellingen</strong>.</p>

## Voorbeeld of export
<div class="options">
<div class="option"><strong>Voorbeeld</strong><p>Toont de bestanden en inhoud die worden gemaakt voordat er iets wordt geschreven.</p></div>
<div class="option"><strong>Exporteren</strong><p>Voert de export uit, toont de voortgang boven de tabbalk met een knop Annuleren en legt het resultaat vast in de geschiedenis en in de kalender van Archief.</p></div>
</div>

## Kies het gegevensdetailniveau

<div class="options">
 <div class="option"> <strong> Samenvatting </strong> <p> Compacte dagelijkse totalen en overzichten voor lezen, notities en dashboards. </p> </div>
 <div class="option"> <strong> Gedetailleerde tijdreeksen </strong> <p> Geselecteerde tijdstempels en intervallen. Dit niveau is beschikbaar op zowel Apple als Android wanneer de gekozen statistiek geschikte details blootlegt. </p> </div>
 <div class="option"> <strong> Gezondheidsgegevens zonder verlies </strong> <p> Het canonieke HealthKit bronrecordarchief. Dit niveau is alleen voor Apple. Android zet Health Connect records niet om in een HealthKit archief. </p> </div>
 </div>

## Wat 'exporteren' eigenlijk doet
 <ol>
 <li> Leg voor elke dag in het bereik geselecteerde samenvattende projecties vast. Voeg compatibele samples toe voor gedetailleerde tijdreeksen. En voor Lossless Health Records kunt u canonieke bronrecords en querydiagnostiek toevoegen. </li>
 <li> Pas het door u gekozen formaat toe ( Markdown , Bases, JSON of CSV) en sjabloon. </li>
 <li> Schrijf één bestand per dag naar <code>{vault}/{subfolder}/</code> , breng bestanden over via de aangesloten Mac-workflow of POST een JSON-envelop met versiebeheer naar uw API-eindpunt. </li>
 <li> Als <em> Individuele tracking </em> is ingeschakeld, leidt u geselecteerde Markdown bestanden per invoer af uit het canonieke archief voor op bestanden gebaseerde doelen. </li>
 <li> Als <em> Dagelijkse notitie-injectie </em> is ingeschakeld, voegt u de geselecteerde overzichtsvelden samen met uw dagelijkse notities. </li>
 </ol>

<p> JSON en CSV kunnen canonieke records bewaren. Markdown en Bases blijven leesbaar en bieden compacte vastlegdiagnostiek in plaats van het archief in te sluiten. Zie de <a href="/nl/docs/reference/"> volledige exportreferentie </a> voor exacte schema's en weglatingsregels. </p>

## Stop, annuleer en probeer het opnieuw

Als u stopt of annuleert, wordt alleen de huidige poging beëindigd. Reeds voltooide bestanden en datums blijven voltooid, terwijl onopgeloste datums beschikbaar blijven om opnieuw te proberen. Als u een geplande poging annuleert, wordt het terugkerende schema ervan niet uitgeschakeld.

## Profielen en betrouwbare geschiedenis

Een opgeslagen profiel legt de instellingen en de bestemming voor de uitvoering vast. Geschiedenisregels van geplande exports en automatiseringen die het profiel kennen, bewaren het gebruikte profiel, terwijl de geschiedenis een privacyvriendelijk label bewaart voor de bestemming die echt is gebruikt. Bij een regel van een handmatige export kan de profielnaam ontbreken. Latere naamswijzigingen en bestemmingswijzigingen herschrijven de bestaande geschiedenis niet. Ontbreekt een profiel waarnaar wordt verwezen, dan mislukt de bewerking zonder andere instellingen te gebruiken. Zie [Exportprofielen](/nl/docs/export-profiles/).

<div class="callout">
 <strong> Ontgrendelingsgedrag. </strong>
 <p style="margin-top:6px;"> De telefoonversies iPhone / iPad en Google Play waarvoor een abonnement is vereist, vereisen een actieve proefversie, abonnement, levenslange of behouden permanente toegang voor export en planning. Er blijft geen lokale vrije-exportvergoeding over. De Mac-companion en F-Droid build met inbegrepen toegang behouden hun gedocumenteerde uitzonderingen. <a href="/nl/docs/paywall/"> Zie de Paywall-pagina </a> voor Apple-aankoopgegevens. </p>
 </div>

## Verwant

<div class="related">
 <a href="/nl/docs/export-profiles/"> <span> Herhaalbare instellingen </span> Exporteer profielen, sla onafhankelijke instellingen, bestemmingen, schema's en stabiele automatiserings-ID's op. </a>
 <a href="/nl/docs/scheduling/"> <span> Dagelijks gebruik </span> Plannen, automatiseer dit zodat je nooit meer op Exporteren tikt. </a>
 <a href="/nl/docs/api-endpoint/"> <span> Integreer </span> API Endpoint, stuur geselecteerde JSON rechtstreeks naar uw eigen service. </a>
 <a href="/nl/docs/format/"> <span> Aanpassen </span> Formaataanpassing, verander hoe elk bestand eruit ziet. </a>
 <a href="/nl/docs/shortcuts/"> <span> Power </span> Shortcuts , activeer exports van Siri , automatiseringen of andere apps. </a>
 <a href="/nl/docs/reference/"> <span> Referentie </span> Exportreferentie, schema's, canonieke records, diagnostiek en gegenereerde voorbeelden. </a>
 </div>
