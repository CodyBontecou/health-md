---
title: "Kurzbefehle & App Intents"
description: "Acht App Intents starten Exporte, rufen Zusammenfassungen ab und schalten den Zeitplan über Siri, die App Kurzbefehle, Fokusfilter, Automationen und andere AppIntent-kompatible Hosts um."
---

## Verfügbare Intents
<div class="options">
<div class="option"><strong>Gesundheitsdaten von gestern exportieren</strong><p>Kurzbefehl ohne Parameter. Der schnellste Weg, um einfach die gestrigen Daten zu exportieren. Verwendet dieselbe Engine wie der manuelle Export.</p></div>
<div class="option"><strong>Gesundheitsdaten für ein Datum exportieren</strong><p>Ein einzelner Parameter <em>Datum</em>. Die Uhrzeit wird ignoriert. Nützlich für kalendergesteuerte Automationen.</p></div>
<div class="option"><strong>Gesundheitsdaten für einen Datumsbereich exportieren</strong><p>Die Parameter <em>Startdatum</em> und <em>Enddatum</em>, beide einschließlich. Für rückwirkende Exporte.</p></div>
<div class="option"><strong>Gesundheitsdaten der letzten N Tage exportieren</strong><p>Parameter <em>Anzahl der Tage</em> (1–366). Endet gestern. Standardwert 7. Geeignet für Automationen wie „jeden Sonntag die letzten 7 Tage exportieren“.</p></div>
<div class="option"><strong>Gesundheitszusammenfassung für ein Datum abrufen</strong><p>Gibt eine strukturierte Momentaufnahme mit Schritten, aktiven Kalorien, Schlaf und Herzfrequenz zurück, ohne etwas in den Vault zu schreiben. Verwenden Sie die Werte in Kurzbefehlen für andere Apps.</p></div>
<div class="option"><strong>Status des letzten Exports abrufen</strong><p>Gibt Zeitstempel, Erfolgsstatus, Zahl der Tage und mögliche Fehlerursache des zuletzt aufgezeichneten Exports zurück. Eine Anfrage bei gesperrtem Gerät bleibt bis zum erneuten Versuch ausstehend und wird daher nicht als aktueller Status zurückgegeben.</p></div>
<div class="option"><strong>Geplanten Export ein- oder ausschalten</strong><p>Boolescher Parameter. Unterbrechen Sie damit den Zeitplan, etwa während eines Urlaubsfokus, und setzen Sie ihn später fort.</p></div>
<div class="option"><strong>Gesundheitsdaten exportieren</strong><p>Allgemeiner Export, der den zuletzt im Exportdialog der App verwendeten Datumsbereich übernimmt. Seltener benötigt; die Varianten mit Datumsbereich sind meist eindeutiger.</p></div>
</div>

## So finden Sie die Intents
<p>Öffnen Sie Kurzbefehle unter iOS oder macOS. Tippen Sie zum Erstellen eines Kurzbefehls auf <em>+</em> und suchen Sie nach „Health.md“ oder einem der obigen Intent-Namen. Sie befinden sich in der Kategorie <em>Health</em>.</p>
<p>Die meisten Intents verwenden <code>openAppWhenRun = false</code> und werden daher ohne App-Start oder sichtbare Oberfläche ausgeführt. Sie funktionieren in Automationen, Fokusfiltern, bei Aufrufen über Hey Siri und über die Aktionstaste.</p>

<div class="callout">
<strong>Die Ausführung im gesperrten Zustand entsperrt HealthKit nicht.</strong>
<p style="margin-top:6px;">Apple schützt HealthKit-Daten bei gesperrtem iPhone und <a href="https://support.apple.com/guide/security/protecting-access-to-users-health-data-sec88be9900f/web">entzieht Apps den Zugriff ungefähr zehn Minuten nach dem Sperren</a>. <em>Ausführung im gesperrten Zustand erlauben</em> lässt Kurzbefehle die Aktion starten, setzt den HealthKit-Datenschutz aber nicht außer Kraft. Auch die Berechtigung für App-Inhalte von Health.md in Kurzbefehle ändert daran nichts.</p>
<p>Ist HealthKit nicht verfügbar, merkt sich Health.md die angefragten Daten als ausstehend und sendet die Mitteilung <em>Gesundheitsexport erfordert Aufmerksamkeit</em>. Entsperren Sie das iPhone und tippen Sie anschließend auf die Mitteilung oder öffnen Sie Health.md, um es erneut zu versuchen. Solange das Telefon gesperrt bleibt, kann ein vollständig unbeaufsichtigter Export nicht garantiert werden.</p>
</div>

<a id="recipe-nightly-export-with-confirmation"></a>
## Rezept: täglicher Export mit Bestätigung
<ol>
<li><strong>Persönliche Automation</strong> → <em>Tageszeit</em> → wählen Sie eine Uhrzeit, zu der Sie Ihr entsperrtes iPhone gewöhnlich verwenden, etwa 8:00 AM.</li>
<li>Intent <em>Gesundheitsdaten von gestern exportieren</em>.</li>
<li>Intent <em>Status des letzten Exports abrufen</em>.</li>
<li><em>Mitteilung anzeigen</em> mit dem Ergebnis.</li>
</ol>
<p><strong>Hinweis zu ausstehenden Statuswerten:</strong> <em>Status des letzten Exports abrufen</em> liest den jüngsten aufgezeichneten Eintrag im Exportverlauf. Wenn HealthKit bei diesem Durchlauf wegen der Gerätesperre nicht verfügbar war, kann bis zum erneuten Versuch weiterhin der vorherige Export angezeigt werden. Für ausstehende Aufgaben ist die Wiederherstellungsmitteilung von Health.md maßgeblich.</p>

## Rezept: einmaliger rückwirkender Export
<ol>
<li>Erstellen Sie einen Kurzbefehl.</li>
<li><em>Gesundheitsdaten für einen Datumsbereich exportieren</em> mit Start = 2024-01-01 und Ende = 2024-12-31.</li>
<li>Führen Sie ihn in Kurzbefehle aus. Das Jahr wird durchlaufen und pro Tag eine Datei geschrieben. Bei vollständigen Jahren kann dies einige Minuten dauern.</li>
</ol>

## Rezept: Zeitplan im Urlaub pausieren
<ol>
<li><strong>Fokusfilter</strong>: Wenn der Fokus <em>Urlaub</em> aktiviert wird, führen Sie <em>Geplanten Export ein- oder ausschalten</em> mit Aktiviert = false aus.</li>
<li>Führen Sie den Intent beim Deaktivieren des Fokus erneut mit Aktiviert = true aus.</li>
</ol>

<div class="callout">
<strong>Autorisierung erforderlich.</strong>
<p style="margin-top:6px;">Intents übernehmen die HealthKit-Berechtigung und Vault-Auswahl der App. Sie schlagen mit einer eindeutigen Fehlermeldung fehl, wenn die App auf diesem Gerät nicht mindestens einmal geöffnet und eingerichtet wurde.</p>
</div>

## Verwandte Themen
<div class="related">
  <a href="/de/docs/scheduling/"><span>Quelle</span>Zeitplanung – die entsprechende Schaltfunktion in der App.</a>
  <a href="/de/docs/export/"><span>Quelle</span>Export – die entsprechenden Datumsbereichsfunktionen in der App.</a>
</div>
