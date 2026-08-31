---
title: "Health.md MCP-Server und App"
description: "Verwenden Sie Codex oder Claude für begrenzte Apple Health-Analysen, native Diagramme und persistente Health.md-Exporte über eine lokale MCP App in der Sandbox."
---

Health.md für Mac liefert einen signierten `healthmd-mcp` stdio-Helfer. Damit können Codex, Claude und andere MCP-Hosts sachliche Apple Health-Daten abfragen, Visualisierungen rendern, verschlüsselten lokalen Kontext aktualisieren und genehmigte persistente Exporte über die offene Mac-App ausführen.

```text
Codex / Claude / another local MCP host
  <-> MCP JSON-RPC over stdio
  <-> signed healthmd-mcp helper
  <-> Health.md Mac loopback API on 127.0.0.1:17645
  <-> connected iPhone for fresh HealthKit reads and exports
```

<div class="availability available">
<strong>Ab sofort verfügbar · Health.md für Mac</strong>
<p>Der mitgelieferte Server stellt 21 feste Tools bereit. Er selbst liest weder HealthKit noch Exportordner, security-scoped-Lesezeichen oder beliebige Dateien.</p>
</div>

<div class="availability preview">
<strong>Vorschau · portables direktes MCP</strong>
<p>Die separate Topologie mit 19 Tools über <code>healthmd mcp serve</code> für macOS, Linux und Windows ist als ausdrücklich unqualifizierte Vorschau öffentlich paketiert. Der cloudfreie Einstiegspunkt <code>serve-read-only</code> stellt nach der lokalen Kopplung nur die 13 Bereitschafts- und Abfragetools bereit. Installieren Sie unter macOS oder Linux mit <code>brew install CodyBontecou/tap/healthmd</code>.</p>
</div>

## Voraussetzungen für den mitgelieferten Mac

- Health.md für Mac installiert und geöffnet.
- Health.md ist auf dem verbundenen iPhone geöffnet, wenn das Aktualisierungstool oder ein Export neue HealthKit-Arbeit startet.
- Ein lokaler MCP-Host mit stdio-Unterstützung.
- Der Pfad des signierten Helfers, der unter **Health.md für Mac → CLI** angezeigt wird.

Der übliche Helferpfad ist `/Applications/Health.md.app/Contents/Helpers/healthmd-mcp`. Unterstützte Kernversionen des MCP-Protokolls sind `2024-11-05`, `2025-03-26`, `2025-06-18` und `2025-11-25`. Starten Sie `healthmd-mcp` nicht als normalen interaktiven Befehl; der MCP-Host besitzt stdin und den Prozesslebenszyklus.

## Voraussetzungen für portable Direktverbindung

- Installiere die eigenständige Vorschau unter macOS, Linux oder Windows; Mac-App und Loopback-Dienst sind nicht erforderlich.
- Kopple einmal ein abfragefähiges iPhone und lasse Health.md für jede neue typisierte Anfrage im Vordergrund. Typisiertes MCP wird unter Android nicht unterstützt.
- Nutze Manual IP oder Tailscale und den nativen Anmeldedatenspeicher; Linux erfordert einen entsperrten Secret-Service-Anbieter.
- Konfiguriere den installierten Kompatibilitätsstarter oder den gleichen stdio-Server. Beide verwenden die gekoppelte Direktverbindung.

## Codex-Setup

Fügen Sie den mitgelieferten Helfer zu `~/.codex/config.toml` hinzu:

```toml
[mcp_servers.healthmd]
command = "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
args = []
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_files]
approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_job_resume]
approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_job_cancel]
approval_mode = "prompt"
```

Starten Sie Codex neu, rufen Sie `healthmd_doctor` auf, ermitteln Sie IDs mit `healthmd_metrics`, erfassen Sie mit dem Aktualisierungstool ausdrücklich einen kleinen exakten Umfang und fragen Sie diesen dann mit `healthmd_metric_chart` ab. Hosts ohne interaktive MCP Apps erhalten weiterhin exaktes JSON und ein Standard-PNG-Diagramm.

## Claude-Setup

Verwenden Sie diesen lokalen stdio-Eintrag in der MCP-Konfiguration von Claude Desktop oder eine vertrauenswürdige `.mcp.json` von Claude Code:

```json
{
  "mcpServers": {
    "healthmd": {
      "command": "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp",
      "args": []
    }
  }
}
```

Starten Sie Claude Desktop neu, nachdem Sie seine Konfiguration bearbeitet haben. Claude-Projektkonfigurationen erfordern Vertrauen in den Workspace und eine explizite Servergenehmigung.

Claude Desktop-Versionen, die die stabile MCP Apps-Erweiterung bewerben, rendern die interaktive Ansicht von Health.md inline. Claude-Code und andere textorientierte Clients behalten die JSON- und Bild-Fallbacks bei.

## Vorschau auf portables direktes MCP

In der öffentlichen eigenständigen Vorschau koppelt `healthmd setup codex` ein im Vordergrund geöffnetes iPhone und erstellt sicher einen `healthmd mcp serve`-Eintrag für dieselbe Binärdatei. Diese Topologie verwendet authentifizierten verschlüsselten Manual IP- oder Tailscale-Transport auf Port `17647`, native Anmeldedatenspeicherung und explizite iPhone-Lesevorgänge pro Anfrage. Für Linux ist zusätzlich ein freigeschalteter Secret Service-Anbieter erforderlich. Windows verwendet Credential Manager.

Verwenden Sie die exakte `healthmd-cli/v<version>`-Vorabversion statt des repositoryweiten Zeigers auf die neueste Veröffentlichung. Siehe [Direktes iPhone CLI](/de/docs/cli-direct/) für den ausdrücklich unqualifizierten Kopplungs- und Transportvertrag.

## Native MCP App-Visualisierungen

Health.md implementiert eine stabile `io.modelcontextprotocol/ui`-Aushandlung mit `text/html;profile=mcp-app`.

Nachdem ein Host diesen MIME-Typ ankündigt, stellt der Server Folgendes bereit:

- `ui://healthmd/query-visualization-v1`;
- Standardmethoden `resources/list` und `resources/read`;
- `_meta.ui.resourceUri` zu Analyse- und Exportbeleg-Tools;
- validierter `structuredContent` neben dem exakten JSON-Text.

Die Ansicht ist eine eigenständige HTML5-Ressource ohne Netzwerk, Remote-Skripte, Remote-Schriftarten, Speicher oder verschachtelte Frames. Die deklarierte CSP enthält leere Verbindungs-/Ressourcen-/Frame-/Basisdomänenlisten. Es folgt dem standardmäßigen Initialisierungs-, Werkzeugergebnis-, Design-, Größenänderungs-, Abbruch- und Abbaulebenszyklus.

Es kann Folgendes rendern:

- metrische Liniendiagramme mit Einheiten und expliziten fehlenden Datenlücken;
- Periodenvergleiche mit vom Aufrufer ausgewählter Aggregation;
- Schlafsitzungen und Zusammenfassungen der Schlafphasendauer;
- Trainingseinheiten und tatsächliche Trainings-/Schlafzeiten;
- Abdeckung, fehlende Intervalle, Nachweise und Einschränkungen;
- Belege für die vollständige Paginierung;
- Fortschritt persistenter Exporte, Ziele und Auftragsbelege.

Wenn der Host MCP Apps nicht unterstützt, funktionieren die Tools trotzdem. `healthmd_metric_chart` fügt `image/png`-Inhalte für Image-fähige Hosts hinzu und behält dabei den gesamten JSON als Text bei.

## Verfügbare Tools

Der mitgelieferte Mac-Server stellt 21 feste Tools bereit: 13 für Bereitschaft und Abfragen, vier für Aufträge mit generierten Dateien und vier für Aktualisierungsaufträge des verschlüsselten Kontexts. Die portable Vorschau mit 19 Tools behält die 13 Bereitschafts-/Abfragetools und vier Exporttools bei, ersetzt Mac-Aktualisierungsaufträge durch zwei Tools zur direkten Kopplung und führt typisierte Abfragen direkt auf dem im Vordergrund geöffneten iPhone aus.

### Bereitschaft und Entdeckung

| Werkzeug | Zweck |
|---|---|
| `healthmd_status` | Überprüfen Sie die Mac-App, den Kontext, das iPhone und die Exportbereitschaft |
| `healthmd_doctor` | Diagnose des mitgelieferten Helfers und der Mac-Loopback-Topologie |
| `healthmd_capabilities` | Funktionen für direkte Abfragen, Nachweise, Exporte, Schemas und Paginierung auflisten |
| `healthmd_metrics` | Kanonische Metrik-IDs, Kategorien, Einheiten und Anforderungen auflisten |

### Analyse und Visualisierung

| Werkzeug | Zweck |
|---|---|
| `healthmd_metric_chart` | Metrikreihen abfragen und native Diagramme mit Abdeckung und Einheiten rendern |
| `healthmd_sleep_sessions` | Stabile Schlafsitzungen und physiologische Abdeckung auflisten und visualisieren |
| `healthmd_training_alignment` | Zeigen Sie den tatsächlichen Trainingszeitpunkt im Vergleich zum vorhergehenden/nachfolgenden Schlaf an |
| `healthmd_workouts` | Trainingseinheiten auflisten und visualisieren |
| `healthmd_coverage` | Überprüfen Sie die Abdeckung und fehlende Metrik- oder Datumswerte |
| `healthmd_compare_periods` | Vergleichen Sie genaue Zeiträume mit expliziter Aggregationssemantik |
| `healthmd_training_evidence` | Erstellen Sie ein sachliches Trainingsnachweispaket |
| `healthmd_query` | Senden Sie ein genaues `healthmd.query_request` und durchlaufen Sie optional Seiten |
| `healthmd_evidence_packet` | Senden Sie eine exakte Nachweisanfrage und durchlaufen Sie optional die Seiten |

### Exporte generierter Dateien

| Werkzeug | Zweck |
|---|---|
| `healthmd_export_files` | Persistenten Dateiexport ausführen; gebündelter Mac nutzt den ausgewählten Ordner, portables Direkt-MCP erfordert ein ausdrückliches Computerziel |
| `healthmd_export_job_status` | Überprüfen Sie den Exportfortschritt und den Zielbeleg |
| `healthmd_export_job_resume` | Setzen Sie den exakt festgelegten unveränderlichen persistenten Exportauftrag fort |
| `healthmd_export_job_cancel` | Den Exportauftrag explizit abbrechen |

Die Tools zum Exportieren, Fortsetzen und Abbrechen werden als potenziell destruktive Schreibvorgänge markiert und erfordern eine explizite Interaktion auf aktuellen Claude-Hosts, da konfigurierte Exportmodi generierte Dateien aktualisieren oder überschreiben können. Die obige Codex-Konfiguration weist als zusätzlichen Schutz auf diese Tools hin.

### Aufträge zur Erfassung verschlüsselten Kontexts · nur auf dem Mac mitgeliefert

| Werkzeug | Zweck |
|---|---|
| `healthmd_refresh` | Übertragen Sie einen autorisierten Bereich vom iPhone in den temporären verschlüsselten Mac-Kontext |
| `healthmd_job_status` | Überprüfen Sie den Aktualisierungsfortschritt, ohne Gesundheitswerte zu lesen |
| `healthmd_job_resume` | Den genau akzeptierten Aktualisierungsauftrag fortsetzen |
| `healthmd_job_cancel` | Einen akzeptierten Aktualisierungsauftrag explizit abbrechen |

### Vollständige Abfragestruktur ermitteln

MCP `tools/list` enthält ein vollständiges verschachteltes JSON-Schema für Datumsangaben, Metriken, Quellen, Paginierung, Zeiträume, Aggregationen und das erweiterte `healthmd.query_request`. Die typisierten Tools enthalten auch konkrete Beispiele. Ein Agent sollte direkt das passende typisierte Tool aufrufen, statt die allgemeine Shell-Hilfe auszuwerten. Insbesondere verwenden Fragen zum Schlaf `healthmd_sleep_sessions`; `healthmd extract` erzeugt eine andere kanonische Quelldatenprojektion.

In der portablen Vorschau können Sie dasselbe Schema lokal prüfen, ohne einen Netzwerk-Listener zu öffnen oder das iPhone zu kontaktieren. Verwenden Sie für den veröffentlichten Mac-Helfer MCP tools/list.

```bash
healthmd mcp schema healthmd_sleep_sessions
healthmd mcp schema healthmd_metric_chart
healthmd mcp schema # complete fixed catalog
```

Ein minimaler Schlafaufruf hat diese Form (die Inklusivdaten für die eigentliche Anfrage auflösen):

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-22",
      "end_date": "2026-07-28"
    }
  },
  "all_pages": true
}
```

Kanonische Schlafmetriken und verlustfreie Sitzungsdetails stellt `healthmd_sleep_sessions` automatisch bereit.

## Daten analysieren und grafisch darstellen

Rufen Sie zuerst `healthmd_doctor` auf und ermitteln Sie Metrik-IDs mit `healthmd_metrics`. In der veröffentlichten Mac-Topologie lesen typisierte Abfragetools den verschlüsselten Mac-Kontext; sie kontaktieren das iPhone nicht implizit. Rufen Sie für aktuelle Daten das Aktualisierungstool mit ausdrücklichen Datumsangaben, Metriken und Quellen auf, warten Sie auf den Abschluss des persistenten Auftrags und zeichnen Sie dann denselben Umfang:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-01",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps", "resting_heart_rate"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "all_pages": true
}
```

Übergeben Sie dieses Objekt an `healthmd_metric_chart`. Die interaktive Ansicht verwendet einheitensichere kleine Vielfache. Ein fehlender oder teilweiser Punkt unterbricht die Linie, anstatt zu Null zu werden.

Die veröffentlichten typisierten Mac-Tools werten verschlüsselten lokalen Kontext aus und geben begrenzte Seiten mit Abdeckung, fehlenden Daten, Nachweisen und Einschränkungen zurück. Nur eine ausdrückliche Aktualisierung kontaktiert das verbundene, im Vordergrund geöffnete iPhone und ersetzt den angeforderten Kontextumfang. Die portable Vorschau wertet jede typisierte Anfrage stattdessen direkt auf ihrem gekoppelten, im Vordergrund geöffneten iPhone aus.

## Export generierter Dateien ausführen

Wählen und speichern Sie zuerst in Health.md für Mac einen beschreibbaren Zielordner. Nachdem der Host die vollständigen Argumente angezeigt hat und der Benutzer zustimmt, rufen Sie `healthmd_export_files` auf:

```json
{
  "date_selection": "explicit_range",
  "date_range": {
    "start": "2026-07-01",
    "end": "2026-07-07"
  },
  "settings_policy": "requested_dates_only",
  "categories": ["Sleep"],
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

Für eine vollständige Historie verwenden Sie `date_selection: "all_available"` ohne `date_range`. Mit den optionalen Feldern `metric_ids`, `categories` oder `all_metrics` begrenzen Sie die iPhone-Erfassung, ohne gespeicherte Einstellungen zu ändern. `detail_level` gilt nur, wenn eine dieser Auswahlmöglichkeiten vorhanden ist. `all_metrics` kann nicht mit expliziten Metrik-/Kategorielisten kombiniert werden.

Um stattdessen ein gespeichertes Exportprofil auszuführen, setze `settings_policy` auf `"profile"` und übergib `profile_reference` mit der stabilen UUID. Der optionale `name` dient im öffentlichen Protokoll als Anzeige- und Fehlerkontext. Aktuelle Smartphone-Implementierungen können ihn nach einer fehlgeschlagenen ID-Suche berücksichtigen; das ist jedoch nicht umbenennungssicher. Automatisierung muss die UUID als stabile Identität behandeln:

```json
{
  "date_selection": "explicit_range",
  "date_range": { "start": "2026-07-01", "end": "2026-07-07" },
  "settings_policy": "profile",
  "profile_reference": { "profileID": "11111111-2222-4333-8444-555555555555" }
}
```

Das Profil besitzt den Einstellungsbereich: `profile_reference` lässt sich nicht mit `metric_ids`, `categories`, `all_metrics` oder der Gespeicherte-Einstellungen-Richtlinie kombinieren, und eine nicht auflösbare Referenz schlägt mit einem typisierten Fehler fehl, anstatt auf live Einstellungen zurückzufallen.

Die Beispiele oben verwenden das gebündelte Mac-Ziel. Beim portablen Direkt-MCP benötigt jeder Dateiexport zusätzlich einen vorhandenen absoluten Computerordner in `destination`; das Smartphone-Profil liefert Ausgabeeinstellungen, nicht diesen Hostpfad:

```json
{
  "date_selection": "explicit_range",
  "date_range": { "start": "2026-07-01", "end": "2026-07-07" },
  "settings_policy": "profile",
  "profile_reference": { "profileID": "11111111-2222-4333-8444-555555555555" },
  "destination": "/absolute/existing/HealthVault",
  "wait_timeout_seconds": 300
}
```

Portable Direktaufrufe weisen ein fehlendes, relatives, nicht vorhandenes oder symbolisch verknüpftes Ziel zurück, bevor der Smartphone-Auftrag startet.

Überprüfen:

- `status` und persistenter `state`;
- `job_id`;
- verarbeitete Tage, Gesamtzahl der Tage und Fortschritt;
- geschriebene Dateien oder tägliche Notizen;
- validiertes Desktop-Ziel;
- bestätigte Partitionen und Bytes;
- Grund für Pause oder Fehler sowie Ablaufzeitpunkt.

Eine Zeitüberschreitung oder ein geschlossener MCP-Wartevorgang bricht den persistenten Auftrag nicht ab. Überprüfen Sie `healthmd_export_job_status`, bevor Sie nach einem unbekannten Ergebnis fortfahren. Nur ein ausdrücklicher Abbruch beendet den Auftrag.

Der Roh- und kanonische Quellentransport kann Gigabytes an Routen, klinischem Text, Anhängen und Quellendatensätzen enthalten. Health.md überträgt diese Inhalte bewusst nicht in ein MCP-Gespräch. Verwenden Sie die validierte Streaming-CLI für Ausgaben in der Struktur der Quelle:

```bash
healthmd extract --metric workouts --last 30 --detail lossless --output workouts.json
healthmd export --iphone --all --raw --output health-corpus.json
```

Die MCP-Analyse bleibt eine abgeleitete sachliche Sichtweise; Exporte generierter Dateien verwenden weiterhin den öffentlichen `healthmd.health_data`-Vertrag über die produktiven Exporter.

## Paginierung und Vollständigkeit

Abfrage- und Nachweistools bieten `all_pages: true` an, sofern sie dies unterstützen. Der Helfer folgt opaken Cursorn, erkennt Zyklen und hält Gesamtobergrenzen für Bytes und Seiten ein. Jede versionierte Antwort bleibt unter `healthmd.mcp_query_pages` v1 erhalten. Wird eine Obergrenze der automatischen Paginierung erreicht, setzt der erfolgreiche Teil-Wrapper `receipt.traversal_complete` auf `false` und gibt den exakten Wert `receipt.next_cursor` für eine verlustfreie Fortsetzung zurück. Das iPhone behält den paginierten kompakten Snapshot bei Inaktivität im Vordergrund zehn Minuten lang und löscht ihn nach der letzten Seite oder beim Wechsel in den Hintergrund. Für eine Anfrage gelten Schutzgrenzen von 366.000 Tagen und 64 MiB codiertem Kompaktkontext. `query_scope_too_large` bedeutet, dass Sie Datumsbereiche oder Metrik-IDs auf mehrere Aufrufe verteilen müssen, nicht dass der logische Verlauf nicht verfügbar ist. Seiten begrenzen Listen fehlender Intervalle und Quelldeskriptoren; ausdrückliche Zähl-, Kürzungs- und Einschränkungsfelder weisen darauf hin.

Transporterfolg ist keine Vollständigkeit. Überprüfen Sie immer:

- angeforderter Umfang und Korpusstatus;
- Abdeckung und fehlende Intervalle;
- Einschränkungen und Nachweise;
- `next_cursor` oder Paginierungsbeleg;
- nicht zum Umfang gehörende Auslassungen;
- Quellschema und Version.

Die MCP-App zeigt diese Felder an, anstatt sie auszublenden. Wenn die automatische Paginierung ihre Sicherheitsobergrenze erreicht, schränken Sie den Bereich ein oder fahren Sie manuell fort.

## Sicherheits- und Datenschutzgrenzen

Der Helfer verfügt über keine Eingabeaufforderungen, Roots, Sampling, Shell, SQL, beliebige Dateilesevorgänge, beliebige URL-Abrufe, HealthKit-Schreibvorgänge, Loopback-HTTP-Dienste oder Remote-MCP-Endpunkte. Die einzige MCP-Ressource ist das mitgelieferte App-Dokument. Schreibvorgänge in generierte Dateien sind ein fester, genehmigungsgesteuerter Vorgang. Der veröffentlichte Mac-Helfer verwendet den in Health.md für Mac ausgewählten Ordner; die portable Vorschau erfordert ein ausdrückliches vorhandenes Ziel, das sie vor der Übertragung validiert und dauerhaft bindet.

Direkte Vertrauensstellung wird in Keychain, Secret Service oder Windows Credential Manager gespeichert. Beim Pairing wird das vorhandene authentifizierte verschlüsselte Protokoll verwendet. Das iPhone muss im Vordergrund stehen und explizit mit der LAN- oder Tailscale-Adresse des Computers verbunden sein. Abfrageseiten sind an die ausgehandelten Byte-/Elementgrenzen gebunden, und die automatische Aggregation aller Seiten weist zusätzliche Byte-/Seitenobergrenzen auf. Unbegrenzte Rohdateninhalte bleiben auf dem validierten Streaming-CLI-Pfad.

Health.md meldet sachliche Beobachtungen mit Einheiten, Herkunft, Abdeckung und fehlenden Daten. Es wird keine Diagnose gestellt, keine Behandlung empfohlen, keine Ursache abgeleitet oder eine Richtung zum Besseren oder Schlechteren angegeben.

## Fehlerbehebung

| Symptom | Aktion |
|---|---|
| Der Host kann den Helfer nicht starten | Verwenden Sie den absoluten Pfad der installierten `healthmd`-Datei oder `.exe` mit den Argumenten `mcp serve` |
| Der Helfer wartet bei Ausführung im Terminal | Erwartetes Verhalten; ein MCP-Host muss JSON-RPC über stdin senden |
| `healthmd_not_paired` | Führen Sie `healthmd direct pair` aus und schließen Sie die Kopplung auf dem iPhone ab |
| `healthmd_unavailable` | Entsperren Sie das iPhone, öffnen Sie Health.md im Vordergrund, aktivieren Sie Direct CLI Access und stellen Sie die Verbindung zum Computer her |
| `query_scope_too_large` | Verteilen Sie Datumsbereiche oder Metrik-IDs auf mehrere Aufrufe; das logische Korpus bleibt über mehrere Anfragen hinweg verfügbar |
| Kein interaktives Diagramm | Aktualisieren Sie den Host; der Server gibt weiterhin exaktes JSON und ersatzweise ein PNG-Metrikdiagramm zurück |
| Exportziel nicht verfügbar | Mac: Wählen Sie den gespeicherten Ordner in Health.md erneut aus. Portable Vorschau: Erstellen und übergeben Sie ein vorhandenes absolutes Desktop-Verzeichnis, das kein symbolischer Link ist. |
| Zeitüberschreitung beim Warten auf den Export | Prüfen Sie den persistenten Exportauftrag anhand der ID, bevor Sie ihn fortsetzen |
| Ergebnis hat `next_cursor` | Setzen Sie `all_pages: true` oder setzen Sie den Cursor manuell fort |

## Verwandt

<div class="related">
<a href="/de/docs/agents/"><span>Architektur</span>Lokale Agenten, verschlüsselter Kontext, Anfrageumfang und Nachweise.</a>
<a href="/de/docs/agent-queries/"><span>Analyse</span>Typisierte Abfragen für Metriken, Schlaf, Trainingseinheiten, Vergleiche und Abdeckung.</a>
<a href="/de/docs/cli-extract/"><span>Quelldaten</span>Validierte kanonische Extraktion für umfangreiche quellstrukturierte Ergebnisse.</a>
<a href="/de/docs/reference/evidence-packets/"><span>Verträge</span>Typisierte Werte, fehlende Daten, Nachweise und Paketidentitäten.</a>
</div>
