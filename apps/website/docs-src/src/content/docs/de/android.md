---
title: Android-App
description: Richten Sie Health.md für Android ein, exportieren Sie Health Connect-Daten als Markdown, Obsidian Bases, JSON und CSV, wählen Sie Ordner über das Storage Access Framework, planen Sie Exporte und automatisieren Sie sie mit Tasker oder adb.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Health Connect-Daten in privaten Dateien</p>
  <p>Health.md für Android liest Health Connect auf dem Gerät und schreibt Markdown, Obsidian Bases, JSON oder CSV in die von Ihnen gewählten Ordner. Kein Health.md-Konto, keine Cloud für Gesundheitsdaten und kein Abonnement.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Bei Google Play herunterladen</a>
    <a class="docs-button-secondary" href="/de/docs/export/">Exportdokumentation lesen</a>
  </div>
</div>

<div class="reference-stats">
<div><strong>106</strong><span>auswählbare Health Connect-Metriken</span></div>
<div><strong>4</strong><span>Exportformate</span></div>
<div><strong>10</strong><span>kostenlose manuelle Exporte</span></div>
<div><strong>0</strong><span>erforderliche Health.md-Cloud-Konten</span></div>
</div>

## Was die Android-App macht

Health.md für Android macht Health Connect zu einem lokalen Gesundheitstagebuch. Wählen Sie die Metriken aus, die Ihnen wichtig sind, prüfen Sie die Ausgabe in der Vorschau und exportieren Sie anschließend übersichtliche Dateien in einen lokalen Ordner, einen Obsidian-Vault, einen synchronisierten Anbieterordner oder den Ordner eines anderen Android-Dokumentanbieters, der Schreibzugriff gewährt.

<div class="options">
  <div class="option"><strong>Health Connect als Quelle</strong><p>Liest Aktivität, Schlaf, Herz, Vitalzeichen, Körpermessungen, Ernährung, Trainingseinheiten und weitere Kategorien über die Health Connect-APIs auf dem Android-Gerät.</p></div>
  <div class="option"><strong>Ausgabe für Obsidian</strong><p>Schreibt Tagesnotizen, YAML/frontmatter, für Obsidian Bases geeignete Notizen, Einzeleinträge und JSON, das mit dem Health.md-Obsidian-Plugin kompatibel ist.</p></div>
  <div class="option"><strong>Android-nativer Speicher</strong><p>Verwendet das Storage Access Framework, damit Sie Ordner auswählen können, die vom lokalen Speicher, von Obsidian, Google Drive, OneDrive, Syncthing oder einem anderen Anbieter bereitgestellt werden.</p></div>
</div>

## Voraussetzungen

- Android 9 / API 28 oder neuer.
- Ein Gerät oder Emulator mit Unterstützung für Health Connect.
- Health Connect-Daten aus Android-Apps, Wearables oder Diensten, die in Health Connect schreiben.
- Ein Ordner oder Dokumentanbieter, der Schreibzugriff für Exporte erlaubt.

## Erster Export

1. Installieren Sie Health.md über Google Play.
2. Öffnen Sie die Einrichtung von **Health Connect** und gewähren Sie nur Zugriff auf die Kategorien, die Health.md exportieren soll.
3. Wählen Sie das Exportziel über die Android-Ordnerauswahl.
4. Wählen Sie Formate aus: Markdown, Obsidian Bases, JSON, CSV oder eine beliebige Kombination.
5. Wählen Sie Metriken und Datumsbereich.
6. Prüfen Sie die Ausgabe in der Vorschau.
7. Tippen Sie auf „Exportieren“ und verifizieren Sie die generierten Dateien in Ihrem Ordner oder Vault.

Der kostenlose Tarif umfasst 10 manuelle Exportaktionen. So können Sie Berechtigungen, Ordnerzugriff, Formate und Ihren Obsidian-Workflow testen, bevor Sie unbegrenzte Exporte freischalten.

## Ziele unter Android

Android verwendet nicht das lokale Netzwerkziel iPhone → Mac. Stattdessen nutzt es das Storage Access Framework von Android.

| Ziel | Android-Status |
|---|---|
| Lokaler Geräteordner | Über die Ordnerauswahl unterstützt |
| Obsidian-Vault | Unterstützt, wenn der Vault-Ordner in der Android-Ordnerauswahl verfügbar ist |
| Google Drive, OneDrive, Syncthing, Obsidian Sync und ähnliche Anbieter | Unterstützt, wenn der Anbieter beschreibbare Ordner bereitstellt |
| Lokales Netzwerkziel iPhone/Mac | Apple-plattformspezifisch; wird von Android nicht verwendet |

Wenn ein Anbieter über die Android-Ordnerauswahl keine beschreibbaren Ordner bereitstellt, kann Health.md dort nicht sicher direkt schreiben. Wählen Sie einen Anbieterordner mit dauerhaftem Schreibzugriff oder exportieren Sie lokal und synchronisieren Sie mit dem Tool Ihrer Wahl.

## Formate

Die Android-App verfolgt dieselben Ziele für einfache Dateien wie die Apple-App:

| Format | Geeignet für |
|---|---|
| Markdown | Lesbare tägliche Gesundheitsübersichten, Vorlagen und Notizen |
| Obsidian Bases | Auf frontmatter ausgerichtete Notizen, die in Obsidian-Datenbankansichten abgefragt werden können |
| JSON | Strukturierte tägliche Payloads für Skripte, Dashboards, Notebooks und das Health.md Obsidian-Plugin |
| CSV | Tabellenkalkulations- und Analyseworkflows |

JSON-Exporte unter Android sind auf Kompatibilität mit den Health.md-Visualisierungen in Obsidian ausgelegt. Markdown- und Bases-Exporte verwenden denselben auf frontmatter ausgerichteten Workflow, der im [Formatleitfaden](/de/docs/format/) beschrieben wird.

## Zeitplanung und Automatisierung

Geplante Exporte erfordern die einmalige dauerhafte Freischaltung. Geplante Exporte verwenden einen einmaligen Alarm mit genauer Zeitangabe, wenn Sie Android den Zugriff auf „Wecker & Erinnerungen“ gewähren, und dauerhafte WorkManager-Aufträge als Ausweichlösung. Ohne Zugriff auf genaue Alarme wird WorkManager zum primären Zeitplaner. Die ausgewählte Uhrzeit ist dann ein Ziel und keine feste Garantie. Health.md zeichnet den Exportverlauf auf, kann verpasste geplante Exporttage nachholen und lässt Sie fehlgeschlagene Durchläufe wiederholen.

Für Tasker, adb oder andere Automatisierungstools stellt Health.md Broadcast-Intents bereit, die nur explizit aufgerufen werden können. Externe Aufrufer müssen die Empfängerkomponente direkt adressieren:

```text
com.healthmd.android/com.healthmd.automation.AutomationReceiver
```

Beispiele:

```bash
adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_YESTERDAY

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_LAST_DAYS \
  --ei com.healthmd.android.extra.DAYS 7

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_RANGE \
  --es com.healthmd.android.extra.START_DATE 2026-03-01 \
  --es com.healthmd.android.extra.END_DATE 2026-03-07
```

Die Automatisierung verwendet standardmäßig das aktive Profil mit fixiertem Ziel, Formaten, Metriken, Anrechnung und Verlauf. Ein übergebenes Extra `PROFILE` kann ein stabiles Profil anhand von ID oder Name auswählen; ein unbekannter Verweis bricht sicher ab, statt aktuelle Einstellungen zu verwenden. Auch geplante Läufe bleiben an ihr Profil gebunden. Siehe [Exportprofile](/de/docs/export-profiles/).

### Hintergrundbereitschaft und geplanter Abbruch

- Erlaube Health-Connect-Lesevorgänge im Hintergrund für unbeaufsichtigte Exporte; andernfalls öffne Health.md zum Lesen der Daten.
- Lass Benachrichtigungen aktiv, damit laufende Arbeit, nötige Vordergrunddienste und Wiederherstellungshinweise sichtbar sind.
- Erlaube Alarme und Erinnerungen nur für exakte Alarme. Ohne diese Berechtigung bleibt die Arbeit persistent, die Uhrzeit aber ungefähr.
- Der Abbruch eines geplanten Laufs stoppt nur diesen Versuch. Abgeschlossene Tage bleiben erhalten, offene sind wiederholbar und der Zeitplan bleibt aktiv.

## Gesundheitsquellen

Health Connect ist der standardmäßige lokale Exportpfad. Die Android-App enthält außerdem einen Einrichtungsbereich für Gesundheitsquellen wie Samsung Health, Huawei Health, Fitbit, Garmin, Withings, Oura, Polar und WHOOP. Wenn diese Ökosysteme Daten in Health Connect schreiben, kann Health.md die daraus entstehenden Health Connect-Datensätze exportieren. Direkte Importe von Cloud-Anbietern erfordern eine Autorisierung beim Anbieter und können zusätzliche Einrichtungs- oder Verfügbarkeitsbedingungen haben.

Google Fit wird bewusst nicht als unterstützter Anbieter aufgeführt, da Health Connect die bevorzugte Gesundheitsdatenschicht von Android ist.

### Exakte Tagesschritte

Tagesschritte verwenden exakte lokale Tagesgrenzen mit Zeitzone. Health.md beschneidet und teilt Health-Connect-Intervalle an der lokalen Mitternacht, damit Reisen und Zeitumstellungen keine Schritte verschieben.

## Preise und Wiederherstellung

- Die Android-App umfasst 10 kostenlose manuelle Exporte.
- Unbegrenzte Exporte und geplante Automatisierungen werden durch einen einmaligen Kauf mit dauerhafter Freischaltung über Google Play Billing freigeschaltet.
- Es gibt kein Abonnement und keine wiederkehrenden Kosten.
- Google Play zeigt vor dem Kauf den aktuellen lokalen Preis an.
- „Kauf wiederherstellen“ verwendet das Google-Konto, mit dem Premium gekauft wurde.

Nach einer vorübergehenden Trennung von Google Play Billing verbindet sich Health.md erneut und aktualisiert die Berechtigung automatisch. Premium geht dadurch nicht dauerhaft verloren; nutze Kauf wiederherstellen nur, wenn das Konto nach Rückkehr der Verbindung ungeklärt bleibt.

## Datenschutzmodell

Health.md für Android arbeitet lokal:

- Health Connect-Datensätze werden auf Ihrem Android-Gerät gelesen.
- Exporte werden direkt in die von Ihnen gewählten Ordner geschrieben.
- Health.md betreibt keinen Cloud-Dienst für Gesundheitsdaten.
- Einstellungen und Exportverlauf bleiben auf dem Gerät.
- Die Abrechnung erfolgt über Google Play.
- Anbieterbasierte Ordner werden gemäß den Bedingungen des jeweiligen Anbieters synchronisiert.

Für eine möglichst strikt lokale Einrichtung führen Sie manuelle Exporte in einen lokalen Geräteordner aus und deaktivieren Sie geplante Exporte sowie die anbieterbasierte Synchronisierung.

## Verwandte Dokumentation

<div class="related">
  <a href="/de/docs/export-profiles/"><span>Profile</span>Speichere unabhängige Ziele, Ausgabeeinstellungen, Zeitpläne und stabile Automatisierungs-IDs.</a>
  <a href="/de/docs/export/"><span>Export</span>Manueller Exportablauf, Datumsbereiche, Vorschauen, Verlauf und Dateiausgabe.</a>
  <a href="/de/docs/metrics/"><span>Metriken</span>So funktionieren Metrikauswahl und Kategorien in Health.md.</a>
  <a href="/de/docs/format/"><span>Formate</span>Markdown, Bases, JSON, CSV, Einheiten, Dateinamen und frontmatter.</a>
  <a href="/de/docs/visualizations-roadmap/"><span>Obsidian</span>So bilden exportiertes JSON und Markdown die Grundlage für Health.md-Visualisierungen.</a>
</div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">Zuletzt aktualisiert am 31. August 2026</p>
