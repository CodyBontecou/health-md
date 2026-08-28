---
title: Visualisierungen & Roadmap
description: Aktuelle Abdeckung der Health.md-Visualisierungen für Obsidian und geplante Diagramme, geordnet nach exportiertem Datentyp.
---

Health.md exportiert einen lokal gespeicherten, versionierten Datensatz für Markdown, Obsidian Bases, JSON und CSV. Die folgende Roadmap verbindet diese Daten mit dem begleitenden Obsidian-Plugin: Sie zeigt, was bereits vorhanden ist, welche weiteren Darstellungen die exportierten Daten ermöglichen und welche Kategorien generische, schemabewusste Diagramme benötigen.

<div class="callout">
<strong>Datenquelle.</strong>
<p style="margin-top:6px;">Diese Seite folgt dem Exportschema und Datenwörterbuch von Health.md: Aktivität, Schlaf, Herz, Vitalwerte, Körper, Ernährung, Achtsamkeit, Medikamente, Trainingseinheiten, reproduktive Gesundheit, Symptome, Hören sowie Lebensstil- und Umweltmetriken.</p>
</div>

## Einheiten pro Visualisierung überschreiben

Füge `units` in einen einzelnen `health-viz`-Block ein, wenn ein Diagramm ein anderes Anzeigesystem als die globale Plugin-Einstellung verwenden soll:

```health-viz
type: workout-trends
metric: distance
units: imperial
```

Verwende `auto`, um dem im Export angegebenen Einheitensystem zu folgen, `metric`, um Kilometer, Kilogramm, Meter und Celsius anzuzeigen, oder `imperial`, um Meilen, Pfund, Fuß und Fahrenheit anzuzeigen. Die Überschreibung gilt nur für diese Visualisierung und hat Vorrang vor der globalen Einstellung Units. Sie ändert nur die angezeigten Werte; exportierte Health.md-Dateien bleiben unverändert. Nicht konvertierbare Metriken wie Schritte, BPM, Prozentwerte und Kalorien bleiben unverändert.

## Aktuelle Visualisierungsabdeckung
<div class="reference-stats">
<div><strong>43</strong><span>aktuelle Plugin-Renderer</span></div>
<div><strong>18</strong><span>Exportdatenkategorien</span></div>
<div><strong>220+</strong><span>kanonische Exportschlüssel</span></div>
<div><strong>1</strong><span>noch benötigte generische Metrikebene</span></div>
</div>

## Plattformunterstützung nach Exporter

Die Unterstützung hängt davon ab, ob Quelldaten sowohl in Apple HealthKit als auch in Android Health Connect oder nur im Apple-HealthKit-Exportvertrag vorhanden sind.

### iOS und Android

| Kategorie | Visualisierungstypen |
| --- | --- |
| Übersicht | `intro-stats`, `summary-card`, `trend-tile` |
| Aktivität | `activity-rings`, `vitals-rings`, `bar-chart`, `activity-heatmap`, `step-spiral`, `weekday-average` |
| Herz | `heart-terrain`, `heart-range`, `hrv-trend` |
| Atmung und Vitalwerte | `oxygen-river`, `oxygen-range`, `breathing-wave` |
| Schlaf | `sleep-schedule`, `sleep-quality-bars`, `sleep-architecture`, `sleep-polar` |
| Mobilität | `walking-symmetry`* |
| Trainingseinheiten | `workout-log`, `workout-heart-rate`, `workout-zones`, `workout-trends`, `workout-intervals`, `workout-map` |

Hinweise:
- `walking-symmetry` ist unter Android eingeschränkt: Gehgeschwindigkeit ist vorhanden, Apple-spezifische Asymmetrie- und Doppelstützdetails nicht.
- `activity-rings` ist unter Android beim Stehen eingeschränkt: Fehlt `standHours`, verwendet das Plugin einen aus Schritten abgeleiteten Näherungswert.
- Diagramme für Trainingsrouten und Messwerte erfordern detaillierte Trainingsdaten sowie Berechtigung beziehungsweise Einwilligung für Routen.

### Nur iOS

HealthKit-Visualisierungen für Gemütszustand und Stimmung:
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

Visualisierungen für Medikamentenkatalog und Einnahmeereignisse:
- `medication-overview` / `medications` / `medication-adherence`
- `medication-inventory`
- `medication-adherence-summary`
- `medication-dose-status` / `per-medication-dose-status`
- `medication-adherence-trend` / `medication-daily-adherence-trend`
- `medication-recent-dose-events` / `medication-dose-events`

Android Health Connect stellt keine entsprechenden HealthKit-Datensätze für Gemütszustand oder Medikamentenkatalog und Einnahmeereignisse bereit.

### Nur Android

Derzeit keine im Visualisierungsregister des Obsidian-Plugins. Android exportiert native Daten wie PHR/FHIR-Ressourcen, geplante Trainingseinheiten und Aktivitätsintensität, doch noch kein Visualisierungstyp verwendet diese Felder.

<span id="visualization-screenshot-gallery"></span>

## Visualisierungskatalog

Jeder Eintrag verweist auf die passende öffentliche Variante in der [Health.md-Visualisierungsgalerie](/visualizations/). Die Links verwenden die Variante `theme-colors`, damit die Dokumentation schnell und stabil bleibt, statt jeden Renderer einzubetten.

### Zusammenfassung und Übersicht
- [Einführungsstatistik](/visualizations/overview-trends/intro-stats/theme-colors/) — `intro-stats`
- [Zusammenfassungskarte](/visualizations/overview-trends/summary-card/theme-colors/) — `summary-card`
- [Trendkachel](/visualizations/overview-trends/trend-tile/theme-colors/) — `trend-tile`

### Aktivität
- [Aktivitätsringe](/visualizations/activity-fitness/activity-rings/theme-colors/) — `activity-rings`
- [Balkendiagramm](/visualizations/activity-fitness/bar-chart/theme-colors/) — `bar-chart`
- [Aktivitäts-Heatmap](/visualizations/activity-fitness/activity-heatmap/theme-colors/) — `activity-heatmap`
- [Schrittspirale](/visualizations/activity-fitness/step-spiral/theme-colors/) — `step-spiral`
- [Wochentagsmittel](/visualizations/activity-fitness/weekday-average/theme-colors/) — `weekday-average`

### Herz
- [Herzterrain](/visualizations/heart-health/heart-terrain/theme-colors/) — `heart-terrain`
- [Herzfrequenzbereich](/visualizations/heart-health/heart-range/theme-colors/) — `heart-range`
- [HRV-Trend](/visualizations/heart-health/hrv-trend/theme-colors/) — `hrv-trend`

### Atmung, Sauerstoff und Vitalwerte
- [Sauerstofffluss](/visualizations/respiratory-oxygen/oxygen-river/theme-colors/) — `oxygen-river`
- [Sauerstoffbereich](/visualizations/respiratory-oxygen/oxygen-range/theme-colors/) — `oxygen-range`
- [Atemwelle](/visualizations/respiratory-oxygen/breathing-wave/theme-colors/) — `breathing-wave`
- [Vitalwertringe](/visualizations/activity-fitness/vitals-rings/theme-colors/) — `vitals-rings`

### Schlaf
- [Schlafplan](/visualizations/sleep-analysis/sleep-schedule/theme-colors/) — `sleep-schedule`
- [Schlafqualitätsbalken](/visualizations/sleep-analysis/sleep-quality-bars/theme-colors/) — `sleep-quality-bars`
- [Schlafarchitektur](/visualizations/sleep-analysis/sleep-architecture/theme-colors/) — `sleep-architecture`
- [Polares Schlafdiagramm](/visualizations/sleep-analysis/sleep-polar/theme-colors/) — `sleep-polar`

### Achtsamkeit und Stimmung
- [Stimmungstrend](/visualizations/mindfulness-mood/mood-trend/theme-colors/) — `mood-trend`
- [Stimmungs-Kalender-Heatmap](/visualizations/mindfulness-mood/mood-calendar-heatmap/theme-colors/) — `mood-calendar-heatmap`
- [Stimmung × Schlaf-Streudiagramm](/visualizations/mindfulness-mood/mood-sleep-scatter/theme-colors/) — `mood-sleep-scatter`
- [Stimmung im Tagesverlauf](/visualizations/mindfulness-mood/mood-day-timeline/theme-colors/) — `mood-day-timeline`
- [Stimmung nach Zusammenhang](/visualizations/mindfulness-mood/mood-association-breakdown/theme-colors/) — `mood-association-breakdown`
- [Stimmungs-Schlagwortwolke](/visualizations/mindfulness-mood/mood-label-cloud/theme-colors/) — `mood-label-cloud`
- [Stimmungsschwankungen](/visualizations/mindfulness-mood/mood-volatility/theme-colors/) — `mood-volatility`
- [Tägliche und momentane Stimmung](/visualizations/mindfulness-mood/mood-kind-split/theme-colors/) — `mood-kind-split`
- [Zirkadiane Stimmungsuhr](/visualizations/mindfulness-mood/mood-circadian-clock/theme-colors/) — `mood-circadian-clock`
- [Erholungs- und Einstellungskachel](/visualizations/mindfulness-mood/mood-recovery-tile/theme-colors/) — `mood-recovery-tile`
- [Matrix der Stimmungszusammenhänge](/visualizations/mindfulness-mood/mood-association-matrix/theme-colors/) — `mood-association-matrix`

### Medikamente
- [Medikamentenübersicht](/visualizations/medication-adherence/medication-overview/theme-colors/) — `medication-overview`
- [Medikamentenbestand](/visualizations/medication-adherence/medication-inventory/theme-colors/) — `medication-inventory`
- [Zusammenfassung der Einnahmetreue](/visualizations/medication-adherence/medication-adherence-summary/theme-colors/) — `medication-adherence-summary`
- [Einnahmestatus](/visualizations/medication-adherence/medication-dose-status/theme-colors/) — `medication-dose-status`
- [Trend der Einnahmetreue](/visualizations/medication-adherence/medication-adherence-trend/theme-colors/) — `medication-adherence-trend`
- [Jüngste Einnahmeereignisse](/visualizations/medication-adherence/medication-recent-dose-events/theme-colors/) — `medication-recent-dose-events`

### Mobilität, Gang und Laufform
- [Gehasymmetrie](/visualizations/mobility-gait/walking-symmetry/theme-colors/) — `walking-symmetry`

### Trainingseinheiten
- [Trainingsprotokoll](/visualizations/workout-analytics/workout-log/theme-colors/) — `workout-log`
- [Trainingsherzfrequenz](/visualizations/workout-analytics/workout-heart-rate/theme-colors/) — `workout-heart-rate`
- [Trainingszonen](/visualizations/workout-analytics/workout-zones/theme-colors/) — `workout-zones`
- [Trainingstrends](/visualizations/workout-analytics/workout-trends/theme-colors/) — `workout-trends`
- [Trainingsintervalle](/visualizations/workout-analytics/workout-intervals/theme-colors/) — `workout-intervals`
- [Trainingskarte](/visualizations/workout-analytics/workout-map/theme-colors/) — `workout-map`

## Roadmap der Grundlage

Die größte Produktlücke ist kein einzelnes fehlendes Diagramm, sondern eine generische, schemabewusste Metrikebene. Mit ihr ließe sich jedes exportierte Health.md-Feld darstellen, ohne für jede Metrik einen eigenen Parser und Renderer zu schreiben.

### Umgesetzt
- Erkennung der Schemakompatibilität für Tagesexporte, ältere Dateien, Roll-ups und Datenwörterbücher.
- Laden von JSON, CSV, Markdown und Obsidian Bases.
- Berücksichtigung von Roll-ups, damit Wochen-, Monats- und Jahreszusammenfassungen Tagesdiagramme nicht verfälschen.
- Navigation von Diagrammpunkten zur beitragenden Health.md-Quelldatei.

### Geplant
- **Generischer schemabewusster Metrikzugriff** – liest `_healthmd_data_dictionary.json` für Beschriftungen, Einheiten, Kategorien, Aggregationsregeln und Aliasse.
- **Generischer Metriktrend** – Linien- oder Flächendiagramm für jeden numerischen Exportschlüssel.
- **Generische Metrikbalken** – verallgemeinerte Tages-, Wochen- und Monatsbalken mit Ziel- und Grenzlinien.
- **Generische Kalender-Heatmap** – jede numerische Tagesmetrik als Kalenderraster.
- **Bericht zur Visualisierungsabdeckung** – zeigt im Vault vorhandene Felder und durch eigene Renderer abgedeckte Felder.

---

## Zusammenfassung und Übersicht
### Umgesetzt
- [`intro-stats`](/visualizations/overview-trends/intro-stats/theme-colors/) – Datensatzübersicht mit Summen, Mittelwerten, Schlaf und Vitalwerten.
- [`summary-card`](/visualizations/overview-trends/summary-card/theme-colors/) – KPI-Karte im Apple-Stil mit Sparkline und Vergleich zum vorherigen Zeitraum.
- [`trend-tile`](/visualizations/overview-trends/trend-tile/theme-colors/) – Trendkartenvergleich zwischen aktuellem und vorherigem Zeitraum.
### Geplant
- Automatisch generiertes Dashboard anhand der Felder im ausgewählten Health.md-Ordner.
- Dashboard zur Schemaabdeckung nach Datenkategorie.
- Korrelationskarten, etwa Schlaf und Stimmung, HRV und Training, Symptome und Medikamente oder Alkohol und Schlaf.

---

## Aktivität
Health.md exportiert Schritte, aktive und basale Energie, Trainings- und Stehzeit, gestiegene Stockwerke, Geh-/Laufdistanz, Radfahren, Schwimmen, Rollstuhlaktivität, Abfahrtsskidistanz, Bewegungszeit, körperliche Anstrengung und VO₂ max.
### Umgesetzt
- [`activity-rings`](/visualizations/activity-fitness/activity-rings/theme-colors/)
- [`vitals-rings`](/visualizations/activity-fitness/vitals-rings/theme-colors/)
- [`bar-chart`](/visualizations/activity-fitness/bar-chart/theme-colors/)
- [`activity-heatmap`](/visualizations/activity-fitness/activity-heatmap/theme-colors/)
- [`step-spiral`](/visualizations/activity-fitness/step-spiral/theme-colors/)
- [`weekday-average`](/visualizations/activity-fitness/weekday-average/theme-colors/)
### Geplant
- Aktivitätsbelastungs-Dashboard für Schritte, Kalorien, Training, Stehstunden und körperliche Anstrengung.
- VO₂-max-Trend.
- Konsistenzdiagramm für Bewegung, Training und Stehen.
- Distanzverteilung auf Gehen/Laufen, Radfahren, Schwimmen, Rollstuhl und Wintersport.
- Schwimmdistanz und Schwimmzüge.
- Rollstuhldistanz und Schübe.

---

## Schlaf
Health.md exportiert Gesamtschlaf, Schlafens- und Aufwachzeit, Dauer von Tief-, REM-, Kern- und Wachphasen sowie Bettzeit und detaillierte Schlafphasenintervalle.
### Umgesetzt
- [`sleep-schedule`](/visualizations/sleep-analysis/sleep-schedule/theme-colors/)
- [`sleep-quality-bars`](/visualizations/sleep-analysis/sleep-quality-bars/theme-colors/)
- [`sleep-architecture`](/visualizations/sleep-analysis/sleep-architecture/theme-colors/)
- [`sleep-polar`](/visualizations/sleep-analysis/sleep-polar/theme-colors/)
### Geplant
- Schlafdefizit und Konsistenzwert.
- Trend der Schlafphasenanteile.
- Heatmap der Regelmäßigkeit von Schlafens- und Aufwachzeit.
- Erholungs-Dashboard für Schlaf, HRV und Ruheherzfrequenz.

---

## Herz
Health.md exportiert Ruhe- und Gehherzfrequenz, mittlere/minimale/maximale Herzfrequenz, HRV, Herzfrequenz- und HRV-Messwerte, Herzfrequenzerholung und Vorhofflimmerbelastung.
### Umgesetzt
- [`heart-terrain`](/visualizations/heart-health/heart-terrain/theme-colors/)
- [`heart-range`](/visualizations/heart-health/heart-range/theme-colors/)
- [`hrv-trend`](/visualizations/heart-health/hrv-trend/theme-colors/)
### Geplant
- Trend der Ruheherzfrequenz.
- Trend der Gehherzfrequenz.
- Trend der Herzfrequenzerholung.
- Diagramm der Vorhofflimmerbelastung.
- Erholungskachel für HRV und Ruheherzfrequenz.
- Zirkadianes Herzfrequenzprofil nach Tageszeit.

---

## Atmung und Sauerstoff
Health.md exportiert mittlere/minimale/maximale Blutsauerstoffwerte und Messwerte sowie mittlere/minimale/maximale Atemfrequenz und Messwerte.
### Umgesetzt
- [`oxygen-river`](/visualizations/respiratory-oxygen/oxygen-river/theme-colors/)
- [`oxygen-range`](/visualizations/respiratory-oxygen/oxygen-range/theme-colors/)
- [`breathing-wave`](/visualizations/respiratory-oxygen/breathing-wave/theme-colors/)
### Geplant
- Eigenes Bereichsdiagramm für die Atemfrequenz.
- Diagramm für Sauerstoffentsättigungsereignisse.
- Nächtliches Atem-Dashboard aus Schlafphasen, Sauerstoff und Atemfrequenz.

---

## Vitalwerte
Health.md exportiert Körpertemperatur, Blutdruck, Blutzucker, Basal- und Handgelenktemperatur, elektrodermale Aktivität, forcierte Vitalkapazität, FEV1, exspiratorischen Spitzenfluss und Inhalatornutzung.
### Umgesetzt
- Teilweise Abdeckung durch Zusammenfassungskarten und generische Tagesdiagramme.
### Geplant
- Systolisch/diastolisches Blutdruckbereichsdiagramm mit Grenzbändern.
- Blutzuckerbereichsdiagramm.
- Trends für Körper-, Basal- und Handgelenktemperatur.
- Erholungs-/Krankheitskachel für Handgelenktemperatur.
- Atemfunktions-Dashboard für FVC, FEV1, Spitzenfluss und Inhalatornutzung.
- Trend für elektrodermale Aktivität und Stress.

---

## Körpermaße
Health.md exportiert Gewicht, Größe, BMI, Körperfettanteil, fettfreie Körpermasse und Taillenumfang.
### Umgesetzt
- Noch kein eigener Renderer für Körperzusammensetzung.
### Geplant
- Dashboard zur Körperzusammensetzung.
- Gewichtstrend mit gleitendem Mittelwert und Ziellinie.
- BMI-Trend mit Kategoriebändern.
- Körperfett im Vergleich zur fettfreien Masse.
- Trend des Taillenumfangs.

---

## Mobilität, Gang und Laufform
Health.md exportiert Gehgeschwindigkeit, Schrittlänge, Doppelstützphase, Gehasymmetrie, Treppenauf-/abstiegsgeschwindigkeit, Sechs-Minuten-Gehtest, Gehstabilität, Laufgeschwindigkeit, Schrittlänge beim Laufen, Bodenkontaktzeit, vertikale Oszillation und Laufleistung.
### Umgesetzt
- [`walking-symmetry`](/visualizations/mobility-gait/walking-symmetry/theme-colors/)
### Geplant
- Gang-Dashboard.
- Anzeige der Gehstabilität.
- Trend des Sechs-Minuten-Gehtests.
- Diagramm der Treppenauf- und -abstiegsgeschwindigkeit.
- Laufform-Dashboard für Geschwindigkeit, Schrittlänge, Bodenkontakt, vertikale Oszillation und Leistung.

---

## Trainingseinheiten
Health.md exportiert Anzahl, Minuten, Kalorien, Distanz und Typen von Trainingseinheiten, Herzfrequenzstatistiken, Lauf-/Radform, Leistung, Höhe, Runden, Abschnitte, Routenpunkte, Herzfrequenzzonen und Zeitreihenmesswerte.
### Umgesetzt
- [`workout-log`](/visualizations/workout-analytics/workout-log/theme-colors/)
- [`workout-heart-rate`](/visualizations/workout-analytics/workout-heart-rate/theme-colors/)
- [`workout-zones`](/visualizations/workout-analytics/workout-zones/theme-colors/)
- [`workout-trends`](/visualizations/workout-analytics/workout-trends/theme-colors/)
- [`workout-intervals`](/visualizations/workout-analytics/workout-intervals/theme-colors/)
- [`workout-map`](/visualizations/workout-analytics/workout-map/theme-colors/)
### Geplant
- Trainings-Kalender-Heatmap.
- Trainingsbelastungsdiagramm auf Grundlage von Dauer und Intensität.
- Wöchentliche Verteilung der Trainingseinheiten nach Typ.
- Tempo- und Geschwindigkeitstrend nach Trainingsart.
- Trend für Höhengewinn und -verlust.
- Kleine Mehrfachdiagramme zum Routenvergleich.
- Leistungskurve und Bestleistungen.
- Dashboards für Laufform und Radleistung.

---

## Achtsamkeit und Stimmung
Health.md exportiert Achtsamkeitsminuten und -sitzungen, Gemütszustandseinträge, mittlere Valenz, Tagesstimmung, momentane Emotionen, Schlagwörter und Zusammenhänge.
### Umgesetzt
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
### Geplant
- Trend der Achtsamkeitsminuten.
- Serie und Kalender für Achtsamkeitssitzungen.
- Stimmung im Verhältnis zur Medikamenteneinnahmetreue.
- Stimmung im Verhältnis zu Ernährung, Alkohol und Koffein.
- Zeitleiste der Stimmungsschlagwörter.

---

## Medikamente
Health.md exportiert Medikamentenbestand, aktive/archivierte Anzahlen, Einnahmeereignisse, eingenommene/ausgelassene Dosen, Details, RxNorm-/Codierungsmetadaten, Dosismengen, Zeitplantyp, geplante/Start-/Enddaten, Status und Metadaten.
### Umgesetzt
- [`medication-overview`](/visualizations/medication-adherence/medication-overview/theme-colors/)
- [`medication-inventory`](/visualizations/medication-adherence/medication-inventory/theme-colors/)
- [`medication-adherence-summary`](/visualizations/medication-adherence/medication-adherence-summary/theme-colors/)
- [`medication-dose-status`](/visualizations/medication-adherence/medication-dose-status/theme-colors/)
- [`medication-adherence-trend`](/visualizations/medication-adherence/medication-adherence-trend/theme-colors/)
- [`medication-recent-dose-events`](/visualizations/medication-adherence/medication-recent-dose-events/theme-colors/)
### Geplant
- Zeitachse für den Medikamentenplan.
- Kalender-Heatmap zur Medikamenteneinnahmetreue.
- Verspätungsdiagramm für geplante und tatsächliche Einnahmezeit.
- Trend der Dosismenge.
- Korrelationen zwischen Medikamenten und Symptomen/Stimmung.
- Detailbereich für RxNorm und Codierung.

---

## Ernährung
Health.md exportiert Kalorien, Eiweiß, Kohlenhydrate, Fett, gesättigte/einfach ungesättigte/mehrfach ungesättigte Fette, Ballaststoffe, Zucker, Natrium, Cholesterin, Wasser und Koffein.
### Umgesetzt
- Noch kein eigener Ernährungsrenderer.
### Geplant
- Ernährungs-Dashboard.
- Diagramm der Makronährstoffverteilung.
- Aufgenommene gegenüber aktiven Kalorien.
- Trend der Flüssigkeitszufuhr.
- Diagramm der täglichen Koffeinmenge und des Einnahmezeitpunkts.
- Grenzwertdiagramme für Zucker und Natrium.
- Zielfortschritt für Ballaststoffe und Eiweiß.

---

## Vitamine und Mineralstoffe
Health.md exportiert Vitamine A, B6, B12, C, D, E, K, Thiamin, Riboflavin, Niacin, Folat, Biotin, Pantothensäure, Kalzium, Eisen, Kalium, Magnesium, Phosphor, Zink, Selen, Kupfer, Mangan, Chrom, Molybdän, Chlorid und Jod.
### Umgesetzt
- Noch kein eigener Mikronährstoffrenderer.
### Geplant
- Mikronährstoff-Heatmap.
- Fortschrittsraster für den empfohlenen Tagesbedarf.
- Dashboard für Vitamintrends.
- Dashboard für Mineralstofftrends.
- Hinweise auf Unter- oder Überversorgung.
- Wert für die Vollständigkeit der Ernährung.

---

## Hören
Health.md exportiert Kopfhörerlautstärke und Umgebungsschallpegel.
### Umgesetzt
- Nur teilweise Abdeckung auf Zusammenfassungsebene.
### Geplant
- Trend der Lärmbelastung.
- Kalender lauter Tage.
- Grenzbänder für sichere Lärmbelastung.
- Wöchentliche Belastungsübersicht.

---

## Reproduktive Gesundheit und Zyklusverfolgung
Health.md exportiert Menstruationsfluss, sexuelle Aktivität, Ovulationstestergebnis, Zervixschleimqualität und Zwischenblutungen.
### Umgesetzt
- Noch kein eigener Renderer für reproduktive Gesundheit.
### Geplant
- Zykluskalender.
- Menstruationsfluss-Heatmap.
- Zeitleiste der Fruchtbarkeitssignale.
- Zyklus-Symptomüberlagerung aus reproduktiver Gesundheit, Symptomen, Stimmung und Schlaf.
- Zeitleiste für Schmier- und Zwischenblutungen.

---

## Symptome
Health.md exportiert tägliche Anzahlen für Kopfschmerzen, Müdigkeit, Übelkeit, Schwindel, Stimmungs-, Schlaf- und Appetitveränderungen, Hitzewallungen, Schüttelfrost, Fieber, Schmerzen, Verdauungs-, Atemwegs-, Herz-, Haut-, Gedächtnis- und weitere erfasste Symptome.
### Umgesetzt
- Noch kein eigener Symptomrenderer.
### Geplant
- Symptom-Kalender-Heatmap.
- Rangliste der Symptomhäufigkeit.
- Matrix gleichzeitig auftretender Symptome.
- Zeitleiste der Symptomschübe.
- Explorer für Symptomkorrelationen.
- Nach Körpersystem gruppiertes Symptom-Dashboard.

---

## Weitere Gesundheit, Lebensstil und Umwelt
Health.md exportiert UV-Belastung, Tageslichtzeit, Stürze, Blutalkohol, alkoholische Getränke, Insulinabgabe, Zähneputzen, Händewaschen, Wassertemperatur und Tauchtiefe.
### Umgesetzt
- Noch kein eigener Renderer für Lebensstil und Umwelt.
### Geplant
- Tageslicht- und UV-Kalender.
- Sturzzeitleiste.
- Alkohol im Verhältnis zu Schlaf und HRV.
- Trend der Insulinabgabe.
- Serien für Zähneputzen und Händewaschen.
- Diagramm für Wassertemperatur und Tauchtiefe.

---

## Prioritäten
1. Generische schemabewusste Metrikinfrastruktur.
2. Generische Trend-, Balken- und Kalender-Heatmap-Renderer.
3. Vitalwertpaket: Blutdruck, Blutzucker, Temperatur und Atemfunktion.
4. Dashboard zur Körperzusammensetzung.
5. Ernährungs-Dashboard.
6. Symptom-Heatmap, Rangliste und Korrelationsansichten.
7. Kalender für Zyklus und reproduktive Gesundheit.
8. Mikronährstoff-Heatmap und RDA-Raster.
9. Erweitertes Dashboard für Mobilität und Laufform.
10. Diagramme für Hören, Lebensstil und Umwelt.

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">Zuletzt aktualisiert: 2026-06-25</p>
