---
title: "Dates du sommeil et notes quotidiennes"
description: "Choisir la date d’export du sommeil : fenêtre de midi à midi, coucher après minuit, siestes et résultats vides."
---

Pour la nuit passée, le mardi matin, exportez **lundi**, généralement **Hier**. Le résumé quotidien du sommeil de Health.md utilise une fenêtre locale de **12:00 à 12:00** : du lundi midi au mardi midi, plutôt que la limite de minuit des activités.

<div id="sleep-journal-window"></div>

## Pourquoi le sommeil apparaît dans la note d’hier

La fenêtre garde une nuit habituelle ensemble, même si le coucher est après minuit. Le premier midi est inclus, le suivant exclu. Un sommeil qui traverse midi peut contribuer aux résumés de deux jours voisins. Les horodatages d’origine ne sont pas modifiés pour correspondre à la note.

Apple et Android partagent cette fenêtre pour les résumés compatibles. Les mesures, phases, enregistrements et agrégations peuvent différer. Aucun réglage ne déplace le résumé au jour du réveil.

<div id="sleep-date-examples"></div>

## Quelle date exporter ?

Exemples fictifs en heure locale, sans données personnelles :

| Sommeil ou activité | Date d’export |
| --- | --- |
| Lundi 23:45 à mardi 07:30 | **Lundi** |
| Mardi 01:00 à mardi 07:30 | **Lundi**, pas mardi |
| Sieste du mardi, 14:00 à 14:30 | **Mardi** |
| Pas et activité du mardi | **Mardi** |
| Nuit du lundi et activité du mardi | **Lundi et mardi** |

Vérifiez le fuseau local de l’export. La date de réveil d’une autre app ou la modification du fichier ne détermine pas le jour du journal.

<div id="sleep-empty-checks"></div>

## Si la note attendue est vide

1. Vérifiez le jour du journal et les mesures de sommeil sélectionnées.
2. Laissez la montre ou l’app source synchroniser vers Apple Health ou Health Connect, puis prévisualisez et réexportez ce jour.
3. Vérifiez les autorisations. Sur iPhone, un résultat HealthKit vide ne révèle pas si la lecture a été refusée. Sur Android, la source doit avoir écrit l’enregistrement compatible dans Health Connect.
4. Contrôlez la destination et les résultats écrits, ignorés ou échoués. Une prévisualisation ne prouve pas qu’un fichier a été enregistré. Une absence n’est pas zéro.

Daily Note Injection et les résumés API Endpoint suivent la même fenêtre. Si la source arrive tard, répétez le jour ou vérifiez la période rétrospective du programme. Le travail en arrière-plan ne garantit pas une écriture réussie à une heure précise.

<div id="sleep-records-and-queries"></div>

## Résumés, sources et requêtes de sessions

Les enregistrements bruts ou canoniques gardent leurs horodatages et leurs propres règles d’appartenance. Ne reconstruisez pas une session depuis un total quotidien et n’y ajoutez pas les intervalles comme du sommeil supplémentaire.

`healthmd_sleep_sessions` exige une configuration CLI/MCP **Apple Health** prise en charge. Les requêtes MCP typées Android ne sont pas disponibles actuellement. Consultez les [capacités par plateforme](/fr/docs/guides/platform-features/) et [MCP](/fr/docs/mcp/).

Voir aussi la [planification](/fr/docs/scheduling/), le [dépannage](/fr/docs/troubleshooting/) et les [formats](/fr/docs/format/).
