---
title: "API de requête en boucle locale"
description: "Appelez les routes locales versionnées de requête, de preuve, d’actualisation, de préparation, de métriques et de tâches persistantes de Health.md via HTTP ou la commande de bas niveau healthmd agent."
---

Health.md for Mac expose une API locale versionnée sous `/v1/agent/`. Elle traite les requêtes de contexte chiffré, les paquets de preuves, l’acquisition iPhone limitée à une requête, l’état de préparation et les tâches persistantes d’acquisition.

L’API écoute sur l’interface de bouclage, port `17645`. Elle accepte uniquement les pairs IPv4 ou IPv6 de bouclage validés.

<div class="callout">
<strong>N’exposez pas ce port.</strong>
<p style="margin-top:6px;">Il n’existe ni bearer token, ni inscription d’appelant, ni profil d’accès, ni base de données d’autorisations. L’accès par l’interface de bouclage constitue tout le périmètre d’autorisation. Tout processus local peut émettre des requêtes pendant que Health.md est ouverte.</p>
</div>

## Routes

| Méthode | Route | Objectif |
|---|---|---|
| `GET` | `/v1/agent/capabilities` | Lister les schémas versionnés, la prise en charge des portées et les bornes de page |
| `GET` | `/v1/agent/metrics` | Renvoyer les ID de métriques interrogeables canoniques, catégories, unités et prérequis |
| `GET` | `/v1/agent/readiness` | Renvoyer l’état de préparation du contexte chiffré et des données iPhone actualisées avec les prochaines actions |
| `POST` | `/v1/agent/query` | Exécuter une page bornée de requête typée |
| `POST` | `/v1/agent/evidence` | Dériver une page bornée de paquet de preuves factuel |
| `POST` | `/v1/agent/refresh` | Acquérir une portée explicite depuis l’iPhone dans le contexte Mac chiffré |
| `GET` | `/v1/agent/jobs/{id}` | Inspecter une tâche locale persistante d’acquisition |
| `POST` | `/v1/agent/jobs/{id}/resume` | Reprendre la requête immuable d’acquisition |
| `POST` | `/v1/agent/jobs/{id}/cancel` | Demander une annulation explicite |

Les anciennes routes `/v1/agent/profiles` et `/v1/agent/activity/query` renvoient `410 removed_endpoint`.

Le back-end iPhone direct n’héberge pas ces routes HTTP. La commande autonome `healthmd` l’utilise pour l’extraction et l’export canoniques, tandis que `healthmd mcp serve` implémente directement les outils de requête typée actualisée, de preuve, de catalogue de métriques, de préparation, de visualisation et d’export persistant via le protocole de requête iPhone v3. Le jumelage et MCP utilisent la même identité d’exécutable ; l’actualisation et le contexte Mac chiffré restent propres à cette API HTTP.

## Préférer l’adaptateur CLI

La CLI de bas niveau conserve les corps de requête exacts et gère les erreurs de transport en boucle locale :

```bash
healthmd agent capabilities
healthmd agent query --input query-body.json
healthmd agent query --input - < query-body.json
healthmd agent evidence --input evidence-body.json
healthmd agent refresh --input refresh-body.json
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
healthmd agent job cancel JOB_UUID
```

Utilisez `--json JSON` au lieu de `--input` pour un petit corps. La CLI n’élargit ni ne réduit silencieusement le JSON fourni à ces commandes.

Utilisez des commandes de haut niveau telles que `healthmd query`, `healthmd sleep sessions` ou `healthmd compare` pour les flux de travail ordinaires. Elles valident les sélecteurs et construisent l’opération typée pour vous.

## Corps de requête

`POST /v1/agent/query` accepte uniquement `request` et `detail_level` facultatif au premier niveau :

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "metric_series"
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144
    }
  },
  "detail_level": "summary"
}
```

Les champs d’enveloppe inconnus sont rejetés. Le contrat de requête définit les métriques, sources, dates, opérations et contrôles de page. `detail_level` vaut `summary` ou `lossless`.

La réponse est `healthmd.query_response` v1. Elle contient des éléments typés, la couverture, les preuves, les descripteurs de sources, les limites et un `next_cursor` facultatif.

Inspectez une réponse synthétique complète dans [`agent-query-response.json`](/docs/reference/generated/automation/agent-query-response.json).

## Continuer un curseur

Pour demander la page suivante, envoyez la même requête sémantique et placez le curseur renvoyé dans `page.cursor` :

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "metric_series"
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144,
      "cursor": "OPAQUE_CURSOR_FROM_PRIOR_RESPONSE"
    }
  },
  "detail_level": "summary"
}
```

Suivez `next_cursor` jusqu’à son absence. Les curseurs sont authentifiés et liés à la requête ainsi qu’à la révision du corpus chiffré. Health.md rejette les curseurs modifiés, incompatibles et obsolètes.

Les bornes de page protègent chaque requête sans imposer de plafond total d’historique ou de résultats.

## Corps de preuve

`POST /v1/agent/evidence` utilise la même enveloppe. L’opération est `derive_packet` avec un type de paquet et des détails explicitement sélectionnés.

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps", "resting_heart_rate"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "derive_packet",
      "kind": "doctor_visit",
      "detail_ids": []
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144
    }
  },
  "detail_level": "summary"
}
```

La réponse reste une réponse de requête paginée et contient un fragment `healthmd.evidence_packet` v1. Les faits incluent valeurs typées et preuves. Le paquet inclut la limite observations-factuelles-seulement.

Consultez [`agent-evidence-response.json`](/docs/reference/generated/automation/agent-evidence-response.json) pour une réponse synthétique complète.

## Corps d’actualisation

L’actualisation acquiert uniquement une portée explicite. Le corps accepte dates, métriques, sources, niveau de détail et délai d’attente fini :

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-01",
      "end_date": "2026-07-07"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["sleep_total"]
  },
  "sources": {
    "type": "explicit",
    "source_ids": ["apple_health"],
    "provider_ids": []
  },
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

Le Mac valide la portée par rapport aux catalogues actuels et la transforme en une sélection canonique immuable. L’iPhone lit uniquement les types HealthKit ordinaires sélectionnés. Les réglages limités à la requête ne modifient pas les préférences d’export iPhone enregistrées.

L’actualisation utilise un mode de transfert `encrypted_context` dédié :

- il n’écrit aucun fichier d’export ;
- il ne consomme pas le quota d’export de fichiers ;
- il transfère des partitions bornées et reprenables ;
- le Mac valide chaque jour propriétaire compact déterministe avant l’accusé de réception ;
- la requête exacte est conservée avec la tâche persistante.

Une portée fournisseur seul ne nécessite pas de lecture Apple Health. L’historique natif du fournisseur reste une preuve native du fournisseur et n’est pas converti en métriques Apple Health synthétiques.

## Sélection de tout ce qui est disponible

Les sélecteurs de métriques et de dates peuvent utiliser `all_available` :

```json
{
  "dates": {"type": "all_available"},
  "metrics": {"type": "all_available"},
  "sources": {"type": "all_available"},
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

L’iPhone résout le plus ancien enregistrement Apple Health sélectionné disponible et chaque jour de calendrier source jusqu’à aujourd’hui. L’acquisition fournisseur suit des curseurs d’historique natifs du fournisseur. Les identifiants résolus sont figés avant le transfert, afin que la reprise ne puisse pas déplacer la requête.

Il n’existe pas de plafond de dates ou de résultats fixe. Les partitions, les pages, le déchiffrement d’une journée à la fois, l’espace disque et les attentes finies fournissent les bornes de ressources.

## Tâches persistantes d’acquisition

Une attente d’actualisation peut expirer pendant que la tâche continue. La réponse inclut un ID de tâche et une progression dépourvue de données de santé.

```bash
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
healthmd agent job cancel JOB_UUID
```

La tâche expire sept jours après sa création. La reprise réutilise la même requête, le même Mac, le même iPhone, la même portée de sources et le même périmètre validé.

L’annulation ne devient définitive qu’après accusé de réception par l’iPhone. Un iPhone indisponible peut laisser la tâche en état cancellation-pending.

## Appels HTTP directs

La CLI est préférable, mais un logiciel local peut appeler HTTP directement :

```bash
curl --fail-with-body --max-time 5 \
  http://127.0.0.1:17645/v1/agent/readiness

curl --fail-with-body --max-time 30 \
  -H 'Content-Type: application/json' \
  --data @query-body.json \
  http://127.0.0.1:17645/v1/agent/query
```

L’écouteur applique des limites sur les en-têtes et les corps JSON, une méthode et un type de contenu explicites, des délais de réception et un comportement de requête fini.

Gardez les clients HTTP directs sur le même Mac. N’ajoutez pas de liaison LAN, proxy, tunnel ni wrapper MCP HTTP distant.

## Valeurs typées et données manquantes

Les résultats de requête préservent le type et l’unité. Les valeurs peuvent être des quantités, durées, nombres, chaînes, catégories, booléens, horodatages, dates calendaires, tableaux imbriqués ou valeurs typées futures inconnues.

Les états manquants incluent complete-empty, partial, failed, unsupported, skipped, cancelled, not requested, legacy unavailable, redacted et not synchronized. Les consommateurs ne doivent pas les convertir en zéro.

La couverture inclut les plages demandées et disponibles, les jours considérés, les jours avec valeurs et les intervalles manquants portant un état et compressés.

## Gestion des erreurs

Les erreurs utilisent `healthmd.query_error` v1 avec un code stable, un message, la possibilité de réessayer et des détails typés. Les erreurs distinctes couvrent :

- les contrôles de page invalides ;
- les curseurs mal formés ou falsifiés ;
- l’incompatibilité entre curseur et requête ;
- la révision de corpus obsolète ;
- une plage de dates invalide ;
- la validation de métrique ou de source ;
- une incompatibilité d’unité ou d’agrégation ;
- une opération non prise en charge ;
- une violation de portée de preuve ;
- l’état de préparation de l’iPhone ou du stockage chiffré ;
- l’état d’une tâche persistante.

Ne relancez pas aveuglément une actualisation après un résultat inconnu. Inspectez d’abord l’état de sa tâche.

## Pages associées

<div class="related">
  <a href="/fr/docs/agents/"><span>Vue d’ensemble</span>Agents locaux et contexte de santé : configuration, stockage chiffré, portée et règles de reporting.</a>
  <a href="/fr/docs/agent-queries/"><span>Haut niveau</span>Recettes de requêtes typées : commandes validées pour les questions courantes sur les métriques, le sommeil, les entraînements et les preuves.</a>
  <a href="/fr/docs/mcp/"><span>Outils</span>Serveur MCP local : configuration stdio, outils typés, pagination et limites du bac à sable.</a>
  <a href="/fr/docs/reference/api-and-cli/"><span>Référence</span>Contrat API et CLI : export, extraction, requête, back-end direct et limites opérationnelles.</a>
  <a href="/fr/docs/reference/evidence-packets/"><span>Contrats de données</span>Requêtes compactes et paquets de preuves : types, curseurs, opérations et ID de paquets déterministes.</a>
</div>
