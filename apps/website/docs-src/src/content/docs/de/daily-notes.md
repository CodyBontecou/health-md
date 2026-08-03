---
title: "Einfügen in tägliche Notizen"
description: "Fügen Sie ausgewählte Gesundheitsmetriken in das YAML-frontmatter und optional den Text Ihrer vorhandenen täglichen Notizen ein – unabhängig davon, ob Sie diese in Obsidian oder einer anderen Markdown-App führen."
---

## Funktionsweise
<p>Wenn Sie tägliche Notizen führen, etwa <code>Daily/2026-04-28.md</code>, können Sie diese Funktion aktivieren. Die App <em>führt</em> Ihre ausgewählten Metriken bei jedem Export mit dem YAML-frontmatter dieser Notizen zusammen, ohne den übrigen Inhalt anzutasten.</p>

<div class="doc-diagram merge-preview" aria-label="frontmatter einer täglichen Notiz vor und nach dem Zusammenführen durch Health.md">
<div class="merge-card">
<strong>Vorher</strong>
<pre><code>---
title: Tuesday note
mood: focused
---

Wrote launch notes...</code></pre>
</div>
<div class="merge-card">
<strong>Nach dem Export</strong>
<pre><code>---
title: Tuesday note
mood: focused
steps: 12642
sleep_total_hours: 7.31
workout_count: 1
---

Wrote launch notes...</code></pre>
</div>
</div>

<p>Optional kann die App außerdem Markdown-Abschnitte wie Schlaf, Aktivität und Herz in den Text der Notiz einfügen. Diese Abschnitte werden von der App verwaltet und bei jedem Export sauber ersetzt. Ihre eigenen Überschriften bleiben unverändert.</p>

## Speicherort
<div class="options">
<div class="option"><strong>Ordner</strong><p>Relativer Pfad innerhalb des Vaults zum Ordner Ihrer täglichen Notizen. Standard: <code>Daily</code>. Lassen Sie das Feld leer, um das Vault-Stammverzeichnis zu verwenden. Beispiele: <code>Daily</code>, <code>Journal/Daily</code>.</p></div>
<div class="option"><strong>Dateiname</strong><p>Muster für den Dateinamen der Notiz ohne Erweiterung. Der Standard <code>{date}</code> wird zu <code>2026-04-28</code> aufgelöst.</p></div>
</div>

## Platzhalter für Dateinamen
<p>Sie können diese beliebig kombinieren:</p>
<ul>
<li><code>{date}</code> – vollständiges ISO-Datum (<code>2026-04-28</code>)</li>
<li><code>{year}</code>, <code>{month}</code>, <code>{day}</code></li>
<li><code>{weekday}</code> – Kurzname (<code>Tue</code>)</li>
<li><code>{monthName}</code> – ausgeschriebener Name (<code>April</code>)</li>
<li><code>{quarter}</code> – Q1 / Q2 / Q3 / Q4</li>
</ul>
<p>Beispiel: <code>{year}/{monthName}/{date}-{weekday}</code> → <code>2026/April/2026-04-28-Tue.md</code>. Die Vorschauzeile unter dem Feld zeigt den aufgelösten Pfad sofort an.</p>

## Optionen
<div class="options">
<div class="option"><strong>Fehlende Notiz erstellen</strong><p>Erstellt für ein Datum eine neue tägliche Notiz, falls noch keine vorhanden ist. Lassen Sie diese Option aus, wenn Sie tägliche Notizen selbst mit Obsidian Templater oder einem ähnlichen Plugin erstellen.</p></div>
<div class="option"><strong>Metrikabschnitte einfügen</strong><p>Schreibt zusätzlich Überschriften wie Schlaf, Aktivität und Herz in den Text der Notiz. Sie werden von der App verwaltet und bei jedem Export sauber ersetzt. Standardmäßig deaktiviert.</p></div>
</div>

## Welche Metriken eingefügt werden
<p>Es werden die unter <em>Gesundheitsmetriken</em> ausgewählten Metriken verwendet. Hier gibt es keine separate Auswahl. Wenn Sie dort die Metrikauswahl ändern, übernimmt „Einfügen in tägliche Notizen“ diese Änderung.</p>

## frontmatter-Vorschau
<p>Am unteren Rand der Ansicht befindet sich eine Livevorschau des zusammenzuführenden frontmatter. Sie wird aktualisiert, wenn Sie die Metrikauswahl oder die frontmatter-Felder der Formatanpassung ändern.</p>

<div class="callout">
<strong>So funktioniert das Zusammenführen.</strong>
<p style="margin-top:6px;">Besitzt Ihre tägliche Notiz bereits frontmatter, behält die App Ihre Schlüssel bei und fügt nur die von ihr verwalteten Schlüssel hinzu oder aktualisiert sie. Von der App verwaltete Textabschnitte werden in HTML-Kommentare eingeschlossen, sodass wiederholte Durchläufe idempotent sind.</p>
</div>

## Verwandte Themen

<div class="related">
  <a href="/de/docs/metrics/"><span>Voraussetzung</span>Gesundheitsmetriken – wählen Sie aus, was eingefügt wird.</a>
  <a href="/de/docs/format/"><span>Format</span>Editor für frontmatter-Felder – benennen Sie Schlüssel um und fügen Sie eigene Felder hinzu.</a>
  <a href="/de/docs/individual-tracking/"><span>Detailliert</span>Einzelverfolgung – eine Alternative zur Verfolgung einzelner Ereignisse.</a>
</div>
