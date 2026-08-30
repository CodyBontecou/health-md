---
title: Visualisaties en roadmap
description: Huidige dekking van Health.md-visualisaties in Obsidian en geplande grafieken, geordend op type geëxporteerde gegevens.
---

Health.md exporteert een lokale gegevensverzameling met een schemaversie naar Markdown, Obsidian Bases, JSON en CSV. De onderstaande roadmap verbindt die gegevens met de bijbehorende visualisatieplugin voor Obsidian. Je ziet welke visualisaties al bestaan, welke visualisaties de exportgegevens verder mogelijk maken en voor welke categorieën nog generieke, schemabewuste grafieken nodig zijn.

<div class="callout">
<strong>Gegevensbron.</strong>
<p style="margin-top:6px;">Deze pagina volgt het exportschema en gegevenswoordenboek van Health.md: activiteit, slaap, hart, vitale functies, lichaam, voeding, mindfulness, medicatie, work-outs, reproductieve gezondheid, symptomen, gehoor en meetwaarden voor leefstijl en omgeving.</p>
</div>

## Eenheden per visualisatie overschrijven

Voeg `units` toe aan een afzonderlijk `health-viz`-blok wanneer een grafiek een ander weergavesysteem moet gebruiken dan de algemene pluginvoorkeur:

```health-viz
type: workout-trends
metric: distance
units: imperial
```

Gebruik `auto` om het eenhedensysteem van de export te volgen, `metric` om kilometers, kilogrammen, meters en Celsius weer te geven, of `imperial` om mijlen, ponden, feet en Fahrenheit weer te geven. De overschrijving geldt alleen voor deze visualisatie en heeft voorrang op de algemene instelling Units. Alleen de weergegeven waarden veranderen; geëxporteerde Health.md-bestanden blijven ongewijzigd. Niet-converteerbare metrieken zoals stappen, BPM, percentages en calorieën blijven hetzelfde.

## Huidige visualisatiedekking

<div class="reference-stats">
<div><strong>43</strong><span>huidige pluginrenderers</span></div>
<div><strong>18</strong><span>gegevenscategorieën in exports</span></div>
<div><strong>220+</strong><span>canonieke exportsleutels</span></div>
<div><strong>1</strong><span>nog benodigde generieke meetwaardenlaag</span></div>
</div>

## Platformondersteuning per exporter

Ondersteuning voor een visualisatie hangt ervan af of de brongegevens zowel in Apple HealthKit als Android Health Connect bestaan, of alleen in het exportcontract van Apple HealthKit.

### iOS en Android

Deze visualisaties gebruiken gedeelde exportvelden van HealthKit en Health Connect:

| Categorie | Visualisatietypen |
| --- | --- |
| Overzicht | `intro-stats`, `summary-card`, `trend-tile` |
| Activiteit | `activity-rings`, `vitals-rings`, `bar-chart`, `activity-heatmap`, `step-spiral`, `weekday-average` |
| Hart | `heart-terrain`, `heart-range`, `hrv-trend` |
| Ademhaling en vitale functies | `oxygen-river`, `oxygen-range`, `breathing-wave` |
| Slaap | `sleep-schedule`, `sleep-quality-bars`, `sleep-architecture`, `sleep-polar` |
| Mobiliteit | `walking-symmetry`* |
| Work-outs | `workout-log`, `workout-heart-rate`, `workout-zones`, `workout-trends`, `workout-intervals`, `workout-map` |

Opmerkingen:

- `walking-symmetry` heeft op Android gedeeltelijke ondersteuning: Android bevat loopsnelheid, maar niet de uitsluitend op Apple beschikbare details over asymmetrie of dubbele ondersteuning.
- `activity-rings` heeft op Android gedeeltelijke ondersteuning voor Staan: als `standHours` ontbreekt, gebruikt de plugin een benadering op basis van stappen.
- Voor route- en meetgrafieken van work-outs zijn gedetailleerde work-outgegevens en toestemming voor routes nodig.

### Alleen iOS

Visualisaties voor HealthKit State of Mind en stemming:

- `mood-trend` / `state-of-mind`
- `mood-calendar-heatmap`
- `mood-sleep-scatter`
- `mood-day-timeline`
- `mood-association-breakdown`
- `mood-label-cloud`
- `mood-volatility`
- `mood-kind-split`
- `mood-circadian-clock`
- `mood-recovery-tile`
- `mood-association-matrix`

Visualisaties voor de medicatiecatalogus en dosisgebeurtenissen:

- `medication-overview` / `medications` / `medication-adherence`
- `medication-inventory`
- `medication-adherence-summary`
- `medication-dose-status` / `per-medication-dose-status`
- `medication-adherence-trend` / `medication-daily-adherence-trend`
- `medication-recent-dose-events` / `medication-dose-events`

Android Health Connect biedt geen equivalent voor HealthKit State of Mind-records of HealthKit-records voor een medicatiecatalogus en dosisgebeurtenissen.

### Alleen Android

Geen in het huidige visualisatieregister van de Obsidian-plugin. Android exporteert wel systeemeigen Android-gegevens, zoals PHR/FHIR-resources, geplande work-outs en activiteitsintensiteit, maar geen huidig visualisatietype gebruikt die velden.

<span id="visualization-screenshot-gallery"></span>

## Visualisatiecatalogus

Elk item verwijst naar de bijbehorende openbare variant in de [Health.md-visualisatiegalerij](/visualizations/). Deze links gebruiken de variant `theme-colors`, zodat de documentatie snel en stabiel blijft zonder elke renderer op deze pagina in te sluiten.

### Samenvatting en overzicht

- [Inleidende statistieken](/visualizations/overview-trends/intro-stats/theme-colors/) — `intro-stats`
- [Samenvattingskaart](/visualizations/overview-trends/summary-card/theme-colors/) — `summary-card`
- [Trendtegel](/visualizations/overview-trends/trend-tile/theme-colors/) — `trend-tile`

### Activiteit

- [Activiteitsringen](/visualizations/activity-fitness/activity-rings/theme-colors/) — `activity-rings`
- [Staafdiagram](/visualizations/activity-fitness/bar-chart/theme-colors/) — `bar-chart`
- [Activiteitsheatmap](/visualizations/activity-fitness/activity-heatmap/theme-colors/) — `activity-heatmap`
- [Stappenspiraal](/visualizations/activity-fitness/step-spiral/theme-colors/) — `step-spiral`
- [Weekdaggemiddelde](/visualizations/activity-fitness/weekday-average/theme-colors/) — `weekday-average`

### Hart

- [Hartslagterrein](/visualizations/heart-health/heart-terrain/theme-colors/) — `heart-terrain`
- [Hartslagbereik](/visualizations/heart-health/heart-range/theme-colors/) — `heart-range`
- [HRV-trend](/visualizations/heart-health/hrv-trend/theme-colors/) — `hrv-trend`

### Ademhaling, zuurstof en vitale functies

- [Zuurstofrivier](/visualizations/respiratory-oxygen/oxygen-river/theme-colors/) — `oxygen-river`
- [Zuurstofbereik](/visualizations/respiratory-oxygen/oxygen-range/theme-colors/) — `oxygen-range`
- [Ademhalingsgolf](/visualizations/respiratory-oxygen/breathing-wave/theme-colors/) — `breathing-wave`
- [Ringen voor vitale functies](/visualizations/activity-fitness/vitals-rings/theme-colors/) — `vitals-rings`

### Slaap

- [Slaapschema](/visualizations/sleep-analysis/sleep-schedule/theme-colors/) — `sleep-schedule`
- [Balken voor slaapkwaliteit](/visualizations/sleep-analysis/sleep-quality-bars/theme-colors/) — `sleep-quality-bars`
- [Slaaparchitectuur](/visualizations/sleep-analysis/sleep-architecture/theme-colors/) — `sleep-architecture`
- [Polaire slaapgrafiek](/visualizations/sleep-analysis/sleep-polar/theme-colors/) — `sleep-polar`

### Mindfulness en stemming

- [Stemmingstrend](/visualizations/mindfulness-mood/mood-trend/theme-colors/) — `mood-trend`
- [Kalenderheatmap voor stemming](/visualizations/mindfulness-mood/mood-calendar-heatmap/theme-colors/) — `mood-calendar-heatmap`
- [Spreidingsdiagram van stemming en slaap](/visualizations/mindfulness-mood/mood-sleep-scatter/theme-colors/) — `mood-sleep-scatter`
- [Tijdlijn van stemming per dag](/visualizations/mindfulness-mood/mood-day-timeline/theme-colors/) — `mood-day-timeline`
- [Stemming per associatie](/visualizations/mindfulness-mood/mood-association-breakdown/theme-colors/) — `mood-association-breakdown`
- [Woordwolk met stemmingslabels](/visualizations/mindfulness-mood/mood-label-cloud/theme-colors/) — `mood-label-cloud`
- [Stemmingsvolatiliteit](/visualizations/mindfulness-mood/mood-volatility/theme-colors/) — `mood-volatility`
- [Dagelijkse tegenover tijdelijke stemming](/visualizations/mindfulness-mood/mood-kind-split/theme-colors/) — `mood-kind-split`
- [Circadiaanse stemmingsklok](/visualizations/mindfulness-mood/mood-circadian-clock/theme-colors/) — `mood-circadian-clock`
- [Tegel voor herstel en mindset](/visualizations/mindfulness-mood/mood-recovery-tile/theme-colors/) — `mood-recovery-tile`
- [Associatiematrix voor stemming](/visualizations/mindfulness-mood/mood-association-matrix/theme-colors/) — `mood-association-matrix`

### Medicatie

- [Medicatieoverzicht](/visualizations/medication-adherence/medication-overview/theme-colors/) — `medication-overview`
- [Medicatie-inventaris](/visualizations/medication-adherence/medication-inventory/theme-colors/) — `medication-inventory`
- [Samenvatting van medicatietrouw](/visualizations/medication-adherence/medication-adherence-summary/theme-colors/) — `medication-adherence-summary`
- [Status van medicatiedoses](/visualizations/medication-adherence/medication-dose-status/theme-colors/) — `medication-dose-status`
- [Trend in medicatietrouw](/visualizations/medication-adherence/medication-adherence-trend/theme-colors/) — `medication-adherence-trend`
- [Recente gebeurtenissen met medicatiedoses](/visualizations/medication-adherence/medication-recent-dose-events/theme-colors/) — `medication-recent-dose-events`

### Mobiliteit, looppatroon en hardloopvorm

- [Loopsymmetrie](/visualizations/mobility-gait/walking-symmetry/theme-colors/) — `walking-symmetry`

### Work-outs

- [Work-outlogboek](/visualizations/workout-analytics/workout-log/theme-colors/) — `workout-log`
- [Hartslag tijdens work-outs](/visualizations/workout-analytics/workout-heart-rate/theme-colors/) — `workout-heart-rate`
- [Work-outzones](/visualizations/workout-analytics/workout-zones/theme-colors/) — `workout-zones`
- [Work-outtrends](/visualizations/workout-analytics/workout-trends/theme-colors/) — `workout-trends`
- [Work-outintervallen](/visualizations/workout-analytics/workout-intervals/theme-colors/) — `workout-intervals`
- [Work-outkaart](/visualizations/workout-analytics/workout-map/theme-colors/) — `workout-map`

## Roadmap voor de basis

Het grootste ontbrekende onderdeel is niet één grafiek, maar een generieke, schemabewuste meetwaardenlaag. Daarmee kan elk geëxporteerd Health.md-veld in een grafiek worden gezet zonder voor elke meetwaarde een afzonderlijke parser en renderer te schrijven.

### Gebouwd

- Detectie van schemacompatibiliteit voor dagelijkse exports, oudere bestanden, periodeoverzichten en gegevenswoordenboeken.
- Laden van JSON, CSV, Markdown en Obsidian Bases.
- Herkenning van periodeoverzichten, zodat week-, maand- en jaarsamenvattingen dagelijkse grafieken niet vervuilen.
- Navigatie vanuit een grafiekpunt terug naar het Health.md-bronbestand dat de gegevens leverde.

### Gepland

- **Generieke schemabewuste toegang tot meetwaarden** — lees `_healthmd_data_dictionary.json` voor labels, eenheden, categorieën, aggregatieregels en aliassen.
- **Generieke meetwaardetrend** — lijn- of vlakgrafiek voor elke geëxporteerde numerieke sleutel.
- **Generieke meetwaardebalken** — algemene balken per dag, week of maand, met doel- en drempellijnen.
- **Generieke kalenderheatmap** — elke dagelijkse numerieke meetwaarde als kalenderraster.
- **Rapport over visualisatiedekking** — toon welke velden in een kluis aanwezig zijn en voor welke velden een specifieke renderer bestaat.

---

## Samenvatting en overzicht

### Gebouwd

- [`intro-stats`](/visualizations/overview-trends/intro-stats/theme-colors/) — samenvatting van de gegevensverzameling met totalen, gemiddelden, slaap en vitale functies.
- [`summary-card`](/visualizations/overview-trends/summary-card/theme-colors/) — KPI-kaart in Apple-stijl met een miniatuurgrafiek en vergelijking met de vorige periode.
- [`trend-tile`](/visualizations/overview-trends/trend-tile/theme-colors/) — vergelijking van trendkaarten tussen het huidige en het vorige venster.

### Gepland

- Automatisch gegenereerd dashboard op basis van de velden in de geselecteerde Health.md-map.
- Dashboard met schemadekking per gegevenscategorie.
- Samenvattingskaarten voor correlaties, zoals slaap tegenover stemming, HRV tegenover work-outs, symptomen tegenover medicatie of alcohol tegenover slaap.

---

## Activiteit

Health.md exporteert stappen, actieve energie, basale energie, trainingstijd, sta-tijd, beklommen trappen, wandel- en hardloopafstand, fietsen, zwemmen, rolstoelactiviteit, afstand bij sneeuwsporten, bewegingstijd, lichamelijke inspanning en VO₂ max.

### Gebouwd

- [`activity-rings`](/visualizations/activity-fitness/activity-rings/theme-colors/)
- [`vitals-rings`](/visualizations/activity-fitness/vitals-rings/theme-colors/)
- [`bar-chart`](/visualizations/activity-fitness/bar-chart/theme-colors/)
- [`activity-heatmap`](/visualizations/activity-fitness/activity-heatmap/theme-colors/)
- [`step-spiral`](/visualizations/activity-fitness/step-spiral/theme-colors/)
- [`weekday-average`](/visualizations/activity-fitness/weekday-average/theme-colors/)

### Gepland

- Dashboard voor activiteitsbelasting met stappen, calorieën, training, sta-uren en lichamelijke inspanning.
- Trend in VO₂ max.
- Grafiek voor de regelmaat van bewegen, trainen en staan.
- Grafiek met de verdeling van afstanden over wandelen en hardlopen, fietsen, zwemmen, rolstoelgebruik en sneeuwsporten.
- Grafiek met zwemafstand en zwemslagen.
- Grafiek met rolstoelafstand en duwen.

---

## Slaap

Health.md exporteert totale slaap, bedtijd, wektijd, de duur van diepe slaap, REM-slaap, kernslaap, wakker zijn en tijd in bed, plus gedetailleerde intervallen van slaapfasen.

### Gebouwd

- [`sleep-schedule`](/visualizations/sleep-analysis/sleep-schedule/theme-colors/)
- [`sleep-quality-bars`](/visualizations/sleep-analysis/sleep-quality-bars/theme-colors/)
- [`sleep-architecture`](/visualizations/sleep-analysis/sleep-architecture/theme-colors/)
- [`sleep-polar`](/visualizations/sleep-analysis/sleep-polar/theme-colors/)

### Gepland

- Slaapschuld en consistentiescore.
- Trend in de verhouding tussen slaapfasen.
- Heatmap voor regelmaat van bed- en wektijden.
- Hersteldashboard met slaap, HRV en hartslag in rust.

---

## Hart

Health.md exporteert hartslag in rust, hartslag tijdens wandelen, gemiddelde, minimale en maximale hartslag, HRV, hartslagmetingen, HRV-metingen, hartslagherstel en AFib-belasting.

### Gebouwd

- [`heart-terrain`](/visualizations/heart-health/heart-terrain/theme-colors/)
- [`heart-range`](/visualizations/heart-health/heart-range/theme-colors/)
- [`hrv-trend`](/visualizations/heart-health/hrv-trend/theme-colors/)

### Gepland

- Trend in hartslag in rust.
- Trend in hartslag tijdens wandelen.
- Trend in hartslagherstel.
- Grafiek van AFib-belasting.
- Hersteltegel met HRV en hartslag in rust.
- Circadiaans hartslagprofiel per tijdstip van de dag.

---

## Ademhaling en zuurstof

Health.md exporteert gemiddelde, minimale en maximale bloedzuurstof, bloedzuurstofmetingen, gemiddelde, minimale en maximale ademhalingsfrequentie en metingen van de ademhalingsfrequentie.

### Gebouwd

- [`oxygen-river`](/visualizations/respiratory-oxygen/oxygen-river/theme-colors/)
- [`oxygen-range`](/visualizations/respiratory-oxygen/oxygen-range/theme-colors/)
- [`breathing-wave`](/visualizations/respiratory-oxygen/breathing-wave/theme-colors/)

### Gepland

- Afzonderlijke bereikgrafiek voor ademhaling.
- Grafiek met gebeurtenissen van zuurstofdesaturatie.
- Nachtdashboard met slaapfasen, zuurstof en ademhalingsfrequentie.

---

## Vitale functies

Health.md exporteert lichaamstemperatuur, bloeddruk, bloedglucose, basale lichaamstemperatuur, polstemperatuur, elektrodermale activiteit, geforceerde vitale capaciteit, FEV1, piekuitademingsstroom en gebruik van een inhalator.

### Gebouwd

- Gedeeltelijke dekking via samenvattingskaarten en generieke dagelijkse grafieken.

### Gepland

- Bereikgrafiek voor systolische en diastolische bloeddruk met drempelbanden.
- Bereikgrafiek voor bloedglucose.
- Trend in lichaams-, basale en polstemperatuur.
- Tegel voor herstel of ziekte op basis van polstemperatuur.
- Dashboard voor ademhalingsfunctie met FVC, FEV1, piekstroom en inhalatorgebruik.
- Trend in elektrodermale activiteit en stress.

---

## Lichaamsmetingen

Health.md exporteert gewicht, lengte, BMI, lichaamsvetpercentage, vetvrije massa en tailleomtrek.

### Gebouwd

- Nog geen specifieke renderer voor lichaamssamenstelling.

### Gepland

- Dashboard voor lichaamssamenstelling.
- Gewichtstrend met voortschrijdend gemiddelde en doellijn.
- BMI-trend met categoriebanden.
- Grafiek van lichaamsvet tegenover vetvrije massa.
- Trend in tailleomtrek.

---

## Mobiliteit, looppatroon en hardloopvorm

Health.md exporteert wandelsnelheid, staplengte, dubbele ondersteuning, asymmetrie bij het lopen, snelheid bij traplopen en afdalen, de zesminutenwandeltest, loopstabiliteit, hardloopsnelheid, paslengte, grondcontacttijd, verticale oscillatie en hardloopvermogen.

### Gebouwd

- [`walking-symmetry`](/visualizations/mobility-gait/walking-symmetry/theme-colors/)

### Gepland

- Dashboard voor looppatroon.
- Meter voor loopstabiliteit.
- Trend in de zesminutenwandeltest.
- Grafiek van snelheid bij traplopen en afdalen.
- Dashboard voor hardloopvorm met snelheid, paslengte, grondcontact, verticale oscillatie en vermogen.

---

## Work-outs

Health.md exporteert aantallen work-outs, minuten, calorieën, afstand, typen work-outs, hartslagstatistieken, meetwaarden voor hardloop- en fietsvorm, vermogen, hoogte, ronden, tussentijden, routepunten, hartslagzones en tijdreeksmetingen van work-outs.

### Gebouwd

- [`workout-log`](/visualizations/workout-analytics/workout-log/theme-colors/)
- [`workout-heart-rate`](/visualizations/workout-analytics/workout-heart-rate/theme-colors/)
- [`workout-zones`](/visualizations/workout-analytics/workout-zones/theme-colors/)
- [`workout-trends`](/visualizations/workout-analytics/workout-trends/theme-colors/)
- [`workout-intervals`](/visualizations/workout-analytics/workout-intervals/theme-colors/)
- [`workout-map`](/visualizations/workout-analytics/workout-map/theme-colors/)

### Gepland

- Kalenderheatmap voor work-outs.
- Grafiek van trainingsbelasting op basis van duur en intensiteit.
- Wekelijkse verdeling van work-outs per type.
- Trend in tempo en snelheid per type work-out.
- Trend in hoogtewinst en -verlies.
- Compacte deelgrafieken voor routevergelijking.
- Vermogenscurve en beste prestaties.
- Dashboards voor hardloopvorm en fietsprestaties.

---

## Mindfulness en stemming

Health.md exporteert mindfulnessminuten, mindfulnesssessies, State of Mind-items, gemiddelde valentie, dagelijkse stemming, tijdelijke emoties, labels en associaties.

### Gebouwd

- [`mood-trend`](/visualizations/mindfulness-mood/mood-trend/theme-colors/)
- [`mood-calendar-heatmap`](/visualizations/mindfulness-mood/mood-calendar-heatmap/theme-colors/)
- [`mood-sleep-scatter`](/visualizations/mindfulness-mood/mood-sleep-scatter/theme-colors/)
- [`mood-day-timeline`](/visualizations/mindfulness-mood/mood-day-timeline/theme-colors/)
- [`mood-association-breakdown`](/visualizations/mindfulness-mood/mood-association-breakdown/theme-colors/)
- [`mood-label-cloud`](/visualizations/mindfulness-mood/mood-label-cloud/theme-colors/)
- [`mood-volatility`](/visualizations/mindfulness-mood/mood-volatility/theme-colors/)
- [`mood-kind-split`](/visualizations/mindfulness-mood/mood-kind-split/theme-colors/)
- [`mood-circadian-clock`](/visualizations/mindfulness-mood/mood-circadian-clock/theme-colors/)
- [`mood-recovery-tile`](/visualizations/mindfulness-mood/mood-recovery-tile/theme-colors/)
- [`mood-association-matrix`](/visualizations/mindfulness-mood/mood-association-matrix/theme-colors/)

### Gepland

- Trend in mindfulnessminuten.
- Reeks of kalender van mindfulnesssessies.
- Stemming tegenover medicatietrouw.
- Stemming tegenover voeding, alcohol en cafeïne.
- Tijdlijn van stemmingslabels.

---

## Medicatie

Health.md exporteert de medicatie-inventaris, aantallen actieve en gearchiveerde medicijnen, aantallen dosisgebeurtenissen, aantallen ingenomen en overgeslagen doses, medicatiegegevens, metadata voor RxNorm en codering, dosishoeveelheden, het schematype, geplande datums, begin- en einddatums, statussen en metadata.

### Gebouwd

- [`medication-overview`](/visualizations/medication-adherence/medication-overview/theme-colors/)
- [`medication-inventory`](/visualizations/medication-adherence/medication-inventory/theme-colors/)
- [`medication-adherence-summary`](/visualizations/medication-adherence/medication-adherence-summary/theme-colors/)
- [`medication-dose-status`](/visualizations/medication-adherence/medication-dose-status/theme-colors/)
- [`medication-adherence-trend`](/visualizations/medication-adherence/medication-adherence-trend/theme-colors/)
- [`medication-recent-dose-events`](/visualizations/medication-adherence/medication-recent-dose-events/theme-colors/)

### Gepland

- Tijdlijn voor medicatieschema's.
- Kalenderheatmap voor medicatietrouw.
- Grafiek van vertraging bij medicatie, met een vergelijking tussen het geplande en werkelijke innametijdstip.
- Trend in dosishoeveelheid.
- Correlatieweergaven voor medicatie tegenover symptomen of stemming.
- Detailpaneel voor RxNorm en codering.

---

## Voeding

Health.md exporteert voedingscalorieën, eiwitten, koolhydraten, vet, verzadigd vet, enkelvoudig onverzadigd vet, meervoudig onverzadigd vet, vezels, suiker, natrium, cholesterol, water en cafeïne.

### Gebouwd

- Nog geen specifieke renderer voor voeding.

### Gepland

- Voedingsdashboard.
- Grafiek met de verdeling van macronutriënten.
- Grafiek van ingenomen calorieën tegenover actieve calorieën.
- Hydratatietrend.
- Grafiek met dagelijkse hoeveelheid en timing van cafeïne.
- Drempelgrafieken voor suiker en natrium.
- Voortgang naar doelen voor vezels en eiwitten.

---

## Vitaminen en mineralen

Health.md exporteert vitamine A, B6, B12, C, D, E en K, thiamine, riboflavine, niacine, folaat, biotine, pantotheenzuur, calcium, ijzer, kalium, magnesium, fosfor, zink, selenium, koper, mangaan, chroom, molybdeen, chloride en jodium.

### Gebouwd

- Nog geen specifieke renderer voor micronutriënten.

### Gepland

- Heatmap voor micronutriënten.
- Voortgangsraster voor aanbevolen dagelijkse hoeveelheden.
- Dashboard voor vitaminetrends.
- Dashboard voor mineralentrends.
- Paneel met signalen voor tekorten en overschotten.
- Score voor volledigheid van voeding.

---

## Gehoor

Health.md exporteert het geluidsniveau van koptelefoons en het omgevingsgeluidsniveau.

### Gebouwd

- Alleen gedeeltelijke dekking op samenvattingsniveau.

### Gepland

- Trend in geluidsblootstelling.
- Kalender met dagen met veel geluid.
- Drempelbanden voor veilige blootstelling.
- Wekelijkse samenvatting van blootstelling.

---

## Reproductieve gezondheid en cyclusregistratie

Health.md exporteert menstruatiebloeding, seksuele activiteit, resultaten van ovulatietests, kwaliteit van baarmoederhalsslijm en tussentijdse bloedingen.

### Gebouwd

- Nog geen specifieke renderer voor reproductieve gezondheid.

### Gepland

- Cycluskalender.
- Heatmap voor menstruatiebloeding.
- Tijdlijn van vruchtbaarheidssignalen.
- Overlay van cyclussymptomen met reproductieve gezondheid, symptomen, stemming en slaap.
- Tijdlijn van spotting en tussentijdse bloedingen.

---

## Symptomen

Health.md exporteert dagelijkse symptoomaantallen voor hoofdpijn, vermoeidheid, misselijkheid, duizeligheid, stemmingsveranderingen, slaapveranderingen, eetlustveranderingen, opvliegers, koude rillingen, koorts, lage rugpijn, een opgeblazen gevoel, verstopping, diarree, brandend maagzuur, hoesten, keelpijn, een loopneus, kortademigheid, pijn op de borst, een overgeslagen hartslag, een snelle hartslag, acne, een droge huid, haaruitval, geheugenproblemen, nachtelijk zweten, overgeven, buikkrampen, pijn in de borsten, bekkenpijn, pijn in het lichaam, flauwvallen, verlies van reuk, verlies van smaak, een piepende ademhaling, verstopte bijholten, blaasincontinentie en vaginale droogheid.

### Gebouwd

- Nog geen specifieke renderer voor symptomen.

### Gepland

- Kalenderheatmap voor symptomen.
- Ranglijst van symptoomfrequentie.
- Matrix van gelijktijdig optredende symptomen.
- Tijdlijn van opvlammingen.
- Verkenner voor symptoomcorrelaties.
- Symptoomdashboard gegroepeerd per lichaamssysteem.

---

## Overige gezondheid, leefstijl en omgeving

Health.md exporteert uv-blootstelling, tijd in daglicht, valincidenten, alcoholgehalte in het bloed, alcoholische dranken, insulinetoediening, tandenpoetsen, handen wassen, watertemperatuur en diepte onder water.

### Gebouwd

- Nog geen specifieke renderer voor leefstijl en omgeving.

### Gepland

- Kalender voor daglicht en uv-blootstelling.
- Tijdlijn van valincidenten.
- Grafiek van alcohol tegenover slaap of HRV.
- Trend in insulinetoediening.
- Reeksen voor tandenpoetsen en handen wassen.
- Grafiek van watertemperatuur en diepte onder water.

---

## Prioriteitsvolgorde

1. Generieke, schemabewuste infrastructuur voor meetwaarden.
2. Generieke renderers voor trends, balken en kalenderheatmaps.
3. Reeks voor vitale functies: bloeddruk, glucose, temperatuur en ademhalingsfunctie.
4. Dashboard voor lichaamssamenstelling.
5. Voedingsdashboard.
6. Symptoomheatmap, ranglijst en correlatieweergaven.
7. Kalender voor cyclus en reproductieve gezondheid.
8. Heatmap voor micronutriënten en raster voor aanbevolen dagelijkse hoeveelheden.
9. Uitgebreid dashboard voor mobiliteit en hardloopvorm.
10. Grafieken voor gehoor, leefstijl en omgeving.

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">Laatst bijgewerkt op 25 juni 2026</p>
