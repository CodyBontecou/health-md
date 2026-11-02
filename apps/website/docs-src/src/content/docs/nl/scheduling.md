---
title: "Plan Apple Health exports en los problemen met gemiste runs op"
description: "Controleer een geplande export, krijg inzicht in de terugblik op voltooide dagen en herstel openstaande datums. iPhone achtergrondtiming is de beste inspanning; geschiedenis Opnieuw proberen gebruikt huidige instellingen."
---

Deze pagina beschrijft de planning van iPhone . Android heeft verschillende achtergrondrechten en aankoopvereisten; zie [Android-automatisering](/nl/docs/android/).

## Controleer de eerste geplande export

1. Activeer het beoogde profiel. Controleer de statistieken, formaten, gegevensdetails, schrijfgedrag en bestemming. Voer een voltooide dag handmatig uit en inspecteer het opgeslagen bestand of eindpuntresultaat voordat u automatisering inschakelt.
2. Open Schema en stel vervolgens Schema in of Beheer Schema. Schakel het schema in, kies Dagelijks, Wekelijks of Aangepast, stel de tijd in en begin met een overzicht van één dag. Sta meldingen toe als u lokale herstelherinneringen wilt.
3. Controleer of planning is ingeschakeld, de volgende gebeurtenis en het laatste resultaat. Inspecteer na een poging de geschiedenisgegevens en de daadwerkelijke bestemming; een label of melding voor de volgende run is geen bewijs dat er gegevens zijn geschreven.
4. Controleer de geëxporteerde data, eenheden, dekking en ontbrekende gegevens. Een opgeslagen bestand bewijst op zichzelf niet dat de bron volledig is vastgelegd.

In de telefoonversie met abonnement vereisen geplande en handmatige exports een actieve proefperiode, abonnement, levenslange aankoop of behouden permanente toegang. Er is geen lokale vrije exportvergoeding. Verlopen toegang moet worden hersteld voordat lopende werkzaamheden kunnen worden hervat. Zie [ontgrendelen en betaalmuur](/nl/docs/paywall/).

## Begrijp het voltooide dagvenster

Dagelijkse, wekelijkse en aangepaste schema's kunnen terugkijken. Aangepaste cadans wordt elke N dagen, weken of maanden vanaf de startdatum herhaald. Bij elk nieuw exemplaar wordt het gehele geconfigureerde voltooide-dagvenster opnieuw geëxporteerd, inclusief eerder geëxporteerde datums. Een driedaagse terugblik beslaat gisteren en de twee voorgaande dagen; vertraagde uitvoering zorgt ervoor dat het venster verankerd blijft op de geplande branddag.

Today Refresh is afzonderlijk werk voor de huidige dag en geen vervanging voor het voltooide-dagvenster. Inspecteer paden en schrijfgedrag voordat exporten elkaar overlappen; Voeg geen herhaalde dagelijkse momentopnamen toe als nieuwe metingen.

## Kies het juiste herstelpad

- **In afwachting van gepland herstel:** ontgrendel iPhone , open Health.md en inspecteer de lopende poging. Het behoudt de exacte onopgeloste datums, opgeslagen instellingen en bestemming. Voltooide datums blijven voltooid; herstel breidt zich niet uit in een nieuwe terugblik.
- **Opnieuw proberen vanuit de geschiedenis:** hiermee start u een nieuwe run voor dat bereik met gebruikmaking van de momenteel geconfigureerde instellingen en bestemming en wordt een nieuwe geschiedenisrij vastgelegd. Controleer de actieve configuratie voordat u op Opnieuw proberen drukt. Het is niet hetzelfde als het hervatten van een bevroren lopende poging.
- **Gewijzigde of niet-beschikbare bestemming:** herstel de toegang of inspecteer het in behandeling zijnde profiel voordat u het opnieuw probeert. Een oud iPhone API-herstel mag niet stilletjes een gewijzigd eindpunt of gewijzigde inloggegevens overnemen. Start niet herhaaldelijk nieuwe pogingen terwijl de oorspronkelijke poging nog niet is opgelost.

Bekijk lopende herstel-, profielidentiteit- en bestemmingsregels in [Profielen exporteren](/nl/docs/export-profiles/).

## Wat iOS wel en niet garandeert

De geselecteerde tijd is een streeftijd en geen gegarandeerde voltooiingstijd. iOS beheert de runtime op de achtergrond en de beveiliging van vergrendelde apparaten kan voorkomen dat HealthKit leest. Achtergrondverzoeken en stille wekmeldingen omzeilen deze bescherming niet.

Voor lokale herstelmeldingen is toestemming voor de melding vereist en dit is geen garantie voor bezorging op het beoogde tijdstip. Als u er een ontvangt, ontgrendelt u het apparaat en opent u het zodat Health.md kan proberen het te herstellen. Als er geen melding binnenkomt, opent u Health.md en controleert u het uitstaande werk en de geschiedenis. Controleer het resultaat in plaats van aan te nemen dat een waarschuwing of verstreken tijd succes betekent.

## Programmatische bediening
 <p> U kunt het schema in-/uitschakelen vanuit Shortcuts met behulp van de intentie <em> Geplande export in- of uitschakelen </em> . <a href="/nl/docs/shortcuts/"> Zie Shortcuts </a> voor voorbeelden. </p>

## Profielschema's en annulering

- Elk profiel kan zijn eigen schema behouden, inclusief een aangepast ritme. Als u van actief profiel wisselt, wordt de planning van een ander profiel niet opnieuw getarget.
- Er verschijnt een botsingswaarschuwing wanneer profielen dezelfde weergegeven paden op dezelfde bestemming kunnen schrijven. Controleer dit voordat u concurrerende schema's inschakelt. Health.md verandert geen van beide profielen stilletjes.
- Stoppen of Annuleren beëindigt alleen de huidige poging. Voltooide datums blijven voltooid, onopgeloste datums kunnen opnieuw worden geprobeerd en de planning blijft ingeschakeld.
- Elke geschiedenisrij blijft vastgezet aan het runtimeprofiel en het privacyveilige bestemmingslabel dat daadwerkelijk wordt gebruikt.

Beheer de bevroren instellingen en de bestemming per profiel in [Profielen exporteren](/nl/docs/export-profiles/).

## Verwant

<div class="related">
 <a href="/nl/docs/export-profiles/"> <span> Meerdere workflows </span> Exporteer profielen, geef elke opgeslagen configuratie zijn eigen bestemming en cadans. </a>
 <a href="/nl/docs/export/"> <span> Handmatig </span> Exporteren, voor eenmalige periodes. </a>
 <a href="/nl/docs/shortcuts/"> <span> Automatiseer </span> Shortcuts , schakel het schema van automatiseringen. </a>
 <a href="/nl/docs/sync/"> <span> Cross-device </span> Mac-synchronisatie, ook plannen op Mac. </a>
 </div>
