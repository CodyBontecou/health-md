---
title: "Eerste iPhone-export"
description: "Geef toegang tot Apple Health, kies een bestemming in Bestanden, bekijk de uitvoer van Health.md, voer een kleine eerste iPhone-export uit en controleer de geschreven bestanden."
---

Gebruik deze stappen om eerst een kleine, controleerbare export te maken voordat je meetwaarden, opmaak of automatisering aanpast. Health.md leest alleen de Apple Health-categorieën waarvoor iOS toestemming geeft en schrijft de gemaakte bestanden naar de map die je kiest.

<div class="availability available">
<strong>Nu beschikbaar · Health.md voor iPhone</strong>
<p>De eerste export valt binnen het gratis tegoed. Planning en andere betaalde functies kun je later instellen.</p>
</div>

## Voordat je begint

Je hebt het volgende nodig:

- Health.md op een iPhone met Apple Health-gegevens;
- leestoegang tot ten minste één Apple Health-categorie;
- een schrijfbare bestemming in Bestanden, zoals iCloud Drive, Op mijn iPhone of een Obsidian-kluis.

Gebruik voor de kortste eerste uitvoering de standaardmeetwaarden en Markdown-uitvoer. Begin met **Gisteren** of een ander bereik van één dag, niet met je volledige geschiedenis.

## 1. De iPhone-configuratie voltooien

Tik bij de eerste start op **Start Setup** en doorloop de zeven onboardingstappen. Geef toegang tot de gewenste gezondheidscategorieën, bekijk de voorbeelduitvoer, kies een map in Bestanden en ga door tot **Ready**. Wanneer de ontgrendelingsstap verschijnt, kun je verder met het gratis tegoed.

Heb je de onboarding al voltooid, open dan het tabblad **Exporteren** en controleer of Apple Health en de lokale map gereed zijn. Gebruik de mapknop om een ontbrekende of ontoegankelijke bestemming te vervangen.

<div class="docs-screenshot-grid">
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/onboarding-start.webp" target="_blank" rel="noopener" aria-label="Open de onboardingscreenshot op volledige grootte">
    <img src="/docs/assets/docs/iphone-first-export/onboarding-start.webp" width="1206" height="2622" loading="lazy" alt="Engelstalig welkomstscherm van de Health.md-onboarding bij stap 1 van 7, met de knop Start Setup." />
  </a>
  <figcaption>Deze gedeelde screenshot heeft bewust een Engelse gebruikersinterface. Start Setup introduceert het lokale archief, geplande notities en het mapmodel voordat Health.md om toegang vraagt.</figcaption>
</figure>
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/export-setup-required.webp" target="_blank" rel="noopener" aria-label="Open de screenshot met ontbrekende configuratie op volledige grootte">
    <img src="/docs/assets/docs/iphone-first-export/export-setup-required.webp" width="1206" height="2622" loading="lazy" alt="Engelstalig tabblad Export van Health.md met Health niet verbonden, Choose Folder beschikbaar, Local iPhone Folder geselecteerd en knoppen voor het datumbereik." />
  </a>
  <figcaption>De gereedheidsbadges maken duidelijk dat Health- en mapconfiguratie ontbreken. Deze gedeelde Engelstalige simulatorscreenshot toont beide vereisten bewust als onvoltooid.</figcaption>
</figure>
</div>

## 2. Een kleine export kiezen

Op het tabblad Exporteren:

1. Selecteer **Lokale iPhone-map** als bestemming.
2. Kies **Gisteren** of een aangepast bereik van één dag.
3. Behoud voor deze eerste uitvoering de standaardselectie van meetwaarden.
4. Laat **Markdown** geselecteerd. Voeg CSV, JSON of Obsidian Bases pas toe als het basisproces werkt.

Met een kort bereik zijn problemen met machtigingen, lege categorieën en bestemmingen eenvoudiger te begrijpen. Bovendien voorkom je dat je een langlopend eerste verzoek ten onrechte als mislukte export beschouwt.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/nl/iphone-first-export/metric-selection.webp" target="_blank" rel="noopener" aria-label="Open de screenshot met de selectie van meetwaarden op volledige grootte">
    <img src="/docs/assets/docs/nl/iphone-first-export/metric-selection.webp" width="1206" height="2622" loading="lazy" alt="Nederlandstalig scherm Gezondheidsmeetwaarden met 217 van 219 ingeschakelde meetwaarden, ingeschakelde standaardmeetwaarden, een zoekveld en uitvouwbare categorieën voor slaap, activiteit en hart." />
  </a>
  <figcaption>Het aantal meetwaarden hangt af van de geïnstalleerde appversie en machtigingen. Deze gelokaliseerde simulatorscreenshot toont 217 van 219 ingeschakelde meetwaarden. Voor de eerste export hoef je dat aantal niet te wijzigen.</figcaption>
</figure>

## 3. Een voorbeeld bekijken voordat je schrijft

Tik op **Voorbeeld**. Voor een voorbeeld is toegang tot Apple Health nodig, maar geen schrijfbare lokale map. Zo kun je een probleem met leesrechten onderscheiden van een probleem met Bestanden.

Controleer of het voorbeeld het volgende toont:

- de gevraagde datum;
- de verwachte namen en eenheden van meetwaarden;
- expliciet ontbrekende of niet-beschikbare waarden in plaats van verzonnen nullen;
- het geselecteerde formaat en de structuur van de bestandsnaam.

Ga terug naar het tabblad Exporteren als je datums, meetwaarden of opmaak wilt aanpassen.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/nl/iphone-first-export/export-preview.webp" target="_blank" rel="noopener" aria-label="Open de screenshot met het exportvoorbeeld op volledige grootte">
    <img src="/docs/assets/docs/nl/iphone-first-export/export-preview.webp" width="1206" height="2622" loading="lazy" alt="Nederlandstalig Health.md-exportvoorbeeld met een schatting voor een Markdown-export van één dag, samenvattingsperioden, bestemming en gegenereerde bestandsnaam." />
  </a>
  <figcaption>Met Voorbeeld controleer je de uitvoer zonder bestanden te schrijven. Deze vaste documentatiescreenshot gebruikt voorbeeldgegevens uit Health en laat expliciet zien dat er geen kluis is geselecteerd.</figcaption>
</figure>

## 4. Exporteren en controleren

Tik op **Gegevens exporteren**. Is de configuratie niet compleet, dan noemt Health.md de ontbrekende Health- of mapvereiste in plaats van ongemerkt een gedeeltelijke schrijfbewerking te starten.

Na voltooiing:

1. Bekijk in de app welke bestanden zijn geschreven, overgeslagen of mislukt.
2. Open de app Bestanden en ga naar de geselecteerde map.
3. Open één gemaakt bestand en controleer de datum, eenheden en frontmatter.
4. Bewaar de resultaatdetails als je een probleem onderzoekt. Neem niet aan dat de export is geslaagd alleen omdat de knop weer inactief is.

<div class="callout">
<strong>Geen gegevens voor de geselecteerde dag?</strong>
<p style="margin-top:6px;">Probeer een dag waarvan je weet dat die activiteits- of slaapgegevens bevat. Controleer daarna de Health-toegang en selectie van meetwaarden. Een leeg, toegestaan bereik is iets anders dan een transport- of schrijffout.</p>
</div>

## Volgende stappen

<div class="related">
  <a href="/nl/docs/metrics/"><span>Gegevens kiezen</span>Zoek Apple Health-meetwaarden en pas categorieën of bijzondere machtigingen aan.</a>
  <a href="/nl/docs/format/"><span>Uitvoer vormgeven</span>Configureer formaten, datums, eenheden, frontmatter, sjablonen en bestandsnamen.</a>
  <a href="/nl/docs/scheduling/"><span>Automatiseren</span>Plan herhaalde exports nadat je één handmatige uitvoering hebt gecontroleerd.</a>
  <a href="/nl/docs/folder-vault/"><span>Bestemming herstellen</span>Lees meer over bestandsproviders, maptoegang en herstel.</a>
</div>
