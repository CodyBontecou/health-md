---
title: "Schlafdaten und tägliche Notizen"
description: "Das richtige Schlaf-Exportdatum: Zeitfenster von Mittag zu Mittag, Einschlafen nach Mitternacht, Nickerchen und leere Ergebnisse."
---

**Beginn der Nacht** ist auf iPhone und Android die Standardeinstellung. Für die vergangene Nacht am Dienstagmorgen exportierst du **Montag**, normalerweise **Gestern**. Die tägliche Schlafübersicht von Health.md nutzt ein lokales Zeitfenster von **12:00 bis 12:00**: Montagmittag bis Dienstagmittag statt der Mitternachtsgrenze normaler Aktivitätsübersichten.

Wähle **Ende am Morgen** in den Exporteinstellungen, um jede vollständige Schlafphase dem Datum ihres Endes in der Zeitzone des Exports zuzuordnen, ohne sie am Mittag abzuschneiden. Für die Nacht von Montag auf Dienstag exportierst du **Dienstag (Heute)**; Nickerchen am Dienstag gehören ebenfalls zu Dienstag. Eine geänderte Einstellung gilt für neue Vorgänge; gespeicherte Vorgänge behalten ihre angenommene Zuordnung.

<div id="sleep-journal-window"></div>

## Warum Schlaf in der gestrigen Notiz steht

Das Fenster hält eine typische Nacht zusammen, auch wenn du erst nach Mitternacht einschläfst. Der erste Mittag ist eingeschlossen, der folgende ausgeschlossen. Schlaf über eine Mittagsgrenze hinweg kann zu benachbarten Tagesübersichten beitragen. Ursprüngliche Zeitstempel werden nicht an das Notizdatum angepasst.

Beide Arten der Schlafzuordnung sind auf Apple und Android verfügbar. Metriken, Schlafphasen, Quelldatensätze und Aggregation können weiterhin je nach Plattform abweichen.

<div id="sleep-date-examples"></div>

## Welches Datum exportieren?

**Beginn der Nacht:** Fiktive Beispiele in Ortszeit, keine Gesundheitsdaten:

| Schlaf oder Aktivität | Exportdatum |
| --- | --- |
| Montag 23:45 bis Dienstag 07:30 | **Montag** |
| Dienstag 01:00 bis Dienstag 07:30 | **Montag**, nicht Dienstag |
| Nickerchen am Dienstag, 14:00 bis 14:30 | **Dienstag** |
| Schritte und Aktivität am Dienstag | **Dienstag** |
| Montagnacht und Dienstagsaktivität | **Montag und Dienstag** |

Prüfe die lokale Zeitzone des Exports. Das Aufwachdatum einer anderen App oder das Änderungsdatum der Datei bestimmt nicht den Journaltag.

<div id="sleep-empty-checks"></div>

## Wenn die erwartete Notiz leer bleibt

1. Prüfe Journaltag und ausgewählte Schlafmetriken.
2. Lass Uhr oder Quell-App mit Apple Health oder Health Connect synchronisieren. Prüfe die Vorschau und exportiere den Journaltag erneut.
3. Prüfe Zugriffsrechte. Ein leeres HealthKit-Ergebnis verrät auf dem iPhone nicht, ob der Lesezugriff verweigert wurde. Unter Android muss die Quelle den unterstützten Datensatz tatsächlich in Health Connect geschrieben haben.
4. Prüfe Zielordner und geschriebene, übersprungene oder fehlgeschlagene Ergebnisse. Eine Vorschau beweist keine gespeicherte Datei. Fehlende Werte sind keine gemessene 0.

Daily Note Injection und API Endpoint verwenden die für den Vorgang gewählte Schlafzuordnung. Exportiere bei späten Quelldaten das zugehörige Datum dieses Modus erneut oder prüfe den Rückblick des Zeitplans. Hintergrundzeiten sind Zielwerte und garantieren keinen erfolgreichen Schreibvorgang.

<div id="sleep-records-and-queries"></div>

## Übersichten, Quelldaten und Sitzungsabfragen

Rohe oder kanonische Datensätze behalten ursprüngliche Zeitstempel und eigene Zuordnungsregeln. Rekonstruiere Sitzungen nicht aus einer Tagessumme und addiere Quellintervalle nicht als zusätzlichen Schlaf dazu.

**Beginn der Nacht:** Auf Apple werden Datensätze im Roharchiv anhand ihres ursprünglichen Beginns dem lokalen Kalendertag von Mitternacht bis Mitternacht zugeordnet. Die Schlafübersicht schneidet Intervalle dagegen auf das Tagebuchfenster von Mittag bis Mittag zu. Eine erfolgreiche rohe Sleep-Analysis-Abfrage kann deshalb morgendliche Datensätze enthalten, während die Schlafübersicht dieses Datums leer ist. Exportiere das vorherige Tagebuchdatum und prüfe `time_context.calendar_timezone`, bevor du eine fehlende Übersicht untersuchst. Beispielsweise gehören Datensätze vom 22. September, 04:03–11:52 UTC, in UTC vollständig zur Übersicht des 21. September; in Europe/Lisbon liegen die letzten 52 Minuten nach dem lokalen Mittag und zählen stattdessen zum 22. September.

Schlafstadien benötigen keinen ausdrücklichen `inBed`-Datensatz: Fehlt er, verwenden Apple-Übersichten die Vereinigungsmenge der verfügbaren als schlafend klassifizierten Intervalle. Fehlende Bettzeitdaten erzeugen keine Bettzeitdauer. Eine fehlgeschlagene Übersichtsabfrage sollte unter `diagnostics.partial_failures` erscheinen; eine erfolgreiche Abfrage ohne passende Intervalle ist ein gültiges Ergebnis ohne Daten. Der Ruhepuls verwendet eine separate Kalendertagsabfrage und erfordert eine tatsächliche Ruhepulsmessung; Schlafstadien oder eine Leseberechtigung allein liefern keine solche Messung.

`healthmd_sleep_sessions` benötigt eine unterstützte **Apple Health**-CLI/MCP-Konfiguration. Typisierte Android-MCP-Abfragen werden derzeit nicht unterstützt. Siehe [Plattformfähigkeiten](/de/docs/guides/platform-features/) und [MCP](/de/docs/mcp/).

Weitere Hilfe: [Zeitpläne](/de/docs/scheduling/), [Fehlersuche](/de/docs/troubleshooting/) und [Exportformate](/de/docs/format/).
