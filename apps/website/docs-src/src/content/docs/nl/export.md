---
title: "Exporteren"
description: "Gebruik het tabblad Exporteren om HealthKit en kluisverbindingen te controleren. Selecteer een bestemming en exporteer een datumbereik."
---

<p> Het tabblad Exporteren bestaat uit drie kleine beslissingen: bevestig de gereedheid, kies een bestemming en kies vervolgens het datumbereik voordat u een voorbeeld bekijkt of exporteert. </p>

## Lees de statusbadges
 <div class="options">
 <div class="option"> <strong> Gezondheidsbadge </strong> <p> Een groene stip betekent dat HealthKit is geautoriseerd. Een rode stip betekent dat er geen toegang wordt verleend. Tik om het iOS-toestemmingsblad opnieuw te proberen. Het blad verschijnt slechts één keer per installatie. Open daarna Instellingen → Privacy &amp; Beveiliging → Gezondheid. </p> </div>
 <div class="option"> <strong> Kluisbadge </strong> <p> Groene stip = er is een kluismap geselecteerd. Tik om de kluis opnieuw te kiezen of te wijzigen. Het label toont de mapnaam. </p> </div>
 </div>
 <p> De actie <em> Exporteren </em> blijft uitgeschakeld totdat HealthKit , het uitvoerformaat en de geselecteerde bestemming gereed zijn. Dit voorkomt de meest voorkomende fout: proberen te exporteren zonder bestemming. </p>

## Kies een exportdoel
 <p> De kaart Exportdoel bepaalt waar de gegevens naartoe gaan: </p>

<div class="options">
 <div class="option"> <strong> Lokale iPhone map </strong> <p> Schrijft rechtstreeks naar de map of Obsidian kluis die u op dit apparaat hebt gekozen. </p> </div>
 <div class="option"> <strong> Verbonden Mac </strong> <p> Verzendt vastgelegde dagelijkse gegevens en een exacte momentopname van de instellingen naar de dichtstbijzijnde Mac-app. De iPhone luidt HealthKit . De Mac rendert de geselecteerde formaten en schrijft de bestanden. </p> </div>
 <div class="option"> <strong> API-eindpunt </strong> <p> POST een JSON-envelop rechtstreeks van iPhone naar een door de gebruiker geconfigureerd HTTP(S)-eindpunt. <a href="/nl/docs/api-endpoint/"> Zie API-eindpunt </a> . </p> </div>
 </div>

## Kies een datumbereik
 <p> Datumvoorinstellingen dekken de gebruikelijke paden: </p>

<div class="options">
 <div class="option"> <strong> Vandaag </strong> <p> Exporteer de huidige dag. Handig voor het testen van de uitvoeropmaak. </p> </div>
 <div class="option"> <strong> Gisteren </strong> <p> De veiligste keuze voor dagelijkse export, omdat de dag voorbij is. </p> </div>
 <div class="option"> <strong> Altijd </strong> <p> Aanvulling vanaf de eerste HealthKit gegevens Health.md kan vinden. </p> </div>
 <div class="option"> <strong> Aangepast </strong> <p> Kies begin- en einddatums voor een specifiek bereik. </p> </div>
 </div>

## Voorbeeld of export
 <div class="options">
 <div class="option"> <strong> Voorbeeld </strong> <p> Toont de bestanden en inhoud die worden gegenereerd voordat er iets wordt geschreven. </p> </div>
 <div class="option"> <strong> Exporteren </strong> <p> Voert de export uit, toont de voortgang op het hoofdscherm en legt de uitkomst vast in de geschiedenis. </p> </div>
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

Een opgeslagen profiel bevriest de instellingen en bestemming voor de run. Profielbewuste geplande en automatiseringsgeschiedenisrijen behouden het runtimeprofiel, terwijl de geschiedenis een privacyveilig label behoudt voor de daadwerkelijk gebruikte bestemming. In een handmatige exporttabbladrij kan de profielnaam weggelaten worden. Latere hernoemingen en bestemmingswijzigingen herschrijven de bestaande geschiedenis niet. Ontbrekende profielreferenties worden niet gesloten in plaats van terug te vallen. Zie [Profielen exporteren](/nl/docs/export-profiles/).

## Tabbalk

<p> De vier tabbladen onder aan het scherm, Exporteren, Plannen, Synchroniseren, Instellingen, bestrijken het gehele app-oppervlak. Al het andere bevindt zich een of twee lagen diep in Instellingen. </p>

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
