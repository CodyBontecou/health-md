---
title: "Extraction canonique des données de santé"
description: "Utilisez healthmd extract pour acquérir des métriques Apple Health sélectionnées et émettre des documents canoniques au schéma v7, des enregistrements sources, des projections JSON Pointer ou du JSONL avec des reçus explicites."
---

`healthmd extract` est la commande de données sources pour les scripts et les agents. Elle demande à l’iPhone d’acquérir uniquement les métriques et le détail sélectionnés, valide le transfert persistant, retire l’enveloppe de transport et émet des documents canoniques `healthmd.health_data` v7 ou des projections clairement étiquetées.

Utilisez l’extraction lorsque vous avez besoin des données Health.md d’origine. Utilisez les [requêtes typées](/fr/docs/agent-queries/) lorsque vous avez besoin de sessions, comparaisons, alignement d’entraînements, couverture ou paquets de preuves.

## Forme de base

Une extraction nécessite :

1. au moins une métrique, catégorie, objet ou sélecteur `--all-metrics` ;
2. un sélecteur de date ;
3. des choix facultatifs de détail, objet, champ, format, sortie, délai d’expiration et résultat partiel.

```bash
healthmd extract \
  (--metric ID | --category NAME | --object NAME | --all-metrics) ... \
  (--from DATE --to DATE | --last N | --yesterday | --all) \
  [--detail summary|lossless] \
  [--source apple_health] \
  [--field /JSON/POINTER] ... \
  [--format json|jsonl] \
  [--timeout 5...900] \
  [--allow-partial] \
  [--output PATH]
```

La source actuelle de l’extraction canonique est `apple_health`. Les fichiers annexes natifs des fournisseurs restent régis par leurs propres contrats et ne sont pas traduits en valeurs Apple Health synthétiques.

## Commencer par une requête étroite

```bash
# One category, one day, summary detail
healthmd extract --category Sleep --yesterday --output sleep.json

# One metric for the last 30 complete days
healthmd extract --metric resting_heart_rate --last 30 \
  --output resting-heart-rate.json

# Every selected source object for one exact range
healthmd extract --all-metrics \
  --from 2026-07-01 --to 2026-07-07 \
  --detail lossless --output health-week.json
```

Les noms de métriques et de catégories sont validés par rapport au catalogue actuel avant le début du travail sur l’iPhone. Répétez les sélecteurs pour les combiner.

```bash
healthmd extract \
  --metric sleep_total \
  --metric resting_heart_rate \
  --category Workouts \
  --last 14 --output recovery-context.json
```

## La sélection précède les lectures HealthKit

L’extraction ne récupère pas un export toutes-métriques enregistré pour le rogner ensuite. La CLI résout votre sélecteur en un `CanonicalHealthDataSelection` immuable et l’envoie à l’iPhone. Health.md vérifie et lit uniquement les types HealthKit ordinaires qui alimentent les métriques sélectionnées.

Cette distinction compte pour la confidentialité, les performances et l’exhaustivité :

- les métriques non sélectionnées ne sont pas acquises ;
- les préférences de métriques enregistrées sur l’iPhone ne changent pas ;
- les requêtes de résumé ne créent pas d’archive source cachée ;
- les requêtes sans perte récupèrent uniquement les types sources nécessaires à la sélection ;
- la sélection fait partie de l’empreinte persistante de la requête.

Les sélecteurs d’objets et JSON Pointer réduisent les données émises après capture. Les sélecteurs de métrique, catégorie, source et détail réduisent l’acquisition iPhone elle-même.

## Détail récapitulatif et sans perte

Le résumé est la valeur par défaut :

```bash
healthmd extract --category Activity --last 7 --detail summary
```

La sortie récapitulative peut inclure des résumés quotidiens typés, des diagnostics de requête et `raw_capture_status: not_requested`. Cet état est honnête : la commande n’a pas récupéré d’enregistrements sources canoniques.

Demandez le détail sans perte lorsque les objets sources, UUID, horodatages exacts, la provenance ou les diagnostics d’archive comptent :

```bash
healthmd extract --metric workouts --last 14 \
  --detail lossless --output workouts-lossless.json
```

Les objets orientés archive tels que `records` impliquent le détail sans perte même si `--detail` est omis.

## Sélecteurs d’objets

Utilisez `--object` pour conserver une portion connue de chaque journée sélectionnée. Les noms actuels incluent :

| Objet | Contenu typique |
|---|---|
| `sleep` | Champs de résumé quotidien du sommeil |
| `activity` | Pas, énergie, distance, exercice et résumés d’activité associés |
| `heart` | Fréquence cardiaque, fréquence cardiaque au repos, VFC et résumés associés |
| `vitals` | Tension artérielle, glucose, température, oxygène et autres résumés vitaux |
| `body` | Poids, composition, taille et mesures corporelles |
| `nutrition` | Résumés de nutriments et d’hydratation |
| `mindfulness` | Sessions de pleine conscience et résumés de bien-être mental |
| `mobility` | Champs de marche, démarche et mobilité |
| `hearing` | Exposition audio et champs auditifs |
| `reproductive-health` | Champs de santé reproductive, grossesse et cycle |
| `cycling` | Résumés de cyclisme |
| `vitamins` / `minerals` | Résumés propres aux nutriments |
| `symptoms` | Données de symptômes |
| `medications` | Données de médicaments lorsqu’elles sont disponibles et autorisées |
| `workouts` | Objets canoniques de résumé d’entraînement |
| `archive` | Enveloppe canonique d’archive HealthKit |
| `records` | Enregistrements sources canoniques ; implique le détail sans perte |
| `external-records` | Enregistrements externes déjà présents dans la journée publique |
| `query-results` | Résultats de capture par requête |
| `warnings` | Avertissements d’intégrité |

Exemples :

```bash
healthmd extract --metric workouts --last 30 \
  --object workouts --output workout-summaries.json

healthmd extract --metric workouts --last 30 \
  --object records --detail lossless --output workout-records.json

healthmd extract --category Sleep --last 7 \
  --object sleep --object query-results --output sleep-with-status.json
```

## Projection JSON Pointer

Répétez `--field` avec des JSON Pointers RFC 6901 pour émettre des valeurs exactes ou des entrées d’état :

```bash
healthmd extract --category Sleep --last 7 \
  --field /sleep/totalDuration \
  --field /sleep/deepSleep \
  --field /raw_capture_status \
  --output selected-sleep-fields.json
```

Les résultats de pointeur sont des projections, pas des documents quotidiens complets. Ils référencent le schéma source et la journée, mais ne portent pas `schema: healthmd.health_data` d’une façon qui pourrait faire passer un sous-arbre pour un export complet.

Un chemin sélectionné absent est signalé avec l’état complet mais vide ou incomplet de la journée. Health.md ne convertit pas l’absence en zéro.

## Sortie JSON

La sortie JSON par défaut contient l’une de ces collections de données :

- `health_data` pour les documents quotidiens canoniques complets ; ou
- `projections` pour les résultats d’objet ou de pointeur.

Elle contient aussi `healthmd.extract_receipt`, qui enregistre :

- la sélection et la plage de dates résolues ;
- la source et le niveau de détail ;
- les résultats par jour ;
- les nombres d’éléments conservés et de captures ;
- les dates manquantes ;
- les diagnostics partiels ou d’échec ;
- l’état d’achèvement de la sortie.

Le reçu est une métadonnée de protocole. Il ne remplace pas le schéma source.

## Sortie JSONL

Utilisez JSONL pour le traitement en flux :

```bash
healthmd extract --category Sleep --last 30 \
  --format jsonl --output sleep.jsonl
```

Chaque ligne est un élément de données. Le reçu n’est pas mélangé au flux de données de santé :

- avec `--output`, il est écrit dans `OUTPUT.receipt.json` ;
- sans `--output`, il est écrit sur stderr.

Cela rend les pipelines prévisibles :

```bash
healthmd extract --metric workouts --last 30 \
  --object workouts --format jsonl --output workouts.jsonl

jq -c 'select(.workouts != null)' workouts.jsonl
jq '{status, retained_item_count, missing_dates}' workouts.jsonl.receipt.json
```

Ne redirigez pas stderr vers l’analyseur JSONL, car stderr transporte le reçu et la progression sans données de santé.

## Résultats complets, vides et partiels

Health.md garde ces états distincts :

| État | Signification |
|---|---|
| `success` | Chaque branche demandée est terminée, y compris les branches complètes-vides |
| `complete_empty` | La portée demandée a été représentée et ne contenait aucune observation |
| `partial_success` | Certaines données demandées sont conservées, mais au moins une branche demandée est incomplète |
| `failed` | Une branche demandée a échoué |
| `unsupported` | La plateforme ou HealthKit ne prend pas en charge la branche demandée |
| `skipped` | Health.md n’a intentionnellement pas interrogé cette branche |
| `cancelled` | L’iPhone a accusé réception de l’annulation |
| `missing` | Une journée ou branche demandée n’a pas été représentée |

Une extraction partielle n’émet aucune donnée conservée par défaut. Ajoutez `--allow-partial` uniquement lorsque votre consommateur est conçu pour accepter et préserver une portée incomplète :

```bash
healthmd extract --category Sleep --last 30 \
  --allow-partial --output sleep-partial.json
```

Cette option modifie le comportement d’émission et le code de sortie. Il ne retire pas les diagnostics et ne transforme pas des données partielles en données complètes.

## Back-ends de l’app Mac et direct

La commande fonctionne avec l’un ou l’autre back-end :

```bash
# Bundled helper default: Mac app loopback and connected iPhone
healthmd extract --category Sleep --last 7 --output sleep.json

# Direct-capable helper: bypass the Mac app
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json
```

Les deux chemins utilisent le même schéma quotidien public et une validation stricte. Le transport, le jumelage, le stockage et les enregistrements de tâches diffèrent.

## Historique volumineux

`--all` n’a pas de plafond de dates fixe :

```bash
healthmd extract --metric steps --all --output all-steps.json
```

L’iPhone résout le plus ancien enregistrement sélectionné disponible, fige chaque jour de calendrier source jusqu’à aujourd’hui et transfère des partitions de taille limitée. La CLI assemble et valide les données sur le disque au lieu de construire en mémoire une réponse de taille illimitée.

Utilisez JSONL ou une sélection plus étroite lorsqu’un corpus est volumineux. L’espace disque disponible et une journée inhabituellement dense restent des limites pratiques.

## Checklist de confidentialité

- Préférez `--output` pour tout résultat contenant des données de santé.
- Protégez les fichiers de sortie et de reçu avec le même soin que la source Apple Health.
- N’utilisez pas le traçage shell autour des commandes de santé.
- Gardez les charges utiles hors des journaux CI et des transcriptions d’agent.
- N’inspectez que les champs de reçu, de nombre, d’état, de schéma et de données manquantes lors du dépannage.
- Supprimez les exports temporaires après leur validation par le système destinataire.

## Pages associées

<div class="related">
  <a href="/fr/docs/cli/"><span>CLI</span>CLI Health.md : configuration, sélection du back-end, liste des commandes et règles de sortie.</a>
  <a href="/fr/docs/agent-queries/"><span>Vues dérivées</span>Recettes de requêtes typées : séries de métriques, sommeil, entraînement, séances d’entraînement, comparaisons et preuves.</a>
  <a href="/fr/docs/reference/daily-records/"><span>Schéma</span>Enregistrements quotidiens : le contrat complet des documents quotidiens au schéma v7.</a>
  <a href="/fr/docs/reference/canonical-healthkit-records/"><span>Archive source</span>Enregistrements Apple Health canoniques : identité, provenance, relations et charges utiles.</a>
  <a href="/fr/docs/reference/api-and-cli/"><span>Protocole</span>Référence API et CLI : requêtes d’extraction, reçus, validation stricte et comportement de sortie.</a>
</div>
