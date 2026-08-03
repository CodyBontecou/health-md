---
title: "Verfolgung einzelner Einträge"
description: "Schreiben Sie optional eine Datei je Eintrag mit Zeitstempel: Jede Trainingseinheit, Blutdruckmessung und Stimmungserfassung erhält eine eigene Markdown-Datei mit dem Zeitstempel im Dateinamen."
---

## Wann diese Funktion sinnvoll ist
<p>Tägliche Exporte liefern eine Datei pro Tag mit Zusammenfassungen. Die <em>Einzelverfolgung</em> eignet sich, wenn Sie <em>auf ein einzelnes Ereignis verweisen</em> möchten, etwa eine bestimmte Trainingseinheit aus einer Tagebuchnotiz oder einen Stimmungseintrag aus einem Wochenrückblick verlinken.</p>

<p>Sie ergänzt den täglichen Export, statt ihn zu ersetzen. Sind beide Funktionen aktiviert, erhalten Sie beide Dateiarten.</p>

## Einrichtung in zwei Schritten
<p>Die Einstellungen sind bewusst zweistufig aufgebaut:</p>
<ol>
<li><strong>Hauptschalter.</strong> Aktivieren Sie die Funktion global.</li>
<li><strong>Auswahl pro Metrik.</strong> Wählen Sie, <em>welche</em> Metriken eigene Dateien erhalten. Die meisten Menschen möchten keine Datei je Herzfrequenzmessung (10,000 / day), wohl aber eine je Trainingseinheit (~1 / day).</li>
</ol>

## Schnellaktionen
<div class="options">
<div class="option"><strong>Empfohlene Metriken aktivieren</strong><p>Sinnvolle Voreinstellungen: Stimmung, Symptome, Trainingseinheiten, Blutdruck und Blutzucker. Bei diesen Metriken ist eine Datei pro Eintrag tatsächlich nützlich.</p></div>
<div class="option"><strong>Alle Metriken aktivieren</strong><p>Aktiviert alles. Vorsicht: Dadurch können Tausende Dateien pro Tag entstehen.</p></div>
<div class="option"><strong>Alle Metriken deaktivieren</strong><p>Hebt die Auswahl einzelner Metriken auf, ohne den Hauptschalter auszuschalten.</p></div>
</div>

## Ordnerstruktur
<div class="options">
<div class="option"><strong>Eintragsordner</strong><p>Relativer Vault-Pfad für einzelne Dateien. Standard: <code>entries</code>.</p></div>
<div class="option"><strong>Nach Kategorie ordnen</strong><p>Ist die Option aktiviert, werden Einträge in Unterordnern nach Kategorie abgelegt (<code>entries/workouts/</code>, <code>entries/symptoms/</code>). Andernfalls liegen alle Einträge gemeinsam in einem flachen Ordner.</p></div>
</div>

## Dateinamenvorlage
<p>Standard: <code>{date}_{time}_{metric}</code>. Verfügbare Platzhalter: <code>{date}</code>, <code>{time}</code>, <code>{metric}</code>, <code>{category}</code>. Beispielausgabe:</p>

<div class="doc-diagram folder-tree" aria-label="Beispiel für die Dateistruktur einzelner Einträge">
<span>{vault}/entries/</span>
<span>├─ workouts/2026_07_14_0920_workouts_workouts_71000000-0000-0000-0000-000000000008.md</span>
<span>├─ symptoms/2026_07_14_0916_symptom_headache_symptom_headache_71000000-0000-0000-0000-000000000002.md</span>
<span>└─ vitals/2026_07_14_0918_blood_pressure_blood_pressure_71000000-0000-0000-0000-000000000004.md</span>
</div>

<p>Bei kanonischen, quellengestützten Einträgen werden die ausgewählte Metrik und die kleingeschriebene HealthKit-UUID an den konfigurierten Dateinamen angehängt. Dadurch bleibt derselbe Quelldatensatz über wiederholte Durchläufe stabil und Kollisionen innerhalb derselben Minute werden vermieden. UUID-freie Kompatibilitätseinträge behalten das kürzere bisherige Dateinamenverhalten bei.</p>

<div class="callout">
<strong>Wichtiger Hinweis.</strong>
<p style="margin-top:6px;">Hier erscheinen nur Kategorien, in denen Sie unter <em>Gesundheitsmetriken</em> mindestens eine Metrik aktiviert haben. Aktivieren Sie dort zunächst eine Metrik und kehren Sie dann zurück, um die Verfolgung pro Eintrag festzulegen. Lesen Sie den <a href="/de/docs/reference/individual-entry-tracking/">Identitätsvertrag für Quelldatensätze</a> und die generierte <a href="/de/docs/reference/generated/individual/filename-path-matrix/">Dateinamenmatrix</a>, bevor Sie Automatisierungen auf Pfaden aufbauen.</p>
</div>

## Verwandte Themen
<div class="related">
  <a href="/de/docs/metrics/"><span>Voraussetzung</span>Gesundheitsmetriken – aktivieren Sie zuerst Metriken.</a>
  <a href="/de/docs/format/"><span>Ausgabe</span>Format – gilt auch für Eintragsdateien.</a>
  <a href="/de/docs/daily-notes/"><span>Alternative</span>Einfügen in tägliche Notizen – eine andere Möglichkeit, Metriken an Notizen anzuhängen.</a>
  <a href="/de/docs/reference/individual-entry-tracking/"><span>Vertrag</span>Referenz für einzelne Einträge – UUID-Identität, frontmatter, spezialisierte Einträge und Kompatibilitäts-Fallbacks.</a>
</div>
