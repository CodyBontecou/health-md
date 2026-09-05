---
title: "Einen Agenten in 10 Minuten verbinden"
description: "Verbinden Sie den freigegebenen Health.md Mac-MCP-Helfer mit Codex oder Claude, holen Sie einen expliziten iPhone-Umfang ab, führen Sie eine begrenzte Abfrage aus und prüfen Sie die Vollständigkeit sicher."
---

<div class="availability available">
<strong>Ab sofort verfügbar · Health.md für Mac</strong>
<p>Dieser Weg nutzt den signierten <code>healthmd-mcp</code>-Helfer, der mit der freigegebenen Mac-App mitgeliefert wird. Er verwendet weder die portable CLI-Vorschau, Direct CLI Access oder einen Kopplungs-QR-Code noch Port 17647.</p>
</div>

Sie verbinden einen lokalen MCP-Host, prüfen die Bereitschaft, ohne Gesundheitswerte zu lesen, holen ausdrücklich einen kleinen Umfang vom iPhone und fragen diesen verschlüsselten Mac-Kontext ab. Planen Sie etwa zehn Minuten ein, wenn beide Apps bereits installiert sind und sich im selben lokalen Netzwerk befinden.

## 1. Health.md installieren und öffnen

[Laden Sie Health.md aus dem App Store herunter](https://apps.apple.com/us/app/health-md/id6757763969), auf dem Mac und auf dem iPhone. Öffnen Sie beide Apps.

HealthKit bleibt auf dem iPhone. Die Mac-App hostet den signierten MCP-Helfer und einen verschlüsselten, verwerfbaren Abfragekontext; sie liest HealthKit nicht selbst aus.

## 2. iPhone und Mac verbinden

1. Lassen Sie Health.md auf dem Mac geöffnet.
2. Öffnen Sie auf dem iPhone **Health.md → Synchronisierung** und aktivieren Sie die Mac-Konnektivität.
3. Halten Sie beide Geräte im selben erreichbaren lokalen Netzwerk und lassen Sie Health.md auf dem iPhone im Vordergrund, solange neue Arbeit beginnt.
4. Bestätigen Sie, dass die Mac-App die beabsichtigte iPhone-Verbindung anzeigt. Wenn nicht, öffnen Sie beide Apps erneut und sehen Sie sich die [Mac-Sync-Bereitschaft](/de/docs/sync/) an.

Dies ist die freigegebene Mac-Verbindung. Führen Sie `healthmd direct pair` nicht aus; dieser Befehl gehört zur separaten portablen Vorschau.

## 3. Signierten Helferpfad kopieren

Öffnen Sie **Health.md für Mac → CLI** und kopieren Sie den angezeigten MCP-Helferpfad. Eine normale `/Applications`-Installation verwendet:

```text
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

Verwenden Sie den angezeigten Pfad, wenn die App an einem anderen Ort installiert ist. Konfigurieren Sie den Helfer direkt — ummanteln Sie ihn nicht mit einer Shell und starten Sie ihn nicht als interaktiven Befehl.

## 4. Codex oder Claude konfigurieren

### Codex

Fügen Sie dies zu `~/.codex/config.toml` hinzu und ersetzen Sie bei Bedarf den Helferpfad:

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

Starten Sie Codex neu, nachdem Sie die Datei gespeichert haben.

### Claude Desktop oder Claude Code

Fügen Sie diesen lokalen stdio-Eintrag zur MCP-Konfiguration von Claude Desktop oder zu einer vertrauenswürdigen `.mcp.json` von Claude Code hinzu:

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

Starten Sie Claude Desktop neu, oder vertrauen Sie dem Claude-Code-Workspace und genehmigen Sie den Server. Lassen Sie Genehmigungsaufforderungen für Aktualisierungs-, Export-, Fortsetzungs- und Abbruchvorgänge aktiviert.

## 5. Bereitschaft prüfen

Rufen Sie `healthmd_doctor` auf. Es liest ausschließlich die Bereitschaft, ohne Gesundheitswerte.

Ein bereites Ergebnis enthält diese Felder:

```json
{
  "schema": "healthmd.local_readiness",
  "schema_version": 1,
  "status": "ready"
}
```

Das vollständige Ergebnis enthält außerdem Prüfungen und nächste Schritte. Lösen Sie jede blockierende Prüfung, bevor Sie fortfahren. Ein verbundener Helfer beweist **nicht**, dass der verschlüsselte Kontext aktuell ist.

Rufen Sie anschließend `healthmd_metrics` auf und bestätigen Sie die kanonische Metrik-ID und die Einheit, die Sie abfragen möchten. Diese Anleitung verwendet `steps` nur als Beispiel.

## 6. Ausdrücklich einen kleinen Umfang aktualisieren

Legen Sie die Daten fest, die Sie tatsächlich abfragen wollen, und rufen Sie dann `healthmd_refresh` mit einem exakten, inklusiven Zeitraum auf. Das Beispiel fordert einen einzelnen Tag zusammengefasster Daten an:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-14",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

Prüfen Sie die Argumente, genehmigen Sie die Erfassung und lassen Sie beide Apps geöffnet. Die Aktualisierung schreibt keine Exportdateien und ändert die gespeicherten iPhone-Exporteinstellungen nicht. Bewahren Sie die zurückgegebene `job_id` auf, bis der Auftrag einen Endzustand erreicht hat.

## 7. Erste begrenzte Abfrage ausführen

Rufen Sie nach Abschluss der Aktualisierung `healthmd_metric_chart` mit denselben Daten, derselben Metrik, derselben Quellenauswahl und derselben Detailebene auf:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-14",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "all_pages": true
}
```

`all_pages: true` durchläuft opake Cursor nur innerhalb der aggregierten Seiten- und Byte-Obergrenzen des Helfers. Rufen Sie für Schlaf `healthmd_sleep_sessions` auf, statt eine kanonische Extraktion zu ersetzen.

## 8. Vollständigkeit prüfen, bevor Sie antworten

Betrachten Sie den Erfolg eines Tools nicht als Beweis für vollständige Gesundheitsabdeckung. Prüfen Sie alles Folgende:

- die Aktualisierung hat für dieselben exakten Daten, Metriken, Quellen und dieselbe Detailebene einen erfolgreichen Endzustand erreicht;
- Antwortschema und -version werden erkannt;
- der angeforderte Zeitraum und die Zeitzone passen zur Frage;
- jeder genannte Wert behält seine kanonische Metrik-ID und Einheit;
- Abdeckungsstatus, berücksichtigte Tage, Tage mit Werten und jedes fehlende Intervall werden gemeldet;
- `complete_empty`, `partial`, `failed`, `unsupported`, `skipped` und `cancelled` werden nicht in Null umgewandelt;
- die Durchquerung ist abgeschlossen, oder jeder verbleibende Cursor bzw. jede aggregierte Obergrenze wird offengelegt;
- Nachweis- und Quellendeskriptoren sowie Einschränkungen bleiben an der Antwort hängen;
- die sachliche Aussage wird nicht in Diagnose, Behandlungsempfehlungen, Kausalität oder „besser/schlechter“-Formulierungen verwandelt.

### Teilergebnisse lesen, ohne nützliche Daten zu verwerfen

Eine typisierte Abfrage kann ein gültiges `healthmd.query_response` zurückgeben, obwohl nur ein Teil des angeforderten Umfangs abgeschlossen wurde. Das generierte [Fixture für partielle Abfrageantworten](/docs/reference/generated/automation/agent-query-response-partial.json) behält ein verfügbares Steps-Element und meldet den fehlgeschlagenen Tag separat:

```json
{
  "schema": "healthmd.query_response",
  "schema_version": 1,
  "coverage": {
    "status": "partial",
    "days_considered": 2,
    "days_with_values": 1,
    "missing": [
      {
        "status": "failed",
        "range": {
          "start_date": "2026-03-16",
          "end_date": "2026-03-16"
        }
      }
    ]
  },
  "items": ["one retained typed item"],
  "limitations": ["one or more requested days did not complete"]
}
```

Die Zeichenfolgen in `items` und `limitations` oben sind erläuternde Abkürzungen; verwenden Sie das herunterladbare generierte Fixture für die exakten Felder und Nachweise. Bewahren Sie das behaltene Element, das fehlgeschlagene Intervall, die Abdeckungszählungen und die Einschränkung gemeinsam auf.

Fügen Sie `status: "partial_success"` nicht zu `healthmd.query_response` hinzu. Dieser Status gehört zu übergeordneten CLI- und Export-Envelopes, wenn Erfassung, Durchquerung oder Dateierzeugung unvollständig sind. Eine Zeitüberschreitung ist wieder etwas anderes: Sie ist ein unbekanntes Ergebnis eines persistenten Auftrags, das anhand der Auftrags-ID geprüft werden muss.

Strukturierte Fehler verwenden `healthmd.query_error` v1 statt einer Teilantwort. Sehen Sie sich [agent-query-error.json](/docs/reference/generated/automation/agent-query-error.json) für die generierte Produktionsform mit stabilem Code, Meldung, Wiederholbarkeit und typisierten Details an.

## 9. Sicher von einer Zeitüberschreitung erholen

Eine Zeitüberschreitung, ein geschlossener Host oder ein abgebrochener MCP-Wartevorgang bricht eine akzeptierte Aktualisierung nicht ab.

1. Bewahren Sie die zurückgegebene `job_id` auf.
2. Rufen Sie `healthmd_job_status` mit dieser ID auf.
3. Wenn der unveränderliche Auftrag fortsetzbar ist, prüfen und genehmigen Sie `healthmd_job_resume` mit derselben ID und einem endlichen Warte-Timeout.
4. Starten Sie eine neue Aktualisierung erst, nachdem der Status beweist, dass kein akzeptierter Auftrag mehr abgeschlossen werden kann.
5. Verwenden Sie `healthmd_job_cancel` nur, wenn Sie den Auftrag beenden wollen; der Abbruch ist erst nach Bestätigung durch das iPhone endgültig.

Wiederholen Sie nach einem unbekannten Ergebnis niemals blindlings. Persistente Aktualisierungsaufträge bewahren den akzeptierten Umfang und den bestätigten Fortschritt.

## Sie sind verbunden

Der erste schreibgeschützte Arbeitsablauf ist abgeschlossen, wenn doctor bereit ist, die ausdrückliche Aktualisierung einen Endzustand erreicht hat, die begrenzte Abfrage vollständig durchlaufen wurde und Sie Abdeckung, Nachweise, Einheiten und Einschränkungen geprüft haben.

Exporte generierter Dateien sind ein separater, genehmigungsgesteuerter Arbeitsablauf. Das freigegebene Mac-Tool schreibt in den Ordner, der bereits in Health.md für Mac ausgewählt wurde; es akzeptiert kein beliebiges Zielargument.

<div class="related">
  <a href="/de/docs/mcp/"><span>Toolkatalog</span>Alle freigegebenen Mac-Tools, exakte Schemas, MCP Apps, Paginierung und Sicherheitsgrenzen.</a>
  <a href="/de/docs/configuration/"><span>Andere Clients</span>Wählen Sie zwischen der freigegebenen Mac-Integration und der klar gekennzeichneten portablen Vorschau.</a>
  <a href="/de/docs/agent-queries/"><span>Nächste Fragen</span>Führen Sie typisierte Metrik-, Schlaf-, Trainings-, Vergleichs-, Abdeckungs- und Nachweis-Workflows aus.</a>
  <a href="/de/docs/agents/"><span>Vertrauensmodell</span>Verstehen Sie verschlüsselten Kontext, Anfrageumfang, Aufbewahrung, Nachweise und Berichtsregeln.</a>
</div>
