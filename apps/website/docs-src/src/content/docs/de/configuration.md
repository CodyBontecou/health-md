---
title: Agenten konfigurieren
description: Wählen Sie die MCP- oder CLI-Schnittstelle von Health.md, konfigurieren Sie Codex, Claude oder einen anderen lokalen Client und verbinden Sie ein gekoppeltes iPhone, ohne HealthKit über einen Cloud-Dienst zu leiten.
---

Die veröffentlichte Mac-App enthält zwei signierte lokale Helfer: `healthmd-mcp` für typisierte Agententools und `healthmd` für explizite CLI-Workflows. Eine separate plattformübergreifende CLI mit direktem iPhone-MCP ist als Vorschau dokumentiert, bis ihr erstes öffentliches Paket die Release-QA auf einem physischen Gerät abgeschlossen hat.

<div class="callout">
<strong>HealthKit bleibt auf dem iPhone.</strong>
<p style="margin-top:6px;">Durch die Konfiguration erhält ein lokaler Client Zugriff auf die begrenzten Schnittstellen von Health.md. Sie gewährt dem Computer oder Agenten keinen direkten HealthKit-Zugriff und lädt Ihren Quelldatenbestand nicht in eine Health.md-Cloud hoch.</p>
</div>

## Schnittstelle auswählen

| Ziel | Einstieg | Weiterführend |
|---|---|---|
| Codex oder Claude auf dem Mac Gesundheitsdaten abfragen und visualisieren lassen | Mitgeliefertes `healthmd-mcp` über stdio | [MCP-Server & Tools](/de/docs/mcp/) |
| Kanonisches JSON oder generierte Dateien in einem Mac-Skript exportieren | Mitgelieferte `healthmd` CLI | [CLI](/de/docs/cli/) |
| Ohne Mac-App direkt eine Verbindung zu einem geöffneten iPhone herstellen | Portable direkte CLI (**Vorschau**) | [Direkter iPhone-Zugriff](/de/docs/cli-direct/) |
| Auf Grundlage exakter Anfrage- und Antwort-API-Envelopes entwickeln | Loopback-API oder öffentliche Verträge | [Loopback-API](/de/docs/agent-api/) |
| Schemas, Datensätze, Nachweise oder generierte Fixtures verarbeiten | Versionierte Referenz | [Datenverträge](/de/docs/reference/) |

Backend und Übertragungsweg wählen Sie ausdrücklich aus; Health.md wechselt nicht unbemerkt vom direkten iPhone-Zugriff zur Mac-App.

## Codex mit der Mac-App

<div class="availability available">
<strong>Jetzt verfügbar · signierter Mac-Helfer</strong>
<p>Installieren Sie Health.md für Mac, öffnen Sie den Bildschirm <strong>CLI</strong> und kopieren Sie den angezeigten Pfad des mitgelieferten MCP-Helfers, wenn sich die App nicht unter <code>/Applications</code> befindet.</p>
</div>

Fügen Sie den separaten signierten `healthmd-mcp`-Helfer zu `~/.codex/config.toml` hinzu:

```toml
[mcp_servers.healthmd]
command = "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
args = []
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"
```

Starten Sie Codex neu, rufen Sie `healthmd_doctor` auf, ermitteln Sie IDs mit `healthmd_metrics`, erfassen Sie mit dem Aktualisierungstool ausdrücklich einen kleinen Umfang und fragen Sie diesen dann mit einem typisierten Tool wie `healthmd_metric_chart` ab. Der mitgelieferte Server stellt 21 Tools bereit, darunter Mac-Bereitschaft, Aktualisierungsaufträge für verschlüsselten Kontext, Nachweise und Visualisierungen.

## Claude Desktop oder Claude Code auf dem Mac

Fügen Sie den mitgelieferten Helfer zur MCP-Konfiguration von Claude Desktop oder zu einer vertrauenswürdigen `.mcp.json` von Claude Code hinzu:

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

Starten Sie den Client neu, nachdem Sie seine Konfiguration geändert haben. Projektbezogene Konfigurationen erfordern weiterhin Vertrauen in den Workspace und eine ausdrückliche Serverfreigabe. Lassen Sie die Mac- und iPhone-Apps geöffnet, wenn ein Tool aktuelle HealthKit-Daten benötigt.

## Beliebiger stdio-MCP-Client auf dem Mac

Konfigurieren Sie einen lokalen Prozess:

```text
command: /Applications/Health.md.app/Contents/Helpers/healthmd-mcp
arguments: none
transport: stdio
```

Der Host verwaltet stdin und den Prozesslebenszyklus. Starten Sie den Helfer nicht als normalen interaktiven Befehl und umschließen Sie ihn nicht mit einer Shell, die die JSON-RPC-Ausgabe verändert. Verwenden Sie MCP `tools/list`, um die exakten Schemas zu ermitteln, die von der installierten App bereitgestellt werden.

## Portable direkte Einrichtung

<div class="availability preview">
<strong>Vorschau · noch nicht öffentlich paketiert</strong>
<p>Die plattformübergreifende Rust-CLI, <code>healthmd setup codex</code>, <code>healthmd mcp serve</code> aus derselben Binärdatei sowie die direkte Kopplung unter Linux/Windows sind implementiert, warten aber noch auf ihre erste qualifizierte öffentliche Veröffentlichung.</p>
</div>

Nach der Veröffentlichung wird `healthmd setup codex` Codex idempotent konfigurieren und die direkte iPhone-Kopplung starten. Verlassen Sie sich bis dahin nicht auf unveröffentlichte Homebrew-, crates.io-, Installationsprogramm- oder GitHub-Release-URLs. Die Seite [Direkte iPhone-CLI](/de/docs/cli-direct/) beschreibt das geplante Übertragungs- und Protokollverhalten.

## Explizite CLI-Workflows

Rufen Sie für die kanonische Extraktion oder dateiorientierte Automatisierung `healthmd` direkt auf, statt einen MCP-Host einen großen Quellinhalt übertragen zu lassen:

```bash
healthmd status
healthmd extract --category Sleep --last 7 --output sleep.json
healthmd export --last 7 --destination "$HOME/Documents/HealthVault"
```

Verfügbarkeit und Befehlssyntax unterscheiden sich zwischen dem mitgelieferten Mac-Helfer und der eigenständigen plattformübergreifenden CLI. Lesen Sie [Health.md CLI](/de/docs/cli/), bevor Sie Befehle in unbeaufsichtigte Automatisierungen übernehmen.

## Portable Kopplung und Bereitschaft

<div class="availability preview">
<strong>Vorschau · portable direkte Workflows</strong>
<p>Diese Schritte beschreiben das kommende plattformübergreifende Paket. Der veröffentlichte mitgelieferte Mac-MCP-Pfad verwendet stattdessen die bestehende iPhone-Verbindung der Mac-App.</p>
</div>

Direkte MCP- und CLI-Workflows erfordern eine einmalige vertrauenswürdige Kopplung mit Health.md auf dem iPhone. Die Kopplung verwendet einen authentifizierten, verschlüsselten Kanal und die native Anmeldedatenspeicherung unter macOS, Linux oder Windows.

1. Aktivieren Sie **Direct CLI-Zugriff** in Health.md auf dem iPhone.
2. Starten Sie die Kopplung über `healthmd setup codex` oder `healthmd direct pair`.
3. Genehmigen Sie die begrenzte Kopplungsanfrage auf dem iPhone.
4. Lassen Sie Health.md im Vordergrund geöffnet, wenn Sie eine Abfrage oder einen Export starten.
5. Rufen Sie vor umfangreicheren Aufgaben `healthmd_doctor` in MCP oder `healthmd status` in der portablen CLI auf.

Unter [Direkter iPhone-Zugriff](/de/docs/cli-direct/) finden Sie Einzelheiten zu Manual IP, Tailscale, Port, vertrauenswürdigen Geräten, Vordergrundbetrieb und Wiederherstellung.

## Konfigurationsgrenzen

Eine lokale Agentenkonfiguration gewährt **nicht**:

- beliebige HealthKit-Lese- oder Schreibzugriffe;
- beliebigen Dateisystemzugriff;
- beliebige URLs, Shell-Befehle, Prompts, Roots oder Sampling über MCP;
- die Berechtigung, fehlende Daten, Abdeckung, Einheiten, Nachweise oder Einschränkungen zu verbergen;
- die Berechtigung, generierte Dateien ohne die erforderliche Genehmigung fortzusetzen, abzubrechen oder zu überschreiben.

Prüfen Sie für ein vollständiges Ergebnis den angeforderten Umfang, die Abdeckung, die Paginierung, die Einschränkungen und das Quellschema — nicht nur den erfolgreichen Prozessabschluss.

## Weiterführend

<div class="related">
  <a href="/de/docs/mcp/"><span>Toolschnittstelle</span>Prüfen Sie die 21 veröffentlichten Mac-Tools, die portable Vorschau mit 19 Tools, MCP Apps, Schemas, Paging, Exporte und Sandbox-Grenzen.</a>
  <a href="/de/docs/agent-queries/"><span>Erste Fragen</span>Führen Sie typisierte Workflows für Metriken, Schlaf, Trainingseinheiten, Vergleiche, Abdeckung und Nachweise aus.</a>
  <a href="/de/docs/cli-extract/"><span>Kanonische Daten</span>Extrahieren Sie ausgewählte Schema-v7-Dokumente und Quelldatensätze, ohne große Inhalte in einen Chat zu stellen.</a>
  <a href="/de/docs/reference/"><span>Verträge</span>Durchsuchen Sie versionierte Datenstrukturen, Feldinventare, generierte Fixtures und Integrationsrezepte.</a>
</div>
