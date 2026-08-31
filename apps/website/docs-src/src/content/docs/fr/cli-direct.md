---
title: "CLI téléphone directe"
description: "Jumelez healthmd avec un iPhone ou un téléphone Android via Manual IP ou Tailscale, puis exportez sans exécuter Health.md for Mac."
---

Le back-end direct connecte `healthmd` à une app Health.md ouverte sur un iPhone ou un téléphone Android, sans faire passer la commande par Health.md for Mac. Le téléphone lit le magasin de santé de sa plateforme — HealthKit sur iPhone, Health Connect sur Android —, prépare le résultat dans un stockage protégé et transfère des partitions validées vers la CLI.

```text
healthmd on the computer
  <-> authenticated encrypted Manual IP, Tailscale, or supported Nearby channel
Health.md on iPhone or Android -> HealthKit / Health Connect -> protected bounded spool
  -> raw snapshots, production-generated files, or (iPhone) canonical and typed query data
```

<div class="availability preview">
<strong>Aperçu · CLI directe portable</strong>
<p>Le back-end Swift direct intégré est disponible sur macOS et se jumelle avec l’iPhone. Le jumelage Android (protocole v2) fait partie de l’aperçu publiquement distribué du client Rust multiplateforme. Les tests QA de publication sur iPhone et Android physiques restent en attente ; les commandes Linux et Windows décrivent un flux de travail explicitement non qualifié.</p>
</div>

## Compatibilité mobile pour 0.1.0-alpha.3

Ce tableau autonome est la matrice applicable à l’aperçu explicitement non qualifié. Aucune paire CLI/mobile publique n’est encore qualifiée.

| Source mobile | Protocole | Contrepartie tag-SHA exacte / seuil non qualifié | Opérations Rust portables | Statut public |
|---|---|---|---|---|
| iPhone avec export | sélecteur 1 / v1 | iOS 3.2.1 (build 202608300209) / iOS 3.0.3 | État, brut, extraction, fichiers, reprise, annulation | Qualification physique en attente |
| iPhone avec requêtes | sélecteur 1 / v1 + requête v3 | iOS 3.2.1 (build 202608300209) / iOS 3.0.3 | V1 plus MCP/requête locale à 19 outils | Qualification physique en attente |
| Android | sélecteur 2 / v2 | Android 1.8.1 (`versionCode 30`) / Android 1.5.4 (`versionCode 25`) | État, brut natif, fichiers, reprise, annulation | Qualification physique en attente |
| Requête MCP typée Android | Non disponible | Non implémentée | Les outils exigent iPhone v3 | Non pris en charge |

## Ce que le mode direct prend en charge

- le jumelage unique et la reconnexion de confiance avec des sources iPhone (protocole v1) ou Android (protocole v2) ;
- l’inspection locale des appareils de confiance et la suppression du jumelage ;
- l’état de préparation du téléphone en direct ;
- l’export brut strict — `healthmd.health_data` au schéma v8 sur iPhone, instantanés Health Connect natifs du fournisseur sur Android ;
- l’extraction canonique sélectionnée (iPhone uniquement) ;
- l’export de fichiers générés en production sur les deux plateformes de téléphone ;
- l’état et la reprise des tâches locales persistantes ;
- l’annulation explicite ;
- le serveur stdio `healthmd mcp serve` dans le même exécutable, avec requêtes typées directes, catalogue de métriques, preuves, interface MCP Apps et repli PNG (iPhone uniquement).

Le back-end direct de la commande `healthmd` n’émule pas les routes HTTP de contexte chiffré de l’app Mac ; les sous-commandes orientées Mac `doctor`, query, evidence et refresh renvoient donc toujours `backend_unsupported` au lieu de changer de back-end. Utilisez `healthmd mcp serve` pour une analyse typée à partir de données actualisées provenant directement de l’iPhone, ou exécutez `healthmd setup codex` pour configurer et jumeler Codex automatiquement. `healthmd mcp schema [TOOL]` affiche localement le schéma d’entrée MCP imbriqué exact et des exemples ; utilisez directement `healthmd_sleep_sessions` pour le sommeil au lieu de traiter la sortie canonique de `extract` comme l’API de requête typée.

## Prérequis

- Un binaire `healthmd` compatible direct et une version Health.md correspondante : iPhone (protocole v1) ou Android (protocole v2). Le jumelage Android exige le client Rust portable ; l’utilitaire macOS intégré ne se jumelle qu’avec l’iPhone.
- Health.md ouverte au premier plan sur le téléphone pour le jumelage et les nouvelles commandes.
- **Settings > Mac Sync > Direct CLI Access** activé sur l’iPhone, ou **Settings → Direct CLI** sur Android.
- Autorisation de santé de la plateforme (HealthKit ou Health Connect), données protégées, autorisation réseau local et quota d’export disponibles.
- Une adresse d’ordinateur joignable et le port TCP `17647` pour Manual IP. Une adresse Tailscale fonctionne.
- Une destination absolue existante pour le mode fichiers générés.

La CLI est l’écouteur. Le téléphone se connecte à l’adresse de l’ordinateur saisie dans Direct CLI Access.

## Prise en charge des transports

| Transport | Utilitaire Swift intégré sur macOS | Client Rust portable |
|---|---:|---:|
| Manual IP sur un LAN | Oui | macOS, Linux, Windows |
| Adresse Tailscale | Oui | macOS, Linux, Windows |
| Nearby / MultipeerConnectivity | Oui | Non |

Nearby utilise la session Multipeer chiffrée d’Apple, avec les mêmes mécanismes d’authentification et de chiffrement applicatifs Health.md que Manual IP. Le client portable renvoie `transport_unsupported` pour Nearby.

## Jumeler une fois avec Manual IP

Démarrez l’écouteur sur l’ordinateur :

```bash
healthmd direct pair --transport manual-ip
```

Le client Rust portable écrit sur stderr un code iPhone à six chiffres, un code Android distinct à 20 chiffres, des adresses candidates pour l’ordinateur et le port de l’écouteur ; l’utilitaire macOS intégré n’affiche que le code iPhone à six chiffres. stdout reste réservé au résultat JSON final.

Sur l’iPhone :

1. Ouvrez **Health.md > Settings > Mac Sync > Direct CLI Access**.
2. Activez Direct CLI Access.
3. Sélectionnez **Manual IP**.
4. Saisissez l’adresse LAN ou Tailscale de l’ordinateur.
5. Saisissez le port `17647`, sauf si la CLI utilise un autre `--port` global.
6. Saisissez le code de jumelage et touchez Pair.
7. Gardez l’app ouverte jusqu’à ce que les deux côtés indiquent la réussite.

Les codes de jumelage iPhone expirent au bout de 10 minutes. Ils ne sont jamais envoyés sur le réseau ni conservés.

## Jumeler un téléphone Android

Le jumelage Android utilise le client Rust portable et le code unique distinct à 20 chiffres (~66 bits) affiché par `healthmd direct pair`. Android ne retombe jamais sur le protocole iPhone.

1. Ouvrez **Health.md > Settings → Direct CLI** sur le téléphone Android.
2. Saisissez l’adresse LAN ou Tailscale de l’ordinateur et le port `17647`.
3. Saisissez le code à 20 chiffres et confirmez le jumelage.
4. Gardez l’app ouverte ; Android exécute un service de premier plan de synchronisation de données, visible et démarré par l’utilisateur, pour une session directe active.

Une fois le code unique consommé, la confiance de reconnexion s’appuie sur le Keystore.

Utilisez un autre port si nécessaire :

```bash
healthmd --port 18000 direct pair --transport manual-ip
healthmd --backend direct --port 18000 status
```

Continuez à utiliser le même port explicite pour les commandes ultérieures d’état, d’export, de reprise et d’annulation.

## Jumeler avec Nearby

Nearby est disponible uniquement dans l’utilitaire Swift intégré :

```bash
healthmd direct pair --transport nearby
```

Sélectionnez Nearby dans Direct CLI Access sur l’iPhone, saisissez le code affiché et gardez les deux appareils ouverts jusqu’à la fin du jumelage. Aucune opération Nearby échouée ne bascule vers Manual IP.

## Appareils de confiance

Le jumelage crée une relation de confiance distincte de la synchronisation avec Health.md for Mac.

```bash
healthmd direct devices
healthmd direct unpair DEVICE_UUID
```

Ces commandes lisent ou modifient la confiance locale et ne contactent pas le téléphone. Sur l’iPhone, utilisez **Forget Paired CLI** pour supprimer l’autre côté ; sur Android, supprimez le jumelage depuis **Settings → Direct CLI**.

Lorsque plusieurs téléphones sont de confiance, sélectionnez explicitement l’installation voulue :

```bash
healthmd --backend direct --device DEVICE_UUID status
```

Utilisez `healthmd direct reset-trust --confirm` uniquement lorsque la confiance locale est corrompue ou appartient à une installation remplacée. Cette commande supprime tous les jumelages directs locaux. Oubliez ces jumelages sur le téléphone avant de recommencer.

## Vérifier l’état de préparation en direct

```bash
healthmd --backend direct --transport manual-ip status
```

Une réponse d’état direct indique l’état de connexion et de sécurité sans valeurs de santé. Le client portable signale la source sous `source` avec une `platform` valant `ios` ou `android` ; l’utilitaire intégré expose les champs `iphone` ci-dessous. Vérifiez ces champs avant de commencer (source iPhone affichée) :

| Champ | État prêt |
|---|---|
| `backend` | `direct` |
| `mac_app` | `bypassed` |
| `direct_cli.paired` | `true` |
| `iphone.connected` | `true` |
| `iphone.app_active` | `true` pour un nouveau travail |
| `iphone.protected_data_available` | `true` |
| `iphone.can_trigger_raw_exports` | `true` pour raw et extract |
| `iphone.can_trigger_exports` | `true` pour les fichiers générés |

La destination de l’état direct reste non sélectionnée. Le mode fichier utilise uniquement le `--destination` explicite fourni à la commande.

Une source Android signale `platform: "android"` avec `app_active`, `protected_data_available`, `export_in_progress` et ses produits bruts disponibles, à la place des indicateurs de déclenchement iPhone.

## Export brut strict (iPhone)

Choisissez un seul sélecteur de plage :

```bash
healthmd --backend direct export --yesterday --raw --output yesterday.json
healthmd --backend direct export --last 7 --raw --output week.json
healthmd --backend direct export \
  --from 2026-07-01 --to 2026-07-07 --raw --output range.json
healthmd --backend direct export --all --raw --output complete-health-corpus.json
```

Omettez `--output` pour diffuser le JSON validé vers stdout. Un fichier de sortie est plus sûr pour les réponses sensibles ou volumineuses.

L’export brut strict iPhone renvoie `healthmd.raw_result` v1 contenant des journées ordinaires `healthmd.health_data` au schéma v8 et leurs archives sources canoniques. Il demande temporairement le détail sans perte sans modifier les réglages iPhone enregistrés. La CLI valide les dates exactes, le profil, le schéma, l’archive, les manifestes, la chaîne d’empreintes, l’empreinte finale du corps et l’état d’achèvement avant d’exposer le résultat.

Une journée complète-vide est réussie. Les données demandées manquantes, partielles, échouées, annulées, non prises en charge ou ignorées produisent `partial_success` et une sortie non nulle, sauf si `--allow-partial` est explicite.

## Export brut natif du fournisseur (Android)

Le client Rust portable est direct par défaut ; les commandes brutes Android omettent donc l’indicateur `--backend` :

```bash
healthmd export --last 7 --raw --provider health_connect \
  --raw-format ndjson --output health-connect.ndjson
```

`--provider` désigne un fournisseur explicite unique et vaut `health_connect` par défaut. `--raw-format` vaut NDJSON par défaut, la forme recommandée pour les instantanés volumineux ; la validation JSON en mémoire est plafonnée à 64 Mio. La sélection de métriques prend en charge `--metric` et `--all-metrics`, mais pas les sélecteurs canoniques ou de fichiers générés — ceux-ci restent des capacités iPhone.

Les instantanés bruts Android conservent leur contrat natif Health Connect du fournisseur. Ils ne sont jamais convertis en journées `healthmd.health_data` façon HealthKit, et les statistiques liées mais différentes conservent leurs propres identités.

## Extraction canonique

L’extraction directe utilise le même transport brut persistant, mais renvoie des données structurées comme la source sélectionnée au lieu de l’enveloppe de transport. C’est une capacité iPhone :

```bash
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json

healthmd --backend direct extract \
  --metric workouts --last 14 --object records \
  --detail lossless --output workout-records.json
```

La sélection de métrique, catégorie, source et détail atteint l’iPhone avant les lectures HealthKit. Consultez [Extraction canonique](/fr/docs/cli-extract/) pour les sélecteurs d’objets, JSON Pointers, JSONL et reçus.

Tant que l’app reste au premier plan, une session directe approuvée peut se reconnecter automatiquement après une coupure transitoire, avec un nombre et des délais bornés. Cela ne réveille pas une app en arrière-plan et n’en promet pas l’accès ; rouvrez Health.md avant de reprendre.

## Fichiers générés en production

Le mode fichier direct demande au téléphone d’exécuter les exportateurs de production de Health.md, puis transfère les fichiers résultants vers une destination explicite sur l’ordinateur.

```bash
mkdir -p "$HOME/Documents/HealthVault"

healthmd --backend direct export --yesterday \
  --destination "$HOME/Documents/HealthVault"

healthmd --backend direct export --last 7 \
  --category Sleep --detail summary \
  --destination "$HOME/Documents/HealthVault"

healthmd --backend direct export --yesterday --use-iphone-settings \
  --destination "$HOME/Documents/HealthVault"
```

La destination doit déjà exister, être absolue et ne pas se résoudre via un lien symbolique. Le mode direct ne devine jamais et n’utilise jamais de signet de l’app Mac. `--output` sert à la sortie brute ou d’extraction ; `--destination` sert aux fichiers générés.

Par défaut, une requête conserve les formats enregistrés, le sous-dossier Health, les noms de fichiers, les modèles, le mode d’écriture, Daily Note Injection et Daily Notes Only. Elle supprime les roll-ups et le mode résumé seul pour cette tâche. Les options répétables `--metric` ou `--category`, plus `--detail`, remplacent uniquement la portée des métriques et du détail de la tâche. `--use-iphone-settings` reflète tous les réglages enregistrés et ne peut pas être combiné avec des sélecteurs.

L’iPhone peut préparer JSON, CSV, Markdown, ZIP, dictionnaires de données, agrégations, enregistrements individuels, notes quotidiennes et fichiers annexes de fournisseurs. La CLI valide chaque chemin relatif, nombre d’octets, empreinte et manifeste de fichiers, identité de destination et empreinte de requête avant validation. Elle rejette les traversées, les ancêtres sous forme de liens symboliques, les mutations de racine, les collisions de chemins et les changements d’empreinte. L’écrasement est atomique. L’ajout et la fusion Markdown utilisent des plans persistés afin qu’une relecture ne duplique pas le contenu.

Les destinations de fichiers générés fonctionnent avec le protocole iPhone v1 comme avec le protocole Android v2 sur tous les systèmes d’exploitation de la CLI — macOS, Linux et Windows. Android limite chaque tâche à 4 096 fichiers.

Les tâches de fichiers du protocole Android v2 tirent leurs réglages de sortie des sélections enregistrées sur l’appareil ou de `--profile PROFILE_ID` ; les sélecteurs CLI de métrique, de catégorie et de détail sont rejetés. Sur les deux plateformes de téléphone, `--profile` résout des réglages de sortie figés, tandis que le paramètre `--destination` obligatoire continue de désigner le dossier explicite sur l’ordinateur.
Pour les identifiants stables et l’échec sûr, voir [Profils d’exportation](/fr/docs/export-profiles/).

## Comportement au premier plan et en arrière-plan

Le jumelage et les nouveaux travaux exigent que l’app du téléphone soit au premier plan. Direct CLI Access ne transforme pas le téléphone en serveur d’export sans interface et ne peut pas réveiller l’app à la demande.

Sur l’iPhone, si un export est déjà connecté lorsque l’app passe en arrière-plan, Health.md demande un temps d’exécution iOS en arrière-plan limité. L’export peut se terminer pendant cette allocation. Si iOS l’expire, la connexion se ferme et la tâche persistante se met en pause. Rouvrez Health.md et reprenez la même tâche.

Sur Android, une session directe active exécute un service de premier plan de synchronisation de données, visible et démarré par l’utilisateur. Gardez l’app au premier plan pour le jumelage et les nouveaux travaux.

Sur l’iPhone, une bannière d’activité globale pendant le travail direct comprend la phase de capture et de transfert, les jours terminés, la progression en octets et l’état en pause ou terminé, sans afficher de valeurs de santé.

Tant que l’application du téléphone reste au premier plan, une session directe approuvée peut se reconnecter automatiquement après une coupure passagère. Les nouvelles tentatives utilisent des délais croissants plafonnés à une courte durée. Cela ne réveille pas une application en arrière-plan et n’en garantit pas l’accès ; rouvrez Health.md avant de reprendre si elle n’est plus au premier plan.

## Reprise d’une tâche persistante et annulation

Les tâches directes expirent sept jours après leur création. Délai d’expiration, Ctrl-C, mort du processus, déconnexion et expiration en arrière-plan ne les annulent pas.

```bash
healthmd --backend direct status --job JOB_UUID
healthmd --backend direct resume JOB_UUID --timeout 300 --output recovered.json
healthmd --backend direct cancel JOB_UUID
```

La reprise conserve les dates, réglages, destination, empreinte de requête, appareil et limite de partition d’origine. Vous ne pouvez pas pointer une tâche fichier vers une autre destination lors de la reprise.

La commande d’annulation enregistre une requête persistante, mais l’annulation ne devient définitive qu’après accusé de réception par l’iPhone. Si l’iPhone est indisponible, l’état reste `cancellation_pending`. Rouvrez le même iPhone et renouvelez la demande d’annulation.

## Modèle de sécurité

- Le jumelage utilise un accord de clés éphémère et des preuves de transcription liés au code de jumelage de la plateforme — le flux iPhone à six chiffres ou le code unique Android distinct à haute entropie de 20 chiffres (~66 bits).
- La reconnexion prouve un secret aléatoire stocké et les deux identités d’installation.
- Chaque connexion dérive de nouvelles clés et de nouveaux nonces.
- Les messages et trames binaires utilisent ChaCha20-Poly1305 avec des contrôles de séquence monotones.
- Les partitions utilisent des manifestes SHA-256 et une chaîne d’empreintes entre les partitions.
- La confiance iPhone est stockée dans Keychain ; la confiance de reconnexion Android s’appuie sur le Keystore.
- La confiance portable utilise Keychain, Secret Service ou Windows Credential Manager et ne retombe jamais sur du texte brut.
- Les spools et journaux utilisent le stockage privé de l’application et excluent les sauvegardes lorsque la plateforme le permet.

Manual IP reste chiffré sur un réseau local ou Tailscale. Tailscale protège aussi le chemin réseau, mais ne remplace pas l’authentification applicative de Health.md.

## Erreurs courantes

| Erreur | Action |
|---|---|
| `direct_not_paired` | Jumelez cette installation CLI avec l’iPhone. |
| `direct_device_selection_required` | Passez le `--device` de confiance voulu. |
| `direct_trust_invalid` | Conservez les diagnostics. Réinitialisez la confiance uniquement si la récupération est impossible. |
| `direct_iphone_unavailable` | Vérifiez l’état au premier plan de l’app, le commutateur d’accès, l’adresse, le port, l’autorisation et la joignabilité LAN ou Tailscale. |
| `direct_export_paused` | Inspectez la tâche, rouvrez l’iPhone et reprenez-la. |
| `direct_cancellation_pending` | Rouvrez l’iPhone jumelé et renouvelez la demande d’annulation. |
| `transport_unsupported` | Utilisez Manual IP ou Tailscale dans le client portable. |
| `backend_unsupported` | Utilisez le back-end de l’app Mac pour query, evidence, doctor, metrics ou MCP. |
| `invalid_direct_raw_response` | Ne consommez pas la sortie. Conservez les diagnostics de validation. |
| `invalid_direct_file_receipt` | Ne réparez pas les fichiers manuellement. Inspectez et reprenez la tâche. |
| `job_expired` | La durée de vie de sept jours de l’état est terminée. Confirmez avant de commencer un nouveau travail. |

## Pages associées

<div class="related">
  <a href="/fr/docs/cli/"><span>Vue d’ensemble</span>CLI Health.md : installez les utilitaires intégrés et choisissez le bon back-end.</a>
  <a href="/fr/docs/android/"><span>Android</span>Health.md pour Android : sources Health Connect, destinations de dossiers et automatisation sur l’appareil.</a>
  <a href="/fr/docs/cli-extract/"><span>Données</span>Extraction canonique : sélectionnez et émettez des données Health.md structurées comme la source (iPhone).</a>
  <a href="/fr/docs/cli-jobs/"><span>Fiabilité</span>Tâches persistantes et automatisation : reprise, annulation, résultats partiels et scripts.</a>
  <a href="/fr/docs/reference/connected-mac-iphone-protocol/"><span>Protocole</span>Référence Mac et iPhone connectés : capacités, transfert borné et états de résultat.</a>
</div>
