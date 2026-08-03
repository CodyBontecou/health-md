---
title: Einstieg in Health.md.
description: Exportieren Sie Apple Health- oder Health Connect-Daten, verbinden Sie den signierten Mac-Helfer mit einem lokalen Agenten und entwickeln Sie auf Grundlage versionierter Health.md-Verträge.
---

<div class="docs-hero" data-strand-stage>
  <canvas class="docs-dna" data-three-strand aria-hidden="true"></canvas>
  <div class="docs-hero-copy">
    <p class="docs-eyebrow">Jetzt verfügbar · signierter Mac-Helfer</p>
    <p>Exportieren Sie Gesundheitsdaten von Ihrem Smartphone, verbinden Sie einen lokalen Agenten über die signierten Mac-Helfer oder entwickeln Sie auf Grundlage versionierter Verträge. HealthKit-Lesevorgänge bleiben auf dem iPhone und Health Connect-Lesevorgänge auf Android.</p>
    <div class="docs-command" aria-label="Mitgelieferter Health.md-Bereitschaftsbefehl"><span aria-hidden="true">$</span> "/Applications/Health.md.app/Contents/Helpers/healthmd" doctor</div>
    <p class="docs-command-note">An einem anderen Ort installiert? Kopieren Sie den Pfad des mitgelieferten Helfers unter <strong>Health.md for Mac → CLI</strong>.</p>
    <div class="docs-actions">
      <a class="docs-button" href="/de/docs/iphone-first-export/">Erster iPhone-Export</a>
      <a class="docs-button-secondary" href="/de/docs/configuration/">Agenten verbinden</a>
      <a class="docs-button-secondary" href="/de/docs/reference/">Verträge durchsuchen</a>
    </div>
  </div>
</div>

<div class="agent-path" aria-label="Ziel für Health.md auswählen">
  <a href="/de/docs/iphone-first-export/"><span>01 · Exportieren</span><strong>Auf dem iPhone beginnen</strong>Autorisieren Sie Apple Health, wählen Sie einen Ordner, prüfen Sie die Vorschau und führen Sie den ersten Export aus.</a>
  <a href="/de/docs/configuration/"><span>02 · Fragen</span><strong>Lokalen Agenten verbinden</strong>Verwenden Sie den signierten Mac-MCP-Helfer mit Codex, Claude oder einem anderen stdio-Client.</a>
  <a href="/de/docs/reference/"><span>03 · Entwickeln</span><strong>Stabile Verträge verwenden</strong>Integrieren Sie Schemas, Datensätze, Nachweise, generierte Fixtures und exakte API-Envelopes.</a>
</div>

<div class="reference-stats">
<div><strong>21</strong><span>mitgelieferte Mac-MCP-Tools</span></div>
<div><strong>4</strong><span>Exportformate</span></div>
<div><strong>v7</strong><span>öffentliches Exportschema</span></div>
<div><strong>0</strong><span>erforderliche Umwege über eine Health.md-Cloud</span></div>
</div>

<p class="docs-section-kicker">Jetzt verfügbar · macOS</p>

## Schnellstart für lokale Agenten in fünf Minuten

Öffnen Sie Health.md auf dem Mac. Öffnen Sie dann Health.md auf dem gekoppelten iPhone und warten Sie, bis die Verbindung hergestellt ist. Der mitgelieferte Helfer prüft die Bereitschaft, ohne Gesundheitswerte zurückzugeben, listet Schlafmetriken auf und führt eine Abfrage für einen Tag aus:

```bash
HMD="/Applications/Health.md.app/Contents/Helpers/healthmd"
"$HMD" doctor
"$HMD" metrics list --category Sleep
"$HMD" query --category Sleep --yesterday
```

Ein bereites `doctor`-Ergebnis verwendet das Schema `healthmd.cli_doctor` und enthält die nächsten Schritte, wenn die Einrichtung unvollständig ist. Fahren Sie für Codex oder Claude mit [Agenten konfigurieren](/de/docs/configuration/) fort und verweisen Sie den Client auf den separaten signierten `healthmd-mcp`-Helfer.

<p class="docs-section-kicker">Nach Ziel auswählen</p>

## Konfigurieren und verbinden

<div class="related">
  <a href="/de/docs/configuration/"><span>Jetzt verfügbar · Mac</span>Konfiguration — verbinden Sie Codex, Claude oder einen anderen stdio-Client mit dem signierten MCP-Helfer.</a>
  <a href="/de/docs/mcp/"><span>Jetzt verfügbar · Mac</span>MCP-Server &amp; App — entdecken Sie 21 mitgelieferte Tools, erstellen Sie private Visualisierungen und lernen Sie die portable Vorschau kennen.</a>
  <a href="/de/docs/cli/"><span>Jetzt verfügbar · Mac</span>Health.md CLI — installieren Sie den mitgelieferten Helfer, prüfen Sie die Bereitschaft, fragen Sie Daten ab und unterscheiden Sie die portable Vorschau.</a>
  <a href="/de/docs/agents/"><span>Architektur</span>Agentenkontext — erfahren Sie mehr über den Anfrageumfang, lokales Vertrauen, verschlüsselten Kontext, Nachweise, Aufbewahrung und Datenschutz.</a>
</div>

<p class="docs-section-kicker">Täglicher Betrieb</p>

## Abfragen, extrahieren und automatisieren

<div class="related">
  <a href="/de/docs/agent-queries/"><span>Typisierte Abfragen</span>Fragen Sie Metriken, Schlafphasen, Trainingseinheiten, Vergleiche, Abdeckung und sachliche Nachweise ab.</a>
  <a href="/de/docs/cli-direct/"><span>Vorschau · portable CLI</span>Direkter iPhone-Zugriff — informieren Sie sich vor der Veröffentlichung des eigenständigen Pakets über die Kopplung per Manual IP oder Tailscale.</a>
  <a href="/de/docs/cli-extract/"><span>Quelldaten</span>Kanonische Extraktion — beziehen Sie ausgewählte Schema-v7-Tage, Quelldatensätze, Projektionen oder JSONL.</a>
  <a href="/de/docs/cli-jobs/"><span>Zuverlässige Ausführungen</span>Persistente Aufträge — behandeln Sie Zeitüberschreitungen, unbekannte Ergebnisse, Fortsetzung, Abbruch und Teilergebnisse sicher.</a>
  <a href="/de/docs/agent-api/"><span>Low-Level</span>Loopback-API — verwenden Sie exakte Routen für Abfragen, Nachweise, Cursor, Aktualisierung und persistente Aufträge.</a>
  <a href="/de/docs/reference/integration-recipes/"><span>Muster</span>Integrationsrezepte — analysieren und validieren Sie Health.md-Ausgaben, ohne deren Verträge abzuschwächen.</a>
</div>

<p class="docs-section-kicker">Stabile Schnittstellen</p>

## Datenverträge und Strukturen

<div class="related">
  <a href="/de/docs/reference/"><span>Vertragsübersicht</span>Exportreferenz — durchsuchen Sie Schemas, Metriken, Formate, Datensätze und Interoperabilitäts-Fixtures.</a>
  <a href="/de/docs/reference/api-and-cli/"><span>Automatisierung</span>API- &amp; CLI-Verträge — prüfen Sie API-Envelopes, Routen, Exit-Verhalten und generierte Beispiele.</a>
  <a href="/de/docs/reference/evidence-packets/"><span>Agentenergebnisse</span>Abfragen &amp; Nachweise — typisierte Werte, Abdeckung, fehlende Daten, Operationen und deterministische Identitäten.</a>
  <a href="/de/docs/reference/daily-records/"><span>Schema v7</span>Tagesdatensätze — lernen Sie das öffentliche Quelldokument und seine Regeln zur Datumszuordnung kennen.</a>
  <a href="/de/docs/shared-metric-registry/"><span>Vokabular</span>Metrikregister — verwenden Sie stabile plattformübergreifende Metrik-IDs, Kategorien, Einheiten und Profilmetadaten.</a>
  <a href="/de/docs/reference/generated/"><span>Maschinenlesbar</span>Generierte Artefakte — öffnen Sie kanonische Felder, Fixtures, Nachrichteninventare und CLI-Verträge.</a>
</div>

<p class="docs-section-kicker">Produktworkflows</p>

## Apps und Exporte

<div class="related">
  <a href="/de/docs/iphone-first-export/"><span>Hier beginnen · iPhone</span>Erster Export — autorisieren Sie Apple Health, wählen Sie einen Ordner, prüfen Sie die Vorschau und verifizieren Sie die geschriebenen Dateien.</a>
  <a href="/de/docs/android/"><span>Android</span>Health Connect — wählen Sie einen Ordner eines Dokumentanbieters und konfigurieren Sie die Plattformautomatisierung.</a>
  <a href="/de/docs/export/"><span>Dateien</span>Export — exportieren Sie explizite Datumsbereiche in Markdown, CSV, JSON oder Obsidian Bases.</a>
  <a href="/de/docs/format/"><span>Struktur</span>Formatanpassung — steuern Sie Einheiten, Datumsangaben, frontmatter, Dateinamen und Schreibverhalten.</a>
  <a href="/de/docs/scheduling/"><span>Hintergrund</span>Zeitplanung — verstehen Sie das Verhalten täglicher und wöchentlicher Exporte sowie Plattformgrenzen.</a>
  <a href="/de/docs/shortcuts/"><span>Automatisierung</span>Kurzbefehle &amp; App Intents — lösen Sie Exporte, Zusammenfassungen und Statusprüfungen aus Apple-Workflows aus.</a>
</div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:12px; font-family:var(--sl-font-mono);">Dokumentationsstruktur aktualisiert am 2. August 2026</p>
