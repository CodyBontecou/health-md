---
title: "Eerste iPhone-export"
description: "Geef toegang tot Apple Health, kies een bestemming in Bestanden, bekijk de uitvoer van Health.md, voer een kleine eerste iPhone-export uit en controleer de geschreven bestanden."
---

Gebruik deze stappen om eerst een kleine, controleerbare export te maken voordat je meetwaarden, opmaak of automatisering aanpast. Health.md leest alleen de Apple Health-categorieën waarvoor iOS toestemming geeft en schrijft de gemaakte bestanden naar de map die je kiest.

<div class="availability available">
<strong>Nu beschikbaar · Health.md voor iPhone</strong>
<p>Voor exports heb je een actieve proefperiode, een abonnement of Lifetime-toegang nodig. Schema’s en andere automatiseringen kun je later instellen.</p>
</div>

## Voordat je begint

Zorg dat je het volgende hebt:

- [Health.md in de App Store](https://apps.apple.com/app/health-md/id6757763969), geïnstalleerd op een iPhone met Apple Health-gegevens
- toestemming om minstens één Apple Health-categorie te lezen
- een beschrijfbare map in Bestanden: iCloud Drive, Op mijn iPhone of een Obsidian-kluis.

Houd de standaardmeetwaarden en het Markdown-formaat aan. Kies **Gisteren** voor een periode van één dag.

## 1. Rond de iPhone-configuratie af

Health.md toont vijf instelstappen. Geen enkele blokkeert: Apple Health-toegang en de map kun je overslaan en later regelen.

Tik bij de eerste start op **Apple Health verbinden**. Geef toegang tot de gewenste gezondheidscategorieën, bekijk de voorbeelduitvoer, kies een map in Bestanden en ga door tot de laatste stap.

Na de configuratie opent de app op **Archief**. Als Apple Health of de map aandacht nodig heeft, vertelt de kaart **Vraagt aandacht** bovenaan wat je moet oplossen.

<div class="docs-screenshot-grid">
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/onboarding-start.webp" target="_blank" rel="noopener" aria-label="Open de schermafbeelding van de configuratie op volledige grootte">
    <img src="/docs/assets/docs/iphone-first-export/onboarding-start.webp" width="1206" height="2622" loading="lazy" alt="Configuratie van Health.md bij stap 1 van 5 met drie stappen en de knop om Apple Health te verbinden." />
  </a>
  <figcaption>De configuratie legt uit wat Health.md leest en waar bestanden terechtkomen voordat er om toegang wordt gevraagd. De interface in deze opname blijft Engels.</figcaption>
</figure>
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/export-now.webp" target="_blank" rel="noopener" aria-label="Open de schermafbeelding van Nu exporteren op volledige grootte">
    <img src="/docs/assets/docs/iphone-first-export/export-now.webp" width="1206" height="2622" loading="lazy" alt="Health.md-blad Nu exporteren met Gisteren geselecteerd, een schakelaar voor alleen de samenvatting van het bereik, een overzicht van één bestand voor één dag en een exportknop." />
  </a>
  <figcaption>Nu exporteren laat zien wat er wordt geschreven voordat je begint. Ook deze referentieopname toont de interface in het Engels.</figcaption>
</figure>
</div>

## 2. Kies een kleine export

Tik op de ronde knop **Nu exporteren** naast de tabbalk. Daarna:

1. Kies **Gisteren**.
2. Laat **Alleen samenvatting van het datumbereik** uit staan.
3. Controleer dat **Wordt geschreven** je map noemt en ongeveer één bestand voor één dag.

De standaardautomatisering gebruikt de standaardselectie van meetwaarden en **Markdown**. Om die te wijzigen open je **Automatiseringen**, kies je de automatisering en dan **Meetwaarden** of **Formaten**. Voeg CSV, JSON of Obsidian Bases toe als deze export gelukt is. Met een korte periode vind je problemen met toestemming, lege gegevens en de map makkelijker.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/nl/iphone-first-export/metric-selection.webp" target="_blank" rel="noopener" aria-label="Open de schermafbeelding van de meetwaardeselectie op volledige grootte">
    <img src="/docs/assets/docs/nl/iphone-first-export/metric-selection.webp" width="1206" height="2622" loading="lazy" alt="Health.md-pagina Meetwaarden met het aantal ingeschakelde meetwaarden, de knoppen Aanbevolen, Alles selecteren en Alles deselecteren, een zoekveld en categorieën met aantallen." />
  </a>
  <figcaption>Het aantal meetwaarden hangt af van de appversie en de toestemmingen. Deze gelokaliseerde opname toont 217 van de 219 ingeschakelde metrieken.</figcaption>
</figure>

## 3. Bekijk het voorbeeld voordat je schrijft

Tik in **Nu exporteren** op **Voorbeeld**. Het voorbeeld heeft Apple Health-toegang nodig, maar geen beschrijfbare map.

Gebruik het voorbeeld om een toestemmingsprobleem met Apple Health te vinden voordat je de map test.

Controleer dat het voorbeeld het volgende toont:

- de gevraagde datum
- de verwachte namen van meetwaarden en eenheden
- ontbrekende of niet-beschikbare waarden in plaats van onterechte nullen
- het gekozen formaat en de structuur van de bestandsnaam.

Sluit het voorbeeld en wijzig de instellingen van de automatisering als je meetwaarden of formaten moet aanpassen.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/nl/iphone-first-export/export-preview.webp" target="_blank" rel="noopener" aria-label="Open de schermafbeelding van het exportvoorbeeld op volledige grootte">
    <img src="/docs/assets/docs/nl/iphone-first-export/export-preview.webp" width="1206" height="2622" loading="lazy" alt="Exportvoorbeeld van Health.md met het slaapvenster, een schatting voor één dag Markdown, de samenvattingsperiode, de doelmap en de gegenereerde bestandsnaam." />
  </a>
  <figcaption>Dit voorbeeld gebruikt voorbeeldgegevens.</figcaption>
</figure>

## 4. Exporteer en controleer

Tik op **Gisteren exporteren**. Als de configuratie onvolledig is, vertelt Health.md wat er ontbreekt aan Apple Health of de map.

Als de export klaar is:

1. Bekijk in het resultaat welke bestanden zijn geschreven, overgeslagen of mislukt. De dag verschijnt in de kalender van **Archief**.
2. Open de app Bestanden en de gekozen map.
3. Open een gegenereerd bestand en controleer de datum, eenheden en frontmatter.
4. Bewaar de resultaatdetails als je een probleem moet onderzoeken.

Een gedekte dag in de kalender is een samenvatting; tik op de dag om de status van elke automatisering op die datum te zien.

<div class="callout">
<strong>Geen gegevens voor de gekozen dag?</strong>
<p style="margin-top:6px;">Kies een dag met activiteits- of slaapgegevens. Controleer daarna de Apple Health-toestemming en de selectie van meetwaarden. Een lege periode is geen schrijffout.</p>
</div>

## Volgende stappen

<div class="related">
  <a href="/nl/docs/metrics/"><span>Gegevens kiezen</span>Zoek Apple Health-meetwaarden en pas categorieën of bijzondere machtigingen aan.</a>
  <a href="/nl/docs/format/"><span>Uitvoer vormgeven</span>Configureer formaten, datums, eenheden, frontmatter, sjablonen en bestandsnamen.</a>
  <a href="/nl/docs/scheduling/"><span>Automatiseren</span>Plan herhaalde exports nadat je één handmatige uitvoering hebt gecontroleerd.</a>
  <a href="/nl/docs/folder-vault/"><span>Bestemming herstellen</span>Lees meer over bestandsproviders, maptoegang en herstel.</a>
</div>
