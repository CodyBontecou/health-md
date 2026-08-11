---
title: "Agents locaux et contexte de santé"
description: "Connectez des agents locaux à Health.md via des commandes CLI à portée limitée ou MCP direct pour iPhone, et préservez les preuves, la couverture et les données manquantes."
---

Health.md offre aux agents locaux de code et d’automatisation deux façons de travailler avec les données Apple Health :

- la CLI `healthmd` pour les commandes terminal explicites et l’extraction canonique ;
- `healthmd mcp serve` et sa MCP App pour les outils typés, les visualisations natives et les exports de fichiers générés approuvés.

Le serveur MCP portable communique directement avec l’iPhone au premier plan et ne nécessite pas Health.md for Mac. La CLI peut utiliser le même canal direct pour les exports bruts/canoniques, ou l’API en boucle locale de l’app Mac pour les flux de travail indexés sur Mac. Les lectures HealthKit se produisent toujours sur iPhone, et `healthmd.health_data` v7 reste le contrat source public.

```text
local agent -> healthmd mcp serve -> authenticated encrypted port 17647 -> foreground iPhone
local agent -> healthmd CLI -> direct iPhone or optional Mac loopback workflow
```

## Ce qu’un agent peut faire

- vérifier le jumelage direct et l’état de préparation de l’iPhone au premier plan sans lire de valeurs de santé ;
- lister les ID de métriques et catégories canoniques ;
- acquérir depuis l’iPhone une portée exacte de métrique, source, date et détail ;
- extraire des documents quotidiens canoniques ou des enregistrements sources ;
- interroger des séries de métriques typées avec preuves et couverture ;
- construire des sessions de sommeil stables et des fenêtres de sommeil fixes ;
- aligner les entraînements avec le sommeil précédent et suivant ;
- lister les entraînements et inspecter la couverture ;
- comparer des périodes exactes avec une agrégation explicite ;
- créer des paquets de preuves factuels sur l’entraînement ;
- parcourir un corpus logique non borné à l’aide de requêtes bornées ;
- afficher des vues de métriques, sommeil, entraînement, comparaison, couverture et preuves dans MCP Apps ;
- lancer des exports de fichiers générés approuvés vers une destination explicite existante sur l’ordinateur ;
- inspecter, reprendre ou annuler des tâches d’export persistantes.

Health.md ne diagnostique pas, ne recommande pas de traitement, n’infère pas de causalité et ne qualifie pas un résultat de sain, nocif, meilleur ou pire.

## Configurer les utilitaires locaux

<div class="availability preview">
<strong>Aperçu · configuration directe portable</strong>
<p>Les étapes ci-dessous utilisent le paquet multiplateforme non publié. Pour un flux de travail disponible aujourd’hui, configurez l’utilitaire Mac signé <code>healthmd-mcp</code> dans <a href="/fr/docs/configuration/">Configurer votre agent</a>.</p>
</div>

1. Installez le paquet CLI Health.md multiplateforme.
2. Exécutez `healthmd setup codex` ; il configure Codex et ouvre le jumelage lorsqu’aucun iPhone n’est encore de confiance.
3. Terminez le jumelage dans Direct CLI Access dans Health.md sur iPhone et gardez l’app au premier plan.
4. Pour Claude ou une configuration manuelle d’hôte, configurez le chemin absolu `healthmd` avec les arguments `mcp serve` à l’aide du [serveur MCP et App Health.md](/fr/docs/mcp/).
5. Redémarrez l’hôte lorsque la configuration signale une modification, puis appelez `healthmd_doctor`.

Health.md for Mac reste une installation facultative et un moyen de distribuer les compétences aux utilisateurs Mac ; elle n’est pas une dépendance de MCP portable.

Le programme d’installation de la compétence crée `healthmd-cli/SKILL.md` dans le répertoire que vous approuvez. Il remplace uniquement le dossier de compétence de Health.md. La compétence présente les commandes bornées, le traitement des résultats structurés, les règles de confidentialité et la récupération sûre après des résultats inconnus.

Utilisez l’invite de configuration de l’app Mac si vous voulez qu’un agent crée les liens symboliques. Health.md elle-même ne modifie pas silencieusement les fichiers de démarrage shell ni `/usr/local/bin`.

## Vérifier d’abord l’état de préparation

Pour les clients MCP portables, appelez `healthmd_doctor`. Il vérifie la confiance directe locale et l’iPhone connecté au premier plan sans lire de valeurs de santé, puis renvoie des erreurs exploitables sans données de santé. Chaque requête MCP typée envoie ensuite une demande explicite de données actualisées à cet iPhone : elle capture uniquement la portée demandée, évalue la requête typée sur l’appareil et renvoie des pages bornées.

Les utilisateurs de la CLI Mac en boucle locale peuvent toujours exécuter `healthmd doctor` pour l’état de préparation `healthmd.cli_doctor` v1, la couverture du contexte chiffré et les prochaines actions.

## Chaque requête porte sa propre portée

Health.md n’utilise pas de profils d’accès enregistrés, d’inscriptions d’appelants, d’enregistrements d’autorisations ni d’identifiants CLI. Chaque requête fournit la portée complète des données dont elle a besoin :

- ID de métriques ou catégories ;
- sélecteurs de sources Apple Health et de fournisseurs facultatifs ;
- dates exactes ou toutes les dates disponibles ;
- détail récapitulatif ou sans perte ;
- opération de requête ;
- contrôles de page bornés.

L’acquisition de données actualisées valide la portée par rapport aux catalogues actuels et la conserve avec la tâche persistante et l’applique sur l’iPhone sans modifier les préférences d’export enregistrées.

Une requête sans sélection d’acquisition explicite est rejetée au lieu d’hériter des réglages d’export habituels de l’utilisateur.

## Périmètres d’autorisation

Le MCP portable utilise le protocole direct jumelé : stockage natif des identifiants, authentification mutuelle de transcript, paquets chiffrés, protection contre la relecture et connexion d’un iPhone au premier plan à l’adresse explicite de l’ordinateur. L’API de requête Mac facultative écoute uniquement sur les interfaces de bouclage IPv4 et IPv6 et vérifie que le pair utilise bien cette interface.

Pour le mode Mac facultatif en boucle locale, tout processus local pouvant atteindre le port `17645` pendant que Health.md est ouverte peut émettre les mêmes requêtes. Traitez l’accès à la machine locale comme l’autorité de requête :

- ne liez pas et ne proxifiez pas le port vers une interface LAN ;
- ne le tunnelisez pas vers une autre machine ;
- ne placez pas de proxy inverse HTTP devant lui ;
- ne configurez pas MCP avec une URL extérieure à l’interface de bouclage ;
- vérifiez quels agents locaux peuvent exécuter l’utilitaire.

Les anciennes routes de profil et d’activité renvoient `410 removed_endpoint` pour compatibilité.

## Données canoniques et vues dérivées

Utilisez `healthmd extract` lorsque l’agent a besoin de données structurées comme la source ou d’un grand corps brut/canonique validé :

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

Utilisez les commandes de requête ou les outils MCP pour les vues dérivées et les visualisations dans l’hôte :

```bash
healthmd query --metric resting_heart_rate --last 30 --all-pages
healthmd sleep sessions --last-nights 14 --window first:4h
healthmd training align --last 14 --workout running --sleep-window first:4h
```

La distinction est volontaire :

| Interface | Rôle contractuel |
|---|---|
| `healthmd.health_data` v7 | Document source quotidien public |
| `healthmd.healthkit_records` v1 | Archive canonique d’enregistrements sources dans les documents quotidiens sans perte |
| `healthmd.extract_receipt` | Métadonnées de portée et d’achèvement de l’extraction |
| `healthmd.query_context_day` v1 | Enregistrement d’index chiffré jetable |
| `healthmd.query_response` v1 | Résultat dérivé typé paginé |
| `healthmd.evidence_packet` v1 | Paquet factuel lié aux preuves sources |
| Reçus de tâches et de parcours | Métadonnées de transport, de persistance et d’achèvement |

Une projection ou un résultat typé ne se fait jamais passer pour un document source quotidien complet.

## Acquisition de données actualisées

Les requêtes de haut niveau acquièrent par défaut des données actualisées :

```bash
healthmd query --category Sleep --last 14
```

Health.md crée une requête dédiée de contexte chiffré. Elle n’écrit pas de fichiers d’export et ne consomme pas le quota d’export de fichiers. L’iPhone lit la portée explicite, construit des journées de référence compactes et déterministes et envoie des partitions bornées et reprenables. Le Mac valide chaque journée chiffrée avant d’en accuser réception.

Pour vérifier l’exhaustivité des données actualisées, Health.md contrôle chaque métrique, source ou fournisseur et chaque jour de référence demandés par rapport aux blobs remplacés après le début de cette actualisation. Les anciennes valeurs en cache et les données d’un autre fournisseur ne peuvent pas masquer une acquisition échouée.

Les requêtes fournisseur seul peuvent ignorer HealthKit. Le parcours d’historique fournisseur suit des curseurs natifs du fournisseur au lieu d’imposer une limite totale fixe de résultats.

## Contexte Mac chiffré

Le Mac stocke une génération chiffrée distincte pour chaque journée de référence. Une clé aléatoire de 256 bits vit dans Keychain comme élément propre à cet appareil et disponible uniquement déverrouillé.

- les blobs quotidiens et le manifeste utilisent AES-256-GCM ;
- les noms de fichiers sont des UUID aléatoires, pas des dates ni des noms de métriques ;
- les dates propriétaires et les entrées d’index sont chiffrées ;
- les fichiers ont des permissions réservées au propriétaire et sont exclus des sauvegardes ;
- les validations écrivent une nouvelle génération immuable avant de remplacer le manifeste chiffré ;
- les lectures n’exposent aucune donnée en cas de clé manquante, d’échec de l’authentification, de dates mal formées ou de non-concordance avec le manifeste.

Le stockage n’a pas de plafond configuré de métriques, de jours, d’historique ou de résultats. Les commandes restent bornées parce qu’elles déchiffrent un jour à la fois et paginent les résultats.

L’index est jetable. Les exports canoniques restent la source de référence.

## Conservation et suppression

Health.md ne supprime pas le contexte de requête selon un calendrier de conservation implicite. Sur Mac, Réglages affiche le nombre de journées de référence stockées et la plage de dates.

Utilisez :

- **Delete Older Context** pour supprimer les dates propriétaires strictement antérieures à une limite sélectionnée ;
- **Delete All Encrypted Context** pour supprimer chaque génération chiffrée et la clé Keychain dédiée.

La suppression complète reste disponible même si la clé ou le texte chiffré est endommagé. La suppression de la clé fournit une crypto-suppression pour les restes de texte chiffré non supprimés.

La suppression du contexte de requête ne supprime pas les fichiers d’export, les identifiants des fournisseurs connectés ni les données Apple Health.

## Valeurs typées et données manquantes

Les valeurs de requête sont étiquetées. Un résultat peut transporter une quantité et une unité canonique, une durée, un compte signé, une chaîne, une catégorie, un booléen, un horodatage UTC, une date calendaire, un tableau imbriqué ou une charge utile typée future inconnue.

Les données manquantes restent explicites :

- `complete_empty` signifie que la portée représentée n’avait aucune observation correspondante ;
- `partial` signifie qu’une partie seulement de la portée demandée s’est terminée ;
- `failed`, `unsupported`, `skipped` et `cancelled` conservent leur signification ;
- `not_requested`, `legacy_unavailable`, `redacted` et `not_synchronized` restent distincts.

Health.md ne convertit jamais une valeur absente en zéro numérique. Un vrai zéro est encodé comme une valeur typée disponible.

## Preuves et langage neutre

Les résultats relient les faits à des preuves sources telles que :

- les clés de résumé quotidien ;
- les UUID HealthKit canoniques ;
- les identités externes ;
- les résultats du manifeste de requête ;
- les avertissements d’intégrité ;
- les échecs partiels.

La résolution des preuves vérifie ensemble l’ID de preuve, le localisateur, le schéma source, la version source et l’empreinte de la source.

La direction d’une comparaison de périodes se limite à `increased`, `decreased`, `unchanged` ou `not_comparable`. L’alignement d’entraînement rapporte des horodatages et des écarts, pas des effets causaux. Les paquets de preuves rapportent les observations stockées et la couverture, pas des conclusions médicales.

Un agent doit préserver ces limites dans sa propre réponse. Il doit signaler les données manquantes, éviter de transformer une corrélation en cause et orienter les questions médicales vers un clinicien qualifié.

## Pages de taille limitée, accès logique complet

Les pages de requête utilisent `max_items`, `max_bytes` et un `next_cursor` opaque. Il n’existe pas de plafond contractuel sur le nombre total de jours, d’entraînements, de métriques ou éléments de résultat stockés.

Un curseur est protégé en intégrité et lié à la requête sémantique ainsi qu’à la révision du corpus chiffré. Health.md rejette :

- un curseur modifié ;
- un curseur utilisé avec une autre requête ;
- un curseur émis avant un changement du corpus ;
- un curseur répété pendant le parcours automatique.

Utilisez `--all-pages` ou MCP `all_pages: true` pour un parcours automatique borné. Réduisez la portée ou paginez manuellement si une invocation atteint son plafond de sécurité global.

## Checklist de reporting d’agent

Lorsque vous résumez un résultat, indiquez :

- la commande ou l’outil utilisé ;
- les dates, métriques, sources et détails exacts demandés ;
- le mode actualisé, en cache ou avec réutilisation de la couverture ;
- l’état de la portée demandée et du corpus séparément ;
- l’achèvement de la page ou du parcours ;
- les unités et les preuves sources pour toute valeur énoncée ;
- les intervalles manquants, limites et omissions sans rapport ;
- l’ID de tâche lorsque le travail est en pause ou reprenable.

N’incluez pas d’enregistrements bruts, itinéraires, textes cliniques, détails de médicaments, entrées d’humeur ni pièces jointes, sauf si l’utilisateur demande explicitement ces valeurs et comprend la divulgation.

## Choisir une intégration

<div class="related">
  <a href="/fr/docs/agent-queries/"><span>Recettes CLI</span>Requêtes d’agent typées : métriques, sessions de sommeil, alignement d’entraînement, entraînements, couverture, comparaison et preuves.</a>
  <a href="/fr/docs/mcp/"><span>Protocole d’outils</span>Configuration Codex et Claude, 21 outils Mac publiés, 19 outils portables en aperçu, graphiques MCP App, exports, pagination et limites du bac à sable.</a>
  <a href="/fr/docs/agent-api/"><span>Bas niveau</span>API de requête en boucle locale : routes, JSON de requête directe, curseurs et tâches persistantes d’acquisition.</a>
  <a href="/fr/docs/cli-extract/"><span>Objets sources</span>Extraction canonique : documents sélectionnés au schéma v7, enregistrements, projections et reçus.</a>
  <a href="/fr/docs/reference/evidence-packets/"><span>Contrats</span>Requêtes compactes et paquets de preuves : valeurs typées, couverture, opérations et ID déterministes.</a>
</div>
