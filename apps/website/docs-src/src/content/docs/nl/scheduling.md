---
title: "Apple Health-exports plannen en gemiste uitvoeringen oplossen"
description: "Controleer geplande exports, het venster met voltooide dagen en herstel. iOS garandeert geen tijdstip; Opnieuw proberen in de geschiedenis gebruikt huidige instellingen."
---

Deze pagina beschrijft planning op de iPhone. Android heeft andere achtergrondmachtigingen en aankoopvoorwaarden; zie [Android-automatisering](/nl/docs/android/).

## Controleer de eerste geplande export

1. Activeer het bedoelde profiel. Controleer metingen, formaten, detailniveau, schrijfgedrag en bestemming. Exporteer één voltooide dag handmatig en controleer het bestand of endpointresultaat voordat u automatiseert.
2. Open Schema en Schema instellen of Schema beheren. Schakel het in, kies dagelijks, wekelijks of aangepast, stel de tijd in en begin met één voltooide terugkijkdag. Sta meldingen toe als u lokale herstelherinneringen wilt.
3. Controleer inschakeling, volgende uitvoering en laatste resultaat. Bekijk na een poging de geschiedenis en echte bestemming; een geplande datum of melding bewijst niet dat gegevens zijn geschreven.
4. Controleer datums, eenheden, dekking en ontbrekende gegevens. Een opgeslagen bestand bewijst op zichzelf geen volledige bronopname.

Op Apple deelt een geplande aanvraag die minstens één datum exporteert de vijf gratis exportacties met handmatige en andere getelde exports. Full Access verwijdert deze gedeelde limiet. Zie [Ontgrendelen en aankopen](/nl/docs/paywall/).

## Begrijp het venster met voltooide dagen

Dagelijkse, wekelijkse en aangepaste schema’s kunnen een terugkijkperiode hebben. Aangepast herhaalt elke N dagen, weken of maanden vanaf de startdatum. Elke nieuwe uitvoering exporteert het hele ingestelde venster opnieuw, ook eerder geëxporteerde datums. Drie dagen omvatten gisteren en de twee dagen ervoor; bij vertraging blijft de geplande uitvoerdag het anker.

Vandaag vernieuwen staat hier los van en vervangt dit venster niet. Controleer paden en schrijfgedrag bij overlap; herhaalde dagmomentopnamen zijn geen nieuwe metingen.

## Kies het juiste herstelpad

- **Openstaande geplande aanvraag:** ontgrendel de iPhone, open Health.md en bekijk de poging. De exacte onopgeloste datums, opgeslagen instellingen en bestemming blijven behouden. Voltooide dagen blijven voltooid; herstel vergroot het venster niet.
- **Opnieuw proberen vanuit geschiedenis:** start een nieuwe uitvoering voor dat bereik met de huidige instellingen en bestemming en maakt een nieuwe rij. Controleer eerst de actieve configuratie. Dit hervat niet de bevroren aanvraag.
- **Gewijzigde of onbereikbare bestemming:** herstel toegang of bekijk het openstaande profiel. Oude iPhone-API-herstelacties mogen niet stilzwijgend een ander endpoint of gewijzigde referenties gebruiken. Start niet steeds nieuwe pogingen terwijl de oorspronkelijke onopgelost is.

Zie [Exportprofielen](/nl/docs/export-profiles/) voor herstel-, identiteits- en bestemmingsregels.

## Wat iOS wel en niet garandeert

De tijd is een doel, geen gegarandeerde eindtijd. iOS bepaalt achtergrondruntime en toestelvergrendeling kan HealthKit-lezen verhinderen. Achtergrondverzoeken en stille meldingen omzeilen die bescherming niet.

Lokale herinneringen vereisen meldingsmachtiging en garanderen geen aflevering op de doeltijd. Ontgrendel het toestel en open een ontvangen melding om herstel te proberen. Komt er geen melding, open Health.md en bekijk openstaand werk en geschiedenis. Controleer het resultaat in plaats van succes af te leiden uit een melding of verstreken tijd.

## Programmatisch bedienen
<p>Je kunt het schema via Shortcuts in- of uitschakelen met de intentie <em>Geplande export in- of uitschakelen</em>. <a href="/nl/docs/shortcuts/">Bekijk Shortcuts</a> voor voorbeelden.</p>

## Profielschema’s en annulering

- Elk profiel bewaart een eigen schema, inclusief aangepaste regelmaat; wisselen van actief profiel richt een ander schema niet opnieuw.
- Er verschijnt een botsingswaarschuwing wanneer profielen dezelfde gegenereerde paden op dezelfde bestemming zouden kunnen schrijven. Controleer dit vóór concurrerende schema’s; Health.md wijzigt geen profiel stilzwijgend.
- Stoppen of Annuleren eindigt alleen de huidige poging. Voltooide datums blijven behouden, open datums zijn herhaalbaar en het schema blijft actief.
- Elke geschiedenisregel blijft gekoppeld aan het uitvoeringsprofiel en het privacyvriendelijke label van de werkelijke bestemming.

Beheer bevroren instellingen en bestemming in [Exportprofielen](/nl/docs/export-profiles/).

## Gerelateerde documentatie

<div class="related">
  <a href="/nl/docs/export-profiles/"><span>Profielen</span>Beheer onafhankelijke planningen en bestemmingen.</a>
  <a href="/nl/docs/export/"><span>Handmatig</span>Exporteren: voor eenmalige datumbereiken.</a>
  <a href="/nl/docs/shortcuts/"><span>Automatiseren</span>Shortcuts: schakel het schema vanuit automatiseringen.</a>
  <a href="/nl/docs/sync/"><span>Meerdere apparaten</span>Mac-synchronisatie: plan ook op de Mac.</a>
</div>
