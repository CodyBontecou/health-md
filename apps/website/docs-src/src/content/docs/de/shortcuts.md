---
title: "Kurzbefehle & App Intents"
description: "Nutze sieben veröffentlichte Aktionen und zwei Mac-Kontext-Aktionen aus dem Entwicklungsstand in Kurzbefehlen und Siri."
---

<div class="availability preview"><strong>Sieben veröffentlichte Aktionen · neun im aktuellen Quellstand</strong><p>Die beiden Mac-Kontext-Aktionen benötigen kompatible iPhone- und Mac-Builds. Prüfe die Hinweise der genauen Version.</p></div>

## Aktionen

- Gestern, ein Datum, einen Bereich oder die letzten N Tage exportieren;
- Gesundheitsübersicht oder letzten Exportstatus abrufen;
- Zeitplan ein- oder ausschalten;
- **Refresh Mac Health Context** (Entwicklung): profilgebundene, dauerhafte Aktualisierung des verschlüsselten Mac-Kontexts;
- **Get Mac Context Refresh Status** (Entwicklung): Status und Job-ID abrufen.

Die vier Exportaktionen akzeptieren optional ein **Profil**. Ein unbekannter Name schlägt sicher fehl. Normale Kurzbefehle schreiben in den iPhone-Ordner und wechseln nicht still zu API Endpoint oder Connected Mac.

„Im Sperrzustand ausführen“ entsperrt HealthKit nicht. Health.md bewahrt eine ausstehende Anfrage und zeigt **Health Export Needs Attention**.

### Morgenautomation

1. Zeitautomation erstellen.
2. **Export Yesterday's Health Data** hinzufügen.
3. **Get Last Export Status** und eine Mitteilung ergänzen.

Gestern enthält die Schlafperiode, die gestern Abend begann. Siehe [Schlafdaten](/de/docs/sleep-date-attribution/).

<div class="related"><a href="/de/docs/export-profiles/"><span>Profile</span>Stabile Automatisierungs-IDs.</a><a href="/de/docs/release-status/"><span>Kompatibilität</span>Versionen prüfen.</a></div>
