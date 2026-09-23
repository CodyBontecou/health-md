---
title: "Dates du sommeil et notes quotidiennes"
description: "Pourquoi le sommeil nocturne appartient au jour de début et quelle plage exporter le matin."
---

Health.md attribue une session à la date où elle a **commencé**. Un sommeil du lundi 23 h 45 au mardi 7 h 30 appartient au résumé du lundi. Apple et Android partagent cette règle, même si Health Connect affiche le jour du réveil.

| Besoin | Export |
|---|---|
| Sommeil de la nuit, mardi matin | **Hier** (lundi) |
| Activité du mardi | **Aujourd’hui** |
| Les deux | Lundi et mardi |

Les résumés gardent la nuit entière. Les enregistrements canoniques conservent début et fin et appartiennent au jour de début ; Health.md n’invente pas deux moitiés. Pour une vraie sémantique de session, utilisez `healthmd_sleep_sessions`.

Daily Note Injection et API Endpoint suivent la même attribution. Si la source synchronise tard, réexportez le jour de début. Aucun réglage ne réattribue actuellement le résumé au jour du réveil.

<div class="related"><a href="/fr/docs/scheduling/"><span>Automatisation</span>Inclure Hier le matin.</a><a href="/fr/docs/troubleshooting/"><span>Aide</span>Données vides ou tardives.</a></div>
