---
title: "Direkte iPhone-CLI"
description: "Koppeln Sie healthmd über Manual IP, Tailscale oder einen unterstützten Nearby-Übertragungsweg mit einem iPhone und exportieren Sie ohne Health.md für Mac."
---

Das direkte Backend verbindet `healthmd` mit einer geöffneten Health.md-App auf dem iPhone, ohne den Befehl durch Health.md für Mac zu leiten. Das iPhone liest HealthKit, stellt das Ergebnis im geschützten Speicher bereit und überträgt validierte Partitionen an die CLI.

```text
healthmd on the computer
  <-> authenticated encrypted Manual IP, Tailscale, or supported Nearby channel
Health.md on iPhone -> HealthKit -> protected bounded spool / typed query evaluator
  -> canonical JSON, production-generated files, or bounded MCP query pages
```

<div class="availability preview">
<strong>Vorschau · portable direkte CLI</strong>
<p>Das mitgelieferte direkte Swift-Backend ist unter macOS verfügbar. Der plattformübergreifende Rust-Client ist eine Alphaversion, deren Release-QA mit einem physischen iPhone und deren erstes öffentliches Paket noch ausstehen; die Befehle für Linux und Windows beschreiben den vorbereiteten Arbeitsablauf.</p>
</div>

## Unterstützte Funktionen des Direktmodus

- einmalige Kopplung und vertrauenswürdige Wiederverbindung;
- lokale Prüfung und Entkopplung vertrauenswürdiger Geräte;
- Live-Bereitschaft des iPhone;
- strikter Rohdatenexport nach Schema v7;
- ausgewählte kanonische Extraktion;
- Export von mit den produktiven Exportern erzeugten Dateien;
- Status und Fortsetzung persistenter lokaler Aufträge;
- ausdrücklicher Abbruch;
- der stdio-Server `healthmd mcp serve` in derselben ausführbaren Datei mit direkten typisierten Abfragen, Metrikkatalog, Nachweisen, MCP-Apps-Oberfläche und PNG-Fallback.

Das direkte Backend des Befehls `healthmd` emuliert nicht die HTTP-Routen der Mac-App für verschlüsselten Kontext. Mac-orientierte Unterbefehle für `doctor`, Abfragen, Nachweise und Aktualisierung geben daher weiterhin `backend_unsupported` zurück, statt das Backend zu wechseln. Verwenden Sie `healthmd mcp serve` für neue typisierte Analysen direkt vom iPhone oder `healthmd setup codex`, um Codex automatisch zu konfigurieren und zu koppeln. `healthmd mcp schema [TOOL]` gibt das exakte verschachtelte MCP-Eingabeschema und lokale Beispiele aus. Verwenden Sie für Schlaf direkt `healthmd_sleep_sessions`, statt die kanonische Ausgabe von `extract` als typisierte Abfrage-API zu behandeln.

## Voraussetzungen

- Eine direktfähige `healthmd`-Binärdatei und eine passende Health.md-Version auf dem iPhone.
- Health.md muss für Kopplung und neue Befehle im Vordergrund des iPhone geöffnet sein.
- **Settings > Mac Sync > Direct CLI Access** muss auf dem iPhone aktiviert sein.
- HealthKit-Berechtigung, geschützte Daten, Berechtigung für das lokale Netzwerk und Exportkontingent müssen verfügbar sein.
- Eine erreichbare Computeradresse und TCP-Port `17647` für Manual IP. Eine Tailscale-Adresse funktioniert ebenfalls.
- Ein vorhandenes absolutes Ziel für den Modus mit generierten Dateien.

Die CLI ist der Listener. Das iPhone verbindet sich mit der Computeradresse, die unter Direct CLI Access eingegeben wurde.

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

Der Befehl gibt einen sechsstelligen Code aus, mögliche Computeradressen und den Listener-Port auf stderr; stdout bleibt für das abschließende JSON-Ergebnis reserviert.

Auf dem iPhone:

1. Öffnen Sie **Health.md > Settings > Mac Sync > Direct CLI Access**.
2. Aktivieren Sie Direct CLI Access.
3. Wählen Sie **Manual IP**.
4. Geben Sie die LAN- oder Tailscale-Adresse des Computers ein.
5. Geben Sie Port `17647` ein, sofern die CLI keinen anderen globalen `--port` verwendet.
6. Geben Sie den Kopplungscode ein und tippen Sie auf Pair.
7. Lassen Sie die App geöffnet, bis beide Seiten Erfolg melden.

Kopplungscodes laufen nach 10 Minuten ab. Sie werden weder über das Netzwerk gesendet noch dauerhaft gespeichert.

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

Diese Befehle lesen oder ändern lokale Vertrauensstellungen und kontaktieren das iPhone nicht. Verwenden Sie auf dem iPhone **Forget Paired CLI**, um die Gegenseite zu entfernen.

Sind mehrere iPhones vertrauenswürdig, wählen Sie die gewünschte Installation ausdrücklich aus:

```bash
healthmd --backend direct --device DEVICE_UUID status
```

Verwenden Sie `healthmd direct reset-trust --confirm` nur, wenn die lokale Vertrauensstellung beschädigt ist oder zu einer ersetzten Installation gehört. Der Befehl entfernt alle lokalen direkten Kopplungen. Vergessen Sie diese Kopplungen auf dem iPhone, bevor Sie neu beginnen.

## Live-Bereitschaft prüfen

```bash
healthmd --backend direct --transport manual-ip status
```

Eine direkte Statusantwort meldet Verbindungs- und Sicherheitsstatus ohne Gesundheitswerte. Prüfen Sie vor Arbeitsbeginn folgende Felder:

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

## Strikter Rohdatenexport

Wählen Sie genau einen Zeitraumselektor:

```bash
healthmd --backend direct export --yesterday --raw --output yesterday.json
healthmd --backend direct export --last 7 --raw --output week.json
healthmd --backend direct export \
  --from 2026-07-01 --to 2026-07-07 --raw --output range.json
healthmd --backend direct export --all --raw --output complete-health-corpus.json
```

Lassen Sie `--output` weg, um validiertes JSON auf stdout zu streamen. Eine Ausgabedatei ist bei vertraulichen oder großen Antworten sicherer.

Die strikte Rohdatenausgabe enthält `healthmd.raw_result` v1 mit gewöhnlichen Schema-v7-Tagen vom Typ `healthmd.health_data` und deren kanonischen Quellarchiven. Sie fordert vorübergehend verlustfreie Details an, ohne gespeicherte iPhone-Einstellungen zu ändern. Bevor die CLI das Ergebnis bereitstellt, validiert sie exakte Datumswerte, Profil, Schema, Archiv, Manifeste, Digest-Kette, abschließenden Body-Digest und Abschlussstatus.

Ein vollständig leerer Tag ist erfolgreich. Fehlende, partielle, fehlgeschlagene, abgebrochene, nicht unterstützte oder übersprungene angeforderte Daten führen zu `partial_success` und einem von null verschiedenen Exit-Code, sofern `--allow-partial` nicht ausdrücklich gesetzt ist.

## Kanonische Extraktion

Die direkte Extraktion verwendet dieselbe dauerhafte Rohdatenübertragung, gibt jedoch ausgewählte quellstrukturierte Daten statt des Transport-Envelopes zurück:

```bash
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json

healthmd --backend direct extract \
  --metric workouts --last 14 --object records \
  --detail lossless --output workout-records.json
```

Die Auswahl von Metrik, Kategorie, Quelle und Detail erreicht das iPhone vor den HealthKit-Lesevorgängen. Unter [Kanonische Extraktion](/de/docs/cli-extract/) finden Sie Objektselektoren, JSON Pointer, JSONL und Belege.

## Für die Produktion generierte Dateien

Der direkte Dateimodus lässt das iPhone die Produktions-Exporter von Health.md ausführen und überträgt die erzeugten Dateien anschließend an ein ausdrückliches Computerziel.

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

Ziele für generierte Dateien funktionieren unter macOS und Linux. Protokoll v1 weist sie unter Windows zurück. Windows-Benutzer können Rohdatenexport und Extraktion verwenden.

## Verhalten im Vorder- und Hintergrund

Kopplung und neue Arbeit erfordern die iPhone-App im Vordergrund. Direct CLI Access macht iOS nicht zu einem unbeaufsichtigten Exportserver und kann die App nicht bei Bedarf aufwecken.

Wechselt die App während eines bereits verbundenen Exports in den Hintergrund, fordert Health.md begrenzte iOS-Hintergrundausführungszeit an. Der Export kann innerhalb dieses Zeitraums abgeschlossen werden. Läuft er ab, wird die Verbindung geschlossen und der persistente Auftrag pausiert. Öffnen Sie Health.md erneut und setzen Sie denselben Auftrag fort.

Das iPhone zeigt während direkter Arbeit ein globales Aktivitätsbanner. Es enthält Erfassungs- und Übertragungsphase, abgeschlossene Tage, Byte-Fortschritt sowie pausierten oder abgeschlossenen Status, jedoch keine Gesundheitswerte.

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

- Die Kopplung verwendet ephemeren Curve25519-Schlüsselaustausch und an den sechsstelligen Code gebundene Transkript-Nachweise.
- Die Wiederverbindung weist ein zufälliges gespeichertes Geheimnis und beide Installationsidentitäten nach.
- Jede Verbindung leitet neue Schlüssel und Nonces ab.
- Nachrichten und Binärframes verwenden ChaCha20-Poly1305 mit monotonen Sequenzprüfungen.
- Partitionen verwenden SHA-256-Manifeste und eine verkettete Digest-Grenze.
- Die iPhone-Vertrauensstellung wird im Schlüsselbund gespeichert.
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
  <a href="/de/docs/cli-extract/"><span>Daten</span>Kanonische Extraktion: quellstrukturierte Health.md-Daten auswählen und ausgeben.</a>
  <a href="/de/docs/cli-jobs/"><span>Zuverlässigkeit</span>Persistente Aufträge und Automatisierung: Fortsetzung, Abbruch, Teilergebnisse und Skripte.</a>
  <a href="/de/docs/reference/connected-mac-iphone-protocol/"><span>Protokoll</span>Referenz für verbundenen Mac und iPhone: Fähigkeiten, begrenzte Übertragung und Ergebnisstatus.</a>
</div>
