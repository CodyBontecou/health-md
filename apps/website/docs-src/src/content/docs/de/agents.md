---
title: "Lokale Agenten und Gesundheitskontext"
description: "Verbinden Sie lokale Agenten über begrenzte CLI-Befehle oder direktes iPhone-MCP mit Health.md und bewahren Sie Nachweise, Abdeckung und fehlende Daten."
---

Health.md bietet lokalen Coding- und Automatisierungsagenten zwei Wege für die Arbeit mit Apple Health-Daten:

- die `healthmd` CLI für ausdrückliche Terminalbefehle und kanonische Extraktion;
- `healthmd mcp serve` und die zugehörige MCP App für typisierte Tools, native Visualisierungen und genehmigte Exporte generierter Dateien.

Der portable MCP-Server kommuniziert direkt mit dem iPhone im Vordergrund und benötigt Health.md für Mac nicht. Die CLI kann denselben direkten Kanal für rohe oder kanonische Exporte oder die Loopback-API der Mac-App für Mac-Index-Workflows verwenden. HealthKit-Lesevorgänge erfolgen stets auf dem iPhone, und `healthmd.health_data` v8 bleibt der öffentliche Quellvertrag.

```text
local agent -> healthmd mcp serve -> authenticated encrypted port 17647 -> foreground iPhone
local agent -> healthmd CLI -> direct iPhone or optional Mac loopback workflow
```

## Möglichkeiten eines Agenten

- direkte Kopplung und Bereitschaft des iPhone im Vordergrund ohne Gesundheitswerte prüfen;
- kanonische Metrik-IDs und Kategorien auflisten;
- einen exakten Metrik-, Quellen-, Datums- und Detailumfang vom iPhone erfassen;
- kanonische Tagesdokumente oder Quelldatensätze extrahieren;
- typisierte Metrikreihen mit Nachweisen und Abdeckung abfragen;
- stabile Schlafsitzungen und feste Schlaffenster erstellen;
- Trainingseinheiten dem vorherigen und nachfolgenden Schlaf zuordnen;
- Trainingseinheiten auflisten und Abdeckung prüfen;
- exakte Zeiträume mit ausdrücklicher Aggregation vergleichen;
- sachliche Trainingsnachweispakete erstellen;
- einen unbegrenzten logischen Korpus mit begrenzten Anfragen seitenweise durchlaufen;
- Metrik-, Schlaf-, Trainings-, Vergleichs-, Abdeckungs- und Nachweisansichten in MCP Apps darstellen;
- genehmigte Exporte generierter Dateien in ein ausdrückliches vorhandenes Desktop-Ziel ausführen;
- persistente Exportaufträge prüfen, fortsetzen oder abbrechen.

Health.md stellt keine Diagnosen, empfiehlt keine Behandlung, leitet keine Kausalität ab und kennzeichnet Ergebnisse nicht als gesund, schädlich, besser oder schlechter.

## Lokale Helfer einrichten

<div class="availability preview">
<strong>Öffentliche Vorschau · noch keine qualifizierte stabile Version</strong>
<p>Das plattformübergreifende Paket ist als ausdrücklich nicht qualifizierte Vorschau veröffentlicht. Verwenden Sie den exakten mobilen Build aus den Release-Nachweisen; der signierte Mac-Helfer bleibt unter <a href="/de/docs/configuration/">Agenten konfigurieren</a> verfügbar.</p>
</div>

1. Führen Sie unter macOS oder Linux `brew install CodyBontecou/tap/healthmd` aus und prüfen Sie danach `healthmd --version`.
2. Führen Sie `healthmd setup codex` aus. Der Befehl konfiguriert Codex und startet die Kopplung, wenn noch kein iPhone vertrauenswürdig ist.
3. Schließen Sie die Kopplung unter Direct CLI Access in Health.md auf dem iPhone ab und lassen Sie die App im Vordergrund.
4. Konfigurieren Sie für Claude oder eine manuelle Host-Einrichtung den absoluten `healthmd`-Pfad mit den Argumenten `mcp serve`, wie unter [Health.md MCP-Server und App](/de/docs/mcp/) beschrieben.
5. Starten Sie den Host neu, wenn die Einrichtung eine geänderte Konfiguration meldet, und rufen Sie dann `healthmd_doctor` auf.

## Einen Agenten-Skill installieren

Die Health.md-Mac-App bleibt für Mac-Benutzer eine optionale Installations- und Skill-Verteilungsmöglichkeit, ist aber keine Abhängigkeit des portablen MCP.

Die meisten Benutzer sollten nur den [Health.md CLI-Verbraucher-Skill auf skills.sh](https://skills.sh/CodyBontecou/health-md/healthmd-cli) installieren:

```bash
npx skills add CodyBontecou/health-md@healthmd-cli
```

Das öffentliche Repository stellt vier aufgabenspezifische Skills bereit:

| Skill | Vorgesehene Verwendung |
|---|---|
| `healthmd-cli` | Begrenzte, vom Benutzer autorisierte CLI- und MCP-Abfragen und -Exporte |
| `healthmd-cli-operator` | Direkte iPhone-Vorgänge und Wiederherstellung dauerhafter Aufträge |
| `healthmd-cli-development` | Entwicklung von CLI, MCP, Protokoll und iPhone-Dienst |
| `healthmd-cli-qa` | Automatisierte Validierung und Tests auf physischen Geräten |

Installieren Sie einen Mitwirkenden-Skill, indem Sie den Namen nach `@` ersetzen; installieren Sie für gewöhnliche Gesundheitsdatenanfragen keine Entwicklungs- oder QA-Anleitung. Mit `npx skills add CodyBontecou/health-md --list` prüfen Sie das Repository, ohne einen Skill zu installieren. Mit `npx skills update healthmd-cli --project --yes` aktualisieren Sie den projektbezogenen Verbraucher-Skill. Der [Installationsleitfaden im Repository](https://github.com/CodyBontecou/health-md/blob/main/docs/agents/skills.md) dokumentiert alle Befehle und den Veröffentlichungsvertrag.

Ein Skill ist ein Anweisungspaket. Er installiert weder `healthmd` noch `healthmd-mcp`, konfiguriert MCP nicht, koppelt kein Telefon, gewährt keinen Zugriff auf Gesundheitsdaten und aktualisiert sich nicht automatisch. Prüfen Sie vor der Installation den Quelltext.

Das Skill-Installationsprogramm der App erstellt `healthmd-cli/SKILL.md` im genehmigten Verzeichnis. Es ersetzt nur den eigenen Skill-Ordner von Health.md. Der Skill vermittelt begrenzte Befehle, strukturierte Ergebnisbehandlung, Datenschutzregeln, Offenlegungsgrenzen für Modellanbieter und sichere Wiederherstellung nach unbekannten Ergebnissen.

Verwenden Sie den Einrichtungs-Prompt der Mac-App, wenn ein Agent die symbolischen Links erstellen soll. Health.md selbst ändert weder Shell-Startdateien noch `/usr/local/bin` unbemerkt.

## Zuerst die Bereitschaft prüfen

Rufen Sie für portable MCP-Clients `healthmd_doctor` auf. Das Tool prüft lokale direkte Vertrauensstellung und das verbundene iPhone im Vordergrund ohne Gesundheitswerte und gibt umsetzbare, gesundheitsdatenfreie Fehler zurück. Jede typisierte MCP-Abfrage ist anschließend eine ausdrückliche neue Anfrage an dieses iPhone: Sie erfasst nur den angeforderten Umfang, wertet die typisierte Abfrage auf dem Gerät aus und gibt begrenzte Seiten zurück.

Benutzer der Mac-Loopback-CLI können weiterhin `healthmd doctor` ausführen, um Bereitschaft, Abdeckung des verschlüsselten Kontexts und nächste Schritte als `healthmd.cli_doctor` v1 zu erhalten.

## Jede Anfrage enthält ihren eigenen Umfang

Health.md verwendet keine gespeicherten Zugriffsprofile, Aufruferregistrierungen, Berechtigungsdatensätze oder CLI-Anmeldedaten. Jede Anfrage gibt ihren vollständigen Datenumfang an:

- Metrik-IDs oder Kategorien;
- Apple Health und optionale Provider-Quellselektoren;
- exakte oder alle verfügbaren Datumswerte;
- Zusammenfassungs- oder verlustfreie Details;
- Abfragevorgang;
- begrenzte Seitensteuerung.

Die neue Erfassung validiert den Umfang anhand aktueller Kataloge, speichert ihn mit dem persistenten Auftrag und wendet ihn auf dem iPhone an, ohne gespeicherte Exporteinstellungen zu ändern.

Eine Anfrage ohne ausdrückliche Erfassungsauswahl wird abgelehnt, statt die normalen Exporteinstellungen des Benutzers zu übernehmen.

## Autorisierungsgrenzen

Portables MCP verwendet das gekoppelte direkte Protokoll: native Anmeldedatenspeicherung, gegenseitige Transkript-Authentifizierung, verschlüsselte Pakete, Replay-Schutz und eine iPhone-Verbindung im Vordergrund zur ausdrücklichen Adresse des Computers. Die optionale Mac-Abfrage-API lauscht ausschließlich auf IPv4- und IPv6-Loopback und validiert die Gegenstelle als Loopback.

Im optionalen Mac-Loopback-Modus kann jeder lokale Prozess, der Port `17645` bei geöffneter Health.md-App erreicht, dieselben Abfragen stellen. Behandeln Sie lokalen Computerzugriff als Abfrageberechtigung:

- Port nicht an eine LAN-Schnittstelle binden oder weiterleiten;
- keinen Tunnel zu einem anderen Computer einrichten;
- keinen HTTP-Reverse-Proxy davorschalten;
- MCP nicht mit einer Nicht-Loopback-URL konfigurieren;
- prüfen, welche lokalen Agenten den Helfer ausführen können.

Frühere Profil- und Aktivitätsrouten geben aus Kompatibilitätsgründen `410 removed_endpoint` zurück.

## Kanonische Daten und abgeleitete Ansichten

Verwenden Sie `healthmd extract`, wenn der Agent Daten in der Struktur der Quelle oder umfangreiche validierte Rohdaten beziehungsweise kanonische Inhalte benötigt:

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

Verwenden Sie Abfragebefehle oder MCP-Tools für abgeleitete Ansichten und Visualisierungen im Host:

```bash
healthmd query --metric resting_heart_rate --last 30 --all-pages
healthmd sleep sessions --last-nights 14 --window first:4h
healthmd training align --last 14 --workout running --sleep-window first:4h
```

Die Trennung ist beabsichtigt:

| Oberfläche | Vertragsrolle |
|---|---|
| `healthmd.health_data` v8 | Öffentliches tägliches Quelldokument |
| `healthmd.healthkit_records` v1 | Kanonisches Quelldatensatzarchiv in verlustfreien Tagesdokumenten |
| `healthmd.extract_receipt` | Umfang und Abschlussmetadaten der Extraktion |
| `healthmd.query_context_day` v1 | Wegwerfbarer verschlüsselter Indexdatensatz |
| `healthmd.query_response` v1 | Typisiertes paginiertes abgeleitetes Ergebnis |
| `healthmd.evidence_packet` v1 | Sachliches, mit Quellnachweisen verknüpftes Paket |
| Auftrags- und Paginierungsbelege | Metadaten zu Übertragung, Dauerhaftigkeit und Abschluss |

Eine Projektion oder ein typisiertes Ergebnis gibt sich nie als vollständiges tägliches Quelldokument aus.

## Neue Erfassung

High-Level-Abfragen erfassen standardmäßig neue Daten:

```bash
healthmd query --category Sleep --last 14
```

Health.md erstellt eine eigene Anfrage für verschlüsselten Kontext. Sie schreibt keine Exportdateien und verbraucht kein Dateiexportkontingent. Das iPhone liest den ausdrücklichen Umfang, erstellt deterministische kompakte Inhabertage und sendet begrenzte, wiederaufnehmbare Partitionen. Der Mac bestätigt jeden verschlüsselten Tag, bevor er ihn quittiert.

Der neue Abschluss prüft jede angeforderte Metrik, Quelle, jeden Provider und Inhabertag gegen Blobs, die nach Beginn dieser Aktualisierung ersetzt wurden. Ältere Cache-Werte und Daten eines anderen Providers können eine fehlgeschlagene Erfassung nicht verdecken.

Reine Provider-Anfragen können HealthKit überspringen. Das Durchlaufen des Provider-Verlaufs folgt providernativen Cursorn statt einer festen Gesamtgrenze.

## Verschlüsselter Mac-Kontext

Der Mac speichert pro Inhabertag eine unabhängig verschlüsselte Generation. Ein zufälliger 256-Bit-Schlüssel liegt als nur auf diesem Gerät verfügbarer und bei Entsperrung zugänglicher Eintrag im Schlüsselbund.

- Tages-Blobs und Manifest verwenden AES-256-GCM;
- Dateinamen sind zufällige UUIDs statt Datums- oder Metriknamen;
- Inhaberdaten und Indexeinträge sind verschlüsselt;
- Dateien besitzen nur Berechtigungen ausschließlich für den Dateieigentümer und sind von Backups ausgeschlossen;
- Commits schreiben vor dem Ersetzen des verschlüsselten Manifests eine neue unveränderliche Generation;
- Lesevorgänge brechen bei fehlenden Schlüsseln, fehlgeschlagener Authentifizierung, fehlerhaften Datumswerten oder Manifestabweichung sicher ab.

Der Speicher hat keine konfigurierte Gesamtgrenze für Metriken, Tage, Verlauf oder Ergebnisse. Befehle bleiben begrenzt, weil sie tageweise entschlüsseln und Ergebnisse paginieren.

Der Index ist entbehrlich. Kanonische Exporte bleiben die maßgebliche Quelle.

## Aufbewahrung und Löschung

Health.md löscht Abfragekontext nicht nach einem impliziten Zeitplan. In den Mac-Einstellungen werden Anzahl und Datumsbereich der gespeicherten Inhabertage angezeigt.

Verwenden Sie:

- **Delete Older Context**, um Inhaberdaten strikt vor einer ausgewählten Grenze zu entfernen;
- **Delete All Encrypted Context**, um alle verschlüsselten Generationen und den zugehörigen Schlüsselbundschlüssel zu entfernen.

Vollständiges Löschen ist selbst bei beschädigtem Schlüssel oder Chiffretext möglich. Das Entfernen des Schlüssels bewirkt Krypto-Löschung für verbliebene Chiffretextreste.

Das Löschen des Abfragekontexts entfernt keine Exportdateien, Provider-Anmeldedaten oder Apple Health-Daten.

## Typisierte Werte und fehlende Daten

Abfragewerte sind typmarkiert. Ein Ergebnis kann Menge und kanonische Einheit, Dauer, vorzeichenbehaftete Anzahl, String, Kategorie, booleschen Wert, UTC-Zeitstempel, Kalenderdatum, verschachteltes Array oder unbekannte zukünftige typisierte Nutzdaten enthalten.

Fehlende Daten bleiben ausdrücklich gekennzeichnet:

- `complete_empty` bedeutet, dass der dargestellte Umfang keine passenden Beobachtungen enthielt;
- `partial` bedeutet, dass nur ein Teil abgeschlossen wurde;
- `failed`, `unsupported`, `skipped` und `cancelled` behalten ihre Bedeutung;
- `not_requested`, `legacy_unavailable`, `redacted` und `not_synchronized` bleiben getrennt.

Health.md wandelt einen fehlenden Wert nie in numerische null um. Eine echte Null wird als verfügbarer typisierter Wert codiert.

## Nachweise und neutrale Sprache

Ergebnisse verknüpfen Fakten mit Quelldatennachweisen wie:

- Schlüsseln aus Tageszusammenfassungen;
- kanonischen HealthKit-UUIDs;
- externen Identitäten;
- Ergebnissen von Abfragemanifesten;
- Integritätswarnungen;
- Teilfehlern.

Bei der Auflösung werden Nachweis-ID, Fundstelle, Quellschema, Quellversion und Quell-Digest gemeinsam geprüft.

Die Richtung eines Periodenvergleichs ist auf `increased`, `decreased`, `unchanged` oder `not_comparable` beschränkt. Trainingszuordnung meldet Zeitstempel und Abstände, keine Kausalwirkung. Nachweispakete berichten gespeicherte Beobachtungen und Abdeckung, keine medizinischen Schlussfolgerungen.

Ein Agent muss diese Grenzen in seiner Antwort bewahren, fehlende Daten nennen, Korrelation nicht als Ursache darstellen und medizinische Fragen an qualifiziertes Fachpersonal verweisen.

## Begrenzte Seiten, vollständiger logischer Zugriff

Abfrageseiten verwenden `max_items`, `max_bytes` und einen opaken `next_cursor`. Vertraglich gibt es keine Gesamtgrenze für gespeicherte Tage, Trainingseinheiten, Metriken oder Ergebnisse.

Ein Cursor ist integritätsgeschützt und an die semantische Abfrage sowie die Revision des verschlüsselten Korpus gebunden. Health.md weist Folgendes zurück:

- veränderte Cursor;
- Cursor, die mit einer anderen Abfrage verwendet werden;
- Cursor, die vor einer Änderung des Korpus ausgegeben wurden;
- bei der automatischen Paginierung wiederholte Cursor.

Verwenden Sie `--all-pages` oder MCP `all_pages: true`. Schränken Sie den Umfang ein oder paginieren Sie manuell, wenn ein Aufruf seine Gesamtsicherheitsgrenze erreicht.

## Checkliste für Agentenberichte

Geben Sie bei der Zusammenfassung eines Ergebnisses Folgendes an:

- verwendeter Befehl oder verwendetes Tool;
- exakt angeforderte Datumsangaben, Metriken, Quelle und Detailebene;
- Modus: neu erfasst, zwischengespeichert oder mit wiederverwendeter Abdeckung;
- Status des angeforderten Umfangs und Korpusstatus getrennt voneinander;
- Abschluss der Paginierung;
- Einheiten und Quelldatennachweise für jeden genannten Wert;
- fehlende Intervalle, Einschränkungen und nicht zum Umfang gehörende Auslassungen;
- Auftrags-ID, wenn die Arbeit pausiert oder fortgesetzt werden kann.

Geben Sie rohe Datensätze, Routen, klinische Texte, Medikamentendetails, Stimmungseinträge oder Anhänge nur auf ausdrücklichen Wunsch und bei verstandenem Offenlegungsrisiko aus.

## Integration auswählen

<div class="related">
  <a href="/de/docs/agent-queries/"><span>CLI-Rezepte</span>Typisierte Agentenabfragen für Metriken, Schlafsitzungen, Trainingszuordnung, Trainingseinheiten, Abdeckung, Vergleich und Nachweise.</a>
  <a href="/de/docs/mcp/"><span>Toolprotokoll</span>Codex- und Claude-Einrichtung, 21 veröffentlichte Mac-Tools, 19 portable Vorschau-Tools, MCP-App-Diagramme, Exporte, Paginierung und Sandbox-Grenzen.</a>
  <a href="/de/docs/agent-api/"><span>Low-Level</span>Loopback-Abfrage-API: Routen, direkte Anfrage-JSON-Daten, Cursor und persistente Erfassungsaufträge.</a>
  <a href="/de/docs/cli-extract/"><span>Quellobjekte</span>Kanonische Extraktion: ausgewählte Schema-v8-Dokumente, Datensätze, Projektionen und Belege.</a>
  <a href="/de/docs/reference/evidence-packets/"><span>Verträge</span>Kompakte Abfragen und Nachweispakete: typisierte Werte, Abdeckung, Vorgänge und deterministische IDs.</a>
</div>
