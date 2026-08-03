---
title: "CLI iPhone directe"
description: "Jumelez healthmd avec un iPhone via Manual IP, Tailscale ou un transport Nearby pris en charge, puis exportez sans exécuter Health.md for Mac."
---

Le back-end direct connecte `healthmd` à Health.md for iPhone, qui doit être ouverte, sans faire passer la commande par Health.md for Mac. L’iPhone lit HealthKit, prépare le résultat dans un stockage protégé et transfère des partitions validées vers la CLI.

```text
healthmd on the computer
  <-> authenticated encrypted Manual IP, Tailscale, or supported Nearby channel
Health.md on iPhone -> HealthKit -> protected bounded spool / typed query evaluator
  -> canonical JSON, production-generated files, or bounded MCP query pages
```

<div class="availability preview">
<strong>Aperçu · CLI directe portable</strong>
<p>Le back-end Swift direct intégré est disponible sur macOS. Le client Rust multiplateforme est une alpha qui attend les tests QA de publication sur iPhone physique et son premier paquet public ; les commandes Linux et Windows décrivent le flux de travail préparé.</p>
</div>

## Ce que le mode direct prend en charge

- le jumelage unique et la reconnexion de confiance ;
- l’inspection locale des appareils de confiance et la suppression du jumelage ;
- l’état de préparation iPhone en direct ;
- l’export brut strict au schéma v7 ;
- l’extraction canonique sélectionnée ;
- l’export de fichiers générés en production ;
- l’état et la reprise des tâches locales persistantes ;
- l’annulation explicite ;
- le serveur stdio `healthmd mcp serve` dans le même exécutable, avec requêtes typées directes, catalogue de métriques, preuves, interface MCP Apps et repli PNG.

Le back-end direct de la commande `healthmd` n’émule pas les routes HTTP de contexte chiffré de l’app Mac ; les sous-commandes orientées Mac `doctor`, query, evidence et refresh renvoient donc toujours `backend_unsupported` au lieu de changer de back-end. Utilisez `healthmd mcp serve` pour une analyse typée à partir de données actualisées provenant directement de l’iPhone, ou exécutez `healthmd setup codex` pour configurer et jumeler Codex automatiquement. `healthmd mcp schema [TOOL]` affiche localement le schéma d’entrée MCP imbriqué exact et des exemples ; utilisez directement `healthmd_sleep_sessions` pour le sommeil au lieu de traiter la sortie canonique de `extract` comme l’API de requête typée.

## Prérequis

- Un binaire `healthmd` compatible direct et une version Health.md iPhone correspondante.
- Health.md ouverte au premier plan sur un iPhone pour le jumelage et les nouvelles commandes.
- **Settings > Mac Sync > Direct CLI Access** activé sur l’iPhone.
- Autorisation HealthKit, données protégées, autorisation réseau local et quota d’export disponibles.
- Une adresse d’ordinateur joignable et le port TCP `17647` pour Manual IP. Une adresse Tailscale fonctionne.
- Une destination absolue existante pour le mode fichiers générés.

La CLI est l’écouteur. L’iPhone se connecte à l’adresse de l’ordinateur saisie dans Direct CLI Access.

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

La commande écrit un code à six chiffres, des adresses candidates pour l’ordinateur et le port de l’écouteur sur stderr, tout en réservant stdout au résultat JSON final.

Sur l’iPhone :

1. Ouvrez **Health.md > Settings > Mac Sync > Direct CLI Access**.
2. Activez Direct CLI Access.
3. Sélectionnez **Manual IP**.
4. Saisissez l’adresse LAN ou Tailscale de l’ordinateur.
5. Saisissez le port `17647`, sauf si la CLI utilise un autre `--port` global.
6. Saisissez le code de jumelage et touchez Pair.
7. Gardez l’app ouverte jusqu’à ce que les deux côtés indiquent la réussite.

Les codes de jumelage expirent au bout de 10 minutes. Ils ne sont jamais envoyés sur le réseau ni conservés.

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

Ces commandes lisent ou modifient la confiance locale et ne contactent pas l’iPhone. Sur l’iPhone, utilisez **Forget Paired CLI** pour supprimer l’autre côté.

Lorsque plusieurs iPhone sont de confiance, sélectionnez explicitement l’installation voulue :

```bash
healthmd --backend direct --device DEVICE_UUID status
```

Utilisez `healthmd direct reset-trust --confirm` uniquement lorsque la confiance locale est corrompue ou appartient à une installation remplacée. Cette commande supprime tous les jumelages directs locaux. Oubliez ces jumelages sur l’iPhone avant de recommencer.

## Vérifier l’état de préparation en direct

```bash
healthmd --backend direct --transport manual-ip status
```

Une réponse d’état direct indique l’état de connexion et de sécurité sans valeurs de santé. Vérifiez ces champs avant de commencer :

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

## Export brut strict

Choisissez un seul sélecteur de plage :

```bash
healthmd --backend direct export --yesterday --raw --output yesterday.json
healthmd --backend direct export --last 7 --raw --output week.json
healthmd --backend direct export \
  --from 2026-07-01 --to 2026-07-07 --raw --output range.json
healthmd --backend direct export --all --raw --output complete-health-corpus.json
```

Omettez `--output` pour diffuser le JSON validé vers stdout. Un fichier de sortie est plus sûr pour les réponses sensibles ou volumineuses.

L’export brut strict renvoie `healthmd.raw_result` v1 contenant des journées ordinaires `healthmd.health_data` au schéma v7 et leurs archives sources canoniques. Il demande temporairement le détail sans perte sans modifier les réglages iPhone enregistrés. La CLI valide les dates exactes, le profil, le schéma, l’archive, les manifestes, la chaîne d’empreintes, l’empreinte finale du corps et l’état d’achèvement avant d’exposer le résultat.

Une journée complète-vide est réussie. Les données demandées manquantes, partielles, échouées, annulées, non prises en charge ou ignorées produisent `partial_success` et une sortie non nulle, sauf si `--allow-partial` est explicite.

## Extraction canonique

L’extraction directe utilise le même transport brut persistant, mais renvoie des données structurées comme la source sélectionnée au lieu de l’enveloppe de transport :

```bash
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json

healthmd --backend direct extract \
  --metric workouts --last 14 --object records \
  --detail lossless --output workout-records.json
```

La sélection de métrique, catégorie, source et détail atteint l’iPhone avant les lectures HealthKit. Consultez [Extraction canonique](/fr/docs/cli-extract/) pour les sélecteurs d’objets, JSON Pointers, JSONL et reçus.

## Fichiers générés en production

Le mode fichier direct demande à l’iPhone d’exécuter les exportateurs de production de Health.md, puis transfère les fichiers résultants vers une destination explicite sur l’ordinateur.

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

Les destinations de fichiers générés fonctionnent sur macOS et Linux. Protocol v1 les rejette sur Windows. Les utilisateurs Windows en direct peuvent utiliser l’export brut et l’extraction.

## Comportement au premier plan et en arrière-plan

Le jumelage et les nouveaux travaux exigent que l’app iPhone soit au premier plan. Direct CLI Access ne transforme pas iOS en serveur d’export sans interface et ne peut pas réveiller l’app à la demande.

Si un export est déjà connecté lorsque l’app passe en arrière-plan, Health.md demande un temps d’exécution iOS en arrière-plan limité. L’export peut se terminer pendant cette allocation. Si iOS l’expire, la connexion se ferme et la tâche persistante se met en pause. Rouvrez Health.md et reprenez la même tâche.

L’iPhone affiche une bannière d’activité globale pendant le travail direct. Elle comprend la phase de capture et de transfert, les jours terminés, la progression en octets et l’état en pause ou terminé, sans afficher de valeurs de santé.

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

- Le jumelage utilise un accord de clés Curve25519 éphémère et des preuves de transcription liées au code à six chiffres.
- La reconnexion prouve un secret aléatoire stocké et les deux identités d’installation.
- Chaque connexion dérive de nouvelles clés et de nouveaux nonces.
- Les messages et trames binaires utilisent ChaCha20-Poly1305 avec des contrôles de séquence monotones.
- Les partitions utilisent des manifestes SHA-256 et une chaîne d’empreintes entre les partitions.
- La confiance iPhone est stockée dans Keychain.
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
  <a href="/fr/docs/cli-extract/"><span>Données</span>Extraction canonique : sélectionnez et émettez des données Health.md structurées comme la source.</a>
  <a href="/fr/docs/cli-jobs/"><span>Fiabilité</span>Tâches persistantes et automatisation : reprise, annulation, résultats partiels et scripts.</a>
  <a href="/fr/docs/reference/connected-mac-iphone-protocol/"><span>Protocole</span>Référence Mac et iPhone connectés : capacités, transfert borné et états de résultat.</a>
</div>
