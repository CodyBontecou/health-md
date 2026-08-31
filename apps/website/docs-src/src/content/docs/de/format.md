---
title: "Formatanpassung"
description: "Steuern Sie die Ausgabeformatierung, ohne die Datenerfassung zu ändern. Wählen Sie Dateiformat, Datums-, Zeit- und Einheitenkonventionen, passen Sie das YAML-frontmatter an und wählen Sie eine Markdown-Vorlage."
---

## Ausgabeformate
<div class="options">
<div class="option"><strong>Markdown (.md)</strong><p>Standard. Eine Datei pro Tag. Optionales YAML-frontmatter und Abschnitte mit Überschriften je Kategorie.</p></div>
<div class="option"><strong>Obsidian Bases</strong><p>Markdown mit strukturiertem frontmatter, optimiert für das Obsidian-Plugin <a href="https://help.obsidian.md/Plugins/Bases">Bases</a>. Numerische Eigenschaften bleiben Zahlen, Datumswerte bleiben Datumswerte.</p></div>
<div class="option"><strong>JSON</strong><p>Eine JSON-Datei pro Tag. Apple-Tageszusammenfassungen nach Schema v8 können das maßgebliche Archiv <code>healthmd.healthkit_records</code> v1 einbetten, wenn Lossless Health Records aktiviert ist.</p></div>
<div class="option"><strong>CSV</strong><p>Eine CSV-Datei pro Tag mit der Kopfzeile <code>Date,Category,Metric,Value,Unit,Timestamp</code>. Kompatible Zusammenfassungszeilen enthalten fünf Felder und lassen die Zeitstempelspalte aus; Zeilen mit Zeitstempel und kanonische Datensatzzeilen enthalten alle sechs.</p></div>
</div>

<div class="callout">
<strong>Benötigen Sie den exakten Vertrag?</strong>
<p style="margin-top:6px;">Lesen Sie die aus dem Produktcode erzeugte <a href="/de/docs/reference/export-formats/">Formatreferenz</a>, die <a href="/de/docs/reference/generated/core/csv-row-contracts/">CSV-Zeilenverträge</a> und die vollständigen herunterladbaren Fixtures.</p>
</div>

## Datum &amp; Uhrzeit
<p>Wählen Sie Datumsformat, etwa <code>YYYY-MM-DD</code> oder <code>MMM d, yyyy</code>, und Zeitformat mit 12 oder 24 Stunden. Der Vorschaubereich am unteren Rand aktualisiert sich sofort, wenn Sie Einstellungen ändern.</p>

## Einheitensystem
<p>Wechseln Sie zwischen <em>Metrisch</em> und <em>Imperial</em>. Dies wirkt sich unter anderem auf Entfernung (m/km gegenüber ft/mi), Gewicht (kg gegenüber lb) und Temperatur (°C gegenüber °F) aus. HealthKit speichert stets in kanonischen Einheiten; die Umrechnung erfolgt beim Export.</p>

## frontmatter-Felder
<p>Durch Tippen auf <em>frontmatter-Felder</em> öffnen Sie einen eigenen Editor:</p>
<ul>
<li>Aktivieren oder deaktivieren Sie einzelne integrierte Felder (date, weekday, totalSteps usw.).</li>
<li>Benennen Sie ein Feld um, falls Ihre Obsidian-Konfiguration andere Schlüssel erwartet.</li>
<li>Fügen Sie eigene Felder mit statischen Werten hinzu, etwa <code>type: health</code>.</li>
<li>Fügen Sie Platzhalterfelder hinzu, die beim Export aufgelöst werden, etwa <code>weather: {weather}</code>.</li>
</ul>

## Markdown-Vorlage
<p>Durch Tippen auf <em>Markdown-Vorlage</em> öffnen Sie einen Vorlageneditor mit mehreren integrierten Stilen – Kompakt, Abschnitte und Detailliert – sowie einem vollständig benutzerdefinierten Modus. Der Vorschaubereich zeigt das Ergebnis für die heutigen Daten.</p>

## Vorschau
<p>Am unteren Rand der Formatansicht rendert eine Livevorschau die heutigen Daten mit Ihren aktuellen Einstellungen. So können Sie am schnellsten Anpassungen vornehmen: Schalter ändern, Vorschau prüfen, wiederholen.</p>

## Datendetail und Profile

Zusammenfassung erzeugt kompakte Tagesprojektionen. Detaillierte Zeitreihen ergänzen auf Apple und Android ausgewählte Messpunkte und Intervalle, sofern die Metrik sie unterstützt. Verlustfreie Gesundheitsdatensätze fügen das kanonische HealthKit-Archiv hinzu, sind nur bei Apple verfügbar und keine Android-Kompatibilitätsschicht.

Das Datendetail wird mit dem [Exportprofil](/de/docs/export-profiles/) fixiert. Eine Änderung bei aktivem Profil ändert nur dieses Profil.

## Verwandte Themen

<div class="related">
  <a href="/de/docs/export-profiles/"><span>Profile</span>Detailstufe und Format je Workflow speichern.</a>
  <a href="/de/docs/metrics/"><span>Inhalt</span>Gesundheitsmetriken – wählen Sie zuerst die Daten aus.</a>
  <a href="/de/docs/individual-tracking/"><span>Detailliert</span>Einzelverfolgung – eine andere Ausgabe mit einer Datei je Eintrag.</a>
  <a href="/de/docs/daily-notes/"><span>Obsidian</span>Einfügen in tägliche Notizen – verwendet dieselben frontmatter-Felder.</a>
  <a href="/de/docs/reference/export-formats/"><span>Vertrag</span>Exportformate – exaktes Verhalten von JSON, CSV, Markdown und Bases.</a>
</div>
