---
title: "Persistente CLI-Aufträge und Automatisierung"
description: "Automatisieren Sie healthmd sicher mit maschinenlesbarer Ausgabe, begrenzten Wartezeiten, sieben Tage lang persistenten Aufträgen, ausdrücklichen Teilstatuswerten, Fortsetzung und bestätigtem Abbruch."
---

Health.md behandelt verbundene Export- und Kontexterfassungsvorgänge als persistente Aufträge. Die Lebensdauer eines Auftrags ist unabhängig von dem Prozess, der ihn gestartet hat. Ein Terminal kann geschlossen werden oder eine Netzwerkverbindung ausfallen, ohne dass abgeschlossene Partitionen verloren gehen.

Diese Seite gilt für Dateiexporte, strikte Rohdatenexporte, kanonische Extraktionen und die neue Erfassung verschlüsselten Kontexts, sofern ein Befehl keine engere Regel dokumentiert.

## Zentrale Regel

Ein Zeitlimit oder Verbindungsabbruch bedeutet keinen Abbruch des Auftrags.

Starten Sie nach einem unbekannten Ergebnis kein Duplikat. Speichern Sie die zurückgegebene Auftrags-ID, prüfen Sie den Status und setzen Sie denselben Auftrag fort.

Export-, Rohdaten- und Extraktionsaufträge verwenden die übergeordneten Lebenszyklusbefehle:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

Aufträge zur Erfassung verschlüsselten Kontexts verwenden den lokalen Agenten-Lebenszyklus:

```bash
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
```

## Lebensdauer von sieben Tagen

Ein persistenter Auftrag besitzt ein festes `expires_at`, das sieben Tage nach seiner Erstellung liegt. Fortschritt verlängert diese Frist nicht. Beide Gegenstellen speichern die unveränderliche Anfrage sowie genügend bestätigten Übertragungsstatus, um sie sicher fortzusetzen.

Ein Auftrag kann Folgendes speichern:

- exakte Datumswerte oder aufgelöste Kennungen für den gesamten Verlauf;
- Umfang von Metriken, Kategorien, Quellen und Details;
- Bindung an Backend und gekoppeltes Gerät;
- Einstellungsrichtlinie;
- Rohdatenprofil oder Extraktionsauswahl;
- Identität des Dateiziels;
- Fingerabdruck der Anfrage;
- Sitzungs- und Übertragungsmanifeste;
- Digest-Kette der Partitionen;
- bestätigten Partitions- und Byte-Fortschritt;
- Abschluss- oder Abbruchbestätigung.

Bei der Fortsetzung darf keines dieser Felder neu interpretiert werden.

## Mehr als nur „läuft“ oder „beendet“

Eine Auftragsantwort kann folgende Felder enthalten:

| Feld | Bedeutung |
|---|---|
| `durable` | Gibt an, ob der Vorgang wiederherstellbaren Auftragsstatus besitzt |
| `state` | Aktueller Lebenszyklusstatus des persistenten Auftrags |
| `job_id` | Stabile Auftragskennung |
| `session_id` | Gebundene Kennung der Übertragungssitzung |
| `paused` | Gibt an, ob dasselbe iPhone erneut verbunden werden muss |
| `processed_days` / `total_days` | Logischer Fortschritt in Inhabertagen |
| `committed_partitions` | Vom Empfänger dauerhaft bestätigte Partitionen |
| `committed_bytes` | Sicher bestätigte Nutzdatenbytes |
| `fraction_complete` | Fortschrittsanteil ohne Gesundheitsdaten |
| `expires_at` | Fester Ablaufzeitpunkt des Auftrags |

Statusfelder enthalten Datumswerte, IDs, Anzahlen, Bytes und Fehler ohne Gesundheitsdaten. Sie sollten keine Gesundheitsmesswerte enthalten.

## Auftrag mit ausdrücklichem Ausgabeplan starten

Rohdatenexport:

```bash
healthmd export --iphone --last 30 --raw \
  --output health-month.json
```

Kanonische Extraktion:

```bash
healthmd extract --category Sleep --last 30 \
  --output sleep-month.json
```

Direkt generierte Dateien:

```bash
healthmd --backend direct export --last 30 \
  --destination "$HOME/Documents/HealthVault"
```

Legen Sie die endgültige Ausgabe oder das Ziel vor Beginn der Anfrage fest. Ein Rohdatenauftrag bindet sein Ausgabeverhalten. Ein direkter Dateiauftrag bindet das exakte Zielstammverzeichnis an die unveränderliche Anfrage.

## Fortsetzen

```bash
healthmd resume JOB_UUID --timeout 300
healthmd resume JOB_UUID --output recovered.json
healthmd resume JOB_UUID --output recovered.json --allow-partial
```

Wählen Sie im Direktmodus dasselbe Backend, Gerät, denselben Übertragungsweg, Port und dasselbe iPhone wie bei der ursprünglichen Anfrage:

```bash
healthmd --backend direct --device DEVICE_UUID \
  --transport manual-ip --port 17647 \
  resume JOB_UUID --timeout 300 --output recovered.json
```

Noch nicht bestätigte Bytes können nach einem Verbindungsabbruch verworfen werden. Bestätigte Partitionen werden weder erneut übertragen noch neu interpretiert. Der Empfänger akzeptiert eine bereits bestätigte Partition nur, wenn alle unveränderlichen Deskriptoren übereinstimmen.

Ein Dateiauftrag akzeptiert bei der Fortsetzung kein Ersatzziel. Hat sich das ursprüngliche Stammverzeichnis geändert, bricht Health.md sicher ab, statt in einen anderen Ordner zu schreiben.

## Abbrechen

Verwenden Sie den Lebenszyklus, mit dem der Auftrag erstellt wurde:

```bash
# Export, raw, or extraction
healthmd cancel JOB_UUID

# Encrypted-context acquisition
healthmd agent job cancel JOB_UUID
```

Ein Abbruch erfolgt in zwei Schritten:

1. Die CLI speichert und sendet eine persistente Abbruchanfrage.
2. Das iPhone bestätigt den Abbruch und macht ihn endgültig.

Ist das iPhone nicht verfügbar, bleibt der Auftrag im Status `cancellation_pending`. Öffnen Sie dasselbe iPhone erneut und wiederholen Sie den Abbruch. Melden Sie einen Auftrag nicht allein aufgrund der lokalen Absicht als abgebrochen.

Ein Prozess, der Ctrl-C empfängt, sollte beendet werden, ohne einen endgültigen Abbruch vorzutäuschen. Verwenden Sie bei beabsichtigtem Abbruch den ausdrücklichen Abbruchbefehl.

## Ausgabekanäle

Health.md trennt Befehlsergebnisse vom Fortschritt:

| Kanal | Inhalt |
|---|---|
| stdout | Versioniertes JSON-Befehlsergebnis, Fehler oder angeforderter JSON-/JSONL-Stream |
| stderr | Kopplungsanweisungen als Klartext, Fortschritt ohne Gesundheitsdaten, JSONL-Beleg beim Streaming und Verwendungshinweise |
| `--output PATH` | Atomar bestätigtes gesundheitsbezogenes JSON oder JSONL |
| `OUTPUT.receipt.json` | Beleg der JSONL-Dateiextraktion ohne Gesundheitsdaten |

`--help` ist Klartext. Argumentfehler vor der Ausführung verwenden stderr und Exit-Code 2. Sobald ein Befehl ausgeführt wird, verwenden Laufzeitfehler maschinenlesbares JSON.

Führen Sie stdout und stderr in einem Automatisierungsparser nicht zusammen.

## Exit-Status und Datenstatus

Der Exit-Status des Prozesses ist nur ein Signal. Parsen Sie die Antwort, bevor Sie Erfolg melden.

| Ergebnis | Standardmäßiges Exit-Verhalten |
|---|---|
| Vollständiger Erfolg | Null |
| Vollständig leerer angeforderter Umfang | Null |
| Validierte partielle Rohdaten oder Extraktion | Ungleich null |
| Teilergebnis mit ausdrücklichem `--allow-partial` | Null, Antwort bleibt jedoch partiell |
| Argumentfehler | Exit 2, Klartext auf stderr |
| Validierungs- oder Übertragungsfehler | Ungleich null mit strukturiertem Laufzeitfehler |

`--allow-partial` ist eine Akzeptanzrichtlinie, keine Datenreparatur. Jeder fehlende Tag, jede fehlgeschlagene Abfrage, jeder nicht unterstützte Typ und jede Warnung bleiben sichtbar.

## Paginierung ist vom Auftragsabschluss getrennt

Typisierte Abfrageantworten sind paginiert. Ein neuer Erfassungsauftrag kann abgeschlossen sein, während für die Abfrage noch eine weitere Seite vorhanden ist.

Prüfen Sie ohne `--all-pages` den Wert `next_cursor`. Ist eine nächste Seite vorhanden, meldet die High-Level-CLI `partial_success`, statt eine vollständige Paginierung vorzutäuschen.

```bash
healthmd query --category Sleep --last 90 --all-pages
```

`--all-pages` folgt opaken Cursorn, prüft Wiederholungen und setzt eine Gesamtgrenze für Seiten und Bytes durch. Wird die Grenze erreicht, schränken Sie den Umfang ein oder verwenden Sie die Low-Level-API für die manuelle Paginierung. Es gibt keine verborgene Obergrenze für die Gesamtergebnisse, ein einzelner Aufruf bleibt jedoch begrenzt.

## Neue, zwischengespeicherte und wiederverwendete Abdeckung

High-Level-Abfragebefehle erfassen standardmäßig neue iPhone-Daten:

```bash
healthmd query --metric resting_heart_rate --last 30
```

Verwenden Sie zwischengespeicherte Daten nur, wenn veralteter Kontext vertretbar ist:

```bash
healthmd query --metric resting_heart_rate --last 30 --cached
```

Verwenden Sie `--reuse-covered`, um die Erfassung nur dann zu überspringen, wenn Health.md eine vollständige metrikbezogene Zusammenfassungsabdeckung für die angeforderten Tage bestätigt:

```bash
healthmd query --metric resting_heart_rate --last 30 --reuse-covered
```

Diese Wiederverwendung gilt nicht für verlustfreie Daten oder neu berechnete Schlafsitzungsvorgänge. Daten eines anderen Providers oder ältere veraltete Blobs gelten niemals als Nachweis für den Abschluss dieser neuen Anfrage.

## Shell-Beispiel

Dieses Beispiel hält die Gesundheitsdaten in einer geschützten Datei und gibt nur Statusfelder ohne Gesundheitsdaten aus. Es setzt GNU `timeout` voraus. Andere Automatisierungshosts sollten ein eigenes Prozesszeitlimit anwenden.

```bash
#!/usr/bin/env bash
set -euo pipefail

output="${HOME}/Private/healthmd/sleep-week.json"
mkdir -p "$(dirname "$output")"
chmod 700 "$(dirname "$output")"

set +e
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output "$output" \
  </dev/null > /tmp/healthmd-command.json
exit_code=$?
set -e

if [ -s /tmp/healthmd-command.json ]; then
  jq '{status, job_id, error, message}' /tmp/healthmd-command.json
fi

if [ "$exit_code" -ne 0 ]; then
  echo "healthmd did not report complete success" >&2
  exit "$exit_code"
fi
```

Aktivieren Sie `set -x` nicht um einen Befehl, der Gesundheits-JSON streamen oder vertrauliche Pfade enthalten kann.

## Agentenverhalten nach unbekanntem Ergebnis

Ein Agent oder Scheduler sollte diese Reihenfolge einhalten:

1. Strukturierten Fehler und Auftrags-ID lesen.
2. Lokal `status --job` ausführen.
3. Prüfen, ob der Auftrag pausiert, endgültig, abgelaufen oder noch nicht bestätigt ist.
4. Dasselbe iPhone erneut öffnen, wenn neue Arbeit oder eine Bestätigung nötig ist.
5. Den bestehenden Auftrag mit demselben Backend und Gerät fortsetzen.
6. Einen neuen Auftrag erst starten, wenn das vorherige Ergebnis bekannt ist oder der Ablauf ausdrücklich akzeptiert wurde.

Das blinde Wiederholen einer Änderung kann Quellarbeit duplizieren, selbst wenn Datei-Commits idempotent sind.

## Häufige maschinenlesbare Fehler

| Code | Bedeutung | Sichere Reaktion |
|---|---|---|
| `timed_out` | Der Befehl wartete nicht bis zum Auftragsende | Zurückgegebenen Auftrag prüfen und fortsetzen |
| `job_not_found` | Für diese ID ist kein lokaler Datensatz eines persistenten Auftrags vorhanden | Backend und Statusverzeichnis prüfen, bevor Sie neu beginnen |
| `job_expired` | Die feste Frist von sieben Tagen ist abgelaufen | Lücke dokumentieren und gegebenenfalls neue Anfrage erstellen |
| `direct_export_paused` | Direkter Vorgang benötigt das gekoppelte iPhone erneut | iPhone öffnen und fortsetzen |
| `direct_cancellation_pending` | Lokale Abbruchabsicht wurde vom iPhone noch nicht bestätigt | iPhone öffnen und Abbruch wiederholen |
| `invalid_direct_raw_response` | Strikte Rohdatenvalidierung fehlgeschlagen | Ausgabe nicht verwenden |
| `invalid_direct_file_receipt` | Validierung des Dateimanifests oder Commit-Belegs fehlgeschlagen | Dateien nicht manuell reparieren oder ergänzen |
| `partial_canonical_extraction` | Angeforderte Extraktion ist unvollständig | Beleg prüfen; Teilergebnis nur ausdrücklich akzeptieren |
| `unvalidated_response_too_large` | Ein Ergebnis kann unter den aktuellen Validierungsgrenzen nicht bereitgestellt werden | Umfang einschränken oder geeigneten Ausgabemodus verwenden |
| `stale_cursor` | Verschlüsselter Kontext änderte sich nach Ausgabe des Cursors | Abfrage gegen den aktuellen Korpus neu starten |

## Fortschritt ohne Protokollierung der Nutzdaten

Verwenden Sie `--progress-json` für High-Level-Abfragephasen und die Paginierung:

```bash
healthmd query --category Sleep --last 30 \
  --all-pages --progress-json --output result.json \
  2> progress.jsonl
```

Fortschritts-JSONL kann Phase, Seitenzahl, Elementzahl, Datumswerte und Diagnosen ohne Gesundheitsdaten enthalten. Gesundheitswerte dürfen nicht enthalten sein. Bewahren Sie es getrennt vom Endergebnis auf und wenden Sie dennoch eine angemessene Aufbewahrungsrichtlinie an.

## Verwandte Themen

<div class="related">
  <a href="/de/docs/cli/"><span>Einrichtung</span>Health.md CLI: installieren, Backend auswählen und Befehlsausgabe verstehen.</a>
  <a href="/de/docs/cli-direct/"><span>Direkt</span>Direkte iPhone-CLI: begrenzte Hintergrundzeit, ausdrückliches Ziel und vertrauenswürdige Fortsetzung.</a>
  <a href="/de/docs/agent-queries/"><span>Paginierung</span>Typisierte Abfragen: neue und zwischengespeicherte Modi, Paginierung, Abdeckung und Belege.</a>
  <a href="/de/docs/reference/generated/cli/exit-codes/"><span>Generierter Vertrag</span>CLI-Exit-Codes: aus dem Produktcode erzeugtes Status- und Fehlerverhalten.</a>
</div>
