---
title: Rohe API-Snapshots
description: Exportieren Sie unveränderliche, versionierte JSON- oder NDJSON-Snapshots von Health Connect-Datensätzen und von Fitbit-, Oura-, WHOOP- und Withings-Anbieterantworten mit Manifesten je Typ und Prüfsummen.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Android · Export in Archivqualität</p>
  <p>Raw API Snapshot ist ein separates Exportprodukt von Health.md für Android für Migrations- und Archivierungsworkflows: ein unveränderliches, versioniertes JSON- oder NDJSON-Artefakt pro ausgewähltem Zeitraum, das native Datensätze bewahrt.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Bei Google Play herunterladen</a>
    <a class="docs-button-secondary" href="/de/docs/android/">Android-App-Leitfaden</a>
  </div>
</div>

## Was ein roher Snapshot ist

Kompatibilitätsexporte wandeln Health Connect-Datensätze in lesbare tägliche `HealthData`-Zusammenfassungen um. Ein roher Snapshot überspringt diese Umwandlung vollständig:

- **Health Connect-Snapshots** bewahren jedes Feld, das die fixierte AndroidX-API bereitstellt, einschließlich nativer Identität und Metadaten, Nanosekunden-Zeitstempel, nullbarer Quelloffsets, roher Enum-Werte, verschachtelter Samples, Stages, Routen und geplanter Workout-Strukturen.
- **Fitbit-, Oura-, WHOOP- und Withings-Snapshots** bewahren die exakten Bytes erfolgreicher Anbieterantworten und legen Endpunkt-Paginierung sowie serverseitige Aggregation offen. Nicht unterstützte Anbieter werden gemeldet, statt normalisiert oder stillschweigend durch Health Connect-Daten ersetzt zu werden.
- Jedes Artefakt endet mit einem **Manifest** mit Status, Problemen, Anzahlen und Prüfsummen je Typ. Ordner-Exporte erhalten zusätzlich eine `.sha256`-Begleitdatei.

Ein roher Snapshot ist API-vollständig für die fixierte Anbieter-API der App, aber kein transaktionaler Backup der Anbieterdatenbank. Er kann nicht zugängliche Datensätze, Originaleinheiten, die die API nicht offenlegt, gelöschte Datensätze oder Felder, die dem installierten SDK unbekannt sind, nicht wiederherstellen.

## Vorschau vor dem Ziel

Rohe Snapshots können ohne konfiguriertes Ziel in der Vorschau angezeigt werden. Die Vorschau führt die vollständige anbieternative Lesung in privaten No-Backup-Speicher aus, behält nur begrenzten Kopf- und Endtext im Speicher und löscht das temporäre Artefakt, ohne etwas hochzuladen.

## Zustellungsregeln

Rohe API-Uploads sind bewusst strenger als Kompatibilitäts-API-Exporte:

| Regel | Grund |
|---|---|
| Nur HTTPS | Das gestreamte Artefakt reist nie im Klartext |
| Weiterleitungen werden abgelehnt | Artefakt und Zugangsdaten können nie an einen anderen Ursprung weitergereicht werden |
| Schema-, Export- und Prüfsummen-Header | Der empfangende Endpunkt kann verifizieren, was er akzeptiert hat |
| Temporäres privates Artefakt wird nach dem Versuch gelöscht | Auf dem Gerät verbleibt keine Kopie |

## Inkrementelle Archive

Das separat versionierte `healthmd.raw-changes`-Backend nutzt Health Connect-Änderungstoken und Löschmarkierungen (Tombstones) für künftige inkrementelle Archivierungsworkflows, sodass ein vollständiger Snapshot nicht die einzige Archivierungsstrategie sein muss.

## Voraussetzungen

- Health.md für Android mit dem Produkt Raw API Snapshot.
- Health Connect-Berechtigungen für die ausgewählten Datensatztypen oder ein verbundenes Fitbit-, Oura-, WHOOP- oder Withings-Konto für Anbieter-Snapshots.
- Ein HTTPS-Endpunkt, wenn Sie Snapshots hochladen; der lokale Ordner-Export hat keine Transportanforderungen.

## Wo Sie mehr erfahren

- [Raw-Snapshot-v1-Vertrag](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-snapshot-v1.md)
- [Raw-Datensatz-v1-Vertrag](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-record-v1.md)
- [Raw-Änderungen-v1-Vertrag](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-changes-v1.md)
