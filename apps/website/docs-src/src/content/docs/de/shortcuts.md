---
title: "Kurzbefehle & App Intents"
description: "Nutze sieben Health.md-Aktionen in Kurzbefehlen und Siri. Mac-Kontext-Aktualisierungen sind vorgeschlagen, nicht verfügbar."
---

<div class="availability preview"><strong>Sieben Aktionen im Quellcode registriert</strong><p>Refresh Mac Health Context und Get Mac Context Refresh Status sind vorgeschlagen, nicht implementiert oder im Entwicklungsstand verfügbar. Verfolge <a href="https://github.com/CodyBontecou/health-md/issues/173">Issue #173</a>; Verfügbarkeit erfordert Implementierung, Qualifizierung und die Hinweise einer genauen Apple-Version.</p></div>

## Aktionen

- Gestern, ein Datum, einen Bereich oder die letzten N Tage exportieren;
- Gesundheitsübersicht oder letzten Exportstatus abrufen;
- Zeitplan ein- oder ausschalten.

### Vorgeschlagene Mac-Kontext-Aktionen (nicht verfügbar)

Die angeforderte Aktion **Refresh Mac Health Context** würde einen expliziten Profil-/Datumsumfang, authentifizierte kompatible Geräte und dauerhafte Kontexterfassung ohne Exportdateien oder Dateiexport-Kontingent nutzen. **Get Mac Context Refresh Status** würde ausstehenden/abgeschlossenen/fehlgeschlagenen Status mit einer wiederherstellbaren Job-Identität melden. Das sind Anforderungen, keine unterstützten Aktionsnamen, Parameter oder Ergebnisse der aktuellen App.

MCP-Aktualisierung vom Computer erfüllt keine persönliche iOS-Automation. Verwende gewöhnliche Export-Kurzbefehle nicht als Ersatz: Sie behalten die iPhone-Ordner-Semantik. Keine Automation darf versprechen, einen schlafenden Mac aufzuwecken oder geschützte HealthKit-Daten zu umgehen. Vor der Qualifizierung dieser Funktion ist weiterhin eine Prüfung der Automation nach dem Aufwachen auf einem echten iPhone erforderlich.

Die vier Exportaktionen akzeptieren optional ein **Profil**. Ein unbekannter Name schlägt sicher fehl. Normale Kurzbefehle schreiben in den iPhone-Ordner und wechseln nicht still zu API Endpoint oder Connected Mac.

„Im Sperrzustand ausführen“ entsperrt HealthKit nicht. Health.md bewahrt eine ausstehende Anfrage und zeigt **Health Export Needs Attention**.

### Morgenautomation

1. Zeitautomation erstellen.
2. **Export Yesterday's Health Data** hinzufügen.
3. **Get Last Export Status** und eine Mitteilung ergänzen.

Gestern enthält die Schlafperiode, die gestern Abend begann. Siehe [Schlafdaten](/de/docs/sleep-date-attribution/).

<div class="related"><a href="/de/docs/export-profiles/"><span>Profile</span>Stabile Automatisierungs-IDs.</a><a href="/de/docs/release-status/"><span>Kompatibilität</span>Versionen prüfen.</a></div>
