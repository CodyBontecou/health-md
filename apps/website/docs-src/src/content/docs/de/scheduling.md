---
title: "Apple Health-Exporte planen und verpasste Ausführungen beheben"
description: "Prüfen Sie geplante Exporte, Rückblick und Wiederherstellung. iOS garantiert keine Ausführungszeit; Wiederholen im Verlauf nutzt aktuelle Einstellungen."
---

Diese Seite beschreibt die iPhone-Zeitplanung. Android hat andere Hintergrundberechtigungen und Kaufvoraussetzungen; siehe [Android-Automatisierung](/de/docs/android/).

## Den ersten geplanten Export prüfen

1. Aktivieren Sie das vorgesehene Profil. Prüfen Sie Metriken, Formate, Datendetail, Schreibverhalten und Ziel. Exportieren Sie einen abgeschlossenen Tag manuell und kontrollieren Sie Datei oder Endpunkt-Ergebnis vor der Automatisierung.
2. Öffnen Sie Zeitplan und Zeitplan einrichten oder Zeitplan verwalten. Aktivieren Sie den Zeitplan, wählen Sie täglich, wöchentlich oder benutzerdefiniert, legen Sie die Uhrzeit fest und beginnen Sie mit einem abgeschlossenen Rückblicktag. Erlauben Sie Mitteilungen für lokale Wiederherstellungshinweise.
3. Prüfen Sie Aktivierung, nächsten Termin und letztes Ergebnis. Kontrollieren Sie nach einem Versuch Verlauf und tatsächliches Ziel; ein Termin oder eine Mitteilung beweist keinen Schreibvorgang.
4. Prüfen Sie Datumsbereich, Einheiten, Abdeckung und fehlende Daten. Eine gespeicherte Datei beweist allein keine vollständige Quellerfassung.

Auf Apple zählt ein geplanter Auftrag mit mindestens einem exportierten Datum zum gemeinsamen Kontingent von fünf kostenlosen Exportaktionen. Full Access hebt dieses Limit auf. Siehe [Freischaltung und Käufe](/de/docs/paywall/).

## Das Fenster abgeschlossener Tage verstehen

Tägliche, wöchentliche und benutzerdefinierte Zeitpläne können einen Rückblick haben. Benutzerdefiniert wiederholt alle N Tage, Wochen oder Monate ab dem Startdatum. Jeder neue Termin exportiert das gesamte konfigurierte Fenster erneut, auch bereits exportierte Tage. Drei Tage umfassen gestern und die zwei Tage davor; bei Verzögerung bleibt der geplante Auslösetag der Bezugspunkt.

Die Heute-Aktualisierung ist eigenständige Arbeit für den laufenden Tag und ersetzt dieses Fenster nicht. Prüfen Sie Pfade und Schreibverhalten bei Überlappungen; wiederholte Tagesstände sind keine zusätzlichen Messungen.

## Den richtigen Wiederherstellungsweg wählen

- **Ausstehender geplanter Auftrag:** Entsperren Sie das iPhone, öffnen Sie Health.md und prüfen Sie den Auftrag. Er behält die exakten offenen Daten, gespeicherten Einstellungen und das Ziel. Abgeschlossene Tage bleiben abgeschlossen; der Rückblick wird nicht erweitert.
- **Wiederholen im Verlauf:** Startet einen neuen Lauf für diesen Bereich mit aktuellen Einstellungen und aktuellem Ziel und erzeugt eine neue Verlaufszeile. Prüfen Sie vorher die aktive Konfiguration. Dies ist keine Fortsetzung des eingefrorenen Auftrags.
- **Geändertes oder unerreichbares Ziel:** Stellen Sie den Zugriff wieder her oder prüfen Sie das ausstehende Profil. Eine alte iPhone-API-Wiederherstellung darf keinen geänderten Endpunkt oder Zugangsnachweis still übernehmen. Starten Sie keine weiteren Wiederholungen, solange der ursprüngliche Versuch ungeklärt ist.

Siehe [Exportprofile](/de/docs/export-profiles/) für Wiederherstellung, Identität und Zielregeln.

## Was iOS garantiert und was nicht

Die Uhrzeit ist ein Ziel, keine garantierte Abschlusszeit. iOS steuert Hintergrundlaufzeit; bei gesperrtem Gerät kann HealthKit nicht lesbar sein. Hintergrundanforderungen und stille Mitteilungen umgehen diesen Schutz nicht.

Lokale Hinweise benötigen Mitteilungsberechtigung und garantieren keine Zustellung zur Zielzeit. Entsperren Sie bei einem Hinweis das Gerät und öffnen Sie ihn für einen Wiederherstellungsversuch. Ohne Hinweis öffnen Sie Health.md und prüfen offene Aufträge und Verlauf. Kontrollieren Sie das Ergebnis statt Erfolg aus einer Mitteilung oder verstrichener Zeit abzuleiten.

## Programmatische Steuerung
<p>Sie können den Zeitplan in Kurzbefehle mit dem Intent <em>Geplanten Export ein- oder ausschalten</em> aktivieren und deaktivieren. Beispiele finden Sie unter <a href="/de/docs/shortcuts/">Kurzbefehle</a>.</p>

## Profilzeitpläne und Abbruch

- Jedes Profil hat einen eigenen Zeitplan einschließlich benutzerdefinierter Frequenz; ein Wechsel des aktiven Profils leitet keinen anderen Zeitplan um.
- Eine Kollisionswarnung erscheint, wenn Profile dieselben erzeugten Pfade am selben Ziel schreiben könnten. Prüfe sie vor konkurrierenden Zeitplänen; Health.md ändert kein Profil unbemerkt.
- Stoppen oder Abbrechen beendet nur den aktuellen Versuch. Abgeschlossene Tage bleiben erhalten, offene Tage sind wiederholbar und der Zeitplan bleibt aktiv.
- Jeder Verlaufseintrag bleibt mit dem Laufprofil und der tatsächlich verwendeten datenschutzfreundlichen Zielbezeichnung verbunden.

Einstellungen und Profilziel verwaltest du unter [Exportprofile](/de/docs/export-profiles/).

## Verwandte Themen

<div class="related">
  <a href="/de/docs/export-profiles/"><span>Profile</span>Unabhängige Zeitpläne und Ziele verwalten.</a>
  <a href="/de/docs/export/"><span>Manuell</span>Export – für einmalige Datumsbereiche.</a>
  <a href="/de/docs/shortcuts/"><span>Automatisieren</span>Kurzbefehle – schalten Sie den Zeitplan über Automationen um.</a>
  <a href="/de/docs/sync/"><span>Geräteübergreifend</span>Mac-Synchronisierung – planen Sie Exporte auch auf dem Mac.</a>
</div>
