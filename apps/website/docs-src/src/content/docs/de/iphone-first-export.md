---
title: "Apple-Health-Daten exportieren: erster iPhone-Export"
description: "Exportieren Sie Apple-Health-Daten mit Health.md in einen eigenen Ordner. Starten Sie mit einem Tag; ergänzen Sie CSV oder JSON nach dem ersten Export."
---

Mit dieser Anleitung erstellen Sie einen kleinen, überprüfbaren Export, bevor Sie Metriken, Formatierung oder Automatisierung ändern. Health.md liest nur die von iOS autorisierten Apple Health-Kategorien und schreibt die generierten Dateien in den von Ihnen gewählten Ordner.

<div class="availability available">
<strong>Jetzt verfügbar · Health.md für iPhone</strong>
<p>Für Exporte benötigen Sie eine aktive Testphase, ein Abo oder Lifetime-Zugang. Zeitpläne und andere Automationen können Sie später einrichten.</p>
</div>

## Bevor Sie beginnen

Stellen Sie vorab sicher, dass Folgendes vorhanden ist:

- [Health.md aus dem App Store](https://apps.apple.com/app/health-md/id6757763969), installiert auf einem iPhone mit Apple-Health-Daten
- die Berechtigung, mindestens eine Apple-Health-Kategorie zu lesen
- ein beschreibbarer Ordner in Dateien, in iCloud Drive, auf „Auf meinem iPhone“ oder in einem Obsidian-Vault.

Behalten Sie die Standardmetriken und das Markdown-Format bei. Wählen Sie **Gestern** für einen Zeitraum von einem Tag.

## 1. iPhone-Einrichtung abschließen

Health.md zeigt fünf Einrichtungsschritte. Keiner davon blockiert: Apple-Health-Zugriff und Ordner können Sie überspringen und später nachholen.

Tippen Sie beim ersten Start auf **Apple Health verbinden**. Autorisieren Sie die gewünschten Gesundheitskategorien, prüfen Sie die Beispielausgabe, wählen Sie einen Ordner in Dateien und fahren Sie bis zum letzten Schritt fort.

Nach der Einrichtung öffnet die App das **Archiv**. Wenn Apple Health oder der Ordner Aufmerksamkeit brauchen, nennt die Karte **Aufmerksamkeit nötig** oben, was zu beheben ist.

<div class="docs-screenshot-grid">
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/onboarding-start.webp" target="_blank" rel="noopener" aria-label="Einrichtungs-Screenshot in voller Größe öffnen">
    <img src="/docs/assets/docs/iphone-first-export/onboarding-start.webp" width="1206" height="2622" loading="lazy" alt="Health.md-Einrichtung bei Schritt 1 von 5 mit drei aufgelisteten Schritten und der Taste zum Verbinden mit Apple Health." />
  </a>
  <figcaption>Die Einrichtung erklärt, was Health.md liest und wohin Dateien gehen, bevor sie Zugriff anfordert. Die Oberfläche dieser Aufnahme bleibt auf Englisch.</figcaption>
</figure>
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/export-now.webp" target="_blank" rel="noopener" aria-label="Screenshot von „Jetzt exportieren“ in voller Größe öffnen">
    <img src="/docs/assets/docs/iphone-first-export/export-now.webp" width="1206" height="2622" loading="lazy" alt="Health.md-Blatt „Jetzt exportieren“ mit ausgewähltem Zeitraum Gestern, einem Schalter für nur die Bereichszusammenfassung, einer Übersicht für eine Datei und einen Tag und einer Exporttaste." />
  </a>
  <figcaption>„Jetzt exportieren“ zeigt vor dem Start, was geschrieben wird. Auch diese Referenzaufnahme zeigt die Oberfläche auf Englisch.</figcaption>
</figure>
</div>

## 2. Kleinen Export auswählen

Tippen Sie auf die runde Taste **Jetzt exportieren** neben der Tab-Leiste. Dann:

1. Wählen Sie **Gestern**.
2. Lassen Sie **Nur Bereichszusammenfassung** ausgeschaltet.
3. Prüfen Sie, dass **Wird geschrieben** Ihren Ordner und etwa eine Datei für einen Tag nennt.

Die Standard-Automation verwendet die Standardauswahl an Metriken und **Markdown**. Zum Ändern öffnen Sie **Automationen**, wählen die Automation und dann **Metriken** oder **Formate**. Fügen Sie CSV, JSON oder Obsidian Bases erst hinzu, wenn dieser Export funktioniert. Ein kurzer Zeitraum macht Berechtigungs-, Leerdaten- und Ordnerprobleme leichter auffindbar.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/de/iphone-first-export/metric-selection.webp" target="_blank" rel="noopener" aria-label="Screenshot der Metrikauswahl in voller Größe öffnen">
    <img src="/docs/assets/docs/de/iphone-first-export/metric-selection.webp" width="1206" height="2622" loading="lazy" alt="Health.md-Seite „Metriken“ mit der Anzahl aktiver Metriken, den Tasten Empfohlen, Alle auswählen und Alle abwählen, einem Suchfeld und Kategorien mit Anzahlen." />
  </a>
  <figcaption>Die Anzahl der Metriken hängt von App-Version und Berechtigungen ab. Diese lokalisierte Aufnahme zeigt 217 von 219 aktivierten Metriken.</figcaption>
</figure>

## 3. Vor dem Schreiben Vorschau prüfen

Tippen Sie in **Jetzt exportieren** auf **Vorschau**. Die Vorschau braucht Apple-Health-Zugriff, aber keinen beschreibbaren Ordner.

Nutzen Sie die Vorschau, um ein Berechtigungsproblem bei Apple Health zu erkennen, bevor Sie den Ordner testen.

Prüfen Sie, ob die Vorschau Folgendes zeigt:

- das angeforderte Datum
- die erwarteten Metriknamen und Einheiten
- fehlende oder nicht verfügbare Werte statt falscher Nullwerte
- das gewählte Format und die Dateinamenstruktur.

Schließen Sie die Vorschau und ändern Sie die Einstellungen der Automation, wenn Sie Metriken oder Formate ändern müssen.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/de/iphone-first-export/export-preview.webp" target="_blank" rel="noopener" aria-label="Screenshot der Exportvorschau in voller Größe öffnen">
    <img src="/docs/assets/docs/de/iphone-first-export/export-preview.webp" width="1206" height="2622" loading="lazy" alt="Health.md-Exportvorschau mit Schlaffenster, Schätzung für einen Markdown-Tag, Zusammenfassungszeitraum, Zielordner und erzeugtem Dateinamen." />
  </a>
  <figcaption>Dieses Beispiel verwendet Beispiel-Gesundheitsdaten.</figcaption>
</figure>

## 4. Exportieren und verifizieren

Tippen Sie auf **Gestern exportieren**. Ist die Einrichtung unvollständig, nennt Health.md die fehlende Apple-Health- oder Ordner-Voraussetzung.

Nach Abschluss des Exports:

1. Prüfen Sie im Ergebnis geschriebene, übersprungene oder fehlgeschlagene Dateien. Der Tag erscheint im Kalender im **Archiv**.
2. Öffnen Sie die App Dateien und den gewählten Ordner.
3. Öffnen Sie eine erzeugte Datei und prüfen Sie Datum, Einheiten und Frontmatter.
4. Bewahren Sie die Ergebnisdetails auf, falls Sie ein Problem untersuchen müssen.

Ein abgedeckter Tag im Kalender ist eine Zusammenfassung; tippen Sie auf den Tag, um den Status jeder Automation für dieses Datum zu sehen.

<div class="callout">
<strong>Keine Daten für den gewählten Tag?</strong>
<p style="margin-top:6px;">Wählen Sie einen Tag mit Aktivitäts- oder Schlafdaten. Prüfen Sie dann die Apple-Health-Autorisierung und die Metrikauswahl. Ein leerer Zeitraum ist kein Schreibfehler.</p>
</div>

## Nächste Schritte

<div class="related">
  <a href="/de/docs/metrics/"><span>Daten auswählen</span>Durchsuchen Sie Apple Health-Metriken und passen Sie Kategorien oder besondere Berechtigungen an.</a>
  <a href="/de/docs/format/"><span>Ausgabe gestalten</span>Konfigurieren Sie Formate, Datumsangaben, Einheiten, frontmatter, Vorlagen und Dateinamen.</a>
  <a href="/de/docs/scheduling/"><span>Automatisieren</span>Planen Sie wiederholte Exporte, nachdem ein manueller Durchlauf verifiziert wurde.</a>
  <a href="/de/docs/folder-vault/"><span>Ziel reparieren</span>Erfahren Sie mehr über Anbieter in Dateien, Ordnerzugriff und Wiederherstellung.</a>
</div>
