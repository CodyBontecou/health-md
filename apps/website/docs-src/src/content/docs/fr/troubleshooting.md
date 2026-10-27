---
title: "Données manquantes dans un export Apple Health ? Dépannage"
description: "Résolvez les exports Apple Health ou Health Connect vides, le sommeil absent, les détails CSV, les erreurs de fichier et les retards de planification."
---

Si des données manquent dans un export Apple Health ou Health Connect, distinguez un **problème de lecture** d'un **problème d'enregistrement du fichier**. Une donnée absente n'est pas un zéro mesuré.

## Commencer par une journée vérifiable

1. Confirmez une valeur et sa date dans Apple Health ou Health Connect. Attendez la fin de la synchronisation de la montre ou de l'app source.
2. Dans Health.md, vérifiez le profil actif, la métrique, les dates, le format et la destination. Commencez par une métrique prise en charge sur une journée terminée.
3. Déverrouillez le téléphone, ouvrez Health.md et lancez l'aperçu s'il est disponible. Exportez ensuite et vérifiez le résultat et la destination réels. L'aperçu ne prouve pas qu'un fichier a été enregistré.

Consultez le [premier export iPhone](/fr/docs/iphone-first-export/) ou la [configuration Android](/fr/docs/android/).

## La source contient des données, mais l'export est vide

Sur iPhone, vérifiez les catégories autorisées pour Health.md dans Apple Health. **HealthKit ne révèle pas si l'accès en lecture a été refusé**. Un résultat vide ne distingue donc pas un accès restreint de l'absence de données correspondantes. Une demande d'autorisation réussie ne confirme pas toutes les catégories. Voir la [documentation Apple](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).

Sur Android, vérifiez que l'app source a bien écrit les données dans Health Connect et que Health.md peut lire ce type pris en charge. Les données visibles uniquement dans une autre app ne sont pas forcément exportables. Voir la [liste de vérification Google](https://support.google.com/android/answer/13770384).

Après synchronisation ou modification des autorisations, revérifiez métrique et date. Ne remplacez pas les valeurs absentes par zéro.

Si un résultat structuré indique `complete_empty`, distinguez-le des sorties non prises en charge, partielles, ignorées ou en échec. Il ne prouve pas un zéro mesuré ni une décision sur le droit de lecture.

## Le sommeil de la nuit manque dans Aujourd'hui

Health.md attribue le sommeil au **jour de début** sur Apple et Android. Le mardi matin, exportez **Hier** (lundi), ou lundi et mardi. Si la source se synchronise tard, réexportez le jour de début. Voir les [dates du sommeil](/fr/docs/sleep-date-attribution/).

## L'aperçu contient des données, mais le dossier est vide

Sur iPhone, vérifiez si le profil actif écrit dans un dossier local, Connected Mac ou API Endpoint. Pour les fichiers, contrôlez dossier, sous-dossier, nom et résultat : écrit, ignoré ou en échec. Un fichier ignoré peut correspondre au mode d'écriture choisi. Resélectionnez un dossier indisponible et vérifiez son fournisseur. Voir [dossiers et vaults](/fr/docs/folder-vault/) et [profils](/fr/docs/export-profiles/).

## Le CSV contient des totaux, pas les relevés attendus

Sur iPhone, Summary et Detailed Time-Series ont des niveaux de détail différents. Vérifiez Data Detail et les métriques avant d'élargir les dates. Les métadonnées ne sont pas des mesures de santé. Conservez les unités et distinguez totaux quotidiens et enregistrements source. Lossless Health Records dispose d'un état de capture distinct ; un résumé ne prouve pas une capture complète. Voir la [référence des formats et de la couverture](/fr/docs/reference/export-formats/).

## Un export planifié n'arrive pas

Les tâches iOS et Android WorkManager utilisent des horaires cibles, sans garantie de livraison. Déverrouillez l'appareil, ouvrez Health.md et vérifiez historique et récupération en attente avant une nouvelle exécution. Une notification ne prouve pas l'enregistrement d'un fichier. Voir la [planification iPhone](/fr/docs/scheduling/) ou l'[automatisation Android](/fr/docs/android/).

## Délai CLI

Un délai dépassé n’annule pas une tâche acceptée :

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

Avant d’annoncer une complétude, examinez état, dates manquantes, couverture, `next_cursor`, version et limites. `--allow-partial` ne change que la politique de sortie.

## Demander de l’aide sans partager les données de santé

Indiquez les versions de l’app et du système, la plateforme, le format et le type de problème : données vides, sortie ignorée ou échec d’écriture. Masquez les informations privées des captures et journaux. Ne publiez pas de valeurs de santé, trajets, documents cliniques, jetons, codes de jumelage ou chemins privés.

<div class="related"><a href="/fr/docs/cli-jobs/"><span>Tâches</span>Reprendre et annuler.</a><a href="/fr/docs/release-status/"><span>Versions</span>Compatibilité exacte.</a></div>
