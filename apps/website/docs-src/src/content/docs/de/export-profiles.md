---
title: "Exportprofile"
description: "Speichere Exporteinstellungen und ein Ziel gemeinsam und führe diese Konfiguration auf iPhone, Android, über Kurzbefehle, die CLI, Tasker oder adb aus oder plane sie."
---

Exportprofile bündeln eine wiederholbare Exportkonfiguration. Verwalte sie in Health.md auf dem iPhone oder unter Android. Auf Apple-Plattformen ist der aktuelle Verwaltungsablauf nur für das iPhone dokumentiert und getestet; für iPad oder Mac wird keine Verwaltungsoberfläche zugesichert.

## Profile verwalten und bearbeiten

Öffne **Einstellungen → Exportprofile**. Die Liste kennzeichnet das aktive Profil. Dort kannst du Profile erstellen, umbenennen, duplizieren, löschen, aktivieren oder prüfen. In der Detailansicht lässt sich die stabile ID kopieren. Das letzte verbleibende Profil kann nicht gelöscht werden.

Der Export-Tab bearbeitet das aktive Profil. Aktiviere vor Änderungen ein anderes Profil, wenn du das aktuelle nicht aktualisieren möchtest.

Jedes Profil fixiert die für eine wiederholbare Ausführung nötigen Optionen:

- ausgewählte Metriken, Datendetails, Formate, Vorlagen, Dateinamen, Einheiten und Schreibverhalten;
- einen eigenen Zielordner mit Unterordner, API-Endpunkt oder ein Ziel auf dem verbundenen Mac, sofern die Plattform dies unterstützt;
- Tagesnotizen, Einzeleinträge, Roll-ups und weitere von der Plattform unterstützte Ausgabeoptionen.

Ein Zeitplan ist separat an die stabile Identität des Profils gebunden. Das Wechseln des aktiven Profils ändert dieses Ziel nicht. Eine Profilausführung verwendet den gespeicherten Stand, statt geänderte Einstellungen eines anderen Profils zu übernehmen.

## Sicher ausführen und planen

- Jedes Profil kann einen eigenen wiederkehrenden Zeitplan einschließlich der angebotenen benutzerdefinierten Frequenz haben.
- Plattformberechtigungen gelten weiterhin: Apples kostenlose Freigrenze kann geplante Aktionen umfassen, während die Android-Zeitplanung die dauerhafte Freischaltung erfordert.
- Health.md warnt, wenn Profile dieselben erzeugten Pfade am selben Ziel beschreiben könnten. Die Warnung ändert weder Profil noch Zeitplan unbemerkt.
- Stoppen oder Abbrechen betrifft nur den aktuellen Versuch. Abgeschlossene Tage bleiben erhalten, offene Tage können erneut versucht werden und der Zeitplan bleibt aktiviert.
- Fehlt das referenzierte Profil, bricht Health.md sicher ab. Es fällt nie auf das aktive Profil oder ein anderes Ziel zurück.

## Namen, stabile IDs und Automatisierung

Der Anzeigename ist für Menschen und kann geändert werden. Die stabile ID eignet sich für umbenennungssichere Automatisierung. Kopiere sie unter **Einstellungen → Exportprofile → Profil-ID**.

- Apple-Kurzbefehle wählen ein Profil über den Anzeigenamen; ein leerer Profilparameter verwendet das aktive Profil.
- Android-Broadcasts über Tasker und adb können im Extra `PROFILE` eine stabile ID oder einen Namen übergeben. Nutze für umbenennungssichere Abläufe möglichst die ID.
- Die direkte CLI akzeptiert `--profile PROFILE_ID` für unterstützte Aufträge mit generierten Dateien. Das Profil liefert seine fixierten Ausgabeeinstellungen; das erforderliche `--destination` wählt weiterhin den vorhandenen Ordner auf dem Computer.

Prüfe vor unbeaufsichtigten Abläufen die jeweilige Automatisierungsanleitung.

## Verlauf, Wiederherstellung und Datenschutz

Profilbezogene geplante und automatisierte Verlaufszeilen speichern das beim Lauf verwendete Profil. Der Verlauf behält außerdem eine datenschutzfreundliche Bezeichnung des tatsächlich verwendeten Ziels. Ein manueller Lauf vom Export-Tab fügt möglicherweise keinen Profilnamen an, obwohl er die Einstellungen des aktiven Profils verwendet. Späteres Umbenennen, ein Zielwechsel oder die Auswahl eines anderen Profils verändert bestehende Einträge nicht.

Ein aus dem Exportverlauf gestarteter erneuter Versuch verwendet die aktuell konfigurierten Einstellungen und das aktuelle Ziel und legt einen neuen Eintrag mit den tatsächlich verwendeten Werten an. Er behauptet nicht, dass das ursprüngliche Profil den Versuch gesteuert hat. Die Wiederherstellung oder Fortsetzung eines offenen geplanten Versuchs behält dagegen dessen genaue Daten, Einstellungen und Ziel bei.

Profile und Zeitpläne sind lokale Geräteeinstellungen. Sie werden nicht zwischen iPhone, iPad, Mac und Android synchronisiert. Richte die gewünschte Konfiguration auf jedem Gerät neu ein und prüfe vor der Automatisierung das Ziel.

## Verwandte Themen

<div class="related">
  <a href="/de/docs/export/"><span>Export</span>Datendetail wählen, Ausgabe prüfen und einen Datumsbereich exportieren.</a>
  <a href="/de/docs/scheduling/"><span>Zeitplanung</span>Profilfrequenzen, Wiederherstellung und Zeitlimits der Plattform verstehen.</a>
  <a href="/de/docs/shortcuts/"><span>Kurzbefehle</span>Ein gespeichertes Profil in Apple-Automationen auswählen.</a>
  <a href="/de/docs/android/"><span>Android-Automatisierung</span>Profilbezogene Tasker- und adb-Aktionen verwenden.</a>
  <a href="/de/docs/cli-direct/"><span>Direkte CLI</span>Gespeicherte Profilausgaben in einen expliziten Computerordner schreiben.</a>
</div>
