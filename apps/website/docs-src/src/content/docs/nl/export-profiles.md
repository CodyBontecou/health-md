---
title: "Exportprofielen"
description: "Bewaar exportinstellingen en een bestemming samen en voer die configuratie uit of plan die vanaf iPhone, Android, Opdrachten, de CLI, Tasker of adb."
---

Exportprofielen houden een herhaalbare exportconfiguratie bij elkaar. Beheer ze in Health.md op iPhone of Android. Op Apple-platforms is de huidige beheerworkflow alleen op iPhone gedocumenteerd en getest; er wordt geen beheeroppervlak op iPad of Mac geclaimd.

## Profielen beheren en bewerken

Open **Instellingen → Exportprofielen**. De lijst markeert het actieve profiel en laat je profielen maken, hernoemen, dupliceren, verwijderen, activeren of bekijken. Open de details van een profiel om de stabiele ID te kopiëren. Het laatste profiel kan niet worden verwijderd.

Het tabblad Exporteren bewerkt het actieve profiel. Activeer eerst een ander profiel als je de huidige instellingen niet wilt wijzigen.

Elk profiel bevriest de keuzes die nodig zijn om een uitvoering te herhalen:

- geselecteerde meetwaarden, Gegevensdetail, formaten, sjablonen, bestandsnamen, eenheden en schrijfgedrag;
- een eigen doelmap en submap, API-endpoint of verbonden Mac wanneer het platform dat ondersteunt;
- dagnotities, afzonderlijke vermeldingen, roll-ups en andere uitvoeropties die het platform ondersteunt.

Een planning is afzonderlijk gekoppeld aan de stabiele identiteit van het profiel. Een ander actief profiel kiezen richt die planning niet opnieuw. Een profieluitvoering gebruikt de opgeslagen momentopname in plaats van gewijzigde instellingen van een ander profiel over te nemen.

## Veilig uitvoeren en plannen

- Elk profiel kan een eigen terugkerende planning hebben, inclusief het aangepaste ritme dat de app aanbiedt.
- Platformrechten blijven gelden: de gratis Apple-ruimte kan geplande acties omvatten, terwijl planning op Android de eenmalige aankoop vereist.
- Health.md waarschuwt wanneer profielen dezelfde gegenereerde paden op dezelfde bestemming zouden kunnen schrijven. De waarschuwing wijzigt geen profiel of planning stilzwijgend.
- Stoppen of annuleren raakt alleen de huidige poging. Voltooide datums blijven voltooid, onopgeloste datums blijven opnieuw uitvoerbaar en de planning blijft ingeschakeld.
- Als een profielreferentie ontbreekt, stopt Health.md veilig. De app valt nooit terug op het actieve profiel of een andere bestemming.

## Namen, stabiele ID's en automatisering

Een weergavenaam is voor mensen en kan veranderen. De stabiele ID maakt automatisering bestand tegen hernoemen. Kopieer die via **Instellingen → Exportprofielen → Profiel-ID**.

- Apple Opdrachten selecteert een profiel op weergavenaam; een lege profielparameter gebruikt het actieve profiel.
- Android-broadcasts via Tasker en adb kunnen de extra `PROFILE` met een stabiele ID of naam meegeven. Gebruik bij voorkeur de ID voor workflows die hernoemen moeten overleven.
- De directe CLI accepteert `--profile PROFILE_ID` voor ondersteunde taken met gegenereerde bestanden. Het profiel levert de bevroren uitvoerinstellingen; het verplichte `--destination` kiest nog steeds de bestaande map op de computer.

Lees de automatiseringshandleiding van het platform voordat je een onbeheerde workflow inschakelt.

## Geschiedenis, herstel en privacy

Geschiedenisrijen van profielgebonden geplande en geautomatiseerde uitvoeringen bewaren het gebruikte profiel. De geschiedenis bewaart ook een privacyveilig label van de werkelijke bestemming. Een handmatige uitvoering vanaf het tabblad Exporteren voegt mogelijk geen profielnaam toe, hoewel de instellingen van het actieve profiel worden gebruikt. Een profiel later hernoemen, de bestemming wijzigen of een ander profiel kiezen herschrijft bestaande geschiedenis niet.

Een nieuwe poging vanuit de exportgeschiedenis gebruikt de momenteel ingestelde configuratie en bestemming en maakt een nieuwe rij met wat werkelijk is gebruikt. De poging wordt niet ten onrechte aan het oorspronkelijke profiel toegeschreven. Herstel of hervatting van een onopgeloste geplande poging behoudt daarentegen de exacte datums, instellingen en bestemming van die poging.

Profielen en planningen zijn lokale apparaatinstellingen. Ze synchroniseren niet tussen iPhone, iPad, Mac en Android. Maak de gewenste configuratie opnieuw op elk apparaat en controleer de bestemming voordat je automatisering inschakelt.

## Gerelateerd

<div class="related">
  <a href="/nl/docs/export/"><span>Exporteren</span>Kies gegevensdetail, bekijk een voorbeeld en exporteer een datumbereik.</a>
  <a href="/nl/docs/scheduling/"><span>Planning</span>Begrijp profielritmes, herstel en timingbeperkingen per platform.</a>
  <a href="/nl/docs/shortcuts/"><span>Opdrachten</span>Selecteer een opgeslagen profiel in Apple-automatiseringen.</a>
  <a href="/nl/docs/android/"><span>Android-automatisering</span>Gebruik profielbewuste Tasker- en adb-acties.</a>
  <a href="/nl/docs/cli-direct/"><span>Directe CLI</span>Voer opgeslagen profielinstellingen uit naar een expliciete computermap.</a>
</div>
