---
title: "Dates du sommeil et notes quotidiennes"
description: "Choisir la date d’export du sommeil : fenêtre de midi à midi, coucher après minuit, siestes et résultats vides."
---

**Début de la nuit** est le réglage par défaut sur iPhone et Android. Pour la nuit passée, le mardi matin, exportez **lundi**, généralement **Hier**. Le résumé quotidien du sommeil de Health.md utilise une fenêtre locale de **12:00 à 12:00** : du lundi midi au mardi midi, plutôt que la limite de minuit des activités.

Choisissez **Fin au matin** dans les réglages d'export pour attribuer chaque session de sommeil entière à la date de sa fin, dans le fuseau horaire de l'export et sans la couper à midi. Pour la nuit du lundi qui se termine mardi, exportez **mardi (Aujourd'hui)** ; les siestes du mardi appartiennent aussi au mardi. Le changement s'applique aux nouvelles opérations ; les opérations enregistrées conservent leur attribution acceptée.

<div id="sleep-journal-window"></div>

## Pourquoi le sommeil apparaît dans la note d’hier

La fenêtre garde une nuit habituelle ensemble, même si le coucher est après minuit. Le premier midi est inclus, le suivant exclu. Un sommeil qui traverse midi peut contribuer aux résumés de deux jours voisins. Les horodatages d’origine ne sont pas modifiés pour correspondre à la note.

Les deux modes d'attribution du sommeil sont disponibles sur Apple et Android. Les mesures, phases, enregistrements sources et agrégations peuvent toujours différer selon la plateforme.

<div id="sleep-date-examples"></div>

## Quelle date exporter ?

**Début de la nuit:** Exemples fictifs en heure locale, sans données personnelles :

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

Les résumés Daily Note Injection et API Endpoint utilisent l'attribution du sommeil choisie pour l'opération. Si les données arrivent tard, réexportez la date correspondante dans ce mode ou vérifiez la période de reprise de la programmation. L'heure d'exécution en arrière-plan est un objectif, sans garantie d'écriture réussie.

<div id="sleep-records-and-queries"></div>

## Résumés, sources et requêtes de sessions

Les enregistrements bruts ou canoniques gardent leurs horodatages et leurs propres règles d’appartenance. Ne reconstruisez pas une session depuis un total quotidien et n’y ajoutez pas les intervalles comme du sommeil supplémentaire.

**Début de la nuit:** Sur Apple, l’archive brute attribue les enregistrements selon leur heure de début d’origine dans la journée locale, de minuit à minuit. Le résumé du sommeil découpe au contraire les intervalles selon la fenêtre du journal, de midi à midi. Une requête brute Sleep Analysis réussie peut donc contenir des enregistrements du matin alors que le résumé du sommeil de cette date est vide. Exportez la date précédente du journal et vérifiez `time_context.calendar_timezone` avant de rechercher la cause d’un résumé manquant. Par exemple, les enregistrements du 22 septembre de 04:03 à 11:52 UTC appartiennent entièrement au résumé du 21 septembre en UTC ; dans Europe/Lisbon, les 52 dernières minutes sont après midi local et contribuent plutôt au 22 septembre.

Les phases de sommeil ne nécessitent pas d’enregistrement explicite `inBed` : en son absence, les résumés Apple utilisent l’union des intervalles disponibles des phases de sommeil. L’absence de données de temps au lit ne crée pas de durée au lit. Une requête de résumé échouée doit apparaître dans `diagnostics.partial_failures` ; une requête réussie sans intervalle admissible constitue une absence de données valide. La fréquence cardiaque au repos utilise une requête distincte par jour civil et nécessite une véritable mesure de fréquence cardiaque au repos ; les phases de sommeil ou la seule autorisation de lecture ne la fournissent pas.

`healthmd_sleep_sessions` exige une configuration CLI/MCP **Apple Health** prise en charge. Les requêtes MCP typées Android ne sont pas disponibles actuellement. Consultez les [capacités par plateforme](/fr/docs/guides/platform-features/) et [MCP](/fr/docs/mcp/).

Voir aussi la [planification](/fr/docs/scheduling/), le [dépannage](/fr/docs/troubleshooting/) et les [formats](/fr/docs/format/).
