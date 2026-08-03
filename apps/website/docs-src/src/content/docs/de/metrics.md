---
title: "Gesundheitsmetriken"
description: "Wählen Sie aus dem aktuellen Apple Health-Metrikkatalog von Health.md. Suchen Sie, schalten Sie ganze Kategorien um oder steuern Sie einzelne Metriken."
---

<div class="callout">
<strong>Hinweis zu Android.</strong>
<p style="margin-top:6px;">Diese Seite beschreibt die Metrikauswahl für Apple Health und die generierte HealthKit-Datenreferenz. Die Android-App stellt 106 Health Connect-Metriken bereit. Einrichtung und plattformspezifisches Verhalten finden Sie im <a href="/de/docs/android/">Android-Leitfaden</a>.</p>
</div>

## Aufbau
<div class="options">
<div class="option"><strong>Auswahlzähler</strong><p>Zeigt laufend die Zahl aktivierter Metriken und Kategorien. Halten Sie die Anzeige gedrückt, um den exakten Auswahlstatus in die Zwischenablage zu kopieren.</p></div>
<div class="option"><strong>Alle Metriken aktiviert</strong><p>Hauptschalter, der alle Kategorien ein- oder ausschaltet. Nützlich als Ausgangspunkt: Aktivieren Sie alles und deaktivieren Sie anschließend, was Sie nicht benötigen.</p></div>
<div class="option"><strong>Suche</strong><p>Filtert Metriknamen und Kennungen sofort. Probieren Sie „heart“, „sleep“ oder „vo2“.</p></div>
</div>

## Kategorien
<p>Die Auswahl gruppiert gewöhnliche Zusammenfassungen und Definitionen von Quelldatensätzen in Kategorien wie Schlaf, Aktivität, Herz, Atmung, Vitalwerte, Körpermaße, Mobilität, Radfahren, Ernährung, Achtsamkeit, reproduktive Gesundheit, Symptome, Medikamente, spezialisierte Datensätze und Trainingseinheiten. Jede Zeile zeigt den Aktivierungsstatus und die aktuelle Zahl aktivierter Definitionen. Der aus dem Produktcode erzeugte <a href="/de/docs/reference/generated/core/metric-catalog/">Metrikkatalog</a> ist das maßgebliche aktuelle Verzeichnis.</p>

<p>Tippen Sie auf eine Kategorie, um deren Metriken aufzurufen. Jede Metrik besitzt einen eigenen Schalter und eine HealthKit-Kennung. Die Punktfarbe zeigt, ob HealthKit auf diesem Gerät derzeit Daten für die Metrik enthält.</p>

## Geltungsbereich der Auswahl
<p>Ihre Metrikauswahl bestimmt <em>alles</em>:</p>
<ul>
<li>Tägliche Exporte – nur aktivierte Metriken erscheinen in der Datei.</li>
<li>Einzelverfolgung – nur aktivierte Metriken erhalten Dateien pro Eintrag.</li>
<li>Einfügen in tägliche Notizen – nur aktivierte Metriken werden mit dem frontmatter zusammengeführt.</li>
<li>Kurzbefehle – Exporte für Datumsbereiche verwenden dieselbe Auswahl.</li>
</ul>

<div class="callout">
<strong>Tipp.</strong>
<p style="margin-top:6px;">Beginnen Sie mit einer kleinen Auswahl. Aktivieren Sie Schlaf, Aktivität und Herz, führen Sie einen Export aus und prüfen Sie die Datei. Fügen Sie danach weitere Kategorien hinzu. Das ist schneller, als sich durch eine 50-zeilige Datei mit irrelevanten Metriken zu arbeiten.</p>
</div>

## Verwandte Themen

<div class="related">
  <a href="/de/docs/reference/"><span>Referenz</span>Exportreferenz – alle Apple-Metriken, Schlüssel, Einheiten, Quelldatensatzdefinitionen und Exportstrukturen.</a>
  <a href="/de/docs/android/"><span>Android</span>Android-App – Einrichtung von Health Connect, Metriken, Ziele und Automatisierung.</a>
  <a href="/de/docs/format/"><span>Darstellung</span>Format – ändern Sie, wie die ausgewählten Metriken geschrieben werden.</a>
  <a href="/de/docs/individual-tracking/"><span>Detailliert</span>Einzelverfolgung – schreiben Sie zusätzlich eine Datei je Eintrag mit Zeitstempel.</a>
  <a href="/de/docs/daily-notes/"><span>Obsidian</span>Einfügen in tägliche Notizen – übernehmen Sie diese Metriken in Ihre täglichen Notizen.</a>
</div>
