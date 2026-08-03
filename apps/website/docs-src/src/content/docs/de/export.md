---
title: "Export"
description: "Der Tab „Export“ ist die zentrale Arbeitsfläche. Er zeigt, ob HealthKit und Ihr Vault verbunden sind, lässt Sie ein Ziel wählen und führt einmalige Exporte für den gewählten Datumsbereich aus."
---

<p>Der Tab „Export“ gliedert sich in drei kurze Entscheidungen: Einsatzbereitschaft bestätigen, Ziel auswählen und anschließend den Datumsbereich festlegen, bevor Sie eine Vorschau anzeigen oder exportieren.</p>

## Statusanzeigen lesen
<div class="options">
<div class="option"><strong>Health-Anzeige</strong><p>Grüner Punkt = HealthKit autorisiert. Rot = nicht erlaubt. Tippen Sie darauf, um das iOS-Berechtigungsfenster erneut aufzurufen. Dies funktioniert pro Installation nur beim ersten Mal; danach reagiert iOS nicht mehr sichtbar und Sie müssen die Berechtigung unter Einstellungen → Datenschutz &amp; Sicherheit → Health korrigieren.</p></div>
<div class="option"><strong>Vault-Anzeige</strong><p>Grüner Punkt = ein Vault-Ordner ist ausgewählt. Tippen Sie darauf, um den Vault erneut auszuwählen oder zu ändern. Die Beschriftung zeigt den Ordnernamen.</p></div>
</div>
<p>Die Aktion <em>Export</em> bleibt deaktiviert, bis HealthKit, Ausgabeformat und gewähltes Ziel bereit sind. So wird der häufigste Fehler vermieden: ein Export ohne Ziel.</p>

## Exportziel auswählen
<p>Die Karte „Exportziel“ legt fest, wohin die Daten gelangen:</p>

<div class="options">
<div class="option"><strong>Lokaler iPhone-Ordner</strong><p>Schreibt direkt in den Ordner oder Obsidian-Vault, den Sie auf diesem Gerät ausgewählt haben.</p></div>
<div class="option"><strong>Verbundener Mac</strong><p>Sendet erfasste Tagesdaten und eine exakte Momentaufnahme der Einstellungen an die Mac-App in der Nähe. Das iPhone liest HealthKit; der Mac rendert die ausgewählten Formate und schreibt die Dateien.</p></div>
<div class="option"><strong>API-Endpunkt</strong><p>Sendet einen API-Envelope per POST direkt vom iPhone an einen vom Benutzer konfigurierten HTTP(S)-Endpunkt. <a href="/de/docs/api-endpoint/">Weitere Informationen zum API-Endpunkt</a>.</p></div>
</div>

## Datumsbereich auswählen
<p>Voreinstellungen decken die häufigsten Fälle ab:</p>

<div class="options">
<div class="option"><strong>Heute</strong><p>Exportiert den aktuellen Tag. Nützlich zum Testen der Ausgabeformatierung.</p></div>
<div class="option"><strong>Gestern</strong><p>Die sicherste Wahl für tägliche Exporte, da der Tag vollständig abgeschlossen ist.</p></div>
<div class="option"><strong>Gesamter Zeitraum</strong><p>Exportiert rückwirkend ab den frühesten HealthKit-Daten, die Health.md finden kann.</p></div>
<div class="option"><strong>Benutzerdefiniert</strong><p>Wählen Sie Start- und Enddatum für einen bestimmten Zeitraum.</p></div>
</div>

## Vorschau oder Export
<div class="options">
<div class="option"><strong>Vorschau</strong><p>Zeigt vor dem Schreiben, welche Dateien und Inhalte erzeugt werden.</p></div>
<div class="option"><strong>Export</strong><p>Führt den Export aus, zeigt den Fortschritt auf dem Hauptbildschirm und zeichnet das Ergebnis im Verlauf auf.</p></div>
</div>

## Was beim „Exportieren“ tatsächlich geschieht
<ol>
<li>Für jeden Tag im Zeitraum werden die ausgewählten Zusammenfassungsprojektionen und, sofern Lossless Health Records aktiviert ist, deren kanonische Quelldatensätze und Abfragediagnosen erfasst.</li>
<li>Das gewählte Format (Markdown, Bases, JSON oder CSV) und die Vorlage werden angewendet.</li>
<li>Pro Tag wird eine Datei in <code>{vault}/{subfolder}/</code> geschrieben, über den Workflow mit dem verbundenen Mac übertragen oder als versionierter API-Envelope per POST an Ihren API-Endpunkt gesendet.</li>
<li>Ist <em>Individual Tracking</em> aktiviert, werden für dateibasierte Ziele ausgewählte Markdown-Dateien pro Eintrag aus dem kanonischen Archiv abgeleitet.</li>
<li>Ist <em>Daily Note Injection</em> aktiviert, werden ausgewählte Zusammenfassungsfelder in Ihre täglichen Notizen eingefügt.</li>
</ol>

<p>JSON und CSV können kanonische Datensätze erhalten. Markdown und Bases bleiben gut lesbar und zeigen kompakte Erfassungsdiagnosen, statt das Archiv einzubetten. Exakte Schemas und Auslassungsregeln finden Sie in der <a href="/de/docs/reference/">vollständigen Exportreferenz</a>.</p>

## Tab-Leiste

<p>Die vier Tabs am unteren Bildschirmrand – Export, Zeitplan, Synchronisierung und Einstellungen – decken die gesamte App ab. Alles Weitere befindet sich eine oder zwei Ebenen tiefer in den Einstellungen.</p>

<div class="callout">
<strong>Freischaltung.</strong>
<p style="margin-top:6px;">Full Access schaltet unbegrenzte Exportdurchläufe, geplante Exporte, Mac-Ziele und Kurzbefehle frei. Weitere Informationen finden Sie auf der <a href="/de/docs/paywall/">Seite zu Freischaltung und Paywall</a>.</p>
</div>

## Verwandte Themen

<div class="related">
  <a href="/de/docs/scheduling/"><span>Tägliche Nutzung</span>Zeitplanung – automatisieren Sie den Vorgang, damit Sie nie wieder auf „Export“ tippen müssen.</a>
  <a href="/de/docs/api-endpoint/"><span>Integration</span>API-Endpunkt – senden Sie ausgewählte JSON-Daten direkt an Ihren eigenen Dienst.</a>
  <a href="/de/docs/format/"><span>Anpassen</span>Formatanpassung – ändern Sie das Erscheinungsbild jeder Datei.</a>
  <a href="/de/docs/shortcuts/"><span>Automatisierung</span>Kurzbefehle – starten Sie Exporte über Siri, Automationen oder andere Apps.</a>
  <a href="/de/docs/reference/"><span>Referenz</span>Exportreferenz – Schemas, kanonische Datensätze, Diagnosen und generierte Beispiele.</a>
</div>
