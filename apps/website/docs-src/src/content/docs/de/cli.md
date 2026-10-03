---
title: "Health.md CLI"
description: "Installieren Sie die eigenständige healthmd-CLI unter macOS, Linux oder Windows, koppeln Sie sie direkt mit einem iPhone oder Android-Gerät, prüfen Sie die Bereitschaft, exportieren Sie Daten, führen Sie Abfragen aus und verwalten Sie persistente Aufträge. Keine Mac-App erforderlich."
---

Die eigenständige `healthmd`-CLI läuft unter macOS, Linux und Windows und koppelt sich direkt mit einer geöffneten Health.md-App auf dem iPhone (Protokoll v1) oder unter Android (Protokoll v2). Sie benötigt niemals die Health.md-Mac-App, hat keine Backend-Auswahl und liest niemals Apple Health oder Health Connect auf dem Computer.

<div class="callout">
<strong>Gesundheitsdaten bleiben auf dem Telefon.</strong>
<p style="margin-top:6px;">Die CLI liest Apple Health oder Health Connect niemals auf dem Computer. Die aktuell geöffnete Health.md-App auf dem iPhone oder Android führt jeden neuen Gesundheitslesevorgang der Plattform aus. Die CLI empfängt validierte Ergebnisse oder Dateien.</p>
</div>

## Eigenständige CLI installieren

<div class="availability preview">
<strong>Öffentliche Vorschau · noch keine qualifizierte stabile Version</strong>
<p>Die plattformübergreifende Rust-CLI ist öffentlich paketiert, ihre exakte mobile Matrix wartet jedoch noch auf die physische Release-Qualifikation.</p>
</div>

Installieren Sie die Vorschau unter macOS oder Linux mit <code>brew install CodyBontecou/tap/healthmd</code>. Verwenden Sie den exakten mobilen Build aus den Release-Nachweisen; die Paketveröffentlichung beweist keine mobile Kompatibilität.

Die eigenständige Rust-CLI läuft unter macOS, Linux und Windows, verwendet direkte Verbindungen über Manual IP oder Tailscale und benötigt die Mac-App nicht. Sie koppelt sich über Protokoll v1 mit iPhone-Quellen und über Protokoll v2 mit Android-Quellen, mit automatisierten Kompatibilitätsgates für Swift↔Rust und Kotlin↔Rust. Die Protokollkompatibilität ist implementiert; vor der ersten qualifizierten stabilen Version muss die Release-QA auf physischen Geräten abgeschlossen sein. Prüfsummen-gesicherte Archive, ein PowerShell-Installationsprogramm und `cargo install healthmd-cli --locked` sind jedem Release beigefügt.

Der portable Client unterstützt auf allen drei Desktop-Plattformen für iPhone- und Android-Quellen Kopplung, Status, Rohdatenexport, Ziele für generierte Dateien, Fortsetzung und Abbruch. Kanonische Extraktion und typisierte MCP-Abfragen sind iPhone-Funktionen; Android-Rohdaten-Snapshots bewahren ihren provider-nativen Health-Connect-Vertrag, statt in HealthKit-strukturierte Daten umgewandelt zu werden, und typisierte Android-Abfragen sind nicht implementiert. Beim Export generierter Dateien behandelt das Telefon das Ziel als opake Zielbezeichnung, während die empfangende CLI es validiert und dauerhaft an das Dateisystem des Hosts bindet. Android-Protokoll v2 schreibt Dateiziele unter jedem CLI-Betriebssystem fest und begrenzt jeden generierten Auftrag auf 4.096 Dateien.

## Befehlsübersicht

| Befehl | Zweck |
|---|---|
| `healthmd status` | Live-Bereitschaft oder einen lokalen persistenten Auftrag prüfen |
| `healthmd export` | Generierte Dateien schreiben oder striktes Rohdaten-JSON zurückgeben |
| `healthmd extract` | Ausgewählte kanonische `healthmd.health_data`-Objekte erfassen (iPhone) |
| `healthmd query` | Feste typisierte Abfrageoperationen ausführen (iPhone) |
| `healthmd resume` | Einen unveränderlichen persistenten Exportauftrag fortsetzen |
| `healthmd cancel` | Einen ausdrücklichen Abbruch anfordern |
| `healthmd direct ...` | Direkte Telefon-Vertrauensstellungen koppeln, auflisten und entfernen |
| `healthmd mcp ...` | Die feste MCP-Tool-Oberfläche bedienen oder prüfen |
| `healthmd setup codex` | Codex konfigurieren und ein iPhone in einem Ablauf koppeln |

Direkte Befehle koppeln sich mit iPhone-Quellen (Protokoll v1) oder Android-Quellen (Protokoll v2). Das kanonische `extract` und jeder typisierte Abfragebefehl sind iPhone-Funktionen; direkte Android-Quellen geben provider-native Health-Connect-Rohdaten-Snapshots und generierte Dateien zurück.

```bash
# Readiness and local trust
healthmd status
healthmd direct devices

# Platform-native raw export; omit --output to stream validated JSON/NDJSON to stdout
healthmd export --yesterday --raw --output yesterday.json
healthmd export --last 7 --raw --output week.json

# Typed query through the same operation registry as MCP (iPhone)
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'

# Scoped canonical extraction (iPhone)
healthmd extract --category Sleep --last 7 --output sleep.json

# Production-generated files on every CLI OS
mkdir -p "$HOME/Documents/HealthVault"
healthmd export --yesterday --destination "$HOME/Documents/HealthVault"

# Durable operations
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --output resumed.json
healthmd cancel JOB_UUID
```

### Portable profilbasierte Dateiexporte

Die eigenständige direkte CLI kann ein gespeichertes Profil auf beiden unterstützten Smartphone-Plattformen anhand seiner stabilen ID auflösen. Das Profil liefert die fixierten Ausgabeeinstellungen; das Computerziel bleibt ausdrücklich angegeben:

```bash
mkdir -p "$HOME/Documents/HealthVault"
healthmd export --last 7 \
  --profile 11111111-2222-4333-8444-555555555555 \
  --destination "$HOME/Documents/HealthVault"
```

`--profile PROFILE_ID` lässt sich nicht mit `--use-device-settings` oder Metrik-/Kategorie-Selektoren kombinieren. Eine unbekannte ID bricht sicher ab, statt Live-Einstellungen zu verwenden. Kopieren Sie die ID auf iPhone oder Android unter **Einstellungen → Exportprofile → Profil-ID**. [Exportprofile](/de/docs/export-profiles/) erklären Automatisierung und Zielverhalten.

Der portable Direktclient kann jeden unterstützten typisierten iPhone-Vorgang ohne MCP-Hülle aufrufen:

```bash
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'
```

## Mitgelieferter Mac-Helfer

Health.md für Mac liefert eigene signierte Swift-Helfer `healthmd` und `healthmd-mcp` innerhalb der App mit. Dieser Helfer ist eine Funktion der Mac-App, kein Backend der eigenständigen CLI: Standardmäßig spricht er den Loopback-Server der laufenden Mac-App an für verschlüsselte lokale Abfragen, MCP-Tools und den bereits in Health.md für Mac ausgewählten Zielordner; zusätzlich bietet er einen kompatiblen direkten iPhone-Modus, der mit `--backend direct` gewählt wird. Die beiden Clients wechseln niemals unbemerkt den Modus.

<div class="availability available">
<strong>Jetzt verfügbar · Health.md für Mac</strong>
<p>Die signierten Swift-Helfer für CLI und MCP sind Bestandteil der veröffentlichten Mac-App.</p>
</div>

Öffnen Sie die Mac-App und wählen Sie **CLI**, um die Pfade Ihrer installierten Version, Einrichtungsbefehle, Agenten-Prompts und das optionale Installationsprogramm für Agenten-Skills anzuzeigen.

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

Prüfen Sie den Helfer, ohne die MCP-stdio-Schleife zu starten:

```bash
healthmd --help
healthmd doctor
```

`healthmd doctor` gibt `healthmd.cli_doctor`-JSON mit dem Bereitschaftsstatus von Mac, verschlüsseltem Kontext und iPhone zurück. Gesundheitswerte werden nicht ausgegeben.

### Befehle des mitgelieferten Helfers

| Befehl | Zweck |
|---|---|
| `healthmd export --iphone ...` | Generierte Dateien schreiben oder striktes Rohdaten-JSON über die Mac-App zurückgeben |
| `healthmd status` | Mac/iPhone-Bereitschaft oder einen persistenten Auftrag prüfen |
| `healthmd doctor` | Bereitschaft von Mac, verschlüsseltem Kontext und iPhone erläutern |
| `healthmd metrics list` | Den kanonischen Katalog abfragbarer Metriken zurückgeben |
| `healthmd query` | Ausgewählte typisierte Metriken erfassen und abfragen |
| `healthmd sleep sessions` | Eigenständige Schlafsitzungen und feste Zeitfenster zurückgeben |
| `healthmd training align` | Trainingseinheiten dem vorherigen und nachfolgenden Schlaf zuordnen |
| `healthmd workouts` | Typisierte Trainingseinheiten mit Nachweisen auflisten |
| `healthmd coverage` | Datums- und Metrikabdeckung oder fehlende Daten prüfen |
| `healthmd compare` | Exakte Zeiträume mit vom Aufrufer gewählter Aggregation vergleichen |
| `healthmd evidence training` | Ein sachliches Nachweispaket zum Training erstellen |
| `healthmd resume` / `healthmd cancel` | Persistente Aufträge verwalten |
| `healthmd agent ...` | Die Low-Level-Loopback-API für Abfragen und Aufträge aufrufen |
| `healthmd --backend direct ...` | Der kompatible direkte iPhone-Modus des Helfers |

Im Direktmodus des Helfers geben Mac-Kontext-Abfrage-, Nachweis-, Doctor-, Metrik- und Refresh-Unterbefehle `backend_unsupported` zurück, statt zur Mac-App zu wechseln.

### Erster Arbeitsablauf mit der Mac-App

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

### Datei- und Rohdatenexporte des mitgelieferten Helfers

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

Verwenden Sie einen Abfragebefehl für eine typisierte, mit Nachweisen verknüpfte Ansicht. Die eigenständige CLI stellt feste typisierte Operationen bereit; der mitgelieferte Mac-Helfer bietet zusätzlich die komfortablen Kurzbefehle:

```bash
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"exact","range":{"start_date":"2026-07-22","end_date":"2026-07-28"}},"all_pages":true}'
healthmd compare --metric steps:sum \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

`healthmd.health_data` v8 ist der öffentliche Apple-Quellvertrag. Abfrage-, Nachweis-, Auftrags- und Belegschemas beschreiben die Übertragung oder abgeleitete Ansichten. Sie ersetzen das Quellschema nicht. Die kanonische Extraktion ist eine iPhone-Funktion; direkte Android-Quellen stellen stattdessen provider-native Health-Connect-Snapshots über den Rohdatenexport bereit.

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
NO_COLOR=1 TERM=dumb timeout 30 healthmd status </dev/null
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

Die lokale Abfrage-API des mitgelieferten Mac-Helfers besitzt weder Bearer-Token noch Registrierung, Zugriffsprofil oder Berechtigungsdatenbank. Die Erreichbarkeit über Loopback ist ihre vollständige Zugriffsgrenze. Jeder lokale Prozess kann sie bei geöffneter Mac-App verwenden; leiten Sie Port `17645` daher niemals per Proxy weiter und stellen Sie ihn keinem anderen Computer bereit.

## Nächste Anleitungen

<div class="related">
  <a href="/de/docs/cli-direct/"><span>Ohne Mac-App</span>Direkte Telefon-CLI: Kopplung mit iPhone oder Android, Übertragungswege, Rohdaten- und Dateiexporte, Hintergrundverhalten und Plattformunterstützung.</a>
  <a href="/de/docs/cli-extract/"><span>Quelldaten</span>Kanonische Extraktion: Metriken, Objekte, Details, JSON Pointer, JSONL und Belege auswählen.</a>
  <a href="/de/docs/cli-jobs/"><span>Automatisierung</span>Persistente Aufträge: Zeitlimits, Fortsetzung, Abbruch, Teilergebnisse und sichere Skripte.</a>
  <a href="/de/docs/agents/"><span>Agenten</span>Lokale Agenten-Workflows: verschlüsselter Kontext, direkter Umfang, typisierte Befehle und Nachweise.</a>
  <a href="/de/docs/mcp/"><span>MCP</span>Den isolierten stdio-Helfer konfigurieren und seine Tool-Grenzen prüfen.</a>
  <a href="/de/docs/reference/api-and-cli/"><span>Vertrag</span>API- und CLI-Referenz: exakte Routen, Schemas, Antworten und generierte Fixtures.</a>
</div>
