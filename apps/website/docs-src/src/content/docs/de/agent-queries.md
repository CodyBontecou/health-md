---
title: "Typisierte Abfragen"
description: "Führen Sie neue oder zwischengespeicherte Health.md-Abfragen für Metriken, Schlaf, Training, Trainingseinheiten, Abdeckung, Zeitvergleiche und Nachweise mit ausdrücklicher Paginierung und fehlenden Daten aus."
---

Die übergeordneten CLI-Befehle wandeln häufige Fragen zu Gesundheitsdaten in feste, typisierte Abfragevorgänge um. Sie erfassen standardmäßig die angeforderten iPhone-Daten, fragen den verschlüsselten Mac-Kontext ab und geben versioniertes JSON mit Nachweisen und Abdeckung zurück.

Verwenden Sie stattdessen [kanonische Extraktion](/de/docs/cli-extract/), wenn Sie vollständige `healthmd.health_data`-Tage oder Quelldatensätze benötigen.

## Überprüfen Sie die Bereitschaft und ermitteln Sie Kennzahlen

```bash
healthmd doctor
healthmd metrics list
healthmd metrics list --category Sleep
```

Der Metrikkatalog gibt kanonische IDs, Anzeigenamen, Kategorien, Einheiten und Verfügbarkeitsanforderungen zurück. Es wird nicht behauptet, dass für eine Metrik eine HealthKit-Autorisierung erteilt wurde.

Kopieren Sie IDs aus dem Katalog, anstatt sie zu erraten.

## Metrikreihe abfragen

```bash
healthmd query \
  --metric sleep_total \
  --metric sleep_deep \
  --from 2026-07-01 --to 2026-07-14 \
  --all-pages
```

Kategorien erweitern sich durch den aktuellen Katalog:

```bash
healthmd query --category Sleep --yesterday
healthmd query --category Heart --last 30 --all-pages
```

Mehrere Metrik- und Kategorieflags werden kombiniert. Durch die Neuerfassung wird die erweiterte Auswahl auf das iPhone übertragen, ohne dass gespeicherte Exporteinstellungen geändert werden.

Die Antwort verwendet einen Envelope vom Typ `healthmd.cli_metric_query` v1. Die Erfassungsdiagnose wird neben der verschachtelten typisierten Abfrageantwort gespeichert.

## Frisch, zwischengespeichert und wiederverwendbar

Frisch ist die Standardeinstellung:

```bash
healthmd query --metric resting_heart_rate --last 30
```

Dadurch wird der genaue Umfang vom angeschlossenen iPhone abgefragt, aktualisierte verschlüsselte Inhabertage übermittelt und diese dann abgefragt.

Der Cache-Modus stellt keine Verbindung zum iPhone her:

```bash
healthmd query --metric resting_heart_rate --last 30 --cached
```

Verwenden Sie den Cache-Modus für die Offline-Analyse nur, wenn die gespeicherte Erfassungszeit und Abdeckung akzeptabel sind.

`--reuse-covered` prüft zunächst die verschlüsselte Zusammenfassungsabdeckung:

```bash
healthmd query --metric resting_heart_rate --last 30 --reuse-covered
```

Health.md überspringt die Erfassung nur, wenn jede angeforderte Metrik und jeder angeforderte Tag eine vollständige kompatible Zusammenfassungsabdeckung aufweist. Verlustfreie Anfragen und neu berechnete Schlafsitzungsvorgänge verwenden diese Verknüpfung nicht.

## Abschlussfelder verstehen

Neue Abfrageantworten unterscheiden drei Konzepte:

| Feld | Frage beantwortet |
|---|---|
| `requested_scope_status` | Wurden alle angeforderten Metriken, Quellen, Anbieter und Inhabertage bei dieser Erfassung abgeschlossen? |
| `corpus_status` | Haben andere Zweige im erfassten Korpus Warnungen, Auslassungen oder Fehler gemeldet? |
| `unrelated_skips` | Welche übersprungenen oder nicht unterstützten Zweige lagen außerhalb des angeforderten Bereichs? |

Ein vollständiger angeforderter Bereich kann mit nicht zum angeforderten Umfang gehörenden Auslassungen im Korpus koexistieren. Health.md behält beide Fakten bei, anstatt das angeforderte Ergebnis fälschlicherweise herabzustufen oder die Korpusdiagnose auszublenden.

Bei neuer Arbeit zählt der Abschluss nur Blobs, die nach Beginn dieser Aktualisierung ersetzt wurden. Veraltete zwischengespeicherte Werte können eine fehlgeschlagene Anforderung nicht erfüllen.

## Durch die Ergebnisse blättern

Ohne `--all-pages` gibt der Befehl eine begrenzte Seite zurück. Überprüfen Sie `next_cursor`:

```bash
healthmd query --category Activity --last 365 --output activity-page-1.json
jq '.query.next_cursor' activity-page-1.json
```

Ein Cursor ungleich Null bedeutet, dass mehr Ergebnisse vorhanden sind. Der äußere High-Level-Status bleibt `partial_success`, bis alle Seiten durchlaufen wurden.

Die automatische Paginierung folgt opaken Cursorn und prüft auf Wiederholungen:

```bash
healthmd query --category Activity --last 365 \
  --all-pages --output activity-all-pages.json
```

Die Antwort behält den ersten `healthmd.query_response` unter `query`, spätere versionierte Antworten unter `pages` und einen `healthmd.cli_query_receipt` v1, der die Anzahl der Seiten, Elemente, Fakten und Nachweise sowie den abschließenden Paginierungsstatus enthält.

Für die automatische Paginierung gilt eine Gesamtobergrenze für Seiten und Bytes. Wenn dies erreicht ist, schränken Sie die Datums- oder Metrikauswahl ein oder verwenden Sie die [Low-Level-API](/de/docs/agent-api/), um manuell zu blättern.

## Fortschritt und Tabellenausgabe

Schreiben Sie den von Gesundheitsdaten freien Phasen- und Seitenfortschritt als JSONL nach stderr:

```bash
healthmd query --category Sleep --last 90 \
  --all-pages --progress-json --output sleep.json \
  2> sleep-progress.jsonl
```

JSON ist die vollständige Ausgabe. Der Tabellenmodus ist eine verlustbehaftete Opt-in-TSV-Ansicht für eine Person an einem Terminal:

```bash
healthmd query --metric resting_heart_rate --last 30 --format table
```

In der Fußzeile der Tabelle werden Angaben zu Abdeckung, Quelle, Einschränkung, Vervollständigung und Hinweise zu nicht zum Umfang gehörenden Auslassungen gespeichert. Verwenden Sie keine Tabellenausgabe, wenn ein Skript exakte typisierte Werte oder Nachweise benötigt.

## Schlafsitzungen

Apple Health-Schlafstadien gehen über Mitternacht und können sich je nach Quelle überschneiden. Der Befehl „sleep“ erstellt stabile Sitzungen, anstatt jeden Inhabertag als eine numerische Summe zu behandeln.

```bash
healthmd sleep sessions --last-nights 14
healthmd sleep sessions --last-nights 14 --include-naps
healthmd sleep sessions --last-nights 14 \
  --window first:4h --physiology-metric heart_rate
```

Genaue Daten und eine Auswahl aller historischen Daten sind ebenfalls verfügbar:

```bash
healthmd sleep sessions \
  --from 2026-07-01 --to 2026-07-14 \
  --window first:3h --all-pages

healthmd sleep sessions --all --all-pages
```

Jede Sitzung kann Folgendes melden:

- stabile Sitzungsidentität;
- Inhaberdatum und lokale Zeitzone;
- genaue lokale und UTC-Start- und Endzeitstempel;
- Nacht- oder Nickerchenklassifizierung;
- Summen der ausgewählten Schlafphasen;
- beobachtete und nicht verfolgte Dauer;
- Vollständigkeit und Ausschlüsse;
- festes sitzungsbezogenes Fenster;
- Physiologie-Abdeckung benachbarter Tage;
- Quellnachweise.

Die Sitzungserfassung erfordert verlustfreie kanonische Schlafphasenintervalle und den vollständigen kanonischen Phasenmetriksatz. Health.md liest höchstens einen technisch erforderlichen angrenzenden Inhabertag für Grenzen und schließt dann nicht verwandte Daten aus dem Ergebnis aus.

Überlappende Schlafphasenquellen werden für die gesamte Schlafdauer dedupliziert. Der nur aggregierte zwischengespeicherte Kontext ist mit `aggregated` gekennzeichnet. Es wird kein Anspruch auf Intervallbeobachtungsabdeckung erhoben. Ein festes `first:4h`-Fenster verteilt niemals ein Tagesaggregat auf vier Stunden.

## Trainings- und Schlafausrichtung

```bash
healthmd training align --last 14
healthmd training align --last 14 --workout running
healthmd training align --last 14 --workout running \
  --sleep-window first:4h \
  --physiology-metric heart_rate \
  --all-pages
```

Für jedes ausgewählte Training ermittelt Health.md innerhalb von 36 Stunden die nächsten geeigneten vorhergehenden und folgenden Schlafsitzungen. Es berichtet:

- stabile Trainings- und Sitzungs-IDs;
- genaue Zeitlücken;
- angeforderte Schlaffenster;
- Anzahl der physiologischen Proben;
- Abdeckung von Schlafphasen und Sitzungen;
- Nachweise und Ausschlüsse.

Die Operation ist eine deterministische zeitliche Ausrichtung. Es wird nicht behauptet, dass ein Training zu einem Schlafergebnis oder dass Schlaf zu einer Trainingsleistung geführt hat. Es liest nicht mehr als zwei technisch erforderliche angrenzende Inhabertage und gibt keine unabhängigen Daten zurück.

## Trainingsliste

```bash
healthmd workouts --yesterday
healthmd workouts --last 14 --all-pages
healthmd workouts \
  --from 2026-07-01 --to 2026-07-31 \
  --format table
```

Die Trainingsauflistung bewahrt eine stabile Identität, genaue Zeitstempel, typisierte Details, Nachweise und fehlende Daten. Die Ergebnisse werden nach Startzeitstempel und stabiler Trainingsidentität sortiert. Es gibt keine feste Obergrenze für das Gesamttraining; die Seitensteuerung begrenzt jede Antwort.

## Abdeckung

Nutzen Sie die Abdeckung, wenn die Frage lautet: „Was habe ich?“ statt „Was ist der Wert?“

```bash
healthmd coverage --category Sleep --last 30
healthmd coverage \
  --metric steps --metric resting_heart_rate \
  --from 2026-01-01 --to 2026-06-30 \
  --all-pages
```

Die Abdeckung gibt angeforderte und verfügbare Bereiche, berücksichtigte Tage, Tage mit Werten und statusbehaftete fehlende Intervalle zurück. Benachbarte Intervalle mit demselben Status und Grund können komprimiert werden, ohne dass ihre Bedeutung verloren geht.

Ein Tag ohne übereinstimmende Beobachtungen kann `complete_empty` sein. Ein Tag, der nie synchronisiert wurde, hat einen anderen Status. Keines wird Null.

## Genaue Zeiträume vergleichen

Der CLI errät nie, ob eine Metrik summiert, gemittelt, minimiert, maximiert, gezählt oder nach dem neuesten Wert ausgewählt werden soll. Platzieren Sie die Aggregation neben jeder Metrik-ID:

```bash
healthmd compare \
  --metric steps:sum \
  --metric resting_heart_rate:average \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

Unterstützte Aggregationen sind:

- `sum`
- `average`
- `minimum`
- `maximum`
- `latest`
- `count`
- `duration_sum`

Nichtübereinstimmungen zwischen Einheiten oder Typen schlagen fehl, anstatt stillschweigend kombiniert zu werden. Ein fehlender Zeitraum hat keinen Gesamtwert. Eine Basislinie der ersten Periode von Null hat eine absolute Änderung, aber keine prozentuale Änderung und enthält `zero_baseline` als Einschränkung.

Die Richtung ist sachlich: `increased`, `decreased`, `unchanged` oder `not_comparable`. Es bedeutet nie besser oder schlechter.

## Trainingsnachweispakete

```bash
healthmd evidence training \
  --category Sleep \
  --metric resting_heart_rate \
  --last 14 \
  --all-pages
```

Fordern Sie spezifische Trainingsdetails nur bei Bedarf an:

```bash
healthmd evidence training \
  --category Sleep \
  --workout-detail distance \
  --workout-detail duration \
  --last 14 --all-pages
```

Durch Auswählen von Trainingsdetails wird der erforderliche verlustfreie Bereich für diese Anforderung angefordert. Das Paket enthält Sachwerte, Abdeckung, Quellenbeschreibungen, Nachweislokalisatoren und Einschränkungen.

Paket-IDs sind deterministische SHA-256-Zusammenfassungen semantischer Inhalte. Durch die erneute Generierung desselben Pakets zu einem anderen Zeitpunkt bleibt die semantische ID erhalten, auch wenn sich die Generierungsmetadaten ändern können.

Zu den Nachweispaketarten in Vertrag v1 gehören `daily_wellness`, `training` und `doctor_visit`. Der komfortable High-Level-Befehl macht derzeit das Trainingspaket verfügbar. Verwenden Sie die Low-Level-API für genaue Anfragetexte.

## Inhaberdatum und Zeitzone

Abfragedaten sind `owner_date`-Werte im kompakten Kontext. Jeder Tag behält außerdem das genaue halboffene UTC-Intervall und die erfasste Zeitzone des IANA-Kalenders bei, die zu seiner Bildung verwendet wurde.

Schlafsitzungen behalten lokale Zeitstempel und Über-Mitternachtsdaten bei. Es gibt technische angrenzende Lesevorgänge, sodass eine Sitzung die Grenze eines Inhabertags überschreiten kann, ohne Daten gemäß der aktuellen Zeitzone des Mac zu verschieben.

Wenn Sie einem Agenten eine datumsabhängige Frage stellen, geben Sie die gemeinten Inhaberdaten an und überprüfen Sie die zurückgegebene Zeitzone, anstatt die Zeitzone des Computers anzunehmen.

## Fehlende Daten in Agentenantworten nicht verschweigen

Eine sichere Zusammenfassung sollte Folgendes enthalten:

- metrische ID und kanonische Einheit;
- Datumsbereich und Zeitzone;
- frischer, zwischengespeicherter oder wiederverwendeter Modus;
- angeforderter Umfang und Korpusstatus;
- Abschluss des Seitendurchlaufs;
- Nachweisverweise oder Quellenübersicht;
- vollständig leere und fehlende Intervalle;
- Warnungen, Einschränkungen und nicht zum angeforderten Umfang gehörende Auslassungen.

Berechnen Sie nicht den Durchschnitt der fehlgeschlagenen Tage, behandeln Sie die Abwesenheit nicht als Null und beschreiben Sie die zeitliche Ausrichtung nicht als Ursache.

## Verwandt

<div class="related">
<a href="/de/docs/agents/"><span>Architektur</span>Lokale Agenten und Gesundheitskontext: Einrichtung, Verschlüsselung, Anfrageumfang, Nachweise und Aufbewahrung.</a>
<a href="/de/docs/mcp/"><span>MCP</span>Lokaler MCP-Helfer: typisierte Entsprechungen für Abfragen, Schlaf, Zuordnung, Trainingseinheiten, Abdeckung, Vergleiche und Nachweise.</a>
<a href="/de/docs/agent-api/"><span>Rohverträge</span>Loopback-Abfrage-API: exakte Anfragen, einseitige Antworten, Aktualisierung und Auftragsrouten.</a>
<a href="/de/docs/reference/evidence-packets/"><span>Referenz</span>Kompakte Abfragen und Nachweispakete: typisierte Werte, Cursor, Vorgänge, Abdeckung und IDs.</a>
</div>
