---
title: "API-Endpunkt"
description: "Senden Sie ausgewählte Apple Health-JSON-Daten direkt vom iPhone an Ihren eigenen HTTP(S)-Endpunkt."
---

<p>Der API-Endpunkt ist ein Exportziel für Benutzer, die Health.md-Daten an ihren eigenen Server, Webhook, ihre Datenbank, ihr Dashboard oder ihre Automatisierung übertragen möchten. Das iPhone liest weiterhin Apple Health; statt Dateien zu schreiben, sendet es JSON per POST an den von Ihnen konfigurierten Endpunkt.</p>

<div class="callout">
<strong>Hinweis zum Datenschutz.</strong>
<p style="margin-top:6px;">Dieses Ziel sendet ausgewählte Gesundheitsdaten bewusst an die von Ihnen eingegebene URL. Verwenden Sie einen Endpunkt, den Sie kontrollieren oder dem Sie vertrauen, bevorzugen Sie HTTPS und beschränken Sie die Metriken auf das, was Ihr Dienst tatsächlich benötigt.</p>
</div>

## Ziel einrichten

<ol>
<li>Öffnen Sie Health.md auf dem iPhone.</li>
<li>Wechseln Sie zu <strong>Export</strong>.</li>
<li>Wählen Sie unter <strong>Export Target</strong> den Eintrag <strong>API Endpoint</strong>.</li>
<li>Geben Sie eine URL wie <code>https://api.example.com/healthmd/ingest</code> ein.</li>
<li>Optional: Geben Sie ein Bearer-Token ein. Health.md speichert es im Schlüsselbund.</li>
<li>Tippen Sie auf <strong>Done</strong>, wählen Sie Datumsbereich und Metriken und tippen Sie anschließend auf <strong>Export</strong>.</li>
</ol>

<p>Wenn Sie ein reines Token eingeben, sendet Health.md es als <code>Authorization: Bearer &lt;token&gt;</code>. Beginnt der Wert bereits mit <code>Bearer </code> oder <code>Basic </code>, sendet Health.md ihn unverändert.</p>

## Struktur der Nutzlast

<p>Health.md sendet pro Exportvorgang eine POST-Anfrage. Der Request-Body ist ein unabhängig versionierter API-Envelope vom Typ <code>healthmd.api_export</code> mit täglichen Datensätzen des öffentlichen Schemas v8 <code>healthmd.health_data</code>. Der API-Envelope v1 enthält die täglichen Datensätze; v2 kann zusätzlich Provider-Sidecars enthalten, ohne das Schema der täglichen Datensätze zu ändern.</p>

<div class="options">
<div class="option"><strong><code>records</code></strong><p>Vollständige tägliche Schema-v8-Objekte, die für den angeforderten Zeitraum beibehalten wurden, einschließlich vollständig leerer Datensätze, deren Abfragemanifest als Nachweis dient.</p></div>
<div class="option"><strong><code>failed_date_details</code></strong><p>Datumswerte, bei denen ein Fehler auftrat, bevor ein Tagesdokument beibehalten werden konnte.</p></div>
<div class="option"><strong><code>daily_record_schema_version</code></strong><p>Die Version des täglichen Schemas innerhalb von <code>records</code>. Sie wird unabhängig von der Version des API-Envelopes weiterentwickelt.</p></div>
<div class="option"><strong>Provider-Sidecars</strong><p>Bedingte externe v2-Datensätze mit eigenem Schema und eigenen Identitätsregeln, wenn ein verbundener Provider aktiviert ist.</p></div>
</div>

<p>Prüfen Sie den vollständigen, mit dem Produktcode erzeugten <a href="/docs/reference/generated/automation/api-export-v1.json">API-Envelope v1</a> und den <a href="/docs/reference/generated/automation/api-export-v2-provider-sidecar.json">API-Envelope v2 mit Provider-Sidecar</a>. Der <a href="/de/docs/reference/api-and-cli/">API- und CLI-Vertrag</a> dokumentiert jedes Feld, jede Versionsgrenze und jede Akzeptanzregel.</p>

## Anforderungen an den Endpunkt

<div class="options">
<div class="option"><strong>Methode</strong><p>Akzeptieren Sie <code>POST</code>.</p></div>
<div class="option"><strong>Inhaltstyp</strong><p>Akzeptieren Sie <code>application/json</code>.</p></div>
<div class="option"><strong>Erfolg</strong><p>Geben Sie einen beliebigen <code>2xx</code>-Status zurück, nachdem die Nutzlast sicher angenommen wurde.</p></div>
<div class="option"><strong>Fehler</strong><p>Geben Sie bei abgelehnten Anfragen <code>4xx</code> oder <code>5xx</code> zurück. Health.md zeigt, sofern verfügbar, eine kurze Vorschau der Antwort an.</p></div>
</div>

<p>Gestalten Sie Ihren Endpunkt für eine zuverlässige Aufnahme pro Datum idempotent. Benutzer können denselben Exportzeitraum erneut senden, nachdem sie Metriken geändert oder einen Serverfehler behoben haben.</p>

## Tipps

<ul>
<li>Testen Sie zunächst mit einem Tag, bevor Sie umfangreiche historische Daten hochladen.</li>
<li>Lassen Sie Lossless Health Records aktiviert, wenn die Vollständigkeit der Quelldaten wichtig ist; verkürzen Sie den Zeitraum bei dichten Routen, klinischen Dokumenten, EKGs oder Anhängen.</li>
<li>Validieren Sie das Token serverseitig, bevor Sie Nutzdaten speichern.</li>
<li>Verwenden Sie <code>records[].date</code> als primären Schlüssel pro Tag.</li>
<li>Geben Sie einen knappen Fehlertext zurück; Health.md zeigt nur eine kurze Vorschau an.</li>
</ul>

## Fehlerbehebung

| Problem | Übliche Ursache | Lösung |
|---|---|---|
| API-Ziel ist nicht bereit | URL ist leer oder ungültig | Öffnen Sie die Einstellungen für API Endpoint erneut und geben Sie eine gültige HTTP(S)-URL ein. |
| HTTP 401 oder 403 | Token fehlt oder wurde abgelehnt | Aktualisieren Sie das Token oder die Authentifizierungsregeln des Servers. |
| HTTP 404 | URL-Pfad ist falsch | Prüfen Sie die Route auf Ihrem Server. |
| HTTP 413 | Nutzlast ist zu groß | Exportieren Sie weniger Tage; verwenden Sie eine reine Zusammenfassung nur, wenn der Empfänger keine kanonischen Quelldatensätze benötigt. |
| Einige Datumswerte fehlen | Für diese Tage sind keine aktivierten HealthKit-Daten vorhanden | Prüfen Sie <code>failed_date_details</code> und Ihre Metrikauswahl. |

## Verwandte Themen

<div class="related">
  <a href="/de/docs/export/"><span>Quelle</span>Export — Ziele und Datumsbereiche auswählen und manuelle Exporte ausführen.</a>
  <a href="/de/docs/reference/api-and-cli/"><span>Schema</span>API- und CLI-Referenz — exakte API-Envelopes, Versionen, Fehlerverhalten und generierte Beispiele.</a>
  <a href="/de/docs/format/"><span>Ausgabe</span>Formatanpassung — JSON, CSV, Markdown, Einheiten und Felder.</a>
</div>
