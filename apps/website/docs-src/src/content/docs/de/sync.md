---
title: "Mac-Synchronisierung"
description: "Verwenden Sie die macOS-Begleit-App als lokales Ziel. Ihr iPhone erfasst HealthKit-Daten und Einstellungen; anschließend rendert und schreibt der Mac die angeforderten Dateien."
---

## Funktionsweise
<p>Mit der Mac-Synchronisierung kann Ihr Mac Exporte erzeugen, ohne selbst HealthKit zu lesen. Das iPhone bleibt die maßgebliche Quelle für Apple Health-Daten: Es erfasst die ausgewählten Tagesdaten und eine exakte Momentaufnahme der Einstellungen und überträgt den Auftrag anschließend an den Mac. Der Mac verwendet die gemeinsamen Exporter, um Pfade zu planen, die gewünschten Formate zu rendern und die Dateien in den ausgewählten Zielordner zu schreiben.</p>

<div class="doc-diagram">
  <div class="flow-steps" aria-label="Exportablauf der Mac-Synchronisierung">
    <span><strong>iPhone</strong>Erfasst HealthKit-Daten und eine Momentaufnahme der wirksamen Einstellungen.</span>
    <span><strong>Lokales Netzwerk</strong>Überträgt den versionierten Auftrag an die Mac-App in der Nähe.</span>
    <span><strong>Mac</strong>Rendert die ausgewählten Formate und schreibt sie in den gewählten Ordner.</span>
    <span><strong>Vault</strong>Der fertige Export landet in Obsidian, iCloud Drive oder einem beliebigen lokalen Ordner.</span>
  </div>
</div>

## Aktivierung
<ol>
<li>Installieren und öffnen Sie die macOS-App.</li>
<li>Wählen Sie auf dem Mac einen Zielordner, damit Health.md Schreibzugriff erhält.</li>
<li>Öffnen Sie auf dem iPhone den Tab „Synchronisierung“ und aktivieren Sie die Mac-Verbindung.</li>
<li>Kehren Sie zum Tab „Export“ zurück, wählen Sie <em>Verbundener Mac</em>, konfigurieren Sie den Export und tippen Sie auf „Export“.</li>
</ol>

## Übertragene Daten
<ul>
<li>Eine versionierte Exportanfrage mit Datumsbereich und wirksamen Einstellungen</li>
<li>Fortschritts- und Funktionsmeldungen, während das iPhone HealthKit-Daten erfasst</li>
<li>Begrenzte, mit Prüfsummen validierte Frames mit erfassten Tagesdaten und der exakten Momentaufnahme der Einstellungen für Dateischreibaufträge</li>
<li>Ein strukturiertes Ergebnis für Abschluss, Teilerfolg, Fehler, Ablehnung oder Nichtverfügbarkeit</li>
</ul>
<p>Weder ein Konto noch eine entfernte Cloud für Gesundheitsdaten ist erforderlich. Die Synchronisierung in der Nähe verwendet verschlüsselte Multipeer Connectivity; Manual IP/Tailscale verwendet einen gekoppelten, verschlüsselten Network.framework-Transport. Beide Geräte müssen einander erreichen können, und das iPhone bleibt das Gerät, das HealthKit liest.</p>

## Einsatzbereiche
<div class="options">
<div class="option"><strong>Vaults nur auf dem Desktop</strong><p>Wenn Ihr Obsidian-Vault ausschließlich auf dem Mac liegt, ist dies der direkte Weg von HealthKit auf dem iPhone zu Dateien auf dem Mac.</p></div>
<div class="option"><strong>Große rückwirkende Exporte</strong><p>Speichern Sie die fertigen Dateien auf einem Desktop-Laufwerk, während das iPhone HealthKit liest und die Exportkonfiguration bereitstellt.</p></div>
<div class="option"><strong>Lokale Archivworkflows</strong><p>Schreiben Sie direkt in Ordner, die unter macOS gesichert, versioniert oder indiziert werden.</p></div>
</div>

<div class="callout">
<strong>Lokales Netzwerk erforderlich.</strong>
<p style="margin-top:6px;">Beide Geräte müssen sich in der Nähe befinden und das lokale Netzwerk verwenden dürfen. Ein iPhone mit reiner Mobilfunkverbindung kann kein Mac-Ziel erkennen. Weist der Bereitschaftsstatus auf ein Problem mit dem Mac hin, öffnen Sie die Mac-App erneut und wählen Sie den Zielordner noch einmal aus.</p>
</div>

## Mac-Synchronisierung und Direct CLI Access sind getrennt

Die Mac-Synchronisierung koppelt das iPhone für Zielexporte und verschlüsselten Agentenkontext mit der Health.md-Mac-App. Direct CLI Access koppelt das iPhone über eine separate Vertrauensdomäne mit einer Befehlszeileninstallation. Im direkten Modus können Rohdaten oder generierte Dateien ohne Mac-App exportiert werden; der verschlüsselte Mac-Abfrageindex und MCP stehen jedoch nicht zur Verfügung.

Lesen Sie [Direkte iPhone-CLI](/de/docs/cli-direct/), bevor Sie die separate iPhone-Einstellung aktivieren.

## Verwandte Themen
<div class="related">
  <a href="/de/docs/macos/"><span>Desktop</span>macOS-App – Export, Zeitplan und Verlauf auf dem Mac.</a>
  <a href="/de/docs/scheduling/"><span>Workflow</span>Zeitplanung – automatisieren Sie wiederkehrende Exporte.</a>
  <a href="/de/docs/cli-direct/"><span>Separates Vertrauen</span>Direkte iPhone-CLI – koppeln Sie eine CLI, ohne Aufträge durch die Mac-App zu leiten.</a>
  <a href="/de/docs/reference/connected-mac-iphone-protocol/"><span>Protokoll</span>Referenz für verbundenen Mac und iPhone – Funktionen, Anfragen, begrenzte Übertragung und Ergebnisse.</a>
</div>
