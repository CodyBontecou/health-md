---
title: "Loopback-Abfrage-API"
description: "Rufen Sie die versionierten lokalen Routen von Health.md für Abfragen, Nachweise, Aktualisierung, Bereitschaft, Metriken und persistente Aufträge über HTTP oder den Low-Level-Befehl healthmd agent auf."
---

Health.md für Mac stellt unter `/v1/agent/` eine versionierte lokale API bereit. Sie bedient Abfragen des verschlüsselten Kontexts, Nachweispakete, anfragebezogene iPhone-Erfassung, Bereitschaft und persistente Erfassungsaufträge.

Die API ist auf Port `17645` an Loopback gebunden. Sie akzeptiert ausschließlich validierte IPv4- oder IPv6-Loopback-Gegenstellen.

<div class="callout">
<strong>Stellen Sie diesen Port nicht bereit.</strong>
<p style="margin-top:6px;">Es gibt weder Bearer-Token noch Aufruferregistrierung, Zugriffsprofil oder Berechtigungsdatenbank. Die Erreichbarkeit über Loopback ist die vollständige Autorisierungsgrenze. Jeder lokale Prozess kann bei geöffneter Health.md-App Anfragen stellen.</p>
</div>

## Routen

| Methode | Route | Zweck |
|---|---|---|
| `GET` | `/v1/agent/capabilities` | Versionierte Schemas, Umfangsunterstützung und Seitengrenzen auflisten |
| `GET` | `/v1/agent/metrics` | Kanonische abfragbare Metrik-IDs, Kategorien, Einheiten und Anforderungen zurückgeben |
| `GET` | `/v1/agent/readiness` | Bereitschaft von verschlüsseltem Kontext und neuen iPhone-Daten samt nächsten Schritten zurückgeben |
| `POST` | `/v1/agent/query` | Eine begrenzte Seite einer typisierten Abfrage ausführen |
| `POST` | `/v1/agent/evidence` | Eine begrenzte Seite eines sachlichen Nachweispakets ableiten |
| `POST` | `/v1/agent/refresh` | Einen ausdrücklichen Umfang vom iPhone in den verschlüsselten Mac-Kontext erfassen |
| `GET` | `/v1/agent/jobs/{id}` | Einen persistenten lokalen Erfassungsauftrag prüfen |
| `POST` | `/v1/agent/jobs/{id}/resume` | Die unveränderliche Erfassungsanfrage fortsetzen |
| `POST` | `/v1/agent/jobs/{id}/cancel` | Einen ausdrücklichen Abbruch anfordern |

Die früheren Routen `/v1/agent/profiles` und `/v1/agent/activity/query` geben `410 removed_endpoint` zurück.

Das direkte iPhone-Backend stellt diese HTTP-Routen nicht bereit. Der eigenständige Befehl `healthmd` verwendet es für kanonische Extraktion und Export; `healthmd mcp serve` implementiert neue typisierte Abfragen, Nachweise, Metrikkatalog, Bereitschaft, Visualisierung und Tools für persistente Exporte direkt über das iPhone-Abfrageprotokoll v3. Kopplung und MCP verwenden dieselbe Identität der ausführbaren Datei; Aktualisierung und verschlüsselter Mac-Kontext bleiben dieser HTTP-API vorbehalten.

## CLI-Adapter bevorzugen

Die Low-Level-CLI übernimmt Request-Bodys unverändert und behandelt Loopback-Übertragungsfehler:

```bash
healthmd agent capabilities
healthmd agent query --input query-body.json
healthmd agent query --input - < query-body.json
healthmd agent evidence --input evidence-body.json
healthmd agent refresh --input refresh-body.json
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
healthmd agent job cancel JOB_UUID
```

Verwenden Sie für einen kleinen Body `--json JSON` statt `--input`. Die CLI erweitert oder verengt das an diese Befehle übergebene JSON nicht unbemerkt.

Für gewöhnliche Arbeitsabläufe eignen sich High-Level-Befehle wie `healthmd query`, `healthmd sleep sessions` oder `healthmd compare`. Sie validieren Selektoren und erstellen den typisierten Vorgang.

## Abfrage-Body

`POST /v1/agent/query` akzeptiert auf oberster Ebene nur `request` und optional `detail_level`:

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "metric_series"
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144
    }
  },
  "detail_level": "summary"
}
```

Unbekannte Wrapper-Felder werden abgelehnt. Der Abfragevertrag definiert Metriken, Quellen, Datumswerte, Vorgang und Seitensteuerung. `detail_level` ist `summary` oder `lossless`.

Die Antwort ist `healthmd.query_response` v1. Sie enthält typisierte Elemente, Abdeckung, Nachweise, Quelldeskriptoren, Einschränkungen und optional `next_cursor`.

Eine vollständige synthetische Antwort finden Sie unter [`agent-query-response.json`](/docs/reference/generated/automation/agent-query-response.json).

## Cursor fortsetzen

Senden Sie für die nächste Seite dieselbe semantische Anfrage und setzen Sie den zurückgegebenen Cursor in `page.cursor`:

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "metric_series"
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144,
      "cursor": "OPAQUE_CURSOR_FROM_PRIOR_RESPONSE"
    }
  },
  "detail_level": "summary"
}
```

Folgen Sie `next_cursor`, bis es fehlt. Cursor sind authentifiziert und an Anfrage sowie Revision des verschlüsselten Korpus gebunden. Health.md weist veränderte, unpassende und veraltete Cursor zurück.

Seitengrenzen schützen jede Anfrage, ohne den Gesamtverlauf oder die Gesamtergebnisse zu begrenzen.

## Nachweis-Body

`POST /v1/agent/evidence` verwendet denselben Wrapper. Der Vorgang ist `derive_packet` mit Paketart und ausdrücklich ausgewählten Details.

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps", "resting_heart_rate"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "derive_packet",
      "kind": "doctor_visit",
      "detail_ids": []
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144
    }
  },
  "detail_level": "summary"
}
```

Die Antwort bleibt paginiert und enthält ein Fragment vom Typ `healthmd.evidence_packet` v1. Fakten enthalten typisierte Werte und Nachweise. Das Paket enthält die Einschränkung auf rein sachliche Beobachtungen.

Eine vollständige synthetische Antwort finden Sie unter [`agent-evidence-response.json`](/docs/reference/generated/automation/agent-evidence-response.json).

## Aktualisierungs-Body

Die Aktualisierung erfasst nur einen ausdrücklichen Umfang. Der Body akzeptiert Datumswerte, Metriken, Quellen, Detailebene und ein begrenztes Wartezeitlimit:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-01",
      "end_date": "2026-07-07"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["sleep_total"]
  },
  "sources": {
    "type": "explicit",
    "source_ids": ["apple_health"],
    "provider_ids": []
  },
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

Der Mac validiert den Umfang anhand aktueller Kataloge und wandelt ihn in eine unveränderliche kanonische Auswahl um. Das iPhone liest nur die ausgewählten gewöhnlichen HealthKit-Typen. Anfragebezogene Einstellungen ändern keine gespeicherten iPhone-Exporteinstellungen.

Die Aktualisierung verwendet einen eigenen Übertragungsmodus `encrypted_context`:

- sie schreibt keine Exportdateien;
- sie verbraucht kein Dateiexportkontingent;
- sie überträgt begrenzte, fortsetzbare Partitionen;
- der Mac bestätigt jeden deterministischen kompakten Inhabertag vor der Bestätigung;
- die exakte Anfrage bleibt mit dem persistenten Auftrag gespeichert.

Ein reiner Provider-Umfang erfordert keinen Apple Health-Lesevorgang. Provider-native Verläufe bleiben provider-native Nachweise und werden nicht in künstliche Apple Health-Metriken umgewandelt.

## Auswahl aller verfügbaren Daten

Metrik- und Datumsselektoren können `all_available` verwenden:

```json
{
  "dates": {"type": "all_available"},
  "metrics": {"type": "all_available"},
  "sources": {"type": "all_available"},
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

Das iPhone ermittelt den frühesten verfügbaren ausgewählten Apple Health-Datensatz und jeden Tag des Quellkalenders bis heute. Die Provider-Erfassung folgt providernativen Verlaufscursorn. Die aufgelösten Kennungen werden vor der Übertragung festgeschrieben, damit sie sich bei einer Fortsetzung nicht verschieben.

Es gibt keine feste Datums- oder Ergebnisgrenze. Partitionen, Seiten, tageweise Entschlüsselung, Speicherplatz und begrenzte Wartezeiten setzen Ressourcengrenzen.

## Persistente Erfassungsaufträge

Ein Aktualisierungs-Waiter kann sein Zeitlimit erreichen, während der Auftrag weiterläuft. Die Antwort enthält eine Auftrags-ID und Fortschritt ohne Gesundheitsdaten.

```bash
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
healthmd agent job cancel JOB_UUID
```

Der Auftrag läuft sieben Tage nach Erstellung ab. Die Fortsetzung verwendet dieselbe Anfrage, denselben Mac, dasselbe iPhone, denselben Quellumfang und denselben bestätigten Fortschritt.

Der Abbruch ist erst nach Bestätigung durch das iPhone endgültig. Ein nicht verfügbares iPhone kann den Auftrag im Status „Abbruch ausstehend“ belassen.

## Direkte HTTP-Aufrufe

Die CLI wird bevorzugt, lokale Software kann HTTP jedoch direkt aufrufen:

```bash
curl --fail-with-body --max-time 5 \
  http://127.0.0.1:17645/v1/agent/readiness

curl --fail-with-body --max-time 30 \
  -H 'Content-Type: application/json' \
  --data @query-body.json \
  http://127.0.0.1:17645/v1/agent/query
```

Der Listener erzwingt begrenzte Header und JSON-Bodys, ausdrückliche Methode und Inhaltstyp, Empfangsfristen und einen garantiert endlichen Anfrageablauf.

Direkte HTTP-Clients müssen auf demselben Mac bleiben. Fügen Sie weder LAN-Bindung, Proxy oder Tunnel noch einen entfernten HTTP-MCP-Wrapper hinzu.

## Typisierte Werte und fehlende Daten

Abfrageergebnisse bewahren Typ und Einheit. Werte können Mengen, Dauern, Anzahlen, Strings, Kategorien, boolesche Werte, Zeitstempel, Kalenderdaten, verschachtelte Arrays oder unbekannte zukünftige typisierte Werte sein.

Status für fehlende Daten umfassen vollständig leer, partiell, fehlgeschlagen, nicht unterstützt, übersprungen, abgebrochen, nicht angefordert, in älteren Daten nicht verfügbar, geschwärzt und nicht synchronisiert. Verbraucher dürfen sie nicht in null umwandeln.

Die Abdeckung enthält angeforderte und verfügbare Zeiträume, berücksichtigte Tage, Tage mit Werten und komprimierte fehlende Intervalle mit Status.

## Fehlerbehandlung

Fehler verwenden `healthmd.query_error` v1 mit stabilem Code, Nachricht, Wiederholbarkeit und typisierten Details. Eigene Fehler decken ab:

- ungültige Seitensteuerung;
- fehlerhafte oder manipulierte Cursor;
- Nichtübereinstimmung von Cursor und Abfrage;
- veraltete Korpusrevision;
- ungültigen Datumsbereich;
- Metrik- oder Quellenvalidierung;
- Einheiten- oder Aggregationskonflikt;
- nicht unterstützten Vorgang;
- Verletzung des Nachweisumfangs;
- Bereitschaft von iPhone oder verschlüsseltem Speicher;
- Status persistenter Aufträge.

Wiederholen Sie eine Aktualisierung nach unbekanntem Ergebnis nicht blind. Prüfen Sie zuerst den Auftragsstatus.

## Verwandte Themen

<div class="related">
  <a href="/de/docs/agents/"><span>Überblick</span>Lokale Agenten und Gesundheitskontext: Einrichtung, verschlüsselter Speicher, Umfang und Berichtsregeln.</a>
  <a href="/de/docs/agent-queries/"><span>High-Level</span>Typisierte Abfragen: validierte Befehle für häufige Metrik-, Schlaf-, Trainings- und Nachweisfragen.</a>
  <a href="/de/docs/mcp/"><span>Tools</span>Lokaler MCP-Server: stdio-Konfiguration, typisierte Tools, Paginierung und Sandbox-Grenzen.</a>
  <a href="/de/docs/reference/api-and-cli/"><span>Referenz</span>API- und CLI-Vertrag: Export, Extraktion, Abfrage, direktes Backend und Betriebsgrenzen.</a>
  <a href="/de/docs/reference/evidence-packets/"><span>Datenverträge</span>Kompakte Abfragen und Nachweispakete: Typen, Cursor, Vorgänge und deterministische Paket-IDs.</a>
</div>
