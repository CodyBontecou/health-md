---
title: "Dépannage de Health.md"
description: "Diagnostiquez exportations vides, sommeil absent, téléphone indisponible, planification, dossiers, résultats partiels et délais dépassés."
---

Commencez avec un appareil, un jour, une catégorie et une destination. Ne publiez jamais données de santé, itinéraires, documents cliniques, jetons, codes d’association ou chemins privés.

## Données vides

Confirmez la valeur dans Apple Health ou Health Connect, vérifiez l’autorisation et exportez une catégorie sur un jour. Distinguez `complete_empty`, autorisation absente, non pris en charge, ignoré, partiel et échec. Absent ne veut pas dire zéro.

## Sommeil absent d’Aujourd’hui

Le sommeil appartient au jour où la nuit commence. Mardi matin, exportez **Hier** ou lundi et mardi. Voir [Dates du sommeil](/fr/docs/sleep-date-attribution/).

## Fichiers et planification

Vérifiez coffre, accès au dossier, sous-dossier, modèle et profil. L’arrière-plan iOS et WorkManager donnent des heures cibles, pas une garantie universelle. Déverrouillez l’appareil et utilisez la récupération.

## Délai CLI

Un délai dépassé n’annule pas une tâche acceptée :

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

Avant d’annoncer une complétude, examinez état, dates manquantes, couverture, `next_cursor`, version et limites. `--allow-partial` ne change que la politique de sortie.

<div class="related"><a href="/fr/docs/cli-jobs/"><span>Tâches</span>Reprendre et annuler.</a><a href="/fr/docs/release-status/"><span>Versions</span>Compatibilité exacte.</a></div>
