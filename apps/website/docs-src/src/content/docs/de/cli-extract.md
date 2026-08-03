---
title: "Kanonische Gesundheitsdaten extrahieren"
description: "Verwenden Sie healthmd extract, um ausgewählte Apple Health-Metriken zu erfassen und kanonische Schema-v7-Dokumente, Quelldatensätze, JSON-Pointer-Projektionen oder JSONL mit ausdrücklichen Belegen auszugeben."
---

`healthmd extract` ist der Quelldatenbefehl für Skripte und Agenten. Er lässt das iPhone nur die ausgewählten Metriken und Details erfassen, validiert die dauerhafte Übertragung, entfernt den Transport-Envelope und gibt kanonische `healthmd.health_data`-v7-Dokumente oder eindeutig gekennzeichnete Projektionen aus.

Verwenden Sie die Extraktion, wenn Sie Health.md-Daten in der Struktur der Quelle benötigen. Verwenden Sie [typisierte Abfragen](/de/docs/agent-queries/) für Sitzungen, Vergleiche, Trainingszuordnung, Abdeckung oder Nachweispakete.

## Grundstruktur

Eine Extraktion benötigt:

1. mindestens einen Metrik-, Kategorie-, Objekt- oder `--all-metrics`-Selektor;
2. einen Datumsselektor;
3. optional Detail-, Objekt-, Feld-, Format-, Ausgabe-, Zeitlimit- und Teilergebnisoptionen.

```bash
healthmd extract \
  (--metric ID | --category NAME | --object NAME | --all-metrics) ... \
  (--from DATE --to DATE | --last N | --yesterday | --all) \
  [--detail summary|lossless] \
  [--source apple_health] \
  [--field /JSON/POINTER] ... \
  [--format json|jsonl] \
  [--timeout 5...900] \
  [--allow-partial] \
  [--output PATH]
```

Die aktuelle kanonische Extraktionsquelle ist `apple_health`. Native Provider-Sidecars bleiben in ihren eigenen Verträgen und werden nicht in künstliche Apple Health-Werte übersetzt.

## Mit einer engen Anfrage beginnen

```bash
# One category, one day, summary detail
healthmd extract --category Sleep --yesterday --output sleep.json

# One metric for the last 30 complete days
healthmd extract --metric resting_heart_rate --last 30 \
  --output resting-heart-rate.json

# Every selected source object for one exact range
healthmd extract --all-metrics \
  --from 2026-07-01 --to 2026-07-07 \
  --detail lossless --output health-week.json
```

Metrik- und Kategorienamen werden vor Beginn der iPhone-Arbeit anhand des aktuellen Katalogs validiert. Wiederholen Sie Selektoren, um sie zu kombinieren.

```bash
healthmd extract \
  --metric sleep_total \
  --metric resting_heart_rate \
  --category Workouts \
  --last 14 --output recovery-context.json
```

## Auswahl erfolgt vor den HealthKit-Lesevorgängen

Die Extraktion ruft nicht zunächst einen gespeicherten Export aller Metriken ab, um ihn anschließend zu beschneiden. Die CLI löst den Selektor in eine unveränderliche `CanonicalHealthDataSelection` auf und sendet sie an das iPhone. Health.md prüft und liest nur die gewöhnlichen HealthKit-Typen, auf denen die ausgewählten Metriken beruhen.

Dieser Unterschied ist für Datenschutz, Leistung und Vollständigkeit wichtig:

- nicht ausgewählte Metriken werden nicht erfasst;
- gespeicherte iPhone-Metrikeinstellungen ändern sich nicht;
- Zusammenfassungsanfragen erzeugen kein verborgenes Quellarchiv;
- verlustfreie Anfragen lesen nur die für die Auswahl nötigen Quelltypen;
- die Auswahl wird Teil des dauerhaften Anfragefingerabdrucks.

Objekt- und JSON-Pointer-Selektoren schränken die ausgegebenen Daten nach der Erfassung ein. Selektoren für Metrik, Kategorie, Quelle und Detail schränken bereits die iPhone-Erfassung ein.

## Zusammenfassungs- und verlustfreie Details

Die Zusammenfassung ist Standard:

```bash
healthmd extract --category Activity --last 7 --detail summary
```

Die Ausgabe kann typisierte tägliche Zusammenfassungen, Abfragediagnosen und `raw_capture_status: not_requested` enthalten. Dieser Status ist korrekt: Der Befehl hat keine kanonischen Quelldatensätze erfasst.

Fordern Sie verlustfreie Details an, wenn Quellobjekte, UUIDs, exakte Zeitstempel, Herkunft oder Archivdiagnosen wichtig sind:

```bash
healthmd extract --metric workouts --last 14 \
  --detail lossless --output workouts-lossless.json
```

Archivbezogene Objekte wie `records` setzen verlustfreie Details voraus, auch wenn `--detail` fehlt.

## Objektselektoren

Mit `--object` behalten Sie einen bekannten Teil jedes ausgewählten Tages bei. Aktuelle Namen umfassen:

| Objekt | Typischer Inhalt |
|---|---|
| `sleep` | Felder der täglichen Schlafzusammenfassung |
| `activity` | Schritte, Energie, Distanz, Training und zugehörige Aktivitätszusammenfassungen |
| `heart` | Herzfrequenz, Ruheherzfrequenz, HRV und zugehörige Zusammenfassungen |
| `vitals` | Blutdruck, Glukose, Temperatur, Sauerstoff und weitere Vitalwertzusammenfassungen |
| `body` | Gewicht, Körperzusammensetzung, Größe und Körpermaße |
| `nutrition` | Nährstoff- und Flüssigkeitszusammenfassungen |
| `mindfulness` | Achtsamkeitssitzungen und Zusammenfassungen zum psychischen Wohlbefinden |
| `mobility` | Felder zu Gehen, Gang und Mobilität |
| `hearing` | Lärmbelastungs- und Hörfelder |
| `reproductive-health` | Reproduktions-, Schwangerschafts- und Zyklusfelder |
| `cycling` | Fahrradzusammenfassungen |
| `vitamins` / `minerals` | Nährstoffbezogene Zusammenfassungen |
| `symptoms` | Symptomdaten |
| `medications` | Medikamentendaten, sofern verfügbar und autorisiert |
| `workouts` | Kanonische Zusammenfassungsobjekte für Trainingseinheiten |
| `archive` | Kanonischer HealthKit-Archiv-Envelope |
| `records` | Kanonische Quelldatensätze; setzt verlustfreie Details voraus |
| `external-records` | Externe Datensätze, die bereits im öffentlichen Tag enthalten sind |
| `query-results` | Erfassungsergebnisse pro Abfrage |
| `warnings` | Integritätswarnungen |

Beispiele:

```bash
healthmd extract --metric workouts --last 30 \
  --object workouts --output workout-summaries.json

healthmd extract --metric workouts --last 30 \
  --object records --detail lossless --output workout-records.json

healthmd extract --category Sleep --last 7 \
  --object sleep --object query-results --output sleep-with-status.json
```

## JSON-Pointer-Projektion

Wiederholen Sie `--field` mit RFC-6901-JSON-Pointern, um exakte Werte oder Statuseinträge auszugeben:

```bash
healthmd extract --category Sleep --last 7 \
  --field /sleep/totalDuration \
  --field /sleep/deepSleep \
  --field /raw_capture_status \
  --output selected-sleep-fields.json
```

Pointer-Ergebnisse sind Projektionen, keine vollständigen Tagesdokumente. Sie verweisen auf Quellschema und Tag, tragen `schema: healthmd.health_data` aber nicht so, dass ein Teilbaum wie ein vollständiger Export wirken könnte.

Ein nicht vorhandener ausgewählter Pfad wird als als vollständig leer oder mit dem Status der unvollständigen Daten des Tages gemeldet. Health.md wandelt Abwesenheit nicht in null um.

## JSON-Ausgabe

Die standardmäßige JSON-Ausgabe enthält eine dieser Datensammlungen:

- `health_data` für vollständige kanonische Tagesdokumente oder
- `projections` für Objekt- oder Pointer-Ergebnisse.

Außerdem enthält sie `healthmd.extract_receipt`, das Folgendes festhält:

- aufgelöste Auswahl und Datumsbereich;
- Quelle und Detailebene;
- Ergebnisse pro Tag;
- Anzahl beibehaltener Elemente und Datensätze;
- fehlende Datumswerte;
- Teil- oder Fehlerdiagnosen;
- Abschlussstatus der Ausgabe.

Der Beleg enthält Protokollmetadaten. Er ersetzt das Quellschema nicht.

## JSONL-Ausgabe

Verwenden Sie JSONL für die Stream-Verarbeitung:

```bash
healthmd extract --category Sleep --last 30 \
  --format jsonl --output sleep.jsonl
```

Jede Zeile enthält ein Datenelement. Der Beleg wird nicht mit dem Gesundheitsdatenstream vermischt:

- mit `--output` wird er nach `OUTPUT.receipt.json` geschrieben;
- ohne `--output` wird er auf stderr geschrieben.

Dadurch bleiben Pipelines vorhersehbar:

```bash
healthmd extract --metric workouts --last 30 \
  --object workouts --format jsonl --output workouts.jsonl

jq -c 'select(.workouts != null)' workouts.jsonl
jq '{status, retained_item_count, missing_dates}' workouts.jsonl.receipt.json
```

Leiten Sie stderr nicht an den JSONL-Parser weiter, da stderr den Beleg und Fortschritt ohne Gesundheitsdaten enthält.

## Vollständige, leere und partielle Ergebnisse

Health.md hält folgende Status getrennt:

| Status | Bedeutung |
|---|---|
| `success` | Jeder angeforderte Zweig wurde abgeschlossen, einschließlich vollständig leerer Zweige |
| `complete_empty` | Der angeforderte Umfang wurde dargestellt und enthielt keine Beobachtungen |
| `partial_success` | Einige angeforderte Daten bleiben erhalten, aber mindestens ein angeforderter Zweig ist unvollständig |
| `failed` | Ein angeforderter Zweig ist fehlgeschlagen |
| `unsupported` | Plattform oder HealthKit unterstützt den angeforderten Zweig nicht |
| `skipped` | Health.md hat diesen Zweig absichtlich nicht abgefragt |
| `cancelled` | Das iPhone hat den Abbruch bestätigt |
| `missing` | Ein angeforderter Tag oder Zweig wurde nicht dargestellt |

Eine partielle Extraktion gibt standardmäßig keine beibehaltenen Daten aus. Fügen Sie `--allow-partial` nur hinzu, wenn Ihr Verbraucher unvollständigen Umfang akzeptieren und bewahren kann:

```bash
healthmd extract --category Sleep --last 30 \
  --allow-partial --output sleep-partial.json
```

Das Flag ändert Ausgabe- und Exit-Verhalten. Es entfernt keine Diagnosen und macht aus Teildaten keine vollständigen Daten.

## Backends der Mac-App und des Direktmodus

Der Befehl funktioniert über beide Backends:

```bash
# Bundled helper default: Mac app loopback and connected iPhone
healthmd extract --category Sleep --last 7 --output sleep.json

# Direct-capable helper: bypass the Mac app
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json
```

Beide Wege verwenden dasselbe öffentliche Tagesschema und strikte Validierung. Übertragung, Kopplung, Speicher und Auftragsdatensätze unterscheiden sich.

## Gesamter Verlauf

`--all` besitzt keine feste Datumsgrenze:

```bash
healthmd extract --metric steps --all --output all-steps.json
```

Das iPhone ermittelt den frühesten verfügbaren ausgewählten Datensatz, schreibt jeden Tag des Quellkalenders bis heute fest und überträgt begrenzte Partitionen. Die CLI setzt die Daten auf dem Datenträger zusammen und validiert sie dort, statt eine unbegrenzte Antwort im Arbeitsspeicher aufzubauen.

Verwenden Sie JSONL oder eine engere Auswahl für einen großen Korpus. Verfügbarer Speicherplatz und ein ungewöhnlich dichter Tag bleiben praktische Grenzen.

## Datenschutz-Checkliste

- Verwenden Sie für jedes Ergebnis mit Gesundheitsdaten vorzugsweise `--output`.
- Schützen Sie Ausgabe- und Belegdateien ebenso sorgfältig wie die Apple Health-Quelle.
- Verwenden Sie kein Shell-Tracing um Gesundheitsbefehle.
- Halten Sie Nutzdaten aus CI-Logs und Agentenprotokollen fern.
- Prüfen Sie bei der Fehlerbehebung nur Beleg-, Anzahl-, Status-, Schema- und Fehlstellenfelder.
- Löschen Sie temporäre Exporte, nachdem der vorgesehene Verbraucher sie sicher übernommen hat.

## Verwandte Themen

<div class="related">
  <a href="/de/docs/cli/"><span>CLI</span>Health.md CLI: Einrichtung, Backend-Auswahl, Befehlsübersicht und Ausgaberegeln.</a>
  <a href="/de/docs/agent-queries/"><span>Abgeleitete Ansichten</span>Typisierte Abfragen: Metrikreihen, Schlaf, Training, Trainingseinheiten, Vergleiche und Nachweise.</a>
  <a href="/de/docs/reference/daily-records/"><span>Schema</span>Tägliche Datensätze: vollständiger Vertrag für tägliche Schema-v7-Dokumente.</a>
  <a href="/de/docs/reference/canonical-healthkit-records/"><span>Quellarchiv</span>Kanonische Apple Health-Datensätze: Identität, Herkunft, Beziehungen und Nutzdaten.</a>
  <a href="/de/docs/reference/api-and-cli/"><span>Protokoll</span>API- und CLI-Referenz: Extraktionsanfragen, Belege, strikte Validierung und Exit-Verhalten.</a>
</div>
