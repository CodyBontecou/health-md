---
title: "Exporteren"
description: "Het tabblad Exporteren is het centrale scherm. Je ziet er of HealthKit en je kluis verbonden zijn, kiest een bestemming en voert een eenmalige export uit voor het gewenste datumbereik."
---

<p>Op het tabblad Exporteren neem je drie beslissingen: controleer of alles gereed is, kies een bestemming en stel het datumbereik in voordat je een voorbeeld bekijkt of de export uitvoert.</p>

## Statusbadges controleren
<div class="options">
<div class="option"><strong>Gezondheidsbadge</strong><p>Een groene stip betekent dat HealthKit toestemming heeft. Rood betekent dat toegang niet is verleend. Tik erop om het iOS-toestemmingsvenster opnieuw te openen. Dat werkt alleen de eerste keer na een installatie. Daarna reageert iOS niet en moet je de toegang aanpassen via Instellingen → Privacy en beveiliging → Gezondheid.</p></div>
<div class="option"><strong>Kluisbadge</strong><p>Een groene stip betekent dat er een kluismap is geselecteerd. Tik erop om de kluis opnieuw te kiezen of te wijzigen. Het label toont de mapnaam.</p></div>
</div>
<p>De actie <em>Exporteren</em> blijft uitgeschakeld totdat HealthKit, het uitvoerformaat en de gekozen bestemming gereed zijn. Zo voorkom je de meest voorkomende fout: exporteren zonder bestemming.</p>

## Een exportbestemming kiezen
<p>De kaart Exportbestemming bepaalt waar de gegevens naartoe gaan:</p>

<div class="options">
<div class="option"><strong>Lokale iPhone-map</strong><p>Schrijft rechtstreeks naar de map of Obsidian-kluis die je op dit apparaat hebt gekozen.</p></div>
<div class="option"><strong>Verbonden Mac</strong><p>Stuurt de vastgelegde dagelijkse gegevens en een exacte momentopname van de instellingen naar de Mac-app in de buurt. De iPhone leest HealthKit; de Mac maakt de gekozen formaten en schrijft de bestanden.</p></div>
<div class="option"><strong>API-eindpunt</strong><p>Stuurt met een POST-verzoek rechtstreeks vanaf de iPhone een JSON-envelop naar een HTTP(S)-eindpunt dat je zelf configureert. <a href="/nl/docs/api-endpoint/">Lees meer over het API-eindpunt</a>.</p></div>
</div>

## Een datumbereik kiezen
<p>De voorinstellingen dekken de meestgebruikte bereiken:</p>

<div class="options">
<div class="option"><strong>Vandaag</strong><p>Exporteert de huidige dag. Handig om de uitvoeropmaak te testen.</p></div>
<div class="option"><strong>Gisteren</strong><p>De veiligste keuze voor een dagelijkse export, omdat de dag compleet is.</p></div>
<div class="option"><strong>Alle gegevens</strong><p>Vult de export aan vanaf de oudste HealthKit-gegevens die Health.md kan vinden.</p></div>
<div class="option"><strong>Aangepast</strong><p>Stel een begin- en einddatum in voor een specifiek bereik.</p></div>
</div>

## Voorbeeld bekijken of exporteren
<div class="options">
<div class="option"><strong>Voorbeeld</strong><p>Toont de bestanden en inhoud die Health.md gaat maken voordat er iets wordt geschreven.</p></div>
<div class="option"><strong>Exporteren</strong><p>Voert de export uit, toont de voortgang op het hoofdscherm en legt het resultaat vast in de geschiedenis.</p></div>
</div>

## Het niveau van gegevensdetail kiezen

<div class="options">
<div class="option"><strong>Samenvatting</strong><p>Compacte dagtotalen en overzichten voor lezen, notities en dashboards.</p></div>
<div class="option"><strong>Gedetailleerde tijdreeks</strong><p>Geselecteerde tijdgestempelde metingen en intervallen. Dit niveau is beschikbaar op Apple en Android als de meetwaarde geschikt detail biedt.</p></div>
<div class="option"><strong>Verliesvrije gezondheidsrecords</strong><p>Het canonieke archief met HealthKit-bronrecords. Dit niveau is alleen voor Apple; Android zet Health Connect-records niet om in een HealthKit-archief.</p></div>
</div>

## Wat er tijdens een export gebeurt
<ol>
<li>Voor elke dag in het bereik legt Health.md de gekozen samenvattingen vast, voegt het compatibele metingen toe voor Gedetailleerde tijdreeks en voegt het bij Verliesvrije gezondheidsrecords canonieke bronrecords en querydiagnostiek toe.</li>
<li>De app past het gekozen formaat (Markdown, Bases, JSON of CSV) en de gekozen sjabloon toe.</li>
<li>De app schrijft één bestand per dag naar <code>{vault}/{subfolder}/</code>, draagt bestanden over via de verbonden Mac-workflow of stuurt een JSON-envelop met versiebeheer naar je API-eindpunt.</li>
<li>Als <em>Individueel bijhouden</em> is ingeschakeld, leidt de app voor bestandsbestemmingen de gekozen Markdown-bestanden per vermelding af uit het canonieke archief.</li>
<li>Als <em>Invoegen in dagelijkse notities</em> is ingeschakeld, voegt de app de gekozen samenvattingsvelden samen met je dagelijkse notities.</li>
</ol>

<p>JSON en CSV kunnen canonieke records behouden. Markdown en Bases blijven leesbaar en tonen compacte diagnostiek over de vastlegging in plaats van het archief in te sluiten. In de <a href="/nl/docs/reference/">volledige exportreferentie</a> staan de exacte schema's en regels voor weglatingen.</p>

## Stoppen, annuleren en opnieuw proberen

Stoppen of annuleren beëindigt alleen de huidige poging. Voltooide bestanden en datums blijven behouden; open datums kunnen opnieuw worden geprobeerd. Een geplande poging annuleren schakelt het terugkerende schema niet uit.

## Profielen en betrouwbare geschiedenis

Een opgeslagen profiel bevriest de instellingen en bestemming voor de uitvoering. Geschiedenisrijen van profielgebonden geplande en geautomatiseerde uitvoeringen bewaren het gebruikte profiel; de geschiedenis bewaart ook een privacyvriendelijk label van de werkelijke bestemming. Een handmatige exportregel kan de profielnaam weglaten. Latere wijzigingen aan naam of bestemming herschrijven bestaande geschiedenis niet. Ontbrekende profielverwijzingen stoppen veilig. Zie [Exportprofielen](/nl/docs/export-profiles/).

## Tabbladbalk

<p>De vier tabbladen onderaan het scherm, Exporteren, Schema, Synchronisatie en Instellingen, omvatten de hele app. Alle overige opties vind je één of twee niveaus dieper onder Instellingen.</p>

<div class="callout">
<strong>Wat Full Access ontgrendelt.</strong>
<p style="margin-top:6px;">Op Apple-platforms geldt de gratis ruimte voor 10 handmatige of geplande exportacties. Full Access heft die limiet op en ontgrendelt Mac-bestemmingsworkflows en Opdrachten. Android biedt daarentegen 10 gratis handmatige acties en vereist de eenmalige aankoop voor planning. Lees de <a href="/nl/docs/paywall/">pagina over Full Access</a> voor de Apple-aankoop.</p>
</div>

## Gerelateerde documentatie

<div class="related">
  <a href="/nl/docs/export-profiles/"><span>Profielen</span>Bewaar onafhankelijke bestemmingen, instellingen, planningen en automatiserings-ID’s.</a>
  <a href="/nl/docs/scheduling/"><span>Dagelijks gebruik</span>Planning: automatiseer de export zodat je niet meer op Exporteren hoeft te tikken.</a>
  <a href="/nl/docs/api-endpoint/"><span>Integratie</span>API-eindpunt: stuur geselecteerde JSON rechtstreeks naar je eigen dienst.</a>
  <a href="/nl/docs/format/"><span>Aanpassen</span>Formaataanpassing: bepaal hoe elk bestand eruitziet.</a>
  <a href="/nl/docs/shortcuts/"><span>Automatisering</span>Shortcuts: start exports met Siri, automatiseringen of andere apps.</a>
  <a href="/nl/docs/reference/"><span>Referentie</span>Exportreferentie: schema's, canonieke records, diagnostiek en gegenereerde voorbeelden.</a>
</div>
