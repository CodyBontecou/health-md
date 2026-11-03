---
title: "Export"
description: "Verwenden Sie die Registerkarte „Exportieren“, um HealthKit und Tresorverbindungen zu überprüfen. Wählen Sie ein Ziel aus und exportieren Sie einen Datumsbereich."
---

<p> Die Registerkarte „Exportieren“ ist in drei kleine Entscheidungen unterteilt: Bestätigen Sie die Bereitschaft, wählen Sie ein Ziel und wählen Sie dann den Datumsbereich aus, bevor Sie eine Vorschau anzeigen oder exportieren. </p>

## Lesen Sie die Status-Badges
 <div class="options">
 <div class="option"> <strong> Gesundheits-Badge </strong> <p> Ein grüner Punkt bedeutet, dass HealthKit autorisiert ist. Ein roter Punkt bedeutet, dass der Zugriff nicht gewährt wird. Tippen Sie, um das iOS-Berechtigungsblatt erneut zu versuchen. Das Blatt erscheint nur einmal pro Installation. Öffnen Sie anschließend Einstellungen → Datenschutz &amp; Sicherheit → Gesundheit. </p> </div>
 <div class="option"> <strong> Tresor-Abzeichen </strong> <p> Grüner Punkt = ein Tresorordner ist ausgewählt. Tippen Sie, um den Tresor erneut auszuwählen oder zu ändern. Die Beschriftung zeigt den Ordnernamen. </p> </div>
 </div>
 <p> Die Aktion <em> Export </em> bleibt deaktiviert, bis HealthKit , das Ausgabeformat und das ausgewählte Ziel bereit sind. Dies verhindert den häufigsten Fehlermodus: den Versuch, ohne Ziel zu exportieren. </p>

## Wählen Sie ein Exportziel
 <p> Die Exportzielkarte entscheidet, wohin die Daten gehen: </p>

<div class="options">
 <div class="option"> <strong> Lokaler iPhone Ordner </strong> <p> Schreibt direkt in den Ordner oder Obsidian Tresor, den Sie auf diesem Gerät ausgewählt haben. </p> </div>
 <div class="option"> <strong> Verbundener Mac </strong> <p> Sendet erfasste Tagesdaten und einen genauen Einstellungs-Snapshot an die nahegelegene Mac-App. Der iPhone lautet HealthKit . Der Mac rendert die ausgewählten Formate und schreibt die Dateien. </p> </div>
 <div class="option"> <strong> API-Endpunkt </strong> <p> POSTET einen JSON-Umschlag direkt von iPhone an einen vom Benutzer konfigurierten HTTP(S)-Endpunkt. <a href="/de/docs/api-endpoint/"> Siehe API-Endpunkt </a> . </p> </div>
 </div>

## Wählen Sie einen Datumsbereich aus
 <p> Datumsvoreinstellungen decken die gängigen Pfade ab: </p>

<div class="options">
 <div class="option"> <strong> Heute </strong> <p> Den aktuellen Tag exportieren. Nützlich zum Testen der Ausgabeformatierung. </p> </div>
 <div class="option"> <strong> Gestern </strong> <p> Die sicherste Wahl für den täglichen Export, da der Tag abgeschlossen ist. </p> </div>
 <div class="option"> <strong> Alle Zeiten </strong> <p> Backfill von den frühesten HealthKit Daten, Health.md finden kann. </p> </div>
 <div class="option"> <strong> Benutzerdefiniert </strong> <p> Wählen Sie Start- und Enddatum für einen bestimmten Bereich. </p> </div>
 </div>

## Vorschau oder Export
 <div class="options">
 <div class="option"> <strong> Vorschau </strong> <p> Zeigt die Dateien und Inhalte an, die generiert werden, bevor etwas geschrieben wird. </p> </div>
 <div class="option"> <strong> Export </strong> <p> Führt den Export aus, zeigt den Fortschritt auf dem Hauptbildschirm an und zeichnet das Ergebnis im Verlauf auf. </p> </div>
 </div>

## Wählen Sie die Datendetailebene

<div class="options">
 <div class="option"> <strong> Zusammenfassung </strong> <p> Kompakte Tagessummen und Rollups zum Lesen, für Notizen und Dashboards. </p> </div>
 <div class="option"> <strong> Detaillierte Zeitreihen </strong> <p> Ausgewählte zeitgestempelte Stichproben und Intervalle. Diese Ebene ist sowohl auf Apple als auch auf Android verfügbar, wenn die ausgewählte Metrik geeignete Details offenlegt. </p> </div>
 <div class="option"> <strong> Verlustfreie Gesundheitsakten </strong> <p> Das kanonische HealthKit Quelldatensatzarchiv. Diese Ebene ist nur für Apple verfügbar. Android wandelt Health Connect Datensätze nicht in ein HealthKit Archiv um. </p> </div>
 </div>

## Was „Exportieren“ tatsächlich bewirkt
 <ol>
 <li> Erfassen Sie für jeden Tag im Bereich ausgewählte zusammenfassende Prognosen. Fügen Sie kompatible Beispiele für detaillierte Zeitreihen hinzu. Und für verlustfreie Gesundheitsakten können Sie kanonische Quelldatensätze hinzufügen und Diagnosen abfragen. </li>
 <li> Wenden Sie das von Ihnen gewählte Format ( Markdown , Bases, JSON oder CSV) und die Vorlage an. </li>
 <li> Schreiben Sie eine Datei pro Tag in <code>{vault}/{subfolder}/</code> , übertragen Sie Dateien über den verbundenen Mac-Workflow oder POSTEN Sie einen versionierten JSON-Umschlag an Ihren API-Endpunkt. </li>
 <li> Wenn <em> Einzelverfolgung </em> aktiviert ist, leiten Sie ausgewählte Markdown Dateien pro Eintrag aus dem kanonischen Archiv für dateibasierte Ziele ab. </li>
 <li> Wenn <em> Daily Note Injection </em> aktiviert ist, führen Sie ausgewählte Zusammenfassungsfelder in Ihre täglichen Notizen ein. </li>
 </ol>

<p> JSON und CSV können kanonische Datensätze beibehalten. Markdown und Bases bleiben lesbar und stellen eine kompakte Erfassungsdiagnose bereit, anstatt das Archiv einzubetten. Genaue Schemata und Auslassungsregeln finden Sie in der vollständigen Exportreferenz <a href="/de/docs/reference/"> </a> . </p>

## Anhalten, abbrechen und erneut versuchen

Durch Stoppen oder Abbrechen wird nur der aktuelle Versuch beendet. Bereits abgeschlossene Dateien und Termine bleiben abgeschlossen, während ungelöste Termine weiterhin für einen erneuten Versuch verfügbar sind. Durch das Abbrechen eines geplanten Versuchs wird dessen wiederkehrender Zeitplan nicht deaktiviert.

## Profile und vertrauenswürdige Geschichte

Ein gespeichertes Profil friert seine Einstellungen und das Ziel für den Lauf ein. Profilbewusste geplante und Automatisierungsverlaufszeilen behalten das Laufzeitprofil bei, während der Verlauf eine datenschutzsichere Bezeichnung für das tatsächlich verwendete Ziel beibehält. In einer manuellen Export-Tab-Zeile kann der Profilname weggelassen werden. Spätere Umbenennungen und Zieländerungen schreiben den vorhandenen Verlauf nicht neu. Fehlende Profilverweise werden nicht geschlossen, sondern zurückgesetzt. Siehe [Profile exportieren](/de/docs/export-profiles/).

## Tab-Leiste

<p> Die vier Registerkarten am unteren Bildschirmrand, Export, Zeitplan, Synchronisierung, Einstellungen, decken die gesamte App-Oberfläche ab. Alles andere befindet sich ein oder zwei Ebenen tief in den Einstellungen. </p>

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
