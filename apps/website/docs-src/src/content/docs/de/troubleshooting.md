---
title: "Daten fehlen beim Apple-Health-Export? Health.md-Fehlerbehebung"
description: "Prüfe leere Apple-Health- oder Health-Connect-Exporte, fehlenden Schlaf, CSV-Details, Schreibfehler und verzögerte Zeitpläne anhand eines Tages."
---

Fehlen Daten im Export aus Apple Health oder Health Connect, unterscheide zuerst ein **Leseproblem** von einem **Problem beim Speichern**. Fehlende Daten sind kein gemessener Nullwert.

## Mit einem überprüfbaren Tag beginnen

1. Prüfe einen aufgezeichneten Wert und sein Datum in Apple Health oder Health Connect. Warte, bis Uhr oder Quell-App synchronisiert haben.
2. Prüfe in Health.md aktives Profil, Messwert, Zeitraum, Format und Ziel. Beginne mit einem unterstützten Messwert für einen abgeschlossenen Tag.
3. Entsperre das Telefon, öffne Health.md und nutze die Vorschau, sofern verfügbar. Exportiere danach und prüfe Ergebnis und tatsächliches Ziel. Eine Vorschau beweist nicht, dass eine Datei gespeichert wurde.

Siehe [erster iPhone-Export](/de/docs/iphone-first-export/) oder [Android-Einrichtung](/de/docs/android/).

## Die Quelle enthält Daten, der Export ist leer

Prüfe auf dem iPhone die für Health.md erlaubten Kategorien in Apple Health. **HealthKit teilt nicht mit, ob eine Leseberechtigung verweigert wurde.** Ein leeres Ergebnis unterscheidet daher nicht zwischen fehlendem Zugriff und fehlenden passenden Datensätzen. Auch eine erfolgreiche Berechtigungsanfrage bestätigt nicht jede Lesekategorie. Siehe [Apples Autorisierungsdokumentation](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).

Prüfe auf Android, ob die Quell-App den Datensatz tatsächlich in Health Connect geschrieben hat und Health.md diesen unterstützten Typ lesen darf. Nur in einer anderen App sichtbare Daten sind nicht unbedingt exportierbar. Siehe [Googles Prüfliste](https://support.google.com/android/answer/13770384).

Prüfe nach Synchronisierung oder Berechtigungsänderungen Messwert und Datum erneut. Ersetze fehlende Werte nicht durch Null.

Meldet ein strukturiertes Ergebnis `complete_empty`, unterscheide es von nicht unterstützter, teilweiser, übersprungener oder fehlgeschlagener Ausgabe. Es beweist weder einen gemessenen Nullwert noch eine Entscheidung über die Leseberechtigung.

## Der Schlaf der letzten Nacht fehlt unter Heute

**Beginn der Nacht (Standard):** Health.md nutzt auf Apple und Android ein lokales Schlaffenster **von Mittag zu Mittag**. Exportiere am Dienstagmorgen **Gestern** (Montag), auch für Schlafbeginn nach Mitternacht am Dienstag, oder Montag und Dienstag für Schlaf und Aktivität. Bei später Synchronisierung wiederhole den Journaltag. Siehe [Datumsbeispiele](/de/docs/sleep-date-attribution/#sleep-date-examples). **Ende am Morgen:** Exportiere stattdessen das Aufwachdatum, also Dienstag für die Nacht von Montag auf Dienstag. Beide Modi verwenden die Zeitzone des Exports.

## Die Vorschau zeigt Daten, der Ordner ist leer

Prüfe auf dem iPhone, ob das aktive Profil in einen lokalen Ordner, an Connected Mac oder API Endpoint schreibt. Prüfe bei Dateien Ordner, Unterordner, Dateiname und Ergebnis: geschrieben, übersprungen oder fehlgeschlagen. Überspringen kann dem gewählten Schreibverhalten entsprechen. Wähle einen nicht verfügbaren Ordner erneut und prüfe seinen Dateianbieter. Siehe [Ordner und Vaults](/de/docs/folder-vault/) und [Exportprofile](/de/docs/export-profiles/).

## Die CSV enthält Summen statt der erwarteten Messungen

Auf dem iPhone liefern Summary und Detailed Time-Series unterschiedliche Details. Prüfe Data Detail und Messwerte vor einem größeren Zeitraum. Metadaten sind keine Gesundheitsmessungen. Behalte Einheiten bei und unterscheide Tagessummen von Quelldatensätzen. Lossless Health Records hat einen eigenen Erfassungsstatus; eine Zusammenfassung beweist keine vollständige Erfassung. Siehe [Format und Abdeckung](/de/docs/reference/export-formats/).

## Ein geplanter Export fehlt

iOS-Hintergrundarbeit und Android WorkManager verwenden Zielzeiten ohne Liefergarantie. Entsperre das Gerät, öffne Health.md und prüfe Verlauf und ausstehende Wiederherstellung vor einem weiteren Lauf. Eine Benachrichtigung beweist keinen erfolgreichen Schreibvorgang. Siehe [iPhone-Zeitpläne](/de/docs/scheduling/) oder [Android-Automatisierung](/de/docs/android/).

## CLI-Timeout

Ein Timeout bricht einen angenommenen Job nicht ab:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

Vor Vollständigkeitsbehauptungen Status, fehlende Tage, Abdeckung, `next_cursor`, Version und Einschränkungen prüfen. `--allow-partial` ändert nur den Exit-Status.

## Hilfe ohne Gesundheitsdaten anfordern

Nenne App- und Betriebssystemversion, Plattform, Format sowie leere Daten, übersprungene Ausgabe oder Schreibfehler. Schwärze private Angaben in Screenshots und Protokollen. Veröffentliche keine Gesundheitswerte, Routen, klinischen Dokumente, Tokens, Kopplungscodes oder privaten Pfade.

<div class="related"><a href="/de/docs/cli-jobs/"><span>Jobs</span>Fortsetzen und abbrechen.</a><a href="/de/docs/release-status/"><span>Versionen</span>Kompatibilität.</a></div>
