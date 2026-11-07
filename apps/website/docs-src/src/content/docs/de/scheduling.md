---
title: "Planen Sie Apple Health Exporte und beheben Sie verpasste Ausführungen"
description: "Überprüfen Sie einen geplanten Export, verstehen Sie den Lookback für abgeschlossene Tage und stellen Sie ausstehende Daten wieder her. iPhone Hintergrund-Timing ist Best-Effort; Verlaufswiederholung verwendet aktuelle Einstellungen."
---

Auf dieser Seite wird iPhone Planung beschrieben. Für Android gelten unterschiedliche Hintergrundberechtigungen und Kaufanforderungen. siehe [Android-Automatisierung](/de/docs/android/).

## Überprüfen Sie den ersten geplanten Export

1. Aktivieren Sie das vorgesehene Profil. Überprüfen Sie die Metriken, Formate, Datendetails, das Schreibverhalten und das Ziel. Führen Sie einen abgeschlossenen Tag manuell aus und überprüfen Sie die gespeicherte Datei oder das Endpunktergebnis, bevor Sie die Automatisierung aktivieren.
2. Öffnen Sie auf dem iPhone **Automationen**, wählen Sie die Automation und tippen Sie auf **Zeitplan**; auf Android öffnen Sie „Zeitplan“ und dann „Zeitplan einrichten“ oder „Zeitplan verwalten“. Aktivieren Sie den Zeitplan, wählen Sie „Täglich“, „Wöchentlich“ oder „Benutzerdefiniert“, legen Sie die Uhrzeit fest und beginnen Sie mit einem Rückblick von einem abgeschlossenen Tag. Erlauben Sie Mitteilungen, wenn Sie lokale Wiederherstellungserinnerungen möchten.
3. Überprüfen Sie, ob die Planung aktiviert ist, das nächste Vorkommen und das letzte Ergebnis. Überprüfen Sie nach einem Versuch die Verlaufsdetails und das tatsächliche Ziel. Ein Etikett oder eine Benachrichtigung für die nächste Ausführung ist kein Beweis dafür, dass Daten geschrieben wurden.
4. Überprüfen Sie die exportierten Daten, Einheiten, Abdeckung und fehlenden Daten. Eine gespeicherte Datei allein beweist nicht, dass die Quelle vollständig erfasst ist.

In der abonnementaktivierten Telefonversion erfordern geplante und manuelle Exporte eine aktive Testversion, ein Abonnement, einen lebenslangen Kauf oder einen beibehaltenen permanenten Zugriff. Es gibt keine örtliche Freiausfuhrbewilligung. Der abgelaufene Zugriff muss wiederhergestellt werden, bevor ausstehende Arbeiten wieder aufgenommen werden können. Siehe [Entsperren und Paywall](/de/docs/paywall/).

## Verstehen Sie das Fenster für den abgeschlossenen Tag

Tägliche, wöchentliche und benutzerdefinierte Zeitpläne können einen Rückblick haben. Die benutzerdefinierte Kadenz wird ab dem Startdatum alle N Tage, Wochen oder Monate wiederholt. Bei jedem neuen Vorkommen wird das gesamte konfigurierte Fenster für den abgeschlossenen Tag erneut exportiert, einschließlich der zuvor exportierten Daten. Ein dreitägiger Rückblick umfasst den gestrigen Tag und die beiden vorangegangenen Tage. Durch die verzögerte Ausführung bleibt das Fenster am geplanten Brandtag verankert.

„Heute aktualisieren“ ist eine separate Arbeit für den aktuellen Tag und kein Ersatz für das Fenster für den abgeschlossenen Tag. Überprüfen Sie Pfade und Schreibverhalten, bevor sich Exporte überschneiden. Fügen Sie wiederholte tägliche Schnappschüsse nicht als neue Messungen hinzu.

## Wählen Sie den richtigen Wiederherstellungspfad

- **Ausstehende geplante Wiederherstellung:** entsperren Sie iPhone , öffnen Sie Health.md und überprüfen Sie den ausstehenden Versuch. Die genauen ungelösten Daten, gespeicherten Einstellungen und das Ziel bleiben erhalten. Abgeschlossene Termine bleiben abgeschlossen; Die Erholung weitet sich nicht zu einem neuen Rückblick aus.
- **Retry from History:** Dies startet einen neuen Lauf für diesen Bereich unter Verwendung der aktuell konfigurierten Einstellungen und des Ziels und zeichnet eine neue Verlaufszeile auf. Überprüfen Sie die aktive Konfiguration, bevor Sie auf „Wiederholen“ klicken. Es ist nicht dasselbe wie die Fortsetzung eines eingefrorenen, ausstehenden Versuchs.
- **Geändertes oder nicht verfügbares Ziel:** Stellen Sie den Zugriff wieder her oder überprüfen Sie das ausstehende Profil, bevor Sie es erneut versuchen. Eine alte iPhone API-Wiederherstellung darf einen geänderten Endpunkt oder Anmeldeinformationen nicht stillschweigend übernehmen. Starten Sie nicht wiederholt neue Versuche, während der ursprüngliche Versuch ungelöst ist.

Überprüfen Sie die ausstehenden Wiederherstellungs-, Profilidentitäts- und Zielregeln in [Profile exportieren](/de/docs/export-profiles/).

## Was iOS garantiert und was nicht

Die ausgewählte Zeit ist ein Ziel und keine garantierte Fertigstellungszeit. iOS steuert die Hintergrundlaufzeit und der Schutz vor gesperrten Geräten kann HealthKit Lesevorgänge verhindern. Hintergrundanfragen und stille Weckbenachrichtigungen umgehen diesen Schutz nicht.

Lokale Wiederherstellungsbenachrichtigungen erfordern eine Benachrichtigungserlaubnis und stellen keine Garantie für die Zustellung zum Zielzeitpunkt dar. Wenn Sie eines erhalten, entsperren Sie das Gerät und öffnen Sie es, damit Health.md die Wiederherstellung versuchen kann. Wenn keine Benachrichtigung eintrifft, öffnen Sie Health.md und überprüfen Sie die ausstehenden Arbeiten und den Verlauf. Überprüfen Sie das Ergebnis, anstatt davon auszugehen, dass eine Warnung oder eine verstrichene Zeit Erfolg bedeuten.

## Programmgesteuerte Steuerung
 <p> Sie können den Zeitplan über Shortcuts mithilfe der Absicht <em> Geplanten Export ein- oder ausschalten </em> ein-/ausschalten. <a href="/de/docs/shortcuts/"> Beispiele finden Sie unter Shortcuts </a> . </p>

## Profilpläne und Stornierung

- Jedes Profil kann seinen eigenen Zeitplan beibehalten, einschließlich einer benutzerdefinierten Kadenz. Durch den Wechsel des aktiven Profils wird der Zeitplan eines anderen Profils nicht neu ausgerichtet.
- Eine Kollisionswarnung wird angezeigt, wenn Profile dieselben gerenderten Pfade an dasselbe Ziel schreiben könnten. Überprüfen Sie es, bevor Sie konkurrierende Zeitpläne aktivieren. Health.md ändert keines der Profile stillschweigend.
- Stop oder Cancel beendet nur den aktuellen Versuch. Abgeschlossene Termine bleiben abgeschlossen, ungelöste Termine können wiederholt werden und der Zeitplan bleibt aktiviert.
- Jede Verlaufszeile bleibt an das tatsächlich verwendete Laufzeitprofil und die datenschutzsichere Zielbezeichnung angeheftet.

Verwalten Sie die eingefrorenen Einstellungen und das Ziel pro Profil unter [Profile exportieren](/de/docs/export-profiles/).

## Verwandt

<div class="related">
 <a href="/de/docs/export-profiles/"> <span> Mehrere Arbeitsabläufe </span> Exportprofile, geben Sie jedem gespeicherten Setup sein eigenes Ziel und seine eigene Kadenz. </a>
 <a href="/de/docs/export/"> <span> Manuell </span> Export, für einmalige Datumsbereiche. </a>
 <a href="/de/docs/shortcuts/"> <span> Automatisieren </span> Shortcuts , schalten Sie den Zeitplan von Automatisierungen um. </a>
 <a href="/de/docs/sync/"> <span> Geräteübergreifend </span> Mac-Synchronisierung, auch auf dem Mac planen. </a>
 </div>
