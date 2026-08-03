---
title: "Health.md CLI"
description: "Wählen Sie die Mac-App oder das direkte iPhone-Backend, installieren Sie healthmd, prüfen Sie die Bereitschaft, exportieren Sie Dateien, extrahieren Sie kanonische Apple Health-Daten, führen Sie typisierte Abfragen aus und automatisieren Sie persistente Aufträge."
---

Der Befehl `healthmd` bietet zwei Betriebsarten. Verwenden Sie das Backend der Mac-App für verschlüsselte lokale Abfragen, MCP-Tools oder den bereits in Health.md für Mac ausgewählten Zielordner. Verwenden Sie das direkte iPhone-Backend, wenn Sie Rohdaten oder generierte Dateien ohne laufende Mac-App benötigen.

<div class="callout">
<strong>HealthKit bleibt auf dem iPhone.</strong>
<p style="margin-top:6px;">Keines der CLI-Backends liest Apple Health auf dem Computer. Die aktuell geöffnete Health.md-App auf dem iPhone führt jeden neuen HealthKit-Lesevorgang aus. Die CLI empfängt validierte Ergebnisse oder Dateien.</p>
</div>

## Backend auswählen

| Funktion | Backend der Mac-App | Direktes iPhone-Backend |
|---|---|---|
| Standard im mitgelieferten Mac-Helfer | Ja | Nein, mit `--backend direct` auswählen |
| Health.md für Mac muss geöffnet sein | Ja | Nein |
| Health.md auf dem iPhone muss für neue Daten geöffnet sein | Ja | Ja |
| Dateiziel | In der Mac-App ausgewählter Ordner | Vorhandenes absolutes `--destination` |
| Strikter Rohdatenexport | Ja | Ja |
| Kanonisches `healthmd extract` | Ja | Ja |
| Verschlüsselter Kontext, typisierte Abfragen und Nachweise | Ja | Nein |
| `healthmd-mcp` | Ja | Nein |
| Manual IP oder Tailscale | Mac-Synchronisierung oder ausdrücklicher Direktmodus | Ja |
| Direkter Transport in der Nähe | Nur mitgelieferter Swift-Helfer | Nicht im portablen Rust-Client |

Backend und Übertragungsweg wechseln niemals unbemerkt. Ein direkter Befehl kann nicht zur Mac-App wechseln, um eine Abfrage zu erfüllen, und eine fehlgeschlagene Nearby-Verbindung kann nicht zu Manual IP wechseln.

## Mitgelieferte Mac-Helfer installieren

<div class="availability available">
<strong>Jetzt verfügbar · Health.md für Mac</strong>
<p>Die signierten Swift-Helfer für CLI und MCP sind Bestandteil der veröffentlichten Mac-App.</p>
</div>

Health.md für Mac enthält die signierten Helfer `healthmd` und `healthmd-mcp`. Öffnen Sie die Mac-App und wählen Sie **CLI**, um die Pfade Ihrer installierten Version, Einrichtungsbefehle, Agenten-Prompts und das optionale Installationsprogramm für Agenten-Skills anzuzeigen.

Die üblichen Pfade im App-Bundle lauten:

```text
/Applications/Health.md.app/Contents/Helpers/healthmd
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

Verwenden Sie Aliasse für eine Shell-Sitzung:

```bash
alias healthmd="/Applications/Health.md.app/Contents/Helpers/healthmd"
alias healthmd-mcp="/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
```

Oder erstellen Sie dauerhafte symbolische Links in einem benutzereigenen bin-Verzeichnis:

```bash
mkdir -p ~/.local/bin
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd" ~/.local/bin/healthmd
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp" ~/.local/bin/healthmd-mcp
```

Fügen Sie `~/.local/bin` zu `PATH` hinzu, falls Ihre Shell das Verzeichnis noch nicht enthält:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Prüfen Sie die CLI, ohne die MCP-stdio-Schleife zu starten:

```bash
healthmd --help
healthmd doctor
```

`healthmd doctor` gibt `healthmd.cli_doctor`-JSON mit dem Bereitschaftsstatus von Mac, verschlüsseltem Kontext und iPhone zurück. Gesundheitswerte werden nicht ausgegeben.

## Status der portablen CLI

<div class="availability preview">
<strong>Vorschau · noch nicht öffentlich paketiert</strong>
<p>Die plattformübergreifende Rust-CLI wartet auf die Release-QA mit einem physischen iPhone und ihr erstes qualifiziertes Paket.</p>
</div>

Eine eigenständige Rust-CLI befindet sich als `0.1.0-alpha.1` in Entwicklung. Sie läuft unter macOS, Linux und Windows, verwendet standardmäßig direkte Verbindungen über Manual IP oder Tailscale und benötigt die Mac-App nicht. Protokollkompatibilität und sprachübergreifende Fixtures sind implementiert; vor der ersten öffentlichen Veröffentlichung müssen jedoch noch die Release-QA auf einem physischen iPhone und die öffentliche Paketierung abgeschlossen werden.

Verwenden Sie bis dahin den mitgelieferten Mac-Helfer. Verlassen Sie sich nicht auf unveröffentlichte Homebrew-, crates.io-, GitHub-Installationsprogramm- oder Download-URLs.

Der portable Client unterstützt auf allen drei Plattformen Rohdatenexport, kanonische Extraktion, Kopplung, Status, Fortsetzung, Abbruch und Ziele für generierte Dateien. Beim Dateiexport mit Protokoll v1 behandelt das iPhone das Ziel als opake Zielbezeichnung; die empfangende CLI validiert es und bindet es dauerhaft an das Dateisystem des Hosts.

## Befehlsübersicht

| Befehl | Zweck | Backend |
|---|---|---|
| `healthmd status` | Live-Bereitschaft oder einen lokalen persistenten Auftrag prüfen | Beide |
| `healthmd doctor` | Bereitschaft von Mac, verschlüsseltem Kontext und iPhone erläutern | Mac-App |
| `healthmd metrics list` | Den kanonischen Katalog abfragbarer Metriken zurückgeben | Mac-App |
| `healthmd extract` | Ausgewählte kanonische `healthmd.health_data`-Objekte erfassen | Beide |
| `healthmd query` | Ausgewählte typisierte Metriken erfassen und abfragen | Mac-App |
| `healthmd sleep sessions` | Eigenständige Schlafsitzungen und feste Zeitfenster zurückgeben | Mac-App |
| `healthmd training align` | Trainingseinheiten dem vorherigen und nachfolgenden Schlaf zuordnen | Mac-App |
| `healthmd workouts` | Typisierte Trainingseinheiten mit Nachweisen auflisten | Mac-App |
| `healthmd coverage` | Datums- und Metrikabdeckung oder fehlende Daten prüfen | Mac-App |
| `healthmd compare` | Exakte Zeiträume mit vom Aufrufer gewählter Aggregation vergleichen | Mac-App |
| `healthmd evidence training` | Ein sachliches Nachweispaket zum Training erstellen | Mac-App |
| `healthmd export` | Generierte Dateien schreiben oder striktes Rohdaten-JSON zurückgeben | Beide |
| `healthmd resume` | Einen unveränderlichen persistenten Exportauftrag fortsetzen | Beide |
| `healthmd cancel` | Einen ausdrücklichen Abbruch anfordern | Beide |
| `healthmd agent ...` | Die Low-Level-Loopback-API für Abfragen und Aufträge aufrufen | Mac-App |
| `healthmd direct ...` | Direkte iPhone-Vertrauensstellungen koppeln, auflisten und entfernen | Direkt |

## Erster Arbeitsablauf mit der Mac-App

1. Öffnen Sie Health.md auf dem Mac und wählen Sie einen Zielordner, wenn Sie Dateien schreiben möchten.
2. Öffnen Sie Health.md auf dem gekoppelten iPhone und warten Sie auf die Mac-Verbindung.
3. Prüfen Sie die Bereitschaft.
4. Führen Sie einen kleinen Befehl aus, bevor Sie einen langen Verlauf anfordern.

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --metric sleep_total --yesterday
```

Neue Abfragen erfassen nur die angegebenen Metriken, Quellen, Datumswerte und Zusammenfassungs- oder verlustfreien Details. Gespeicherte iPhone-Exporteinstellungen werden nicht geändert.

## Datei- und Rohdatenexporte

```bash
# Use the Mac app's selected destination
healthmd export --iphone --yesterday
healthmd export --iphone --last 7
healthmd export --iphone --from 2026-07-01 --to 2026-07-07
healthmd export --iphone --all

# Return strict lossless canonical JSON without writing export files
healthmd export --iphone --yesterday --raw --output yesterday.json
healthmd export --iphone --all --raw --output complete-health-corpus.json

# Replace saved metric scope for this one file job
healthmd export --iphone --last 7 --category Sleep --detail summary

# Mirror saved iPhone settings, including roll-ups
healthmd export --iphone --yesterday --use-iphone-settings
```

Derzeit gibt es keine Begrenzung der Kalendertage. `--all` veranlasst das iPhone, den frühesten verfügbaren Datensatz der ausgewählten Quelle zu ermitteln, den aufgelösten Zeitraum festzuschreiben und ihn in begrenzten Partitionen zu verarbeiten. Verfügbarer Speicherplatz und ein einzelner ungewöhnlich datenreicher Tag bleiben praktische Grenzen.

`--raw` fordert vorübergehend kanonische, verlustfreie Quelldatensätze an, ohne die iPhone-Einstellung zu ändern. Es schreibt keine generierten Dateien und enthält keine Sidecars verbundener Provider.

## Kanonische Extraktion oder abgeleitete Abfrage?

Verwenden Sie `extract`, wenn Sie Daten in der Struktur der Quelle benötigen:

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

Verwenden Sie einen Abfragebefehl für eine typisierte, mit Nachweisen verknüpfte Ansicht:

```bash
healthmd sleep sessions --last-nights 14 --window first:4h
healthmd compare --metric steps:sum \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

`healthmd.health_data` v7 ist der öffentliche Quellvertrag. Abfrage-, Nachweis-, Auftrags- und Belegschemas beschreiben die Übertragung oder abgeleitete Ansichten. Sie ersetzen das Quellschema nicht.

## Maschinenlesbares Verhalten

Befehle verwenden standardmäßig versioniertes JSON auf stdout oder unter dem ausdrücklichen `--output`-Pfad. Die kanonische Extraktion kann JSONL ausgeben, umfangreiche Abfragen optional eine bewusst verlustbehaftete Tabelle. Fortschritt ohne Gesundheitsdaten kann stderr verwenden. `--help` ist Klartext. Argumentfehler vor dem Befehlsstart erscheinen als Klartext auf stderr mit Exit-Code 2.

Ein erfolgreicher Prozessabschluss allein beweist keine vollständigen Gesundheitsdaten. Prüfen Sie:

- den äußeren Status;
- den Status des angeforderten Umfangs;
- Ergebnisse pro Tag und Abfrage;
- fehlende Intervalle;
- `next_cursor` oder den Paginierungsbeleg;
- Quellschema und Version;
- Einschränkungen und Warnungen.

Ein vollständig leeres Ergebnis bedeutet, dass Health.md den angeforderten Umfang dargestellt und keine Beobachtungen gefunden hat. Es ist nicht gleichbedeutend mit null, fehlend, fehlgeschlagen, übersprungen oder nicht unterstützt.

## Sichere Automatisierung

Verwenden Sie das Prozesszeitlimit Ihres Automatisierungshosts und halten Sie stdin für Befehle geschlossen, die keine Eingabe anfordern sollen. Auf Systemen mit GNU `timeout`:

```bash
NO_COLOR=1 TERM=dumb timeout 30 healthmd doctor </dev/null
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output sleep.json </dev/null
```

Zeitlimit, Ctrl-C, Prozessende, Netzwerkverlust und ausgeschöpfte iOS-Hintergrundzeit brechen einen persistenten Auftrag nicht ab. Prüfen Sie die Auftrags-ID und setzen Sie ihn fort, statt ein Duplikat zu starten.

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
healthmd cancel JOB_UUID
```

Nur eine Bestätigung des iPhone macht den Abbruch endgültig.

## Datenschutzregeln

Rohe und verlustfreie Ausgaben können exakte Zeitstempel, Routen, klinische Datensätze, Medikamente, Stimmungseinträge, EKG-Werte, Herkunftsangaben und Anhänge enthalten. Schreiben Sie die Ausgabe vorzugsweise in eine Datei statt ins Terminal. Fügen Sie Nutzdaten nicht in Fehlerberichte, Agentenprotokolle, CI-Logs oder Shell-Traces ein.

Die lokale Abfrage-API besitzt weder Bearer-Token noch Registrierung, Zugriffsprofil oder Berechtigungsdatenbank. Die Erreichbarkeit über Loopback ist ihre vollständige Zugriffsgrenze. Jeder lokale Prozess kann sie bei geöffneter Mac-App verwenden; leiten Sie Port `17645` daher niemals per Proxy weiter und stellen Sie ihn keinem anderen Computer bereit.

## Nächste Anleitungen

<div class="related">
  <a href="/de/docs/cli-direct/"><span>Ohne Mac-App</span>Direkte iPhone-CLI: Kopplung, Übertragungswege, Rohdaten- und Dateiexporte, Hintergrundverhalten und Plattformunterstützung.</a>
  <a href="/de/docs/cli-extract/"><span>Quelldaten</span>Kanonische Extraktion: Metriken, Objekte, Details, JSON Pointer, JSONL und Belege auswählen.</a>
  <a href="/de/docs/cli-jobs/"><span>Automatisierung</span>Persistente Aufträge: Zeitlimits, Fortsetzung, Abbruch, Teilergebnisse und sichere Skripte.</a>
  <a href="/de/docs/agents/"><span>Agenten</span>Lokale Agenten-Workflows: verschlüsselter Kontext, direkter Umfang, typisierte Befehle und Nachweise.</a>
  <a href="/de/docs/mcp/"><span>MCP</span>Den isolierten stdio-Helfer konfigurieren und seine Tool-Grenzen prüfen.</a>
  <a href="/de/docs/reference/api-and-cli/"><span>Vertrag</span>API- und CLI-Referenz: exakte Routen, Schemas, Antworten und generierte Fixtures.</a>
</div>
