---
title: "Export"
description: "Apple-Health-Daten jetzt oder nach Zeitplan exportieren. Prüfen Sie die Bereitschaft im Archiv, wählen Sie in „Jetzt exportieren“ einen Zeitraum und legen Sie für jede Automation ein Ziel fest."
---

<p>Auf dem iPhone hat Health.md drei Tabs, <strong>Archiv</strong>, <strong>Automationen</strong> und <strong>Einstellungen</strong>, sowie eine runde Taste <strong>Jetzt exportieren</strong>. Auf dem iPad stehen die Tabs in einer Seitenleiste.</p>

## Bereitschaft im Archiv prüfen
<p>Der Kalender im <strong>Archiv</strong> zeigt, welche Gesundheitsdaten jede Automation abgedeckt hat. Wenn etwas Exporte blockiert, nennt die Karte <strong>Aufmerksamkeit nötig</strong> oben die Ursache:</p>
<div class="options">
<div class="option"><strong>Apple Health</strong><p>Health.md zeigt den Einrichtungsstatus der App, keinen bestätigten Lesezugriff auf jede Kategorie. HealthKit verrät keine verweigerten Leseberechtigungen. Prüfen Sie die Kategorien in Apple Health. Leere Ergebnisse können verweigerten Zugriff oder fehlende Daten bedeuten. <a href="/de/docs/troubleshooting/">Fehlende Daten beheben</a>.</p></div>
<div class="option"><strong>Ordner</strong><p>Wählen Sie den Ordner in <strong>Einstellungen → Ordner</strong> oder wählen Sie ihn erneut. Verliert iOS nach dem Verschieben eines Ordners den Zugriff, bittet Health.md Sie, ihn erneut zu wählen; es wird nichts gelöscht.</p></div>
</div>

## Exportziel einer Automation wählen
<p>Jede Automation hat ihr eigenes Ziel. Öffnen Sie <strong>Automationen</strong>, wählen Sie die Automation und dann <strong>Ausgabe</strong>:</p>

<div class="options">
<div class="option"><strong>Lokaler Ordner</strong><p>Schreibt direkt in den Ordner oder Obsidian-Vault, den Sie auf diesem Gerät gewählt haben.</p></div>
<div class="option"><strong>Verbundener Mac</strong><p>Sendet erfasste Tagesdaten und eine exakte Momentaufnahme der Einstellungen an die Mac-App in der Nähe. Das iPhone liest HealthKit; der Mac erzeugt die gewählten Formate und schreibt die Dateien.</p></div>
<div class="option"><strong>API-Endpunkt</strong><p>Sendet einen JSON-Umschlag per POST direkt vom iPhone an einen von Ihnen konfigurierten HTTP(S)-Endpunkt. <a href="/de/docs/api-endpoint/">Siehe API-Endpunkt</a>.</p></div>
<div class="option"><strong>Agent Data-Gateway</strong><p>Lädt jede exportierte Datei unverändert auf den Ingestion-Endpunkt Ihres Gateways hoch.</p></div>
</div>

## Zeitraum in „Jetzt exportieren“ wählen
<p>Tippen Sie auf <strong>Jetzt exportieren</strong>, wählen Sie bei mehreren Automationen die gewünschte und dann einen Zeitraum:</p>

<div class="options">
<div class="option"><strong>Gestern</strong><p>Die sicherste Wahl für tägliche Exporte, weil der Tag abgeschlossen ist.</p></div>
<div class="option"><strong>7 Tage / 30 Tage</strong><p>Die letzte Woche oder der letzte Monat, jeweils bis gestern. Bei 30 oder mehr Tagen fragt Health.md vorher nach.</p></div>
<div class="option"><strong>Benutzerdefiniert</strong><p>Start- und Enddatum für einen bestimmten Zeitraum wählen.</p></div>
</div>
<p><strong>Wird geschrieben</strong> zeigt das Ziel und ungefähr, wie viele Dateien und Tage der Export umfasst. <strong>Nur Bereichszusammenfassung</strong> schreibt eine einzige Zusammenfassungsdatei statt Tagesdateien. „Heute“ und „Gesamter Zeitraum“ bleiben unter <strong>Automationen → Alle Exporteinstellungen</strong> verfügbar.</p>

## Vorschau oder Export
<div class="options">
<div class="option"><strong>Vorschau</strong><p>Zeigt die Dateien und Inhalte, die erzeugt werden, bevor etwas geschrieben wird.</p></div>
<div class="option"><strong>Export</strong><p>Führt den Export aus, zeigt den Fortschritt über der Tab-Leiste mit einer Abbrechen-Taste und speichert das Ergebnis im Verlauf und im Kalender des Archivs.</p></div>
</div>

## Wählen Sie die Datendetailebene

<div class="options">
 <div class="option"> <strong> Zusammenfassung </strong> <p> Kompakte Tagessummen und Rollups zum Lesen, für Notizen und Dashboards. </p> </div>
 <div class="option"> <strong> Detaillierte Zeitreihen </strong> <p> Ausgewählte zeitgestempelte Stichproben und Intervalle. Diese Ebene ist sowohl auf Apple als auch auf Android verfügbar, wenn die ausgewählte Metrik geeignete Details offenlegt. </p> </div>
 <div class="option"> <strong> Verlustfreie Gesundheitsakten </strong> <p> Das kanonische HealthKit Quelldatensatzarchiv. Diese Ebene ist nur für Apple verfügbar. Android wandelt Health Connect Datensätze nicht in ein HealthKit Archiv um. </p> </div>
 </div>

## Was „Exportieren“ tatsächlich bewirkt
 <ol>
 <li> Für jeden Tag im Zeitraum werden ausgewählte Tageszusammenfassungen erfasst. Detaillierte Zeitreihen ergänzen verfügbare Messwerte und Intervalle. Verlustfreie Gesundheitsakten ergänzen kanonische Quelldatensätze und Abfragediagnostik. </li>
 <li> Wenden Sie das von Ihnen gewählte Format ( Markdown , Bases, JSON oder CSV) und die Vorlage an. </li>
 <li> Schreiben Sie eine Datei pro Tag in <code>{vault}/{subfolder}/</code> , übertragen Sie Dateien über den verbundenen Mac-Workflow oder POSTEN Sie einen versionierten JSON-Umschlag an Ihren API-Endpunkt. </li>
 <li> Wenn <em> Einzelverfolgung </em> aktiviert ist, leiten Sie ausgewählte Markdown Dateien pro Eintrag aus dem kanonischen Archiv für dateibasierte Ziele ab. </li>
 <li> Wenn <em> Daily Note Injection </em> aktiviert ist, führen Sie ausgewählte Zusammenfassungsfelder in Ihre täglichen Notizen ein. </li>
 </ol>

<p> JSON und CSV können kanonische Datensätze beibehalten. Markdown und Bases bleiben lesbar und stellen eine kompakte Erfassungsdiagnose bereit, anstatt das Archiv einzubetten. Genaue Schemata und Auslassungsregeln finden Sie in der <a href="/de/docs/reference/">vollständigen Exportreferenz</a>. </p>

## Anhalten, abbrechen und erneut versuchen

Durch Stoppen oder Abbrechen wird nur der aktuelle Versuch beendet. Bereits abgeschlossene Dateien und Tage bleiben abgeschlossen; noch offene Tage können erneut versucht werden. Durch das Abbrechen eines geplanten Versuchs wird dessen wiederkehrender Zeitplan nicht deaktiviert.

## Profile und verlässlicher Exportverlauf

Ein gespeichertes Profil friert seine Einstellungen und das Ziel für den Lauf ein. Profilbewusste geplante und Automationsverlaufszeilen behalten das Laufzeitprofil bei, während der Verlauf eine datenschutzsichere Bezeichnung für das tatsächlich verwendete Ziel beibehält. In einer Zeile eines manuellen Exports kann der Profilname fehlen. Spätere Umbenennungen und Zieländerungen schreiben den bestehenden Verlauf nicht um. Fehlt ein referenziertes Profil, schlägt der Vorgang fehl, ohne andere Einstellungen zu verwenden. Siehe [Exportprofile](/de/docs/export-profiles/).

<div class="callout">
 <strong> Entsperrverhalten. </strong>
 <p style="margin-top:6px;"> Die abonnementaktivierten Telefonversionen iPhone / iPad und Google Play erfordern eine aktive Testversion, ein Abonnement, Lifetime oder einen beibehaltenen permanenten Zugriff für Exporte und Planung. Es verbleibt keine örtliche Freiausfuhrbewilligung. Der Mac-Begleiter und der Build mit eingeschlossenem Zugriff F-Droid behalten ihre dokumentierten Ausnahmen bei. <a href="/de/docs/paywall/"> Einzelheiten zum Apple-Kauf finden Sie auf der Paywall-Seite </a> . </p>
 </div>

## Verwandt

<div class="related">
 <a href="/de/docs/export-profiles/"> <span> Wiederholbare Setups </span> Profile exportieren, unabhängige Einstellungen, Ziele, Zeitpläne und stabile Automatisierungs-IDs speichern. </a>
 <a href="/de/docs/scheduling/"> <span> Täglicher Gebrauch </span> Planung, automatisieren Sie dies, damit Sie nie wieder auf „Exportieren“ tippen müssen. </a>
 <a href="/de/docs/api-endpoint/"> <span> Integrieren Sie den </span> API-Endpunkt und senden Sie ausgewähltes JSON direkt an Ihren eigenen Dienst. </a>
 <a href="/de/docs/format/"> <span> Anpassen </span> Formatanpassung, ändern Sie das Aussehen jeder Datei. </a>
 <a href="/de/docs/shortcuts/"> <span> Power </span> Shortcuts , Auslösen von Exporten aus Siri , Automatisierungen oder anderen Apps. </a>
 <a href="/de/docs/reference/"> <span> Referenz </span> Exportreferenz, Schemata, kanonische Datensätze, Diagnosen und generierte Beispiele. </a>
 </div>
