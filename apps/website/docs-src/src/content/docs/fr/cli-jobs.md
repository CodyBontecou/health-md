---
title: "Tâches CLI persistantes et automatisation"
description: "Automatisez healthmd en toute sécurité grâce à une sortie lisible par machine, des attentes bornées, des tâches persistantes pendant sept jours, des états partiels explicites, la reprise et l’annulation confirmée."
---

Health.md traite les opérations d’export connecté et d’acquisition de contexte comme des tâches persistantes. La durée de vie de la tâche est indépendante du processus qui l’a démarrée. Un terminal peut se fermer ou une connexion réseau peut échouer sans supprimer les partitions terminées.

Cette page s’applique à l’export de fichiers, à l’export brut strict, à l’extraction canonique et à l’acquisition de données actualisées dans le contexte chiffré, sauf si une commande documente une règle plus étroite.

## La règle centrale

Un délai d’expiration ou une déconnexion ne signifie pas une annulation.

Ne démarrez pas de doublon après un résultat inconnu. Enregistrez l’ID de tâche renvoyé, inspectez son état et reprenez la même tâche.

Les tâches d’export, de brut et d’extraction utilisent les commandes de cycle de vie de premier niveau :

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

Les tâches d’acquisition de contexte chiffré utilisent le cycle de vie de l’agent local :

```bash
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
```

## Durée de vie de sept jours

Une tâche persistante possède un `expires_at` fixe, sept jours après sa création. La progression ne le prolonge pas. Les deux pairs conservent la requête immuable et un état de transfert validé suffisant pour reprendre l’opération en toute sécurité.

Une tâche peut conserver :

- les dates exactes ou les identifiants résolus pour tout l’historique ;
- la portée de métriques, catégories, sources et détails ;
- le back-end et l’association à l’appareil jumelé ;
- la politique de réglages ;
- le profil brut ou la sélection d’extraction ;
- l’identité de destination des fichiers ;
- l’empreinte de requête ;
- les manifestes de session et de transfert ;
- la chaîne d’empreintes des partitions ;
- la limite des partitions et des octets validés ;
- l’accusé de réception de l’achèvement ou de l’annulation.

La reprise ne peut réinterpréter aucun de ces champs.

## L’état ne se limite pas à en cours ou terminé

Une réponse de tâche peut inclure :

| Champ | Signification |
|---|---|
| `durable` | Indique si l’opération possède un état de tâche récupérable |
| `state` | État actuel du cycle de vie de la tâche persistante |
| `job_id` | Identifiant stable de la tâche |
| `session_id` | Identifiant de session de transfert lié |
| `paused` | Indique si le travail nécessite que le même iPhone se reconnecte |
| `processed_days` / `total_days` | Progression logique par jour propriétaire |
| `committed_partitions` | Partitions dont le récepteur a accusé réception de façon persistante |
| `committed_bytes` | Octets de charge utile validés de façon sûre |
| `fraction_complete` | Fraction de progression sans données de santé |
| `expires_at` | Horodatage fixe d’expiration de la tâche |

Les champs d’état contiennent uniquement des dates, des ID, des nombres, des volumes en octets et des erreurs qui ne révèlent aucune donnée sensible. Ils ne doivent pas contenir d’échantillons de santé.

## Démarrer une tâche avec un plan de sortie explicite

Export brut :

```bash
healthmd export --iphone --last 30 --raw \
  --output health-month.json
```

Extraction canonique :

```bash
healthmd extract --category Sleep --last 30 \
  --output sleep-month.json
```

Fichiers directs générés :

```bash
healthmd --backend direct export --last 30 \
  --destination "$HOME/Documents/HealthVault"
```

Choisissez la sortie finale ou la destination avant le démarrage de la requête. Une tâche brute lie son comportement de sortie. Une tâche fichier directe lie la racine de destination exacte à la requête immuable.

## Reprendre

```bash
healthmd resume JOB_UUID --timeout 300
healthmd resume JOB_UUID --output recovered.json
healthmd resume JOB_UUID --output recovered.json --allow-partial
```

En mode direct, sélectionnez les mêmes back-end, appareil, transport, port et iPhone que ceux utilisés par la requête d’origine :

```bash
healthmd --backend direct --device DEVICE_UUID \
  --transport manual-ip --port 17647 \
  resume JOB_UUID --timeout 300 --output recovered.json
```

Les octets en attente peuvent être abandonnés après une déconnexion. Les partitions validées ne sont ni retransmises ni réinterprétées. Le récepteur accepte une partition déjà validée uniquement lorsque chaque descripteur immuable correspond.

Une tâche fichier n’accepte pas de destination de remplacement lors de la reprise. Si la racine d’origine a changé, Health.md interrompt l’opération sans rien écrire plutôt que d’utiliser un autre dossier.

## Annuler

Utilisez le cycle de vie qui a créé la tâche :

```bash
# Export, raw, or extraction
healthmd cancel JOB_UUID

# Encrypted-context acquisition
healthmd agent job cancel JOB_UUID
```

L’annulation comporte deux étapes :

1. la CLI enregistre et envoie une requête persistante d’annulation ;
2. l’iPhone accuse réception de l’annulation et la rend terminale.

Si l’iPhone est indisponible, la tâche reste `cancellation_pending`. Rouvrez le même iPhone et renouvelez la demande d’annulation. Ne déclarez pas une tâche annulée sur la seule base de l’intention locale.

Un processus qui reçoit Ctrl-C doit quitter sans fabriquer d’annulation terminale. Utilisez la commande d’annulation explicite lorsque l’annulation est voulue.

## Canaux de sortie

Health.md sépare les résultats de commande de la progression :

| Canal | Contenu |
|---|---|
| stdout | Résultat de commande JSON versionné, erreur ou flux JSON/JSONL demandé |
| stderr | Instructions de jumelage en texte brut, progression sans données de santé, reçu JSONL en streaming et texte d’utilisation |
| `--output PATH` | JSON ou JSONL contenant des données de santé, validé atomiquement |
| `OUTPUT.receipt.json` | Reçu d’extraction sans données de santé pour une sortie fichier JSONL |

`--help` est en texte brut. Les échecs d’arguments avant l’exécution utilisent stderr et sortent avec 2. Une fois une commande exécutée, les échecs d’exécution utilisent du JSON lisible par machine.

Ne fusionnez pas stdout et stderr dans un analyseur d’automatisation.

## État de sortie et état des données

Le code de sortie du processus n’est qu’un signal. Analysez la réponse avant de déclarer une réussite.

| Résultat | Comportement de sortie par défaut |
|---|---|
| Réussite complète | Zéro |
| Portée demandée complète mais vide | Zéro |
| Export brut strict ou extraction partielle validés | Non nul |
| Partiel avec `--allow-partial` explicite | Zéro, mais la réponse reste partielle |
| Erreur d’argument | Sortie 2, texte brut sur stderr |
| Échec de validation ou de transport | Non nul avec erreur d’exécution structurée |

`--allow-partial` est une politique d’acceptation, pas une réparation des données. Chaque jour manquant, requête échouée, type non pris en charge et avertissement reste visible.

## Le parcours des pages est distinct de l’achèvement de la tâche

Les réponses de requêtes typées sont paginées. Une tâche d’acquisition de données actualisées peut se terminer alors que la requête a encore une autre page.

Sans `--all-pages`, inspectez `next_cursor`. Lorsqu’une page suivante existe, la CLI de haut niveau signale `partial_success` plutôt que de déclarer un parcours complet.

```bash
healthmd query --category Sleep --last 90 --all-pages
```

`--all-pages` suit des curseurs opaques, vérifie les répétitions et applique un plafond global de pages et d’octets. Si le plafond est atteint, réduisez la portée ou utilisez l’API de bas niveau pour paginer manuellement. Il n’existe pas de plafond total de résultats caché, mais chaque invocation reste bornée.

## Couverture actualisée, en cache et réutilisée

Les commandes de requête de haut niveau acquièrent par défaut des données iPhone actualisées :

```bash
healthmd query --metric resting_heart_rate --last 30
```

Utilisez les données en cache uniquement lorsqu’un contexte obsolète est acceptable :

```bash
healthmd query --metric resting_heart_rate --last 30 --cached
```

Utilisez `--reuse-covered` pour ignorer l’acquisition uniquement après que Health.md a vérifié une couverture récapitulative complète et consciente des métriques pour les jours demandés :

```bash
healthmd query --metric resting_heart_rate --last 30 --reuse-covered
```

Le raccourci de réutilisation ne s’applique pas aux données sans perte ni aux opérations de sessions de sommeil nouvellement projetées. Il ne traite jamais un autre fournisseur ou un ancien blob obsolète comme une preuve que cette requête actualisée est complète.

## Exemple shell

Cet exemple conserve la charge utile de santé dans un fichier protégé et n’affiche que des champs d’état sûrs. Il suppose que GNU `timeout` est installé. Les autres hôtes d’automatisation doivent appliquer leur propre délai d’expiration au processus.

```bash
#!/usr/bin/env bash
set -euo pipefail

output="${HOME}/Private/healthmd/sleep-week.json"
mkdir -p "$(dirname "$output")"
chmod 700 "$(dirname "$output")"

set +e
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output "$output" \
  </dev/null > /tmp/healthmd-command.json
exit_code=$?
set -e

if [ -s /tmp/healthmd-command.json ]; then
  jq '{status, job_id, error, message}' /tmp/healthmd-command.json
fi

if [ "$exit_code" -ne 0 ]; then
  echo "healthmd did not report complete success" >&2
  exit "$exit_code"
fi
```

N’activez pas `set -x` autour d’une commande susceptible de diffuser du JSON de santé ou d’inclure des chemins sensibles.

## Comportement d’agent après un résultat inconnu

Un agent ou planificateur doit suivre cet ordre :

1. Lire l’erreur structurée et l’ID de tâche.
2. Exécuter `status --job` localement.
3. Vérifier si la tâche est en pause, terminale, expirée ou en attente d’accusé de réception.
4. Rouvrir le même iPhone lorsque des données actualisées ou un accusé de réception sont nécessaires.
5. Reprendre la tâche existante avec le même back-end et le même appareil.
6. Démarrer une nouvelle tâche uniquement lorsque le résultat précédent est connu ou que l’expiration est explicitement acceptée.

Relancer aveuglément une mutation peut dupliquer le travail source, même lorsque les validations de fichiers elles-mêmes sont idempotentes.

## Erreurs lisibles par machine courantes

| Code | Signification | Réponse recommandée |
|---|---|---|
| `timed_out` | La commande a cessé d’attendre avant la fin de la tâche | Inspecter la tâche renvoyée et la reprendre |
| `job_not_found` | Aucun enregistrement local persistant n’existe pour cet ID | Confirmer le back-end et le répertoire d’état avant de recommencer |
| `job_expired` | L’échéance fixe de sept jours est dépassée | Enregistrer l’écart et créer une nouvelle requête si approprié |
| `direct_export_paused` | Le travail direct nécessite à nouveau l’iPhone jumelé | Rouvrir l’iPhone et reprendre |
| `direct_cancellation_pending` | L’intention locale d’annulation n’a pas d’accusé de réception iPhone | Rouvrir l’iPhone et réessayer cancel |
| `invalid_direct_raw_response` | La validation brute stricte a échoué | Ne pas consommer la sortie |
| `invalid_direct_file_receipt` | Le manifeste de fichiers ou le reçu de validation a échoué | Ne pas réparer ni ajouter aux fichiers manuellement |
| `partial_canonical_extraction` | L’extraction demandée est incomplète | Inspecter le reçu ; accepter le partiel uniquement lorsqu’il est accepté |
| `unvalidated_response_too_large` | Un résultat ne peut pas être exposé dans les limites de validation actuelles | Réduire la portée ou utiliser un mode de sortie approprié |
| `stale_cursor` | Le contexte chiffré a changé après l’émission du curseur de page | Redémarrer cette requête sur le corpus actuel |

## Progression sans journalisation de charge utile

Utilisez `--progress-json` pour les phases de requête de haut niveau et le parcours des pages :

```bash
healthmd query --category Sleep --last 30 \
  --all-pages --progress-json --output result.json \
  2> progress.jsonl
```

Le JSONL de progression peut inclure la phase, le nombre de pages, le nombre d’éléments, les dates et des diagnostics dépourvus de données de santé. Il ne doit pas inclure de valeurs de santé. Gardez-le séparé du résultat final et appliquez tout de même une politique de conservation appropriée.

## Pages associées

<div class="related">
  <a href="/fr/docs/cli/"><span>Configuration</span>CLI Health.md : installer, choisir un back-end et comprendre la sortie des commandes.</a>
  <a href="/fr/docs/cli-direct/"><span>Direct</span>CLI iPhone directe : jumelage, temps d’arrière-plan limité, destination explicite et reprise de confiance.</a>
  <a href="/fr/docs/agent-queries/"><span>Pagination</span>Recettes de requêtes typées : modes actualisé et en cache, parcours des pages, couverture et reçus.</a>
  <a href="/fr/docs/reference/generated/cli/exit-codes/"><span>Contrat généré</span>Codes de sortie CLI : états et comportements d’erreur générés en production.</a>
</div>
