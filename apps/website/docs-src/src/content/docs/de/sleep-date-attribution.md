---
title: "Schlafdaten und tägliche Notizen"
description: "Das richtige Schlaf-Exportdatum: Zeitfenster von Mittag zu Mittag, Einschlafen nach Mitternacht, Nickerchen und leere Ergebnisse."
---

Für die vergangene Nacht am Dienstagmorgen exportierst du **Montag**, normalerweise **Gestern**. Die tägliche Schlafübersicht von Health.md nutzt ein lokales Zeitfenster von **12:00 bis 12:00**: Montagmittag bis Dienstagmittag statt der Mitternachtsgrenze normaler Aktivitätsübersichten.

<div id="sleep-journal-window"></div>

## Warum Schlaf in der gestrigen Notiz steht

Das Fenster hält eine typische Nacht zusammen, auch wenn du erst nach Mitternacht einschläfst. Der erste Mittag ist eingeschlossen, der folgende ausgeschlossen. Schlaf über eine Mittagsgrenze hinweg kann zu benachbarten Tagesübersichten beitragen. Ursprüngliche Zeitstempel werden nicht an das Notizdatum angepasst.

Apple und Android teilen dieses Fenster für kompatible Übersichten. Metriken, Schlafphasen, Quelldatensätze und Aggregation können weiterhin abweichen. Eine Umstellung auf das Aufwachdatum gibt es nicht.

<div id="sleep-date-examples"></div>

## Welches Datum exportieren?

Fiktive Beispiele in Ortszeit, keine Gesundheitsdaten:

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

Daily Note Injection und API-Endpoint-Übersichten nutzen dasselbe Fenster. Bei verspäteter Synchronisierung wiederhole den Journaltag oder prüfe den Rückblick des Zeitplans. Hintergrundausführung garantiert keine erfolgreiche Dateiablage zu einer exakten Uhrzeit.

<div id="sleep-records-and-queries"></div>

## Übersichten, Quelldaten und Sitzungsabfragen

Rohe oder kanonische Datensätze behalten ursprüngliche Zeitstempel und eigene Zuordnungsregeln. Rekonstruiere Sitzungen nicht aus einer Tagessumme und addiere Quellintervalle nicht als zusätzlichen Schlaf dazu.

Auf Apple ordnet das Roharchiv Datensätze anhand ihres Beginns dem lokalen Kalendertag von Mitternacht bis Mitternacht zu. Die Schlafzusammenfassung schneidet Intervalle dagegen auf das Fenster von Mittag bis Mittag zu. Eine erfolgreiche Sleep-Analysis-Abfrage kann daher morgendliche Datensätze enthalten, während die Zusammenfassung dieses Datums leer ist. Exportiere den vorherigen Journaltag und prüfe `time_context.calendar_timezone`. Beispielsweise gehören Datensätze vom 22. September, 04:03–11:52 UTC, in UTC vollständig zur Zusammenfassung des 21. September; in Europe/Lisbon liegen die letzten 52 Minuten nach lokalem Mittag und tragen stattdessen zum 22. September bei.

Schlafphasen benötigen keinen ausdrücklichen `inBed`-Datensatz: Fehlt er, verwendet Apple die Vereinigung der verfügbaren Schlafphasen, ohne eine Bettzeitdauer zu erfinden. Fehlgeschlagene Abfragen sollten unter `diagnostics.partial_failures` erscheinen; eine erfolgreiche Abfrage ohne passende Intervalle ist eine gültige Abwesenheit. Der Ruhepuls verwendet eine separate Kalendertagsabfrage und benötigt eine tatsächliche Ruhepulsmessung; Schlafphasen oder Leseberechtigung allein liefern sie nicht.

`healthmd_sleep_sessions` benötigt eine unterstützte **Apple Health**-CLI/MCP-Konfiguration. Typisierte Android-MCP-Abfragen werden derzeit nicht unterstützt. Siehe [Plattformfähigkeiten](/de/docs/guides/platform-features/) und [MCP](/de/docs/mcp/).

Weitere Hilfe: [Zeitpläne](/de/docs/scheduling/), [Fehlersuche](/de/docs/troubleshooting/) und [Exportformate](/de/docs/format/).
