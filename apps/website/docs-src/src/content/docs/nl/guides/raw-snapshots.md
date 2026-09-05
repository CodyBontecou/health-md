---
title: Ruwe API-snapshots
description: Exporteer onveranderlijke, versiebeheerde JSON- of NDJSON-snapshots van Health Connect-records en Fitbit-, Oura-, WHOOP- en Withings-providerreacties, met manifests per type en controlesommen.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Android · export op archiefniveau</p>
  <p>Raw API Snapshot is een apart exportproduct van Health.md voor Android voor migratie- en archiefworkflows: één onveranderlijk, versiebeheerd JSON- of NDJSON-artefact per gekozen periode, waarin native records bewaard blijven.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Download via Google Play</a>
    <a class="docs-button-secondary" href="/nl/docs/android/">Android-app-handleiding</a>
  </div>
</div>

## Wat een ruwe snapshot is

Compatibiliteitsexports zetten Health Connect-records om in leesbare dagelijkse `HealthData`-samenvattingen. Een ruwe snapshot slaat die conversie volledig over:

- **Health Connect-snapshots** bewaren elk veld dat de vastgezette AndroidX-API aanbiedt, waaronder native identiteit en metadata, nanoseconde-tijdstempels, nullable bron-offsets, ruwe enum-waarden, geneste samples, fasen, routes en geplande workoutstructuren.
- **Fitbit-, Oura-, WHOOP- en Withings-snapshots** bewaren de exacte bytes van geslaagde providerreacties en leggen endpoint-paginering en serverzijde-aggregatie open. Niet-ondersteunde providers worden gemeld in plaats van genormaliseerd of stilletjes vervangen door Health Connect-gegevens.
- Elk artefact eindigt met een **manifest** met status, problemen, aantallen en controlesommen per type. Mapexports krijgen bovendien een `.sha256`-bestand ernaast.

Een ruwe snapshot is API-compleet voor de vastgezette provider-API van de app, maar geen transactionele back-up van de providerdatabase. Hij kan ontoegankelijke records, originele eenheden die de API niet blootlegt, verwijderde records of velden die onbekend zijn voor de geïnstalleerde SDK niet herstellen.

## Voorbeeld voordat je een bestemming kiest

Ruwe snapshots kun je bekijken zonder ingestelde bestemming. De voorbeeldweergave voert de volledige provider-native leesactie uit naar privé-opslag zonder back-ups, houdt alleen begrensde begin- en eindtekst in het geheugen en verwijdert het tijdelijke artefact zonder iets te uploaden.

## Bezorgingsregels

Ruwe API-uploads zijn opzettelijk strenger dan compatibiliteits-API-exports:

| Regel | Reden |
|---|---|
| Alleen HTTPS | Het gestreamde artefact reist nooit als leesbare tekst |
| Omleidingen geweigerd | Het artefact en de inloggegevens kunnen nooit naar een andere origin worden doorgespeeld |
| Schema-, export- en controlesomheaders | Het ontvangende endpoint kan verifiëren wat het heeft geaccepteerd |
| Tijdelijk privé-artefact na de poging verwijderd | Er blijft geen kopie op het apparaat achter |

## Incrementele archieven

De apart versiebeheerde `healthmd.raw-changes`-backend gebruikt Health Connect-wijzigingstokens en verwijdermarkers (tombstones) voor toekomstige incrementele archiefworkflows, zodat een volledige snapshot niet de enige archiefstrategie hoeft te zijn.

## Vereisten

- Health.md voor Android met het Raw API Snapshot-product.
- Health Connect-machtigingen voor de gekozen recordtypen, of een gekoppeld Fitbit-, Oura-, WHOOP- of Withings-account voor providersnapshots.
- Een HTTPS-endpoint als je snapshots uploadt; export naar een lokale map stelt geen transportvereisten.

## Waar je meer leert

- [Ruwe-snapshot-v1-contract](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-snapshot-v1.md)
- [Ruwe-record-v1-contract](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-record-v1.md)
- [Ruwe-wijzigingen-v1-contract](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-changes-v1.md)
