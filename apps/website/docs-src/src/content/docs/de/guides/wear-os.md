---
title: Wear-OS-Begleiter
description: Health.md für Wear OS fügt Ihrer Uhr Aktivitäts- und Wiederherstellungskacheln sowie zehn Gesundheits-Komplikationen hinzu, während das Telefon die Health Connect-Autorität bleibt.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Android · Wear OS</p>
  <p>Health.md liefert einen Wear-OS-Begleiter unter derselben Google-Play-Eintragung wie die Smartphone-App. Fügen Sie Ihrer Uhr auf einen Blick lesbare Gesundheitsflächen hinzu, während Ihr Smartphone die alleinige Health Connect-Autorität bleibt.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Bei Google Play herunterladen</a>
    <a class="docs-button-secondary" href="/de/docs/android/">Android-App-Leitfaden</a>
  </div>
</div>

## Was die Uhr zeigt

| Fläche | Das erhalten Sie |
|---|---|
| Kachel „Tägliche Aktivität“ | Heutige Aktivitätsübersicht als Zifferblatt-Kachel |
| Wiederherstellungs-Kachel | Heutige Wiederherstellungsübersicht als Zifferblatt-Kachel |
| Komplikationen (10) | Aktivität, Wiederherstellung, Schritte, Bewegung, Training, Schlaf, Ruhepuls, Durchschnittspuls, HRV und Blutsauerstoff als Zifferblatt-Komplikationen |

Komplikationen können über den Zifferblatt-Editor zu den meisten Zifferblättern hinzugefügt werden, und Kacheln erscheinen im Kachel-Karussell der Uhr.

## So funktioniert es

- Die Watch-App wird über dieselbe Play-Eintragung und Signatur-Identität wie die Smartphone-App ausgeliefert.
- Gesundheitsdaten fließen Telefon → Uhr über die Wear-OS-Datenschicht als privater aggregierter Snapshot. Die Uhr hat **kein direktes Health Connect- oder Health-Services-Sensing**; das Telefon bleibt für jede Metrik maßgeblich.
- Watch-Flächen aktualisieren sich aus dem neuesten Snapshot, den die Smartphone-App überträgt — keine Konten, keine Cloud, und keine Gesundheitsdaten verlassen Ihre Geräte.

## Voraussetzungen

- Ein Android-Smartphone mit installiertem Health.md, gekoppelt mit einer Wear-OS-Uhr.
- Health Connect-Daten auf dem Smartphone für die Metriken, die Sie sehen möchten.
- Installieren Sie Health.md auf der Uhr über den Play Store der Uhr oder über den Play-Store-Eintrag des Begleit-Telefons.

## Einrichtung

1. Öffnen Sie den Play Store auf Ihrer Uhr (oder den Uhrenbereich des Play Store am Telefon) und installieren Sie Health.md.
2. Öffnen Sie die Smartphone-App einmal, damit ein Snapshot synchronisiert werden kann.
3. Halten Sie Ihr Zifferblatt lange gedrückt → **Anpassen** → fügen Sie eine Health.md-Komplikation hinzu, oder wischen Sie zum Kachel-Karussell und heften Sie eine Health.md-Kachel an.

## Datenschutz und Validierung

Der Begleiter verwendet einen reinen privaten Aggregat-Transportvertrag, sodass keine rohen Datensätze an die Uhr übertragen werden. Die Release-Qualität wird über Emulator-Suiten sowie Akku- und OEM-QA-Nachweise physisch gekoppelter Geräte abgesichert, bevor Wear-OS-Artefakte ausgeliefert werden. Siehe die [Wear-OS-Implementierungs-Checkliste](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/features/wear-os-implementation.md) für das vollständige Runbook.
