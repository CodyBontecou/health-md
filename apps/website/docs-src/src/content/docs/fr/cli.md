---
title: "CLI Health.md"
description: "Choisissez le back-end de l’app Mac ou le téléphone direct, jumelez healthmd avec un iPhone ou un appareil Android, vérifiez l’état de préparation, exportez des fichiers, extrayez les données Apple Health canoniques, exécutez des requêtes typées et automatisez des tâches persistantes."
---

La commande `healthmd` propose deux modes de fonctionnement. Utilisez le back-end de l’app Mac lorsque vous voulez des requêtes locales chiffrées, des outils MCP ou le dossier de destination déjà sélectionné dans Health.md for Mac. Utilisez le back-end téléphone direct lorsque vous voulez des données brutes ou des fichiers générés sans exécuter l’app Mac. Le mode direct se jumelle avec une app Health.md ouverte sur iPhone (protocole v1) ou Android (protocole v2).

<div class="callout">
<strong>Les données de santé restent sur votre téléphone.</strong>
<p style="margin-top:6px;">Aucun des deux back-ends CLI ne lit Apple Health ni Health Connect depuis l’ordinateur. Une app Health.md à jour et ouverte sur iPhone ou Android effectue chaque nouvelle lecture de santé de la plateforme. La CLI reçoit des résultats ou des fichiers validés.</p>
</div>

## Choisir un back-end

| Capacité | Back-end de l’app Mac | Back-end téléphone direct |
|---|---|---|
| Par défaut dans l’utilitaire Mac intégré | Oui | Non, sélectionnez avec `--backend direct` |
| Appareils sources | iPhone | iPhone (protocole v1) ou Android (protocole v2) |
| Nécessite que Health.md for Mac soit ouverte | Oui | Non |
| Nécessite que l’app Health.md du téléphone soit ouverte pour de nouvelles données | Oui | Oui |
| Destination des fichiers | Dossier sélectionné dans l’app Mac | `--destination` absolu existant |
| Export brut strict | Oui | Oui ; instantanés Health Connect natifs du fournisseur sur Android |
| `healthmd extract` canonique | Oui | iPhone uniquement |
| Contexte chiffré, requêtes typées et preuves | Oui | iPhone uniquement, client portable |
| `healthmd-mcp` | Oui | Non |
| Manual IP ou Tailscale | Synchronisation Mac ou mode direct explicite | Oui |
| Transport direct de proximité | Utilitaire Swift intégré uniquement | Non disponible dans le client Rust portable |

Les choix de back-end et de transport ne changent jamais silencieusement. Une commande directe ne peut pas passer à l’app Mac pour satisfaire une requête, et une connexion Nearby échouée ne peut pas passer à Manual IP.

## Installer les utilitaires Mac intégrés

<div class="availability available">
<strong>Disponible maintenant · Health.md for Mac</strong>
<p>Les utilitaires CLI Swift et MCP signés sont fournis dans l’app Mac publiée.</p>
</div>

Health.md for Mac comprend les utilitaires signés `healthmd` et `healthmd-mcp`. Ouvrez l’app Mac et sélectionnez **CLI** pour voir les chemins de votre copie installée, les commandes de configuration, les invites pour agents et le programme facultatif d’installation de la compétence d’agent.

Les chemins normaux du bundle d’app sont :

```text
/Applications/Health.md.app/Contents/Helpers/healthmd
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

Utilisez des alias pour une session shell :

```bash
alias healthmd="/Applications/Health.md.app/Contents/Helpers/healthmd"
alias healthmd-mcp="/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
```

Ou créez des liens symboliques persistants dans un répertoire bin appartenant à l’utilisateur :

```bash
mkdir -p ~/.local/bin
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd" ~/.local/bin/healthmd
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp" ~/.local/bin/healthmd-mcp
```

Ajoutez `~/.local/bin` à `PATH` si votre shell ne l’inclut pas déjà :

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Vérifiez la CLI sans démarrer la boucle stdio MCP :

```bash
healthmd --help
healthmd doctor
```

`healthmd doctor` renvoie du JSON `healthmd.cli_doctor` avec l’état de préparation du Mac, du contexte chiffré et de l’iPhone. Il n’affiche aucune valeur de santé.

## État de la CLI portable

<div class="availability preview">
<strong>Aperçu · pas encore distribué publiquement</strong>
<p>La CLI Rust multiplateforme attend les tests QA de publication sur iPhone physique et son premier paquet qualifié.</p>
</div>

Une CLI Rust autonome est en développement `0.1.0-alpha.1`. Elle fonctionne sur macOS, Linux et Windows, utilise par défaut des connexions directes Manual IP ou Tailscale, et n’a pas besoin de l’app Mac. Elle se jumelle avec des sources iPhone via le protocole v1 et des sources Android via le protocole v2, avec des contrôles automatisés de compatibilité Swift↔Rust et Kotlin↔Rust. La compatibilité du protocole est implémentée, mais les tests QA de publication sur appareils physiques et la distribution publique doivent encore être terminés avant la première version publique.

Jusqu’à l’existence de cette version, utilisez l’utilitaire Mac intégré. Ne vous fiez pas à des URL Homebrew, crates.io, d’installateur GitHub ou de téléchargement non publiées.

Le client portable prend en charge le jumelage, l’état, l’export brut, les destinations de fichiers générés, la reprise et l’annulation sur les trois plateformes de bureau, pour les sources iPhone et Android. L’extraction canonique et les requêtes MCP typées sont des capacités iPhone ; les instantanés bruts Android conservent leur contrat natif Health Connect du fournisseur au lieu d’être convertis en données façon HealthKit, et les requêtes typées Android ne sont pas implémentées. Pour l’export de fichiers générés, le téléphone traite la destination comme une étiquette de destination opaque, tandis que la CLI qui la reçoit la valide et l’associe de façon persistante au système de fichiers hôte. Le protocole Android v2 valide les destinations de fichiers sur tous les systèmes d’exploitation de la CLI et plafonne chaque tâche générée à 4 096 fichiers ; le protocole iOS v1 rejette les destinations de fichiers sur Windows.

## Carte des commandes

| Commande | Objectif | Back-end |
|---|---|---|
| `healthmd status` | Inspecter l’état de préparation en direct ou une tâche persistante locale | Les deux |
| `healthmd doctor` | Expliquer l’état de préparation du Mac, du contexte chiffré et de l’iPhone | App Mac |
| `healthmd metrics list` | Renvoyer le catalogue canonique des métriques interrogeables | App Mac |
| `healthmd extract` | Acquérir des objets `healthmd.health_data` canoniques sélectionnés | Les deux, source iPhone |
| `healthmd query` | Acquérir et interroger des métriques typées sélectionnées | App Mac |
| `healthmd sleep sessions` | Renvoyer des sessions de sommeil de première classe et des fenêtres fixes | App Mac |
| `healthmd training align` | Aligner les entraînements avec le sommeil précédent et suivant | App Mac |
| `healthmd workouts` | Lister les entraînements typés avec preuves | App Mac |
| `healthmd coverage` | Inspecter la couverture par date et métrique ou les données manquantes | App Mac |
| `healthmd compare` | Comparer des périodes exactes avec une agrégation choisie par l’appelant | App Mac |
| `healthmd evidence training` | Construire un paquet de preuves factuel sur l’entraînement | App Mac |
| `healthmd export` | Écrire des fichiers générés ou renvoyer du JSON brut strict | Les deux |
| `healthmd resume` | Reprendre une tâche persistante d’export avec ses paramètres inchangés | Les deux |
| `healthmd cancel` | Demander une annulation explicite | Les deux |
| `healthmd agent ...` | Appeler l’API de bas niveau en boucle locale pour requêtes et tâches | App Mac |
| `healthmd direct ...` | Jumeler, lister et supprimer la confiance directe du téléphone | Direct |

Les commandes directes se jumellent avec des sources iPhone (protocole v1) ou Android (protocole v2). L’`extract` canonique et toutes les commandes de requête typée sont des capacités iPhone ; le back-end direct Android renvoie des instantanés bruts natifs Health Connect du fournisseur et des fichiers générés.

## Premier flux de travail avec l’app Mac

1. Ouvrez Health.md sur Mac et sélectionnez un dossier de destination si vous prévoyez d’écrire des fichiers.
2. Ouvrez Health.md sur l’iPhone jumelé et attendez la connectivité Mac.
3. Vérifiez l’état de préparation.
4. Exécutez une petite commande avant de demander un historique volumineux.

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --metric sleep_total --yesterday
```

Les requêtes actualisées acquièrent uniquement les métriques, sources, dates et niveaux de détail récapitulatif ou sans perte fournis. Elles ne modifient pas les réglages d’export iPhone enregistrés.

## Exports de fichiers et exports bruts

```bash
# Use the Mac app's selected destination
healthmd export --iphone --yesterday
healthmd export --iphone --last 7
healthmd export --iphone --from 2026-07-01 --to 2026-07-07
healthmd export --iphone --all

# Return strict lossless canonical JSON without writing export files
healthmd export --iphone --yesterday --raw --output yesterday.json
healthmd export --iphone --all --raw --output complete-health-corpus.json

# Replace saved metric scope for this one file job
healthmd export --iphone --last 7 --category Sleep --detail summary

# Mirror saved iPhone settings, including roll-ups
healthmd export --iphone --yesterday --use-iphone-settings

# Run a saved export profile by UUID (frozen settings + destination)
healthmd export --iphone --last 7 --profile 11111111-2222-4333-8444-555555555555
```

`--profile PROFILE_ID` résout un profil d'export enregistré sur l'iPhone via son UUID stable : l'exécution utilise la sélection de métriques, les formats et la destination figés de ce profil plutôt que les réglages actifs de l'app. Il ne peut pas être combiné avec `--use-iphone-settings` ni avec les sélecteurs de métriques/catégories (le profil possède la portée des réglages), et un UUID inconnu échoue avec une erreur typée `profile_not_found` au lieu de revenir aux réglages actifs. Lisez l'UUID dans le sélecteur de profils de l'onglet Export de l'app.

Il n’existe actuellement aucun plafond en jours calendaires. `--all` demande à l’iPhone de découvrir le plus ancien enregistrement source sélectionné disponible, fige la plage résolue et la traite par partitions bornées. Le stockage disponible et une journée inhabituellement dense restent des limites pratiques.

`--raw` demande temporairement des enregistrements sources canoniques sans perte sans modifier la préférence de l’iPhone. Il n’écrit aucun fichier généré et n’inclut pas les fichiers annexes des fournisseurs connectés.

## Extraction canonique ou requête dérivée ?

Utilisez `extract` lorsque vous avez besoin de données structurées comme la source :

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

Utilisez une commande de requête lorsque vous avez besoin d’une vue typée liée à des preuves :

```bash
healthmd sleep sessions --last-nights 14 --window first:4h
healthmd compare --metric steps:sum \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

`healthmd.health_data` v7 est le contrat source public. Les schémas de requête, de preuve, de tâche et de reçu décrivent le transport ou des vues dérivées. Ils ne remplacent pas le schéma source. L’extraction canonique est une capacité iPhone ; les sources directes Android exposent plutôt des instantanés bruts natifs Health Connect du fournisseur via l’export brut.

## Comportement lisible par machine

Les commandes utilisent par défaut du JSON versionné sur stdout ou au chemin explicite `--output`. L’extraction canonique peut opter pour JSONL, et les requêtes de haut niveau peuvent opter pour une table volontairement avec perte. La progression sans données de santé peut utiliser stderr. `--help` est en texte brut. Les échecs d’arguments avant le démarrage d’une commande sont en texte brut sur stderr avec le code de sortie 2.

Une sortie de processus réussie ne suffit pas à prouver que les données de santé sont complètes. Vérifiez :

- l’état externe ;
- l’état de la portée demandée ;
- les résultats par jour et par requête ;
- les intervalles manquants ;
- `next_cursor` ou le reçu de parcours ;
- le schéma source et sa version ;
- les limites et avertissements.

Un résultat complet mais vide signifie que Health.md a représenté la portée demandée et n’a trouvé aucune observation. Ce n’est pas la même chose que zéro, manquant, échoué, ignoré ou non pris en charge.

## Automatisation fiable

Utilisez le délai d’expiration de processus de votre hôte d’automatisation et gardez stdin fermé pour les commandes qui ne doivent pas demander d’entrée. Sur les systèmes avec GNU `timeout` :

```bash
NO_COLOR=1 TERM=dumb timeout 30 healthmd doctor </dev/null
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output sleep.json </dev/null
```

Un délai d’expiration, Ctrl-C, une sortie de processus, une perte réseau et l’épuisement du temps d’arrière-plan iOS n’annulent pas une tâche persistante. Inspectez l’ID de tâche et reprenez-la au lieu de démarrer un doublon.

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
healthmd cancel JOB_UUID
```

Seul un accusé de réception de l’iPhone rend l’annulation terminale.

## Règles de confidentialité

La sortie brute et sans perte peut contenir des horodatages exacts, des itinéraires, des dossiers cliniques, des médicaments, des entrées d’humeur, des valeurs ECG, de la provenance et des pièces jointes. Préférez un fichier de sortie à une sortie dans le terminal. Ne collez pas de charges utiles dans des tickets, transcriptions d’agent, journaux CI ou traces shell.

L’API de requête locale n’a ni bearer token, ni inscription d’appelant, ni profil d’accès, ni base de données d’autorisations. L’accès par l’interface de bouclage constitue tout son périmètre de contrôle d’accès. Tout processus local peut l’utiliser tant que l’app Mac est ouverte ; ne proxifiez donc jamais le port `17645` et ne l’exposez jamais à une autre machine.

## Guides suivants

<div class="related">
  <a href="/fr/docs/cli-direct/"><span>Sans app Mac</span>CLI téléphone directe : jumelez avec un iPhone ou un Android, examinez les transports, les exports bruts et fichiers, le comportement en arrière-plan et la prise en charge des plateformes.</a>
  <a href="/fr/docs/cli-extract/"><span>Données sources</span>Extraction canonique : sélectionnez métriques, objets, détail, JSON Pointers, JSONL et reçus.</a>
  <a href="/fr/docs/cli-jobs/"><span>Automatisation</span>Tâches persistantes : délais d’expiration, reprise, annulation, résultats partiels et scripts fiables.</a>
  <a href="/fr/docs/agents/"><span>Agents</span>Flux de travail d’agent local : contexte chiffré, portée directe, commandes typées et preuves.</a>
  <a href="/fr/docs/mcp/"><span>MCP</span>Configurez l’utilitaire stdio en bac à sable et examinez les limites de ses outils.</a>
  <a href="/fr/docs/reference/api-and-cli/"><span>Contrat</span>Référence API et CLI : routes exactes, schémas, réponses et fixtures générées.</a>
</div>
