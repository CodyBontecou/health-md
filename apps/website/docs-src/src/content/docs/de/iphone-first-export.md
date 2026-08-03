---
title: "Erster iPhone-Export"
description: "Autorisieren Sie Apple Health, wählen Sie ein Ziel in Dateien, prüfen Sie die Health.md-Ausgabe in der Vorschau, führen Sie einen kleinen ersten iPhone-Export aus und verifizieren Sie die geschriebenen Dateien."
---

Mit dieser Anleitung erstellen Sie einen kleinen, überprüfbaren Export, bevor Sie Metriken, Formatierung oder Automatisierung ändern. Health.md liest nur die von iOS autorisierten Apple Health-Kategorien und schreibt die generierten Dateien in den von Ihnen gewählten Ordner.

<div class="availability available">
<strong>Jetzt verfügbar · Health.md für iPhone</strong>
<p>Der erste Export ist im kostenlosen Kontingent enthalten. Zeitplanung und weitere kostenpflichtige Funktionen können Sie später konfigurieren.</p>
</div>

## Bevor Sie beginnen

Sie benötigen:

- Health.md auf einem iPhone mit Apple Health-Daten;
- die Berechtigung, mindestens eine Apple Health-Kategorie zu lesen;
- ein beschreibbares Ziel in Dateien, etwa iCloud Drive, „Auf meinem iPhone“ oder einen Obsidian-Vault.

Behalten Sie für den kürzesten ersten Durchlauf die Standardmetriken und die Markdown-Ausgabe bei. Beginnen Sie mit **Gestern** oder einem anderen Zeitraum von einem Tag statt mit dem gesamten verfügbaren Verlauf.

## 1. iPhone-Einrichtung abschließen

Tippen Sie beim ersten Start auf **Start Setup** („Einrichtung starten“) und führen Sie die sieben Onboarding-Schritte aus. Autorisieren Sie die gewünschten Gesundheitskategorien, prüfen Sie die Beispielausgabe, wählen Sie einen Ordner in Dateien und fahren Sie bis **Ready** („Bereit“) fort. Wenn der Schritt zum Freischalten erscheint, können Sie mit dem kostenlosen Kontingent fortfahren.

Wenn Sie das Onboarding bereits abgeschlossen haben, öffnen Sie den Tab **Export** und vergewissern Sie sich, dass Apple Health und der lokale Ordner bereit sind. Ersetzen Sie ein fehlendes oder nicht erreichbares Ziel über die Ordnerauswahl.

<div class="docs-screenshot-grid">
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/onboarding-start.webp" target="_blank" rel="noopener" aria-label="Onboarding-Screenshot in voller Größe öffnen">
    <img src="/docs/assets/docs/iphone-first-export/onboarding-start.webp" width="1206" height="2622" loading="lazy" alt="Willkommensbildschirm des Health.md-Onboardings bei Schritt 1 von 7 mit der Schaltfläche „Start Setup“." />
  </a>
  <figcaption>„Start Setup“ stellt das lokale Archiv, geplante Notizen und das Ordnermodell vor, bevor die App Zugriff anfordert. Die Benutzeroberfläche dieser authentischen Aufnahme bleibt auf Englisch.</figcaption>
</figure>
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/export-setup-required.webp" target="_blank" rel="noopener" aria-label="Screenshot der erforderlichen Einrichtung in voller Größe öffnen">
    <img src="/docs/assets/docs/iphone-first-export/export-setup-required.webp" width="1206" height="2622" loading="lazy" alt="Health.md-Tab „Export“ mit nicht verbundenem Health-Zugriff, verfügbarer Ordnerauswahl, ausgewähltem lokalen iPhone-Ordner und Schaltflächen für den Datumsbereich." />
  </a>
  <figcaption>Die Bereitschaftskennzeichnungen weisen eindeutig auf fehlende Health- und Ordnereinrichtung hin. Auch diese Referenzaufnahme bleibt auf Englisch und zeigt bewusst beide Anforderungen als unvollständig.</figcaption>
</figure>
</div>

## 2. Kleinen Export auswählen

Im Tab „Export“:

1. Wählen Sie **Lokaler iPhone-Ordner** als Ziel.
2. Wählen Sie **Gestern** oder einen benutzerdefinierten Zeitraum von einem Tag.
3. Behalten Sie für den ersten Durchlauf die Standardauswahl der Metriken bei.
4. Lassen Sie **Markdown** ausgewählt. Sie können CSV, JSON oder Obsidian Bases hinzufügen, nachdem der grundlegende Ablauf funktioniert.

Ein kurzer Zeitraum erleichtert es, Berechtigungen, leere Kategorien und Zielprobleme nachzuvollziehen. Außerdem vermeiden Sie so, eine lange laufende erste Anfrage fälschlich für einen fehlgeschlagenen Export zu halten.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/de/iphone-first-export/metric-selection.webp" target="_blank" rel="noopener" aria-label="Screenshot der Metrikauswahl in voller Größe öffnen">
    <img src="/docs/assets/docs/de/iphone-first-export/metric-selection.webp" width="1206" height="2622" loading="lazy" alt="Aktueller Bildschirm „Gesundheitsmetriken“ mit 217 von 219 aktivierten Metriken, eingeschalteten Standardmetriken, einem Suchfeld und den aufklappbaren Kategorien Schlaf, Aktivität und Herz." />
  </a>
  <figcaption>Die Gesamtzahl der Metriken hängt von der installierten App-Version und den Berechtigungen ab. Diese lokalisierte Aufnahme zeigt 217 von 219 aktivierten Metriken und eingeschaltete Standardmetriken; für den ersten Export ist dieser Umfang nicht erforderlich.</figcaption>
</figure>

## 3. Vor dem Schreiben Vorschau prüfen

Tippen Sie auf **Vorschau**. Die Vorschau benötigt Zugriff auf Apple Health, aber keinen beschreibbaren lokalen Ordner. Dadurch lässt sich ein Problem mit Leseberechtigungen von einem Problem mit Dateien unterscheiden.

Prüfen Sie, ob die Vorschau Folgendes zeigt:

- das angeforderte Datum;
- die erwarteten Metriknamen und Einheiten;
- ausdrücklich fehlende oder nicht verfügbare Werte statt erfundener Nullen;
- das ausgewählte Format und die Dateinamenstruktur.

Kehren Sie zum Tab „Export“ zurück, wenn Sie Datumsangaben, Metriken oder Formatierung anpassen müssen.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/de/iphone-first-export/export-preview.webp" target="_blank" rel="noopener" aria-label="Screenshot der Exportvorschau in voller Größe öffnen">
    <img src="/docs/assets/docs/de/iphone-first-export/export-preview.webp" width="1206" height="2622" loading="lazy" alt="Health.md-Exportvorschau mit Schätzung für einen eintägigen Markdown-Export, Roll-up-Zeiträumen, Ziel und generiertem Dateinamen." />
  </a>
  <figcaption>Die Vorschau trennt die Prüfung der Ausgabe vom Schreiben. Diese reproduzierbare Dokumentationsaufnahme verwendet Beispieldaten und zeigt ausdrücklich, dass kein Vault ausgewählt ist.</figcaption>
</figure>

## 4. Exportieren und verifizieren

Tippen Sie auf **Daten exportieren**. Wenn die Einrichtung unvollständig ist, nennt Health.md die fehlende Health- oder Ordneranforderung, statt unbemerkt einen teilweisen Schreibvorgang zu starten.

Nach Abschluss:

1. Prüfen Sie im Ergebnis der App, welche Dateien geschrieben, übersprungen oder nicht geschrieben wurden.
2. Öffnen Sie die App „Dateien“ und navigieren Sie zum ausgewählten Ordner.
3. Öffnen Sie eine generierte Datei und prüfen Sie Datum, Einheiten und frontmatter.
4. Bewahren Sie die Ergebnisdetails für die Fehlerbehebung auf; schließen Sie nicht allein daraus auf Erfolg, dass die Schaltfläche wieder in den Ruhezustand wechselt.

<div class="callout">
<strong>Keine Daten für den ausgewählten Tag?</strong>
<p style="margin-top:6px;">Probieren Sie einen Tag aus, von dem Sie wissen, dass er Aktivitäts- oder Schlafdaten enthält. Prüfen Sie anschließend die Health-Autorisierung und die Metrikauswahl. Ein autorisierter, aber leerer Zeitraum ist etwas anderes als ein Übertragungs- oder Schreibfehler.</p>
</div>

## Nächste Schritte

<div class="related">
  <a href="/de/docs/metrics/"><span>Daten auswählen</span>Durchsuchen Sie Apple Health-Metriken und passen Sie Kategorien oder besondere Berechtigungen an.</a>
  <a href="/de/docs/format/"><span>Ausgabe gestalten</span>Konfigurieren Sie Formate, Datumsangaben, Einheiten, frontmatter, Vorlagen und Dateinamen.</a>
  <a href="/de/docs/scheduling/"><span>Automatisieren</span>Planen Sie wiederholte Exporte, nachdem ein manueller Durchlauf verifiziert wurde.</a>
  <a href="/de/docs/folder-vault/"><span>Ziel reparieren</span>Erfahren Sie mehr über Anbieter in Dateien, Ordnerzugriff und Wiederherstellung.</a>
</div>
