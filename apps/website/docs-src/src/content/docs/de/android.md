---
title: "Android-App"
description: "Richten Sie Health.md für Android ein. Exportieren Sie Health Connect Daten, wählen Sie Storage Access Framework-Ordner aus, planen Sie Exporte und automatisieren Sie mit Tasker oder ADB."
---

<div class="docs-hero">
 <p class="docs-eyebrow"> Health Connect in private Dateien </p>
 <p> Health.md für Android liest Health Connect auf dem Gerät und schreibt Markdown , Obsidian Bases, JSON oder CSV in von Ihnen ausgewählte Ordner. Für diesen Ordnerexport-Workflow ist kein Health.md Konto erforderlich. Google Play Zugriffsoptionen und F-Droid enthaltene Zugriff werden unten beschrieben. </p>
 <div class="docs-actions">
 <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener"> Weiter Google Play </a>
 <a class="docs-button-secondary" href="#distribution-status"> F-Droid Veröffentlichungsstatus </a>
 <a class="docs-button-secondary" href="/de/docs/export/"> Exportdokumente lesen </a>
 </div>
 <p id="distribution-status"> F-Droid Die Veröffentlichung des Katalogs steht noch aus. Holen Sie sich die aktuelle Android-Version auf Google Play . </p>
 </div>

<div class="reference-stats">
 <div> <strong> 106 </strong> <span> auswählbar Health Connect Metriken </span> </div>
 <div> <strong> 4 </strong> <span> Exportformate </span> </div>
 <div> <strong> 2 </strong> <span> Android-Vertriebskanäle </span> </div>
 <div> <strong> 0 </strong> <span> Health.md Cloud-Konten erforderlich </span> </div>
 </div>

## Was die Android-App macht

Health.md für Android verwandelt Health Connect in ein lokales Gesundheitsjournal. Wählen Sie die benötigten Metriken aus und zeigen Sie eine Vorschau der Ausgabe an. Exportieren Sie dann die Dateien in einen lokalen Ordner, Obsidian Tresor, einen synchronisierten Anbieterordner oder einen beschreibbaren Android-Dokumentanbieter.

<div class="options">
 <div class="option"> <strong> Health Connect Quelle </strong> <p> Liest Aktivität, Schlaf, Herz, Vitalwerte, Körpermaße, Ernährung, Training und andere Kategorien über die geräteinternen Health Connect APIs von Android. </p> </div>
 <div class="option"> <strong> Obsidian -native Ausgabe </strong> <p> Schreibt tägliche Notizen, YAML/Frontmatter, Obsidian Bases-freundliche Notizen, individuelle Einträge und JSON, kompatibel mit dem Health.md Obsidian Plugin. </p> </div>
 <div class="option"> <strong> Android-nativer Speicher </strong> <p> Verwendet das Storage Access Framework, sodass Sie Ordner auswählen können, die durch lokalen Speicher, Obsidian , Google Drive, OneDrive, Syncthing oder einen anderen Anbieter verfügbar gemacht werden. </p> </div>
 </div>

## Anforderungen

- Android 9 / API 28 oder neuer.
- Ein Health Connect -fähiges Gerät oder Emulator.
- Health Connect Daten von Android-Apps, Wearables oder Diensten, die in Health Connect schreiben.
- Ein Ordner oder Dokumentanbieter, der Schreibzugriff für Exporte ermöglicht.

## Erster Export

1. Installieren Sie die aktuelle Version Health.md von Google Play .
2. Öffnen Sie das Setup von ** Health Connect ** und gewähren Sie nur die Kategorien, die Health.md exportieren soll.
3. Wählen Sie das Exportziel über die Ordnerauswahl von Android aus.
4. Wählen Sie Formate: Markdown , Obsidian Bases, JSON, CSV oder eine beliebige Kombination.
5. Wählen Sie Metriken und Datumsbereich aus.
6. Vorschau der Ausgabe.
7. Tippen Sie auf „Exportieren“ und überprüfen Sie die generierten Dateien in Ihrem Ordner oder Tresor.

Die abonnementfähige Google Play Telefonversion erfordert eine aktive Testversion, ein Abonnement, Lifetime oder einen beibehaltenen permanenten Zugriff für manuelle Exporte. Berechtigte Abonnements beinhalten eine 7-tägige Testversion; Lifetime hat keine Testversion. Der Build F-Droid beinhaltet unbegrenzten Zugriff ohne Kauf- oder Wiederherstellungsablauf.

## Ziele auf Android

Android verwendet nicht das lokale Netzwerkziel iPhone → Mac. Stattdessen basiert es auf dem Storage Access Framework von Android.

| Ziel | Android-Status |
| --- | --- |
| Lokaler Geräteordner | Unterstützt durch die Ordnerauswahl |
| Obsidian Tresor | Wird unterstützt, wenn der Tresorordner für die Android-Auswahl verfügbar ist |
| Google Drive, OneDrive, Syncthing, Obsidian Sync und ähnliche Anbieter | Wird unterstützt, wenn der Anbieter beschreibbare Ordner bereitstellt |
| iPhone /Mac lokales Netzwerkziel | Apple-plattformspezifisch; Wird von Android nicht verwendet |

Wenn ein Anbieter keine beschreibbaren Ordner über die Android-Auswahl verfügbar macht, kann Health.md nicht sicher direkt dorthin schreiben. Wählen Sie einen Anbieterordner, der dauerhaften Schreibzugriff gewährt, oder exportieren Sie lokal und synchronisieren Sie mit Ihrem bevorzugten Tool.

## Formate

Die Android-App verfolgt dieselben Klardateiziele wie die Apple-App:

| Format | Benutze es für |
| --- | --- |
| Markdown | Lesbare tägliche Gesundheitszusammenfassungen, Vorlagen und Notizen |
| Obsidian Bases | Frontmatter-First-Notizen, die in Obsidian Datenbankansichten abgefragt werden können |
| JSON | Strukturierte tägliche Payloads für Skripte, Dashboards, Notebooks und das Plugin Health.md Obsidian |
| CSV | Tabellenkalkulations- und Analyse-Workflows |

Android-JSON-Exporte sind so konzipiert, dass sie mit Obsidian Visualisierungen von Health.md kompatibel sind. Markdown und Bases-Exporte verwenden denselben frontmatter-fokussierten Workflow, der im [Formatleitfaden](/de/docs/format/) dokumentiert ist.

## Terminplanung und Automatisierung

In der abonnementaktivierten Telefonversion Google Play erfordern geplante Exporte eine aktive Testversion, ein Abonnement, Lifetime oder einen beibehaltenen permanenten Zugriff; Sie sind im Build F-Droid enthalten. Sie verwenden einen einmaligen, genauen Alarm, wenn Sie den Zugriff auf Alarme und Erinnerungen von Android gewähren, wobei dauerhaftes WorkManager als Backup fungiert. Ohne Zugriff auf den genauen Alarm wird WorkManager zum primären Planer, sodass die ausgewählte Zeit eher ein Ziel als eine feste Garantie ist. Health.md zeichnet den Exportverlauf auf, kann verpasste geplante Daten wiederherstellen und ermöglicht die Wiederholung fehlgeschlagener Ausführungen.

Für Tasker, ADB oder andere Automatisierungstools macht Health.md nur explizite Broadcast-Absichten verfügbar. Externe Anrufer müssen die Empfängerkomponente direkt ansprechen:

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

Die Automatisierung verwendet standardmäßig das aktive Profil, einschließlich seines eingefrorenen Ziels, seiner Formate, Metriken, Abrechnung und seines Verlaufs. Ein bereitgestelltes `PROFILE` Extra kann eine stabile Profil-ID oder einen stabilen Namen auswählen. Eine unbekannte Referenz schlägt fehl, anstatt die aktuellen Einstellungen zu verwenden. Auch geplante Läufe bleiben an ihr Profil gebunden. Siehe [Profile exportieren](/de/docs/export-profiles/).

### Hintergrundbereitschaft und geplante Stornierung

- Hintergrundlesevorgänge von Health Connect für unbeaufsichtigte Exporte zulassen. Andernfalls öffnen Sie Health.md , um das Lesen der Gesundheitsdaten abzuschließen.
- Lassen Sie Benachrichtigungen aktiviert, damit Android aktive Arbeit, Vordergrunddienststatus, Ergebnisse und Wiederherstellungsaktionen anzeigen kann.
- Gewähren Sie Alarme und Erinnerungen nur, wenn Sie eine genaue Alarmplanung wünschen. Ohne sie bleiben dauerhafte WorkManager Arbeiten verfügbar, die gewählte Zeit ist jedoch ein Richtwert.
- Das Abbrechen einer geplanten Ausführung stoppt nur diesen Versuch. Abgeschlossene Termine bleiben vollständig, nicht aufgelöste Termine können wiederholt werden und der wiederkehrende Zeitplan bleibt aktiviert.

## Gesundheitsquellen

Health Connect ist der lokale Exportpfad in beiden Kanälen. Der Google Play Build umfasst auch einen Einrichtungsbereich für Gesundheitsquellen für Ökosysteme wie Samsung Health, Huawei Health, Fitbit, Garmin, Withings, Oura, Polar und WHOOP. Wenn diese Ökosysteme in Health Connect schreiben, kann jeder Build die resultierenden Health Connect Datensätze exportieren. Direkte Importe von Cloud-Anbietern und OAuth-Rückrufe sind nur für die Wiedergabe verfügbar. Der Anbieterkatalog F-Droid enthält nur Health Connect .

Google Fit wurde absichtlich von der Oberfläche der unterstützten Anbieter ausgeschlossen, da Health Connect Androids bevorzugte Gesundheitsdatenschicht ist.

### Genaue lokale Tagesschritte

Die täglichen Schrittsummen verwenden genaue Zonen-, Orts- und Tagesgrenzen. Vor der Aggregation schneidet und teilt Health.md überlappende Health Connect Intervalle um lokale Mitternacht. So führen Reise- und Sommerzeitumstellungen nicht dazu, dass Schritte in den falschen Tag verschoben werden.

## Vertrieb, Preisgestaltung und Umstellung

- ** Google Play :** Die abonnementfähige Telefonversion bietet individuelle wöchentliche/jährliche Abonnements und Lifetime. Berechtigte Erstabonnenten erhalten eine 7-tägige Testversion und verlängern sie dann automatisch zum angezeigten Preis, bis sie über Google Play gekündigt werden. Die lebenslange Laufzeit wird einmalig und ohne Testversion sofort berechnet. Es verbleibt keine örtliche Freiausfuhrbewilligung. Der bestehende permanente Zugang bleibt erhalten. Für die Wiederherstellung des Kaufs wird das Google-Kaufkonto verwendet. Durch das Löschen der App oder den Kauf von Lifetime wird das Abonnement nicht gekündigt. Ältere freigegebene Builds können die vorherige Zulage aufweisen. Die aktuelle Version ist nur für Telefone verfügbar. Der Wear OS Companion wird auf einen späteren Qualifikationszyklus verschoben.
- ** F-Droid :** Unbegrenzter Zugriff ist inbegriffen. Es gibt keinen kostenlosen Zähler, keine Abrechnungsabhängigkeit, keine Paywall, keinen Kauf oder keine Wiederherstellungsaktion.
- ** F-Droid Geltungsbereich:** Nur Health Connect , ohne Wear OS-Integration, direktes Cloud-Anbieter-OAuth, Play-Überprüfung, Zuordnung oder Health.md Onboarding-Telemetrie.
- **Gemeinsames Ergebnis:** Beide Kanäle verwenden dieselbe Health Connect Erfassung, dieselben Exporteure, Schemata, Automatisierungsaktionen und dasselbe Direktgeräteprotokoll.
- **Umschaltung:** Google Play und F-Droid verwenden unterschiedliche Signaturschlüssel, daher muss zum Wechseln der Kanäle zuerst die App deinstalliert werden.

Ein Kanalwechsel migriert keine Käufe, Einstellungen, Verlauf, Anmeldeinformationen oder den privaten Übertragungsstatus. Exportierte Dateien bleiben am gewählten Zielort.

Wenn Google Play Billing vorübergehend die Verbindung trennt, stellt der Play-Build die Verbindung wieder her und aktualisiert den Berechtigungsstatus automatisch. Durch einen vorübergehenden Dienstausfall wird Premium nicht dauerhaft entfernt. Verwenden Sie „Kauf wiederherstellen“ nur, wenn das Konto nach Wiederherstellung der Verbindung weiterhin nicht aufgelöst ist.

## Datenschutzmodell

Health.md für Android ist lokal zuerst:

- Health Connect Datensätze werden auf Ihrem Android-Gerät gelesen.
- Exporte werden direkt in die von Ihnen ausgewählten Ordner geschrieben.
- Kernordnerexporte und direkte Geräteabfragen erstellen standardmäßig keine Health.md Serverkopie.
- Einstellungen und Exportverlauf bleiben auf dem Gerät.
- Die Abrechnung erfolgt im Play-Build über Google Play . F-Droid beinhaltet unbegrenzten Zugriff ohne Abrechnung und enthält keinen Health.md Telemetriecode oder Telemetrieidentität/-status.
- Vom Anbieter unterstützte Ordner werden gemäß den eigenen Bedingungen des Anbieters synchronisiert.

Wenn Sie die strengste lokale Einrichtung wünschen, führen Sie manuelle Exporte in einen lokalen Geräteordner durch und lassen Sie geplante Exporte und die vom Anbieter unterstützte Synchronisierung deaktiviert.

Der separate, optionale Cloud-Pilot Health.md für einen einzelnen Eigentümer behält nur API-Exporte bei, die absichtlich dorthin hochgeladen wurden. Es gibt keine öffentliche Anmeldung und keine automatische Gerätesynchronisierung. Dieser Ordner-Workflow lädt nicht dorthin hoch. Informationen zu Aufbewahrungs-, Lösch-, Kontingent- und nicht gesicherten Speicherrisiken finden Sie in der [Datenschutzrichtlinie](/privacy-policy.html).

## Verwandte Dokumente

<div class="related">
 <a href="/de/docs/export-profiles/"> <span> Profile </span> Speichern Sie unabhängige Ziele, Ausgabeeinstellungen, Zeitpläne und stabile Automatisierungs-IDs. </a>
 <a href="/de/docs/export/"> <span> Export </span> Manueller Exportablauf, Datumsbereiche, Vorschauen, Verlauf und Dateiausgabe. </a>
 <a href="/de/docs/metrics/"> <span> Metriken </span> Wie Metrikauswahl und Kategorien in Health.md funktionieren. </a>
 <a href="/de/docs/format/"> <span> Formate </span> Markdown , Basen, JSON, CSV, Einheiten, Dateinamen und Frontmatter. </a>
 <a href="/de/docs/visualizations-roadmap/"> <span> Obsidian </span> Wie exportiertes JSON und Markdown Health.md Visualisierungen ermöglichen. </a>
 </div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;"> Zuletzt aktualisiert am 04.10.2026 </p>
