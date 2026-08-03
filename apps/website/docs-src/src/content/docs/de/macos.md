---
title: "macOS-App"
description: "Verwenden Sie Health.md für Mac als iPhone-Exportziel, lokalen CLI- und MCP-Host, verschlüsselten Speicher für Gesundheitskontext, Verlaufsanzeige und zentrale Instanz für den Zielordner."
---

Health.md für Mac erfüllt zwei lokale Aufgaben:

1. Die App empfängt Exportaufträge vom iPhone und schreibt Dateien in einen von Ihnen gewählten Ordner.
2. Sie hostet die Loopback-CLI, die Abfrage-API, den verschlüsselten Gesundheitskontext und den von lokalen Agenten verwendeten MCP-Adapter.

Apple Health verbleibt auf dem iPhone. Die Mac-App liest HealthKit nicht direkt.

## Hauptbereiche

<div class="options">
<div class="option"><strong>Synchronisierung</strong><p>Zeigt, ob der Mac auffindbar und für iPhone-Exportaufträge bereit ist.</p></div>
<div class="option"><strong>Zielordner</strong><p>Speichert ein security-scoped-Lesezeichen für Markdown-, JSON-, CSV-, Bases-, Roll-up-, ZIP- und Daily Note-Ausgaben.</p></div>
<div class="option"><strong>Zeitplan</strong><p>Zeigt den Zeitplan und die Einsatzbereitschaft auf dem Mac. Die HealthKit-Daten liefert weiterhin das iPhone.</p></div>
<div class="option"><strong>Verlauf</strong><p>Erfasst Exportergebnisse, wiederaufnehmbaren Fortschritt, Fehler und Wiederholungskontext für auf dem Desktop geschriebene Dateien.</p></div>
<div class="option"><strong>Einstellungen</strong><p>Zeigt die Verfügbarkeit des Ziels, Aufbewahrungsoptionen für verschlüsselten Kontext und die lokale CLI-Konfiguration.</p></div>
<div class="option"><strong>Menüleiste</strong><p>Bietet schnellen Zugriff auf Status, Einstellungen und App, während Health.md lokal verfügbar bleibt.</p></div>
<div class="option"><strong>CLI</strong><p>Installiert die mitgelieferten Helfer <code>healthmd</code> und <code>healthmd-mcp</code>, kopiert Einrichtungs-Prompts, installiert optional den Agenten-Skill und zeigt getestete Befehle.</p></div>
</div>

## Mac-Ziel einrichten

1. Installieren und öffnen Sie Health.md auf dem Mac.
2. Wählen Sie einen Zielordner auf einem lokalen Laufwerk, in iCloud Drive oder in einem Obsidian-Vault.
3. Aktivieren Sie auf dem iPhone im Tab „Synchronisierung“ die Mac-Verbindung.
4. Wählen Sie auf dem iPhone „Verbundener Mac“ als Exportziel.
5. Konfigurieren Sie den Export und tippen Sie auf „Export“.

Das iPhone erfasst HealthKit-Daten und eine Momentaufnahme der wirksamen Einstellungen. Aktuelle Gegenstellen übertragen begrenzte, mit Prüfsummen validierte Partitionen. Der Mac verwendet die produktiven Exporter und schreibt die angeforderten Dateien.

<div class="callout">
<strong>HealthKit-Einschränkung.</strong>
<p style="margin-top:6px;">Der Mac kann Apple Health nicht selbstständig abfragen. Für neue Exporte und Agentenkontext muss die verbundene iPhone-App geöffnet sein. Zwischengespeicherte verschlüsselte Abfragen können ohne neue iPhone-Verbindung ausgeführt werden, wenn die gespeicherte Abdeckung ausreicht.</p>
</div>

## CLI- und Agenteneinrichtung

Öffnen Sie in der Mac-App den Bereich **CLI**, um:

- die exakten Pfade der signierten Helfer in diesem App-Bundle anzuzeigen;
- Aliasse oder Befehle für symbolische Verknüpfungen unter `~/.local/bin` zu kopieren;
- einen Prompt für die Einrichtung durch einen Agenten zu kopieren;
- den optionalen Skill `healthmd-cli` in einem Ordner Ihrer Wahl zu installieren;
- aktuelle Befehle für Status, Diagnose, Extraktion, Abfrage, Schlaf, Training, Trainingseinheiten, Abdeckung und Export anzuzeigen;
- häufige Bereitschaftsfehler zu prüfen.

Die App bearbeitet niemals Startdateien Ihrer Shell und installiert ohne Ihr Zutun nichts in einem Systemverzeichnis.

Beginnen Sie mit:

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --category Sleep --yesterday
```

Informationen zur Backend-Auswahl finden Sie unter [Health.md CLI](/de/docs/cli/), die Abfragearchitektur unter [Lokale Agenten](/de/docs/agents/).

## Verschlüsselter Gesundheitskontext

Neue Abfragen und Nachweisanfragen verwenden einen eigenen Modus zur Kontexterfassung. Das iPhone liest exakt den angefragten Umfang für Metrik, Quelle, Datum und Detailtiefe. Dabei werden weder Exportdateien erzeugt noch gespeicherte Exporteinstellungen geändert.

Der Mac speichert die Daten jedes kompakten Inhabertags in einem separat authentifizierten AES-256-GCM-Blob. Ein nur auf diesem Gerät verfügbarer und im entsperrten Zustand zugänglicher Schlüsselbund-Eintrag enthält den zufälligen Verschlüsselungsschlüssel. Dateinamen sind zufällig und verraten weder Daten noch Metriknamen.

Die Einstellungen zeigen die Anzahl und den Datumsbereich der verschlüsselten Inhabertage. Zwei unabhängige Aktionen steuern die Aufbewahrung:

- **Älteren Kontext löschen** entfernt Inhabertage ausschließlich vor dem gewählten Stichtag.
- **Gesamten verschlüsselten Kontext löschen** entfernt alle Kontextdateien und den zugehörigen Schlüsselbund-Schlüssel.

Die Kontextaufbewahrung löscht niemals Apple Health-Daten, Exportdateien, Lesezeichen für Mac-Ziele oder Zugangsdaten verbundener Anbieter.

## Grenze der Loopback-API

Die Mac-App stellt lokale Routen für Status, Export, Abfragen, Nachweise, Aktualisierungen und persistente Aufträge auf `127.0.0.1` und `::1` an Port `17645` bereit.

Es gibt weder Bearer-Token noch Agentenregistrierung. Jeder lokale Prozess kann die API aufrufen, solange die App geöffnet ist. Stellen Sie den Port niemals einem anderen Rechner bereit und verwenden Sie dafür weder Proxy noch Tunnel.

Der sandboxgeschützte Helfer `healthmd-mcp` akzeptiert ausschließlich kanonische HTTP-Loopback-Endpunkte und stellt Tools ohne Shell, beliebige Dateien, SQL, URL-Abrufe, Ressourcen, Prompts, Roots oder Sampling bereit.

## Direct CLI Access ist getrennt

Die iPhone-Einstellung **Direct CLI Access** schafft eine separate Vertrauensbeziehung zwischen einer direktfähigen CLI und dem iPhone. Sie kann die Mac-App für Rohdatenexporte, kanonische Extraktion, generierte Dateien, Status, Fortsetzung und Abbruch umgehen.

Der direkte Modus verwendet nicht den verschlüsselten Abfragekontext der Mac-App. Stattdessen führt das portable `healthmd mcp serve` neue typisierte Abfragen direkt auf dem im Vordergrund geöffneten iPhone aus und verwendet dabei dieselbe ausführbare Identität wie bei der Kopplung. Informationen zu Kopplung und Plattformunterstützung finden Sie unter [Direkte iPhone-CLI](/de/docs/cli-direct/).

## Verwandte Themen

<div class="related">
  <a href="/de/docs/sync/"><span>Ziel</span>Mac-Synchronisierung: Koppeln Sie iPhone und Mac für lokale Dateiexporte.</a>
  <a href="/de/docs/cli/"><span>Terminal</span>Health.md CLI: Installieren Sie Helfer, wählen Sie ein Backend und führen Sie Befehle aus.</a>
  <a href="/de/docs/agents/"><span>Lokaler Kontext</span>Agenten: begrenzte Erfassung, verschlüsselte Speicherung, Nachweise und Aufbewahrung.</a>
  <a href="/de/docs/mcp/"><span>Tools</span>Lokaler MCP-Server: Einrichtung, Toolkatalog und Sandbox-Grenzen.</a>
  <a href="/de/docs/scheduling/"><span>Workflow</span>Zeitplanung: Automatisieren Sie wiederkehrende Exporte.</a>
</div>
