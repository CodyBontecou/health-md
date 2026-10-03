---
title: "CLI Health.md"
description: "Installez la CLI healthmd autonome sur macOS, Linux ou Windows, jumelez-la directement avec un iPhone ou un appareil Android, vérifiez l’état de préparation, exportez des données, exécutez des requêtes et gérez des tâches persistantes. Aucune app Mac requise."
---

La CLI `healthmd` autonome fonctionne sur macOS, Linux et Windows et se jumelle directement avec une app Health.md ouverte sur iPhone (protocole v1) ou Android (protocole v2). Elle ne nécessite jamais l’app Health.md for Mac, n’offre aucune sélection de back-end et ne lit jamais Apple Health ni Health Connect depuis l’ordinateur.

<div class="callout">
<strong>Les données de santé restent sur votre téléphone.</strong>
<p style="margin-top:6px;">La CLI ne lit jamais Apple Health ni Health Connect depuis l’ordinateur. Une app Health.md à jour et ouverte sur iPhone ou Android effectue chaque nouvelle lecture de santé de la plateforme. La CLI reçoit des résultats ou des fichiers validés.</p>
</div>

## Installer la CLI autonome

<div class="availability preview">
<strong>Aperçu public · version stable qualifiée à venir</strong>
<p>La CLI Rust multiplateforme est publiée, mais sa matrice mobile exacte attend encore la qualification physique de publication.</p>
</div>

Sur macOS ou Linux, installez l’aperçu avec <code>brew install CodyBontecou/tap/healthmd</code>. Utilisez la version mobile exacte nommée par les preuves de publication ; la publication du paquet ne prouve pas la compatibilité mobile.

La CLI Rust autonome fonctionne sur macOS, Linux et Windows, utilise des connexions directes Manual IP ou Tailscale et ne nécessite pas l’app Mac. Elle se jumelle aux sources iPhone via le protocole v1 et aux sources Android via le protocole v2, avec des contrôles automatisés de compatibilité Swift↔Rust et Kotlin↔Rust. La compatibilité des protocoles est implémentée ; la QA de publication sur appareils physiques doit se terminer avant la première version stable qualifiée. Des archives avec somme de contrôle, un installateur PowerShell et `cargo install healthmd-cli --locked` accompagnent chaque publication.

Le client portable prend en charge le jumelage, l’état, l’export brut, les destinations de fichiers générés, la reprise et l’annulation sur les trois plateformes de bureau pour iPhone et Android. L’extraction canonique et les requêtes MCP typées sont des fonctionnalités iPhone. Les instantanés bruts Android conservent leur contrat Health Connect natif du fournisseur au lieu d’être convertis en données au format HealthKit. Les requêtes typées Android ne sont pas implémentées. Pour l’export de fichiers générés, le téléphone traite la destination comme une étiquette opaque ; la CLI réceptrice la valide et la lie durablement au système de fichiers hôte. Le protocole Android v2 valide les destinations de fichiers sur tous les systèmes d’exploitation de la CLI et limite chaque tâche générée à 4 096 fichiers.

## Carte des commandes

| Commande | Rôle |
|---|---|
| `healthmd status` | Inspecter l’état en direct ou une tâche locale persistante |
| `healthmd export` | Écrire des fichiers générés ou renvoyer du JSON brut strict |
| `healthmd extract` | Acquérir des objets canoniques `healthmd.health_data` sélectionnés (iPhone) |
| `healthmd query` | Exécuter des opérations de requête typées fixes (iPhone) |
| `healthmd resume` | Reprendre une tâche d’export persistante immuable |
| `healthmd cancel` | Demander une annulation explicite |
| `healthmd direct ...` | Jumeler, lister et supprimer la confiance directe du téléphone |
| `healthmd mcp ...` | Servir ou inspecter la surface d’outils MCP fixe |
| `healthmd setup codex` | Configurer Codex et jumeler un iPhone en un seul flux |

Les commandes directes se jumellent aux sources iPhone (protocole v1) ou Android (protocole v2). L’`extract` canonique et chaque commande de requête typée sont des fonctionnalités iPhone ; les sources directes Android renvoient des instantanés bruts Health Connect natifs du fournisseur et des fichiers générés.

```bash
# Readiness and local trust
healthmd status
healthmd direct devices

# Platform-native raw export; omit --output to stream validated JSON/NDJSON to stdout
healthmd export --yesterday --raw --output yesterday.json
healthmd export --last 7 --raw --output week.json

# Typed query through the same operation registry as MCP (iPhone)
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'

# Scoped canonical extraction (iPhone)
healthmd extract --category Sleep --last 7 --output sleep.json

# Production-generated files on every CLI OS
mkdir -p "$HOME/Documents/HealthVault"
healthmd export --yesterday --destination "$HOME/Documents/HealthVault"

# Durable operations
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --output resumed.json
healthmd cancel JOB_UUID
```

### Export portable de fichiers basé sur des profils

La CLI directe autonome peut résoudre un profil enregistré sur l’une ou l’autre plateforme téléphonique par son identifiant stable. Le profil fournit ses réglages de sortie figés ; la destination de l’ordinateur reste explicite :

```bash
mkdir -p "$HOME/Documents/HealthVault"
healthmd export --last 7 \
  --profile 11111111-2222-4333-8444-555555555555 \
  --destination "$HOME/Documents/HealthVault"
```

`--profile PROFILE_ID` ne peut pas être combiné avec `--use-device-settings` ni avec des sélecteurs de métriques/catégories, et un identifiant inconnu échoue de manière sûre au lieu d’utiliser les réglages actuels. Copiez l’identifiant depuis **Réglages → Profils d’export → ID de profil** sur iPhone ou Android. Consultez [Profils d’export](/fr/docs/export-profiles/) pour l’automatisation et le comportement des destinations.

Le client direct portable peut invoquer toute opération typée iPhone prise en charge sans enveloppe MCP :

```bash
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'
```

## Utilitaire Mac intégré

Health.md for Mac livre ses propres utilitaires Swift signés `healthmd` et `healthmd-mcp` dans l’app. Cet utilitaire est une fonctionnalité de l’app Mac, pas un back-end de la CLI autonome : par défaut il s’adresse au serveur loopback de l’app Mac en cours d’exécution pour les requêtes locales chiffrées, les outils MCP et le dossier de destination déjà sélectionné dans Health.md for Mac ; il propose en outre un mode direct iPhone compatible sélectionné avec `--backend direct`. Les deux clients ne changent jamais de mode silencieusement.

<div class="availability available">
<strong>Disponible maintenant · Health.md for Mac</strong>
<p>Les utilitaires Swift signés pour la CLI et MCP sont livrés dans l’app Mac publiée.</p>
</div>

Ouvrez l’app Mac et sélectionnez **CLI** pour voir les chemins de votre copie installée, les commandes de configuration, les invites d’agents et l’installateur optionnel de compétences d’agent.

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

Ajoutez `~/.local/bin` au `PATH` si votre shell ne l’inclut pas déjà :

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Vérifiez l’utilitaire sans démarrer la boucle stdio MCP :

```bash
healthmd --help
healthmd doctor
```

`healthmd doctor` renvoie un JSON `healthmd.cli_doctor` avec l’état de Mac, du contexte chiffré et de l’iPhone. Il n’affiche aucune valeur de santé.

### Commandes de l’utilitaire intégré

| Commande | Rôle |
|---|---|
| `healthmd export --iphone ...` | Écrire des fichiers générés ou renvoyer du JSON brut strict via l’app Mac |
| `healthmd status` | Inspecter l’état Mac/iPhone ou une tâche persistante |
| `healthmd doctor` | Expliquer l’état de Mac, du contexte chiffré et de l’iPhone |
| `healthmd metrics list` | Renvoyer le catalogue canonique des métriques requêtables |
| `healthmd query` | Acquérir et requêter des métriques typées sélectionnées |
| `healthmd sleep sessions` | Renvoyer des sessions de sommeil de premier niveau et des fenêtres fixes |
| `healthmd training align` | Aligner les entraînements sur le sommeil précédent et suivant |
| `healthmd workouts` | Lister les entraînements typés avec preuves |
| `healthmd coverage` | Inspecter la couverture de dates et de métriques ou les manques |
| `healthmd compare` | Comparer des périodes exactes avec l’agrégation choisie par l’appelant |
| `healthmd evidence training` | Construire un paquet de preuves d’entraînement factuel |
| `healthmd resume` / `healthmd cancel` | Gérer les tâches persistantes |
| `healthmd agent ...` | Appeler l’API loopback bas niveau de requêtes et de tâches |
| `healthmd --backend direct ...` | Le mode direct iPhone compatible de l’utilitaire |

En mode direct de l’utilitaire, les sous-commandes de requête, preuve, doctor, métriques et rafraîchissement de contexte Mac renvoient `backend_unsupported` au lieu de basculer vers l’app Mac.

### Premier flux de travail avec l’app Mac

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

Les requêtes fraîches n’acquièrent que les métriques, sources, dates et détails de résumé ou sans perte fournis. Elles ne modifient pas les réglages d’export iPhone enregistrés.

### Exports de fichiers et bruts de l’utilitaire intégré

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
```

Il n’y a pas de plafond actuel en jours calendaires. `--all` demande à l’iPhone de découvrir l’enregistrement sélectionné le plus ancien disponible, fixe la plage résolue et la traite via des partitions bornées. Le stockage disponible et une journée inhabituellement dense restent des limites pratiques.

`--raw` demande temporairement des enregistrements canoniques sans perte sans modifier la préférence iPhone. Il n’écrit aucun fichier généré et n’inclut pas les annexes de fournisseurs connectés.

## Extraction canonique ou requête dérivée ?

Utilisez `extract` quand vous avez besoin de données conformes à la source :

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

Utilisez une commande de requête lorsque vous avez besoin d’une vue typée liée à des preuves. La CLI autonome expose des opérations typées fixes ; l’utilitaire Mac intégré propose en plus les commandes de haut niveau suivantes :

```bash
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"exact","range":{"start_date":"2026-07-22","end_date":"2026-07-28"}},"all_pages":true}'
healthmd compare --metric steps:sum \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

`healthmd.health_data` v8 est le contrat public de source Apple. Les schémas de requête, preuve, tâche et reçu décrivent des vues de transport ou dérivées. Ils ne remplacent pas le schéma source. L’extraction canonique est une fonctionnalité iPhone ; les sources directes Android exposent des instantanés Health Connect natifs du fournisseur via l’export brut.

## Comportement lisible par machine

Les commandes utilisent par défaut du JSON versionné sur stdout ou au chemin `--output` explicite. L’extraction canonique peut émettre du JSONL et les requêtes de haut niveau peuvent opter pour un tableau délibérément avec perte. La progression sans données de santé peut utiliser stderr. `--help` est en texte brut. Les échecs d’arguments avant le démarrage d’une commande sont du texte brut sur stderr avec le code de sortie 2.

Une sortie de processus réussie ne suffit pas à prouver des données de santé complètes. Vérifiez :

- l’état externe ;
- l’état de la portée demandée ;
- les résultats par jour et par requête ;
- les intervalles manquants ;
- `next_cursor` ou le reçu de parcours ;
- le schéma et la version de la source ;
- les limites et avertissements.

Un résultat complètement vide signifie que Health.md a représenté la portée demandée et n’a trouvé aucune observation. Ce n’est pas la même chose que zéro, manquant, échoué, ignoré ou non pris en charge.

## Automatisation sûre

Utilisez le délai d’attente de processus de votre hôte d’automatisation et gardez stdin fermé pour les commandes qui ne doivent pas demander d’entrée. Sur les systèmes avec `timeout` GNU :

```bash
NO_COLOR=1 TERM=dumb timeout 30 healthmd status </dev/null
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output sleep.json </dev/null
```

Délai d’attente, Ctrl-C, fin de processus, perte réseau et temps d’arrière-plan iOS épuisé n’annulent pas une tâche persistante. Inspectez l’identifiant de la tâche et reprenez-la au lieu de démarrer un doublon.

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
healthmd cancel JOB_UUID
```

Seul un accusé de réception de l’iPhone rend l’annulation définitive.

## Règles de confidentialité

La sortie brute et sans perte peut contenir des horodatages exacts, des itinéraires, des dossiers cliniques, des médicaments, des entrées d’humeur, des valeurs ECG, des provenances et des pièces jointes. Préférez un fichier de sortie à la sortie terminal. Ne collez pas de charges utiles dans des rapports d’incident, des transcriptions d’agent, des journaux CI ou des traces shell.

L’API de requête locale de l’utilitaire Mac intégré n’a ni jeton porteur, ni inscription, ni profil d’accès, ni base de données d’autorisations. L’accessibilité loopback est sa frontière d’accès complète. Tout processus local peut l’utiliser tant que l’app Mac est ouverte ; ne faites jamais de proxy ni n’exposez le port `17645` à une autre machine.

## Guides suivants

<div class="related">
  <a href="/fr/docs/cli-direct/"><span>Sans app Mac</span>CLI téléphone directe : jumelage avec iPhone ou Android, transports, exports bruts et fichiers, comportement en arrière-plan et prise en charge des plateformes.</a>
  <a href="/fr/docs/cli-extract/"><span>Données sources</span>Extraction canonique : sélectionner métriques, objets, détails, pointeurs JSON, JSONL et reçus.</a>
  <a href="/fr/docs/cli-jobs/"><span>Automatisation</span>Tâches persistantes : délais, reprise, annulation, résultats partiels et scripts sûrs.</a>
  <a href="/fr/docs/agents/"><span>Agents</span>Flux d’agents locaux : contexte chiffré, portée directe, commandes typées et preuves.</a>
  <a href="/fr/docs/mcp/"><span>MCP</span>Configurer l’utilitaire stdio isolé et examiner sa frontière d’outils.</a>
  <a href="/fr/docs/reference/api-and-cli/"><span>Contrat</span>Référence API et CLI : routes exactes, schémas, réponses et fixtures générés.</a>
</div>
