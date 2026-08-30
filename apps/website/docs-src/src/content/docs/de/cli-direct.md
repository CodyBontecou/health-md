---
title: "Direkte Telefon-CLI"
description: "Koppeln Sie healthmd über Manual IP oder Tailscale mit einem iPhone oder Android-Telefon und exportieren Sie ohne Health.md für Mac."
---

Das direkte Backend verbindet `healthmd` mit einer geöffneten Health.md-App auf dem iPhone oder Android, ohne den Befehl durch Health.md für Mac zu leiten. Das Telefon liest den Gesundheitsspeicher seiner Plattform — HealthKit auf dem iPhone, Health Connect auf Android —, stellt das Ergebnis im geschützten Speicher bereit und überträgt validierte Partitionen an die CLI.

```text
healthmd on the computer
  <-> authenticated encrypted Manual IP, Tailscale, or supported Nearby channel
Health.md on iPhone or Android -> HealthKit / Health Connect -> protected bounded spool
  -> raw snapshots, production-generated files, or (iPhone) canonical and typed query data
```

<div class="availability preview">
<strong>Vorschau · portable direkte CLI</strong>
<p>Das mitgelieferte direkte Swift-Backend ist unter macOS verfügbar und koppelt sich mit dem iPhone. Die Android-Kopplung (Protokoll v2) ist Teil des plattformübergreifenden Rust-Clients, einer Alphaversion, deren Release-QA mit physischen iPhone- und Android-Geräten und deren erstes öffentliches Paket noch ausstehen; die Befehle für Linux und Windows beschreiben den vorbereiteten Arbeitsablauf.</p>
</div>

## Unterstützte Funktionen des Direktmodus

- einmalige Kopplung und vertrauenswürdige Wiederverbindung mit iPhone-Quellen (Protokoll v1) oder Android-Quellen (Protokoll v2);
- lokale Prüfung und Entkopplung vertrauenswürdiger Geräte;
- Live-Bereitschaft des Telefons;
- strikter Rohdatenexport — Schema-v7-`healthmd.health_data` auf dem iPhone, provider-native Health-Connect-Snapshots auf Android;
- ausgewählte kanonische Extraktion (nur iPhone);
- Export von mit den produktiven Exportern erzeugten Dateien auf beiden Telefonplattformen;
- Status und Fortsetzung persistenter lokaler Aufträge;
- ausdrücklicher Abbruch;
- der stdio-Server `healthmd mcp serve` in derselben ausführbaren Datei mit direkten typisierten Abfragen, Metrikkatalog, Nachweisen, MCP-Apps-Oberfläche und PNG-Fallback (nur iPhone).

Das direkte Backend des Befehls `healthmd` emuliert nicht die HTTP-Routen der Mac-App für verschlüsselten Kontext. Mac-orientierte Unterbefehle für `doctor`, Abfragen, Nachweise und Aktualisierung geben daher weiterhin `backend_unsupported` zurück, statt das Backend zu wechseln. Verwenden Sie `healthmd mcp serve` für neue typisierte Analysen direkt vom iPhone oder `healthmd setup codex`, um Codex automatisch zu konfigurieren und zu koppeln. `healthmd mcp schema [TOOL]` gibt das exakte verschachtelte MCP-Eingabeschema und lokale Beispiele aus. Verwenden Sie für Schlaf direkt `healthmd_sleep_sessions`, statt die kanonische Ausgabe von `extract` als typisierte Abfrage-API zu behandeln.

## Voraussetzungen

- Eine direktfähige `healthmd`-Binärdatei und eine passende Health.md-Version: iPhone (Protokoll v1) oder Android (Protokoll v2). Die Android-Kopplung erfordert den portablen Rust-Client; der mitgelieferte macOS-Helfer koppelt sich nur mit dem iPhone.
- Health.md muss für Kopplung und neue Befehle im Vordergrund des Telefons geöffnet sein.
- **Settings > Mac Sync > Direct CLI Access** muss auf dem iPhone aktiviert sein oder **Settings → Direct CLI** auf Android.
- Plattform-Gesundheitsberechtigung (HealthKit oder Health Connect), geschützte Daten, Berechtigung für das lokale Netzwerk und Exportkontingent müssen verfügbar sein.
- Eine erreichbare Computeradresse und TCP-Port `17647` für Manual IP. Eine Tailscale-Adresse funktioniert ebenfalls.
- Ein vorhandenes absolutes Ziel für den Modus mit generierten Dateien.

Die CLI ist der Listener. Das Telefon verbindet sich mit der Computeradresse, die unter Direct CLI Access eingegeben wurde.

## Unterstützte Übertragungswege

| Übertragungsweg | Mitgelieferter Swift-Helfer unter macOS | Portabler Rust-Client |
|---|---:|---:|
| Manual IP im LAN | Ja | macOS, Linux, Windows |
| Tailscale-Adresse | Ja | macOS, Linux, Windows |
| Nearby / MultipeerConnectivity | Ja | Nein |

Nearby verwendet Apples verschlüsselte Multipeer-Sitzung sowie dieselbe Health.md-Anwendungsauthentifizierung und -verschlüsselung wie Manual IP. Der portable Client gibt für Nearby `transport_unsupported` zurück.

## Einmalig mit Manual IP koppeln

Starten Sie den Listener auf dem Computer:

```bash
healthmd direct pair --transport manual-ip
```

Der portable Rust-Client gibt einen sechsstelligen iPhone-Code, einen separaten 20-stelligen Android-Code, mögliche Computeradressen und den Listener-Port auf stderr aus; der mitgelieferte macOS-Helfer gibt nur den sechsstelligen iPhone-Code aus. stdout bleibt für das abschließende JSON-Ergebnis reserviert.

Auf dem iPhone:

1. Öffnen Sie **Health.md > Settings > Mac Sync > Direct CLI Access**.
2. Aktivieren Sie Direct CLI Access.
3. Wählen Sie **Manual IP**.
4. Geben Sie die LAN- oder Tailscale-Adresse des Computers ein.
5. Geben Sie Port `17647` ein, sofern die CLI keinen anderen globalen `--port` verwendet.
6. Geben Sie den Kopplungscode ein und tippen Sie auf Pair.
7. Lassen Sie die App geöffnet, bis beide Seiten Erfolg melden.

iPhone-Kopplungscodes laufen nach 10 Minuten ab. Sie werden weder über das Netzwerk gesendet noch dauerhaft gespeichert.

## Android-Telefon koppeln

Die Android-Kopplung verwendet den portablen Rust-Client und den separaten 20-stelligen (~66 Bit) Einmalcode, den `healthmd direct pair` ausgibt. Android fällt nie auf das iPhone-Protokoll zurück.

1. Öffnen Sie **Health.md > Settings → Direct CLI** auf dem Android-Telefon.
2. Geben Sie die LAN- oder Tailscale-Adresse des Computers und Port `17647` ein.
3. Geben Sie den 20-stelligen Code ein und bestätigen Sie die Kopplung.
4. Lassen Sie die App geöffnet; Android führt für eine aktive Direktsitzung einen sichtbaren, vom Benutzer gestarteten Datensynchronisierungs-Vordergrunddienst aus.

Nach dem Verbrauch des Einmalcodes ist das Vertrauen für die Wiederverbindung Keystore-gesichert.

Verwenden Sie bei Bedarf einen anderen Port:

```bash
healthmd --port 18000 direct pair --transport manual-ip
healthmd --backend direct --port 18000 status
```

Verwenden Sie denselben ausdrücklichen Port auch für spätere Status-, Export-, Fortsetzungs- und Abbruchbefehle.

## Mit Nearby koppeln

Nearby ist nur im mitgelieferten Swift-Helfer verfügbar:

```bash
healthmd direct pair --transport nearby
```

Wählen Sie auf dem iPhone unter Direct CLI Access Nearby, geben Sie den angezeigten Code ein und lassen Sie beide Geräte geöffnet, bis die Kopplung abgeschlossen ist. Ein fehlgeschlagener Nearby-Vorgang wechselt nicht zu Manual IP.

## Vertrauenswürdige Geräte

Die Kopplung erstellt eine Vertrauensstellung, die von der Synchronisierungsbeziehung der Health.md-Mac-App getrennt ist.

```bash
healthmd direct devices
healthmd direct unpair DEVICE_UUID
```

Diese Befehle lesen oder ändern lokale Vertrauensstellungen und kontaktieren das Telefon nicht. Verwenden Sie auf dem iPhone **Forget Paired CLI**, um die Gegenseite zu entfernen; entfernen Sie die Kopplung auf Android unter **Settings → Direct CLI**.

Sind mehrere Telefone vertrauenswürdig, wählen Sie die gewünschte Installation ausdrücklich aus:

```bash
healthmd --backend direct --device DEVICE_UUID status
```

Verwenden Sie `healthmd direct reset-trust --confirm` nur, wenn die lokale Vertrauensstellung beschädigt ist oder zu einer ersetzten Installation gehört. Der Befehl entfernt alle lokalen direkten Kopplungen. Vergessen Sie diese Kopplungen auf dem Telefon, bevor Sie neu beginnen.

## Live-Bereitschaft prüfen

```bash
healthmd --backend direct --transport manual-ip status
```

Eine direkte Statusantwort meldet Verbindungs- und Sicherheitsstatus ohne Gesundheitswerte. Der portable Client meldet die Quelle unter `source` mit einer `platform` von `ios` oder `android`; der mitgelieferte Helfer legt die unten aufgeführten `iphone`-Felder offen. Prüfen Sie vor Arbeitsbeginn folgende Felder (iPhone-Quelle gezeigt):

| Feld | Bereitschaftsstatus |
|---|---|
| `backend` | `direct` |
| `mac_app` | `bypassed` |
| `direct_cli.paired` | `true` |
| `iphone.connected` | `true` |
| `iphone.app_active` | `true` für neue Arbeit |
| `iphone.protected_data_available` | `true` |
| `iphone.can_trigger_raw_exports` | `true` für Rohdaten und Extraktion |
| `iphone.can_trigger_exports` | `true` für generierte Dateien |

Das Ziel bleibt im direkten Status nicht ausgewählt. Der Dateimodus verwendet ausschließlich das im Befehl angegebene `--destination`.

Eine Android-Quelle meldet `platform: "android"` mit `app_active`, `protected_data_available`, `export_in_progress` und ihren verfügbaren Rohdatenprodukten statt der iPhone-Auslöseflags.

## Strikter Rohdatenexport (iPhone)

Wählen Sie genau einen Zeitraumselektor:

```bash
healthmd --backend direct export --yesterday --raw --output yesterday.json
healthmd --backend direct export --last 7 --raw --output week.json
healthmd --backend direct export \
  --from 2026-07-01 --to 2026-07-07 --raw --output range.json
healthmd --backend direct export --all --raw --output complete-health-corpus.json
```

Lassen Sie `--output` weg, um validiertes JSON auf stdout zu streamen. Eine Ausgabedatei ist bei vertraulichen oder großen Antworten sicherer.

Die strikte iPhone-Rohdatenausgabe gibt `healthmd.raw_result` v1 mit gewöhnlichen Schema-v7-Tagen vom Typ `healthmd.health_data` und deren kanonischen Quellarchiven zurück. Sie fordert vorübergehend verlustfreie Details an, ohne gespeicherte iPhone-Einstellungen zu ändern. Bevor die CLI das Ergebnis bereitstellt, validiert sie exakte Datumswerte, Profil, Schema, Archiv, Manifeste, Digest-Kette, abschließenden Body-Digest und Abschlussstatus.

Ein vollständig leerer Tag ist erfolgreich. Fehlende, partielle, fehlgeschlagene, abgebrochene, nicht unterstützte oder übersprungene angeforderte Daten führen zu `partial_success` und einem von null verschiedenen Exit-Code, sofern `--allow-partial` nicht ausdrücklich gesetzt ist.

## Provider-native Rohdatenexport (Android)

Der portable Rust-Client ist standardmäßig direkt, daher entfällt bei Android-Rohdatenbefehlen das `--backend`-Flag:

```bash
healthmd export --last 7 --raw --provider health_connect \
  --raw-format ndjson --output health-connect.ndjson
```

`--provider` benennt genau einen Provider und ist standardmäßig `health_connect`. `--raw-format` ist standardmäßig NDJSON, die empfohlene Form für große Snapshots; die JSON-Validierung im Arbeitsspeicher ist auf 64 MiB begrenzt. Die Metrikauswahl unterstützt `--metric` und `--all-metrics`, jedoch keine kanonischen Selektoren oder Selektoren für generierte Dateien — diese bleiben iPhone-Funktionen.

Android-Rohdaten-Snapshots bewahren ihren provider-nativen Health-Connect-Vertrag. Sie werden nie in HealthKit-strukturierte `healthmd.health_data`-Tage umgewandelt, und verwandte, aber unterschiedliche Statistiken behalten ihre eigenen Identitäten.

## Kanonische Extraktion

Die direkte Extraktion verwendet dieselbe dauerhafte Rohdatenübertragung, gibt jedoch ausgewählte quellstrukturierte Daten statt des Transport-Envelopes zurück. Sie ist eine iPhone-Funktion:

```bash
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json

healthmd --backend direct extract \
  --metric workouts --last 14 --object records \
  --detail lossless --output workout-records.json
```

Die Auswahl von Metrik, Kategorie, Quelle und Detail erreicht das iPhone vor den HealthKit-Lesevorgängen. Unter [Kanonische Extraktion](/de/docs/cli-extract/) finden Sie Objektselektoren, JSON Pointer, JSONL und Belege.

## Für die Produktion generierte Dateien

Der direkte Dateimodus lässt das Telefon die Produktions-Exporter von Health.md ausführen und überträgt die erzeugten Dateien anschließend an ein ausdrückliches Computerziel.

```bash
mkdir -p "$HOME/Documents/HealthVault"

healthmd --backend direct export --yesterday \
  --destination "$HOME/Documents/HealthVault"

healthmd --backend direct export --last 7 \
  --category Sleep --detail summary \
  --destination "$HOME/Documents/HealthVault"

healthmd --backend direct export --yesterday --use-iphone-settings \
  --destination "$HOME/Documents/HealthVault"
```

Das Ziel muss bereits vorhanden und absolut sein und darf nicht über einen symbolischen Link aufgelöst werden. Der Direktmodus rät nie ein Ziel und verwendet kein Lesezeichen der Mac-App. `--output` ist für Rohdaten- oder Extraktionsausgaben bestimmt, `--destination` für generierte Dateien.

Standardmäßig behält eine Anfrage gespeicherte Formate, Health-Unterordner, Dateinamen, Vorlagen, Schreibmodus, Daily Note Injection und Daily Notes Only bei. Roll-ups und der reine Zusammenfassungsmodus werden für diesen Auftrag unterdrückt. Wiederholbare Optionen `--metric` oder `--category` zusammen mit `--detail` ersetzen nur den Metrik- und Detailumfang des Auftrags. `--use-iphone-settings` spiegelt alle gespeicherten Einstellungen und kann nicht mit Selektoren kombiniert werden.

Das iPhone kann JSON, CSV, Markdown, ZIP, Datenwörterbücher, Roll-ups, einzelne Datensätze, tägliche Notizen und Provider-Sidecars bereitstellen. Vor dem Commit validiert die CLI jeden relativen Pfad, Byteanzahl, Digest, jedes Dateimanifest, die Zielidentität und den Anfragefingerabdruck. Sie weist Pfadtraversierung, übergeordnete symbolische Links, Änderungen am Stammverzeichnis, Pfadkollisionen und Digest-Änderungen zurück. Überschreiben erfolgt atomar. Anhängen und Markdown-Zusammenführen verwenden gespeicherte Pläne, damit eine Wiederholung keine Inhalte dupliziert.

Ziele für generierte Dateien funktionieren mit iPhone-Protokoll v1 unter macOS und Linux; unter Windows werden sie zurückgewiesen. Android-Protokoll v2 schreibt Dateiziele unter jedem CLI-Betriebssystem fest — macOS, Linux und Windows — und begrenzt jeden generierten Auftrag auf 4.096 Dateien.

Android-Dateiaufträge mit Protokoll v2 beziehen ihren Umfang aus den gespeicherten Exportauswahlen des Geräts oder aus `--profile PROFILE_ID`; das Profil besitzt die eingefrorenen Einstellungen und das Ziel. Metrik-, Kategorie- und Detail-Selektoren der CLI werden für Android-Dateiaufträge zurückgewiesen.

## Verhalten im Vorder- und Hintergrund

Kopplung und neue Arbeit erfordern die Telefon-App im Vordergrund. Direct CLI Access macht das Telefon nicht zu einem unbeaufsichtigten Exportserver und kann die App nicht bei Bedarf aufwecken.

Auf dem iPhone fordert Health.md begrenzte iOS-Hintergrundausführungszeit an, wenn die App während eines bereits verbundenen Exports in den Hintergrund wechselt. Der Export kann innerhalb dieses Zeitraums abgeschlossen werden. Läuft er ab, wird die Verbindung geschlossen und der persistente Auftrag pausiert. Öffnen Sie Health.md erneut und setzen Sie denselben Auftrag fort.

Unter Android läuft eine aktive Direktsitzung als sichtbarer, vom Benutzer gestarteter Datensynchronisierungs-Vordergrunddienst. Halten Sie die App für Kopplung und neue Arbeit im Vordergrund.

Auf dem iPhone zeigt ein globales Aktivitätsbanner während direkter Arbeit Erfassungs- und Übertragungsphase, abgeschlossene Tage, Byte-Fortschritt sowie pausierten oder abgeschlossenen Status an, ohne Gesundheitswerte anzuzeigen.

## Persistente Aufträge fortsetzen und abbrechen

Direkte Aufträge laufen sieben Tage nach ihrer Erstellung ab. Zeitlimit, Ctrl-C, Prozessende, Verbindungsabbruch und Ablauf der Hintergrundzeit brechen sie nicht ab.

```bash
healthmd --backend direct status --job JOB_UUID
healthmd --backend direct resume JOB_UUID --timeout 300 --output recovered.json
healthmd --backend direct cancel JOB_UUID
```

Bei der Fortsetzung bleiben ursprüngliche Datumswerte, Einstellungen, Ziel, Anfragefingerabdruck, Gerät und Partitionsfortschritt erhalten. Ein Dateiauftrag kann beim Fortsetzen nicht auf ein anderes Ziel verweisen.

Der Abbruch wird dauerhaft angefordert, ist aber erst endgültig, wenn das iPhone ihn bestätigt. Ist das iPhone nicht verfügbar, bleibt der Status `cancellation_pending`. Öffnen Sie dasselbe iPhone erneut und wiederholen Sie den Abbruch.

## Sicherheitsmodell

- Die Kopplung verwendet ephemeren Schlüsselaustausch und an den Plattform-Kopplungscode gebundene Transkript-Nachweise — den sechsstelligen iPhone-Ablauf oder den separaten 20-stelligen (~66 Bit) Android-Einmalcode mit hoher Entropie.
- Die Wiederverbindung weist ein zufälliges gespeichertes Geheimnis und beide Installationsidentitäten nach.
- Jede Verbindung leitet neue Schlüssel und Nonces ab.
- Nachrichten und Binärframes verwenden ChaCha20-Poly1305 mit monotonen Sequenzprüfungen.
- Partitionen verwenden SHA-256-Manifeste und eine verkettete Digest-Grenze.
- Die iPhone-Vertrauensstellung wird im Schlüsselbund gespeichert; das Android-Vertrauen für die Wiederverbindung ist Keystore-gesichert.
- Portable Vertrauensstellungen verwenden Keychain, Secret Service oder Windows Credential Manager und greifen nie auf Klartext zurück.
- Spools und Journale verwenden privaten Anwendungsspeicher und werden, soweit von der Plattform unterstützt, von Backups ausgeschlossen.

Manual IP bleibt im lokalen Netzwerk oder über Tailscale verschlüsselt. Tailscale schützt zusätzlich den Netzwerkpfad, ersetzt jedoch nicht die Anwendungsauthentifizierung von Health.md.

## Häufige Fehler

| Fehler | Maßnahme |
|---|---|
| `direct_not_paired` | Diese CLI-Installation mit dem iPhone koppeln. |
| `direct_device_selection_required` | Gewünschtes vertrauenswürdiges `--device` angeben. |
| `direct_trust_invalid` | Diagnosen aufbewahren. Vertrauen nur zurücksetzen, wenn Wiederherstellung unmöglich ist. |
| `direct_iphone_unavailable` | Vordergrundstatus, Zugriffsschalter, Adresse, Port, Berechtigung und LAN- oder Tailscale-Erreichbarkeit prüfen. |
| `direct_export_paused` | Auftrag prüfen, iPhone erneut öffnen und Auftrag fortsetzen. |
| `direct_cancellation_pending` | Gekoppeltes iPhone erneut öffnen und Abbruch wiederholen. |
| `transport_unsupported` | Im portablen Client Manual IP oder Tailscale verwenden. |
| `backend_unsupported` | Für Abfrage, Nachweise, doctor, Metriken oder MCP das Backend der Mac-App verwenden. |
| `invalid_direct_raw_response` | Ausgabe nicht verwenden. Validierungsdiagnosen aufbewahren. |
| `invalid_direct_file_receipt` | Dateien nicht manuell reparieren. Auftrag prüfen und fortsetzen. |
| `job_expired` | Der siebentägige Status ist abgelaufen. Vor neuer Arbeit bestätigen. |

## Verwandte Themen

<div class="related">
  <a href="/de/docs/cli/"><span>Überblick</span>Health.md CLI: mitgelieferte Helfer installieren und das richtige Backend auswählen.</a>
  <a href="/de/docs/android/"><span>Android</span>Health.md für Android: Health-Connect-Quellen, Ordnerziele und Automatisierung auf dem Gerät.</a>
  <a href="/de/docs/cli-extract/"><span>Daten</span>Kanonische Extraktion: quellstrukturierte Health.md-Daten auswählen und ausgeben (iPhone).</a>
  <a href="/de/docs/cli-jobs/"><span>Zuverlässigkeit</span>Persistente Aufträge und Automatisierung: Fortsetzung, Abbruch, Teilergebnisse und Skripte.</a>
  <a href="/de/docs/reference/connected-mac-iphone-protocol/"><span>Protokoll</span>Referenz für verbundenen Mac und iPhone: Fähigkeiten, begrenzte Übertragung und Ergebnisstatus.</a>
</div>
