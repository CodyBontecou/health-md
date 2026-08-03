---
title: "Recettes de requêtes typées"
description: "Exécutez des requêtes Health.md actualisées ou en cache sur les métriques, le sommeil, les entraînements, la couverture, la comparaison de périodes et les preuves, avec pagination et données manquantes explicites."
---

Les commandes CLI de haut niveau transforment les questions courantes sur les données de santé en opérations de requête fixes et typées. Par défaut, elles acquièrent les données demandées sur l’iPhone, interrogent le contexte Mac chiffré et renvoient du JSON versionné avec preuves et couverture.

Utilisez plutôt l’[extraction canonique](/fr/docs/cli-extract/) lorsque vous avez besoin de journées `healthmd.health_data` complètes ou d’enregistrements sources.

## Vérifier la préparation et découvrir les métriques

```bash
healthmd doctor
healthmd metrics list
healthmd metrics list --category Sleep
```

Le catalogue de métriques renvoie les ID canoniques, noms d’affichage, catégories, unités et exigences de disponibilité. Il n’affirme pas que l’autorisation HealthKit a été accordée pour une métrique.

Copiez les ID depuis le catalogue plutôt que de les deviner.

## Interroger des séries de métriques

```bash
healthmd query \
  --metric sleep_total \
  --metric sleep_deep \
  --from 2026-07-01 --to 2026-07-14 \
  --all-pages
```

Les catégories se développent via le catalogue actuel :

```bash
healthmd query --category Sleep --yesterday
healthmd query --category Heart --last 30 --all-pages
```

Plusieurs options de métrique et de catégorie peuvent être combinées. L’acquisition de données actualisées transporte la sélection développée vers l’iPhone sans modifier les réglages d’export enregistrés.

La réponse utilise une enveloppe `healthmd.cli_metric_query` v1. Elle conserve les diagnostics d’acquisition avec la réponse de requête typée imbriquée.

## Données actualisées, en cache et réutilisation de la couverture

Par défaut, les données sont actualisées :

```bash
healthmd query --metric resting_heart_rate --last 30
```

Cette commande demande la portée exacte à l’iPhone connecté, valide les journées de référence chiffrées et actualisées, puis les interroge.

Le mode cache ne contacte pas l’iPhone :

```bash
healthmd query --metric resting_heart_rate --last 30 --cached
```

Utilisez le mode cache pour l’analyse hors ligne uniquement lorsque l’heure de capture stockée et la couverture sont acceptables.

`--reuse-covered` vérifie d’abord la couverture récapitulative chiffrée :

```bash
healthmd query --metric resting_heart_rate --last 30 --reuse-covered
```

Health.md ignore l’acquisition uniquement lorsque chaque métrique et journée demandée possède une couverture récapitulative compatible et complète. Les requêtes sans perte et les opérations de sessions de sommeil nouvellement projetées n’utilisent pas ce raccourci.

## Comprendre les champs d’achèvement

Les réponses fondées sur des données actualisées distinguent trois concepts :

| Champ | Question traitée |
|---|---|
| `requested_scope_status` | L’acquisition de chaque métrique, source, fournisseur et journée de référence demandés s’est-elle terminée pour cette acquisition ? |
| `corpus_status` | D’autres branches du corpus capturé ont-elles signalé des avertissements, omissions ou échecs ? |
| `unrelated_skips` | Quelles branches ignorées ou non prises en charge étaient hors de la portée demandée ? |

Une portée demandée complète peut coexister avec des omissions sans rapport dans le corpus. Health.md conserve les deux faits au lieu de dégrader faussement le résultat demandé ou de masquer les diagnostics du corpus.

Pour une acquisition actualisée, le contrôle d’exhaustivité tient uniquement compte des blobs remplacés après le début de cette actualisation. Des valeurs en cache obsolètes ne peuvent pas satisfaire une requête échouée.

## Parcourir les résultats par pages

Sans `--all-pages`, la commande renvoie une page bornée. Inspectez `next_cursor` :

```bash
healthmd query --category Activity --last 365 --output activity-page-1.json
jq '.query.next_cursor' activity-page-1.json
```

Un curseur non nul signifie qu’il existe d’autres résultats. L’état externe de haut niveau reste `partial_success` jusqu’à la fin du parcours.

Le parcours automatique suit des curseurs opaques avec contrôles de répétition :

```bash
healthmd query --category Activity --last 365 \
  --all-pages --output activity-all-pages.json
```

La réponse conserve la première `healthmd.query_response` sous `query`, les réponses versionnées ultérieures sous `pages` et un `healthmd.cli_query_receipt` v1 contenant le nombre de pages, d’éléments, de faits et de preuves, ainsi que l’état terminal du parcours.

Le parcours automatique possède un plafond global de pages et d’octets. S’il est atteint, réduisez la sélection de dates ou de métriques, ou utilisez l’[API de bas niveau](/fr/docs/agent-api/) pour paginer manuellement.

## Progression et sortie table

Écrivez la progression des phases et des pages sans données de santé en JSONL sur stderr :

```bash
healthmd query --category Sleep --last 90 \
  --all-pages --progress-json --output sleep.json \
  2> sleep-progress.jsonl
```

JSON est la sortie complète. Le mode tableau est une vue TSV volontairement avec perte, à activer explicitement pour une lecture humaine dans le terminal :

```bash
healthmd query --metric resting_heart_rate --last 30 --format table
```

Le pied du tableau conserve les informations sur la couverture, la source, les limites, l’achèvement et les omissions sans rapport. N’utilisez pas la sortie en tableau lorsqu’un script a besoin de valeurs typées exactes ou de preuves.

## Sessions de sommeil

Les phases de sommeil Apple Health traversent minuit et peuvent se chevaucher selon la source. La commande sommeil construit des sessions stables au lieu de traiter chaque journée de référence comme un total numérique.

```bash
healthmd sleep sessions --last-nights 14
healthmd sleep sessions --last-nights 14 --include-naps
healthmd sleep sessions --last-nights 14 \
  --window first:4h --physiology-metric heart_rate
```

Les dates exactes et la sélection de tout l’historique sont également disponibles :

```bash
healthmd sleep sessions \
  --from 2026-07-01 --to 2026-07-14 \
  --window first:3h --all-pages

healthmd sleep sessions --all --all-pages
```

Chaque session peut rapporter :

- une identité de session stable ;
- la date propriétaire et le fuseau horaire local ;
- les horodatages exacts de début et de fin en local et UTC ;
- la classification nuit ou sieste ;
- les totaux de phases sélectionnés ;
- la durée observée et non suivie ;
- le degré d’exhaustivité et les exclusions ;
- une fenêtre fixe relative à la session ;
- la couverture physiologique des jours adjacents ;
- les preuves sources.

L’acquisition de session demande des intervalles canoniques sans perte de phases de sommeil et l’ensemble complet des métriques canoniques de phases. Health.md lit au plus une journée de référence technique adjacente pour les frontières, puis exclut les dates sans rapport du résultat.

Les sources de phases qui se chevauchent sont dédupliquées pour la durée totale endormie. Le contexte agrégé seul en cache est étiqueté `aggregated` ; il ne prétend pas couvrir l’observation d’intervalles. Une fenêtre fixe `first:4h` ne répartit jamais un agrégat quotidien sur quatre heures.

## Alignement entraînement et sommeil

```bash
healthmd training align --last 14
healthmd training align --last 14 --workout running
healthmd training align --last 14 --workout running \
  --sleep-window first:4h \
  --physiology-metric heart_rate \
  --all-pages
```

Pour chaque entraînement sélectionné, Health.md trouve les sessions de sommeil précédentes et suivantes éligibles les plus proches dans une fenêtre de 36 heures. Il rapporte :

- les ID stables de l’entraînement et de la session ;
- les écarts temporels exacts ;
- les fenêtres de sommeil demandées ;
- les nombres d’échantillons physiologiques ;
- la couverture des phases et sessions ;
- les preuves et exclusions.

L’opération est un alignement temporel déterministe. Elle n’affirme pas qu’un entraînement a causé un résultat de sommeil ni que le sommeil a causé une performance d’entraînement. Elle ne lit pas plus de deux journées de référence techniques adjacentes et ne renvoie pas de données sans rapport.

## Liste des entraînements

```bash
healthmd workouts --yesterday
healthmd workouts --last 14 --all-pages
healthmd workouts \
  --from 2026-07-01 --to 2026-07-31 \
  --format table
```

La liste des entraînements préserve l’identité stable, les horodatages exacts, les détails typés, les preuves et les données manquantes. Les résultats sont ordonnés par horodatage de début et identité stable de l’entraînement. Il n’existe pas de plafond total fixe d’entraînements ; les contrôles de page bornent chaque réponse.

## Couverture

Utilisez la couverture lorsque la question est « Qu’est-ce que j’ai ? » plutôt que « Quelle est la valeur ? ».

```bash
healthmd coverage --category Sleep --last 30
healthmd coverage \
  --metric steps --metric resting_heart_rate \
  --from 2026-01-01 --to 2026-06-30 \
  --all-pages
```

La couverture renvoie les plages demandées et disponibles, les jours considérés, les jours avec valeurs et les intervalles manquants portant un état. Les intervalles adjacents avec le même état et la même raison peuvent être compressés sans perdre leur signification.

Un jour sans observations correspondantes peut être `complete_empty`. Un jour qui n’a jamais été synchronisé possède un autre état. Aucun des deux ne devient zéro.

## Comparer des périodes exactes

La CLI ne devine jamais si une métrique doit être additionnée, moyennée, minimisée, maximisée, comptée ou sélectionnée par dernière valeur. Placez l’agrégation à côté de chaque ID de métrique :

```bash
healthmd compare \
  --metric steps:sum \
  --metric resting_heart_rate:average \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

Les agrégations prises en charge sont :

- `sum`
- `average`
- `minimum`
- `maximum`
- `latest`
- `count`
- `duration_sum`

Les incompatibilités d’unité ou de type échouent au lieu d’être combinées silencieusement. Une période manquante n’a pas de valeur agrégée. Une base de première période à zéro possède une variation absolue mais pas de variation en pourcentage et inclut `zero_baseline` comme limite.

La direction est factuelle : `increased`, `decreased`, `unchanged` ou `not_comparable`. Elle ne signifie jamais meilleur ou pire.

## Paquets de preuves d’entraînement

```bash
healthmd evidence training \
  --category Sleep \
  --metric resting_heart_rate \
  --last 14 \
  --all-pages
```

Ne demandez des détails précis sur les entraînements que lorsqu’ils sont nécessaires :

```bash
healthmd evidence training \
  --category Sleep \
  --workout-detail distance \
  --workout-detail duration \
  --last 14 --all-pages
```

La sélection des détails d’entraînement demande la portée sans perte requise pour cette requête. Le paquet contient des valeurs factuelles, la couverture, les descripteurs de sources, les localisateurs de preuves et les limites.

Les ID de paquets sont des empreintes SHA-256 déterministes du contenu sémantique. Régénérer le même paquet à un autre moment conserve l’ID sémantique, même si les métadonnées de génération peuvent changer.

Les types de paquets de preuves dans le contrat v1 incluent `daily_wellness`, `training` et `doctor_visit`. La commande pratique de haut niveau expose actuellement le paquet training. Utilisez l’API de bas niveau pour des corps de requête exacts.

## Propriété des dates et fuseau horaire

Les dates de requête sont des valeurs `owner_date` de contexte compact. Chaque journée préserve aussi l’intervalle UTC semi-ouvert exact et le fuseau horaire calendaire IANA capturé utilisé pour la former.

Les sessions de sommeil conservent les horodatages locaux et les dates traversant minuit. Les lectures techniques adjacentes existent afin qu’une session puisse franchir une limite de journée de référence sans déplacer les données selon le fuseau horaire actuel du Mac.

Lorsque vous posez à un agent une question sensible aux dates, incluez les dates propriétaires voulues et inspectez le fuseau horaire renvoyé au lieu de supposer celui de l’ordinateur.

## Ne masquez pas les données manquantes dans une réponse d’agent

Un résumé fiable doit conserver :

- l’ID de métrique et l’unité canonique ;
- la plage de dates et le fuseau horaire ;
- le mode actualisé, en cache ou avec réutilisation de la couverture ;
- l’état de la portée demandée et du corpus ;
- l’achèvement du parcours des pages ;
- les références de preuves ou l’empreinte de la source ;
- les intervalles complets-vides et manquants ;
- les avertissements, limites et omissions sans rapport.

Ne moyennez pas pour faire disparaître les jours échoués, ne traitez pas l’absence comme zéro et ne décrivez pas l’alignement temporel comme une cause.

## Pages associées

<div class="related">
  <a href="/fr/docs/agents/"><span>Architecture</span>Agents locaux et contexte de santé : configuration, chiffrement, portée de requête, preuves et conservation.</a>
  <a href="/fr/docs/mcp/"><span>MCP</span>Utilitaire MCP local : équivalents typés pour requête, sommeil, alignement, entraînements, couverture, comparaison et preuves.</a>
  <a href="/fr/docs/agent-api/"><span>Contrats bruts</span>API de requête en boucle locale : requêtes exactes, réponses d’une page, actualisation et routes de tâches.</a>
  <a href="/fr/docs/reference/evidence-packets/"><span>Référence</span>Requêtes compactes et paquets de preuves : valeurs typées, curseurs, opérations, couverture et ID.</a>
</div>
