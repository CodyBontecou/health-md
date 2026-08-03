---
title: "Zeitplanung"
description: "Führen Sie Exporte automatisch täglich oder wöchentlich zu einer gewählten Uhrzeit aus. Verwendet iOS-Hintergrundaufgaben und ersatzweise eine geplante lokale Mitteilung, wenn das Gerät gesperrt ist."
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
<div class="option"><strong>Häufigkeit</strong><p>Täglich, wöchentlich oder monatlich. Tägliche Exporte umfassen den Vortag, wöchentliche die vorherigen 7 Tage und monatliche die vorherigen 30 Tage.</p></div>
<div class="option"><strong>Uhrzeit</strong><p>Stunde und Minute. iOS behandelt diese Angabe als Richtwert, nicht als Garantie – beachten Sie den Hinweis zu Einschränkungen weiter unten.</p></div>
</div>

## Exportverlauf
<p>Die Liste am unteren Rand der Zeitplanansicht zeichnet jeden geplanten Durchlauf mit seinem Ergebnis auf. Tippen Sie auf eine Zeile, um Details anzuzeigen. Fehlgeschlagene Durchläufe enthalten die Schaltfläche <em>Wiederholen</em>, die genau diesen Datumsbereich erneut ausführt.</p>

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

## Verwandte Themen

<div class="related">
  <a href="/de/docs/export/"><span>Manuell</span>Export – für einmalige Datumsbereiche.</a>
  <a href="/de/docs/shortcuts/"><span>Automatisieren</span>Kurzbefehle – schalten Sie den Zeitplan über Automationen um.</a>
  <a href="/de/docs/sync/"><span>Geräteübergreifend</span>Mac-Synchronisierung – planen Sie Exporte auch auf dem Mac.</a>
</div>
