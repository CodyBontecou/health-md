---
title: Funktionen nach Plattform
description: Was Health.md auf iPhone, iPad, Mac, Android, Wear OS und der CLI bietet — gemeinsame Funktionen und die ehrlichen Plattformunterschiede.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Plattform-Überblick</p>
  <p>Was Health.md auf iPhone, iPad, Mac, Android, Wear OS und der CLI tut — überall dort gemeinsam, wo es die Plattformen erlauben, und ehrlich, wo sie sich unterscheiden.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://apps.apple.com/us/app/health-md/id6757763969" target="_blank" rel="noopener">iPhone & Mac</a>
    <a class="docs-button-secondary" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Android</a>
  </div>
</div>

Legende: ✓ verfügbar · ◐ verfügbar mit den in der Zeile genannten Plattformunterschieden · △ geplant oder in Qualitätssicherung · ? Verfügbarkeit wird nicht beansprucht · — auf dieser Plattform nicht verfügbar.

Die CLI ist keine eigene Spalte für eine Gesundheitsdatenplattform: CLI-Funktionen erscheinen in den Zeilen zur Automatisierung und behalten die Semantik ihrer iPhone- oder Android-Quelle.

## Einrichtung und Berechtigungen

| Funktion | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Berechtigungen für Gesundheitsdaten (genau festlegen, was gelesen wird) | ✓ Apple Health-Typen | ◐ liest über das gekoppelte iPhone / Mac-Ziel | ✓ Health Connect-Kategorien | — |
| Exportziel wählen | ✓ Obsidian-Vault, iCloud Drive, Dateien | ✓ lokale Ordner | ✓ beliebiger Android-Ordneranbieter (Drive, OneDrive, Syncthing, Obsidian Sync…) | — |
| Onboarding mit Beispielvorschau | ✓ | ✓ | ✓ | — |
| Share My Setup (Einstellungen zwischen Geräten übertragen) | △ in QA | △ in QA | △ in QA | — |

## Lesen und Exportieren

| Funktion | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Tägliche Exporte als Markdown, Obsidian Bases, JSON, CSV | ✓ | ✓ (Dateien kommen vom iPhone) | ✓ | — |
| 225+ Apple Health-Metriken / 106 Health Connect-Metriken | ✓ | ✓ | ✓ | — |
| Vorschau vor dem Schreiben | ✓ | ✓ | ✓ | — |
| Gespeicherte Exportprofile mit unabhängigen Einstellungen | ✓ Verwaltung auf dem iPhone; ? iPad-Verwaltung nicht beansprucht | ? Verwaltung nicht beansprucht | ✓ Verwaltung auf Android | — |
| Wochen-, Monats- und Jahres-Zusammenfassungen | ✓ | ✓ | △ geplant; erfordert ein separat geprüftes Android-Schema-Profil (aktuelle v4/v5 bleiben unverändert) | — |
| Exportverlauf und Wiederholung | ✓ | ✓ | ✓ | — |
| Aktiven Durchlauf stoppen oder abbrechen, ohne den Zeitplan zu deaktivieren | ✓ abgeschlossene Daten bleiben erhalten; offene Daten sind wiederholbar | ✓ | ✓ abgeschlossene Daten bleiben erhalten; offene Daten sind wiederholbar | — |
| ZIP-Archiv einer einzelnen Ausführung | ✓ | ✓ | — | — |
| Zusammenfassungs-Datendetail | ✓ | ✓ | ✓ | — |
| Detaillierte Zeitreihen für ausgewählte Metriken | ✓ | ✓ | ✓ | — |
| Kanonisches Quellarchiv der Lossless Health Records | ✓ `healthmd.healthkit_records` | ✓ | — nur Apple; siehe stattdessen Rohe API-Snapshots | — |
| Export roher API-Snapshots (unveränderliches JSON/NDJSON) | — | — | ✓ Health Connect + Fitbit, Oura, WHOOP, Withings | — |

## Erweiterte Daten

| Funktion | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Einzelverfolgung (Trainingseinheiten, Schlafphasen, Vitalwerte) | ✓ | ✓ | ✓ | — |
| Trainingsdetails mit vollständigen Diagrammen und Routen, wo angeboten | ✓ | ✓ | ✓ | — |
| Export von Stimmung / State of Mind | ✓ | ✓ | — (kein Health-Connect-Äquivalent) | — |
| Ereignisse von Medikamentendosen | ✓ | ✓ | — (kein Health-Connect-Äquivalent) | — |
| Blutdruck-, Glukose-, Sauerstoff- und Temperaturmesswerte | ✓ | ✓ | ✓ | — |
| Daten von Drittanbietern | ◐ WHOOP-Abschnitt im Export (Beta) | ◐ | ✓ anbietereigene rohe Snapshots | — |

Einige Daten werden plattformübergreifend bewusst **nicht als gleichwertig behandelt**: Die Herzfrequenzvariabilität ist SDNN auf Apple und RMSSD auf Android und WHOOP — Health.md führt sie als getrennte Metriken, statt sie zu vermischen. Die Handgelenktemperatur der Apple Watch und die Hauttemperatur von Health Connect werden ebenfalls getrennt geführt.

## Automatisieren und integrieren

| Funktion | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Geplante wiederkehrende Exporte | ✓ Benachrichtigungen + APNs-Fallback | ✓ | ✓ WorkManager (+ optionaler exakter Alarm), Wiederherstellung nach Neustart | — |
| Systemautomatisierung | ✓ Kurzbefehle / Siri / App Intents | — | ✓ Tasker, adb, explizite Broadcast-Intents | — |
| Exporte an Ihren eigenen HTTP(S)-API-Endpunkt senden | ✓ | — | ✓ mit verschlüsselter Speicherung der Header | — |
| Kopplung mit der eigenständigen CLI (`healthmd`) | ✓ Direktdienst im Vordergrund | ✓ gebündelt + eigenständig | ✓ Kopplung mit 20-stelligem Code | — |
| Aufwecken für direkte CLI-Anfragen | ✓ begrenztes Warten + optionale APNs | ✓ CLI-Initiator | ◐ begrenztes Warten; FCM geplant | — |
| MCP-Server für KI-Agenten | ◐ über den Mac gebündelt; das typisierte portable direkte MCP ist ausschließlich für das iPhone | ✓ gebündelt als `healthmd-mcp` | — typisiertes direktes MCP nicht unterstützt | — |

## Geräte und Flächen auf einen Blick

| Funktion | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Widgets auf dem Startbildschirm | ✓ Zusammenfassung, Aktivitätsringe, Herzfrequenzbereich, Schlaf | — | ✓ Zusammenfassung, Aktivität, Herzfrequenzbereich, Schlaf (Schritte ersetzen Stehen-Stunden) | — |
| Live-Aktivität für den Exportfortschritt | ✓ | — | — | — |
| Uhrenflächen | ✓ Watch-App + 10 Komplikationen | — | — | ✓ Kacheln + 10 Komplikationen |
| Mac als Exportziel (verschlüsselte lokale Übertragung) | ✓ iPhone sendet | ✓ empfängt | — | — |

## Kauf und Datenschutz

| Funktion | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Kostenloses Kontingent | ✓ 10 manuelle oder geplante Exportaktionen | — | ✓ 10 manuelle Exportaktionen | — |
| Freischaltung | ✓ einmaliger Lebenszeitkauf (Einzeln / Familie) | ◐ gleiche Apple-Freischaltung | ✓ einmaliger Lebenszeitkauf, Zeitplanung inklusive | — |
| Datenschutz mit lokaler Verarbeitung | ✓ keine Health.md-Cloud für Gesundheitsdaten | ✓ | ✓ | ✓ |
| Arztbericht (ein PDF für Termine) | ✓ | — | ✓ | — |

Health.md betreibt keine Cloud für Gesundheitsdaten. Gesundheitsdaten können in Zielen Ihrer Wahl, in verschlüsseltem lokalem Kontext und in begrenztem privaten Übertragungszustand existieren. Jedes Ziel — Ordner, Mac, API-Endpunkt oder CLI — wird explizit konfiguriert. Profile und Zeitpläne bleiben lokal auf dem Gerät, auf dem sie erstellt wurden. Die Workflows der einzelnen Plattformen finden Sie in den [Exportprofilen](/de/docs/export-profiles/), im [Android-Leitfaden](/de/docs/android/) und im [iPhone-Export-Leitfaden](/de/docs/export/).
