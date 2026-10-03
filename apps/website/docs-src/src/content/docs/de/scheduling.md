---
title: "Zeitplanung"
description: "Führen Sie Exporte automatisch mit täglicher, wöchentlicher oder benutzerdefinierter Kalenderfrequenz aus. iOS nutzt Hintergrundaufgaben und bei nicht verfügbaren geschützten Daten eine lokale Wiederherstellungsmitteilung."
---

## Der Tab „Zeitplan“
<p>Eine Statusansicht, kein Einstellungsbereich. Sie erkennen auf einen Blick:</p>
<ul>
<li>ob der Zeitplan ein- oder ausgeschaltet ist;</li>
<li>den nächsten geplanten Durchlauf, sofern vorhanden;</li>
<li>das Ergebnis des letzten Durchlaufs.</li>
</ul>
<p>Eine Schaltfläche – <em>Zeitplan einrichten</em> oder <em>Zeitplan verwalten</em> – öffnet die Detailansicht.</p>

## Zeitplaneinstellungen
<div class="options">
<div class="option"><strong>Geplante Exporte aktivieren</strong><p>Hauptschalter am oberen Rand. Ist er ausgeschaltet, gibt es weder Hintergrunddurchläufe noch Mitteilungen.</p></div>
<div class="option"><strong>Häufigkeit</strong><p>Täglich, wöchentlich oder benutzerdefiniert. Benutzerdefinierte Zeitpläne wiederholen sich ab einem Startdatum alle N Tage, Wochen oder Monate. Der Rückblick legt fest, wie viele abgeschlossene Tage ein Lauf umfasst.</p></div>
<div class="option"><strong>Uhrzeit</strong><p>Stunde und Minute. iOS behandelt diese Angabe als Richtwert, nicht als Garantie – beachten Sie den Hinweis zu Einschränkungen weiter unten.</p></div>
</div>

## Exportverlauf
<p>Die Liste am unteren Rand der Zeitplanansicht zeichnet jeden geplanten Durchlauf mit seinem Ergebnis auf. Tippen Sie auf eine Zeile, um Details anzuzeigen. Fehlgeschlagene Durchläufe enthalten die Schaltfläche <em>Wiederholen</em>, die den Datumsbereich mit den aktuell konfigurierten Einstellungen und dem aktuellen Ziel erneut ausführt und anschließend eine neue Verlaufszeile anlegt.</p>

## So funktioniert die iOS-Zeitplanung tatsächlich
<div class="doc-diagram">
  <div class="flow-steps" aria-label="Fallback-Ablauf für einen geplanten Export">
    <span><strong>1. Zielzeit</strong>Health.md bittet iOS, die App ungefähr zur gewählten Zeit zu aktivieren.</span>
    <span><strong>2. Hintergrundversuch</strong>Ist das Gerät verfügbar, lässt iOS die App im Hintergrund aktualisieren.</span>
    <span><strong>3. Ersatz bei Sperrung</strong>Ist HealthKit nicht verfügbar, zeigt Health.md eine Mitteilung an.</span>
    <span><strong>4. Zum Abschließen tippen</strong>Wenn Sie die Mitteilung öffnen, kann die App HealthKit lesen und exportieren.</span>
  </div>
</div>

<div class="callout">
<strong>Wichtige Einschränkungen von iOS.</strong>
<p style="margin-top:6px;">Bei gesperrtem Gerät können HealthKit-Daten nicht gelesen werden. Geplante Exporte werden über <code>BGAppRefreshTask</code> ausgeführt, den iOS anhand des Nutzungsverhaltens nach eigenem Ermessen einplant. Ihre Zeitangabe ist daher ein Ziel, keine Zusage. Ist das Gerät gesperrt, sendet die App ersatzweise zur geplanten Zeit eine lokale Mitteilung; tippen Sie darauf, um den Export auszuführen.</p>
</div>
<ul>
<li>Die geplante Uhrzeit ist ungefähr. iOS kann die Aufgabe früher oder später ausführen oder überspringen, wenn das Gerät ausgeschaltet oder nicht verbunden ist.</li>
<li>Geplante Exporte funktionieren am besten, wenn Ihr iPhone regelmäßig ungefähr zur gleichen Tageszeit am Strom angeschlossen und entsperrt ist.</li>
<li>Schlägt der Export wegen eines gesperrten Geräts fehl, tippen Sie auf die Mitteilung. Dadurch wird der Export mit HealthKit-Zugriff ausgeführt.</li>
</ul>

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
