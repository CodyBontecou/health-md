---
title: "Schlafdaten und tägliche Notizen"
description: "Warum Nachtschlaf zum Startdatum gehört und welchen Bereich du morgens exportieren solltest."
---

Health.md ordnet eine Schlafperiode dem Datum zu, an dem sie **begann**. Schlaf von Montag 23:45 bis Dienstag 7:30 gehört zur Montagsübersicht. Apple und Android verwenden diese Regel, auch wenn Health Connect oder eine andere App das Aufwachdatum zeigt.

| Ziel | Export |
|---|---|
| Letzte Nacht am Dienstagmorgen | **Gestern** (Montag) |
| Heutige Aktivität | **Heute** |
| Beides | Montag und Dienstag |

Lesbare Tagesübersichten halten die Nacht zusammen. Kanonische Quelldatensätze behalten ursprüngliche Start- und Endzeit und gehören zum Starttag; Health.md erfindet keine Hälften. Für echte Sitzungssemantik nutze `healthmd_sleep_sessions`.

Daily Note Injection und API Endpoint folgen derselben Zuordnung. Wenn die Quelle spät synchronisiert, exportiere den Starttag erneut. Derzeit gibt es keinen Schalter zur Zuordnung nach Aufwachdatum.

<div class="related"><a href="/de/docs/scheduling/"><span>Automatisierung</span>Gestern morgens einschließen.</a><a href="/de/docs/troubleshooting/"><span>Hilfe</span>Leere oder verspätete Daten prüfen.</a></div>
