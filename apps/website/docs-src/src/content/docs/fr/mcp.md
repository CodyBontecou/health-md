---
title: "Serveur MCP et App Health.md"
description: "Utilisez Codex ou Claude pour lancer des analyses Apple Health à portée limitée, afficher des graphiques natifs et démarrer des exports Health.md persistants via une MCP App locale en bac à sable."
---

Health.md for Mac fournit un utilitaire stdio signé `healthmd-mcp`. Il permet à Codex, Claude et d’autres hôtes MCP d’interroger des données factuelles Apple Health, d’afficher des visualisations, d’actualiser le contexte local chiffré et de lancer des exports persistants approuvés via l’app Mac ouverte.

```text
Codex / Claude / another local MCP host
  <-> MCP JSON-RPC over stdio
  <-> signed healthmd-mcp helper
  <-> Health.md Mac loopback API on 127.0.0.1:17645
  <-> connected iPhone for fresh HealthKit reads and exports
```

<div class="availability available">
<strong>Disponible maintenant · Health.md for Mac</strong>
<p>Le serveur intégré expose 21 outils fixes. Il ne lit pas lui-même HealthKit, les dossiers d’export, les signets à portée de sécurité ni des fichiers arbitraires.</p>
</div>

<div class="availability preview">
<strong>Aperçu · MCP direct portable</strong>
<p>La topologie distincte à 19 outils <code>healthmd mcp serve</code> pour macOS, Linux et Windows est distribuée publiquement comme aperçu explicitement non qualifié. Son entrée sans cloud <code>serve-read-only</code> expose uniquement les 13 outils de préparation/requête après jumelage local. Installez sous macOS ou Linux avec <code>brew install CodyBontecou/tap/healthmd</code>.</p>
</div>

## Conditions pour la version Mac intégrée

- Health.md for Mac installée et ouverte.
- Health.md ouverte sur l’iPhone connecté lorsque l’outil d’actualisation ou un export démarre une nouvelle opération HealthKit.
- Un hôte MCP local avec prise en charge de stdio.
- Le chemin de l’utilitaire signé affiché sous **Health.md for Mac → CLI**.

Le chemin normal de l’utilitaire est `/Applications/Health.md.app/Contents/Helpers/healthmd-mcp`. Les versions principales du protocole MCP prises en charge sont `2024-11-05`, `2025-03-26`, `2025-06-18` et `2025-11-25`. Ne lancez pas `healthmd-mcp` comme une commande interactive ordinaire ; l’hôte MCP possède stdin et le cycle de vie du processus.

## Conditions du mode direct portable

- Installez l’aperçu autonome sur macOS, Linux ou Windows ; l’app Mac et son service en boucle locale ne sont pas requis.
- Associez une fois un iPhone compatible avec les requêtes et gardez Health.md au premier plan pour chaque nouvelle demande typée. Android ne prend pas en charge le MCP typé.
- Utilisez Manual IP ou Tailscale et le stockage natif des identifiants ; Linux exige un fournisseur Secret Service déverrouillé.
- Configurez le lanceur de compatibilité installé ou le serveur stdio du même binaire. Tous deux utilisent le backend direct associé.

## Configuration Codex

Ajoutez l’utilitaire intégré à `~/.codex/config.toml` :

```toml
[mcp_servers.healthmd]
command = "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
args = []
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_files]
approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_job_resume]
approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_job_cancel]
approval_mode = "prompt"
```

Redémarrez Codex, appelez `healthmd_doctor`, résolvez les ID avec `healthmd_metrics`, acquérez explicitement une petite portée exacte avec l’outil d’actualisation, puis interrogez cette portée avec `healthmd_metric_chart`. Les hôtes sans MCP Apps interactives reçoivent tout de même le JSON exact ainsi qu’un graphique PNG standard.

## Configuration Claude

Utilisez cette entrée stdio locale dans la configuration MCP de Claude Desktop ou dans un `.mcp.json` de confiance de Claude Code :

```json
{
  "mcpServers": {
    "healthmd": {
      "command": "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp",
      "args": []
    }
  }
}
```

Redémarrez Claude Desktop après avoir modifié sa configuration. Les configurations de projet Claude nécessitent la confiance accordée à l’espace de travail et l’approbation explicite du serveur.

Les versions de Claude Desktop qui annoncent l’extension MCP Apps stable affichent la vue interactive de Health.md en ligne. Claude Code et les autres clients orientés texte conservent les replis JSON et image.

## Aperçu MCP direct portable

Dans l’aperçu public autonome, `healthmd setup codex` jumelle un iPhone au premier plan et crée en sécurité une entrée `healthmd mcp serve` utilisant le même binaire. Cette topologie utilise un transport chiffré authentifié Manual IP ou Tailscale sur le port `17647`, le stockage natif des identifiants et des lectures iPhone explicites par requête. Linux nécessite en plus un fournisseur Secret Service déverrouillé ; Windows utilise Credential Manager.

Utilisez la préversion exacte `healthmd-cli/v<version>` plutôt que le pointeur vers la dernière version du dépôt entier. Consultez la [CLI iPhone directe](/fr/docs/cli-direct/) pour le contrat de jumelage et de transport explicitement non qualifié.

## Visualisations MCP App natives

Health.md implémente une négociation stable `io.modelcontextprotocol/ui` avec `text/html;profile=mcp-app`.

Après qu’un hôte annonce ce type MIME, le serveur expose :

- `ui://healthmd/query-visualization-v1` ;
- les méthodes standard `resources/list` et `resources/read` ;
- `_meta.ui.resourceUri` sur les outils d’analyse et de reçu d’export ;
- `structuredContent` validé avec le texte JSON exact.

La vue est une ressource HTML5 autonome, sans réseau, scripts distants, polices distantes, stockage ni frames imbriquées. Sa CSP déclarée contient des listes de domaines connect/resource/frame/base vides. Elle suit le cycle de vie standard initialize, tool-result, theme, resize, cancellation et teardown.

Elle peut afficher :

- des graphiques linéaires de métriques avec unités et lacunes explicites pour les données manquantes ;
- des comparaisons de périodes avec agrégation choisie par l’appelant ;
- des sessions de sommeil et des résumés de durée par phase ;
- des entraînements et le timing factuel entraînement/sommeil ;
- la couverture, les intervalles manquants, les preuves et les limites ;
- les reçus de parcours toutes pages ;
- la progression d’un export persistant, les destinations et les reçus de tâche.

Si l’hôte ne prend pas en charge MCP Apps, les outils fonctionnent quand même. `healthmd_metric_chart` ajoute du contenu `image/png` pour les hôtes capables d’afficher des images, tout en conservant le JSON complet sous forme de texte.

## Outils disponibles

Le serveur Mac intégré expose 21 outils fixes : 13 outils de préparation et de requête, quatre outils de tâche de fichiers générés et quatre outils de tâche d’actualisation du contexte chiffré. L’aperçu portable à 19 outils conserve les 13 outils de préparation/requête et les quatre outils d’export, remplace les tâches d’actualisation Mac par deux outils de jumelage direct et exécute les requêtes typées directement sur l’iPhone au premier plan.

### Préparation et découverte

| Outil | Objectif |
|---|---|
| `healthmd_status` | Vérifier l’état de préparation de l’app Mac, du contexte, de l’iPhone et de l’export |
| `healthmd_doctor` | Diagnostiquer l’utilitaire intégré et la topologie Mac en boucle locale |
| `healthmd_capabilities` | Lister les capacités de requête directe, preuve, export, schéma et pagination |
| `healthmd_metrics` | Lister les ID de métriques canoniques, catégories, unités et prérequis |

### Analyse et visualisation

| Outil | Objectif |
|---|---|
| `healthmd_metric_chart` | Interroger des séries de métriques et afficher des graphiques natifs avec couverture et unités |
| `healthmd_sleep_sessions` | Lister et visualiser des sessions de sommeil stables et la couverture physiologique |
| `healthmd_training_alignment` | Afficher le timing factuel des entraînements par rapport au sommeil précédent/suivant |
| `healthmd_workouts` | Lister et visualiser les entraînements |
| `healthmd_coverage` | Inspecter la couverture métrique/date et les données manquantes |
| `healthmd_compare_periods` | Comparer des périodes exactes avec des sémantiques d’agrégation explicites |
| `healthmd_training_evidence` | Créer un paquet de preuves factuel sur l’entraînement |
| `healthmd_query` | Envoyer une `healthmd.query_request` exacte et parcourir éventuellement les pages |
| `healthmd_evidence_packet` | Envoyer une requête de preuve exacte et parcourir éventuellement les pages |

### Exports de fichiers générés

| Outil | Objectif |
|---|---|
| `healthmd_export_files` | Lancer un export de fichiers persistant ; le Mac intégré utilise son dossier sélectionné, tandis que le MCP direct portable exige une destination explicite sur l’ordinateur |
| `healthmd_export_job_status` | Inspecter la progression d’export et le reçu de destination |
| `healthmd_export_job_resume` | Reprendre exactement la tâche persistante d’export, sans en modifier les paramètres |
| `healthmd_export_job_cancel` | Annuler explicitement la tâche d’export |

Les outils d’export, de reprise et d’annulation sont signalés comme des écritures potentiellement destructrices et exigent une interaction explicite sur les hôtes Claude actuels, car les modes d’export configurés peuvent mettre à jour ou écraser des fichiers générés. La configuration Codex ci-dessus demande une confirmation pour ces outils comme protection supplémentaire.

### Tâches d’acquisition de contexte chiffré · Mac intégré uniquement

| Outil | Objectif |
|---|---|
| `healthmd_refresh` | Acquérir une portée approuvée depuis l’iPhone dans un contexte Mac chiffré jetable |
| `healthmd_job_status` | Inspecter la progression d’actualisation sans lire de valeurs de santé |
| `healthmd_job_resume` | Reprendre la tâche d’actualisation acceptée exacte |
| `healthmd_job_cancel` | Annuler explicitement une tâche d’actualisation acceptée |

### Découvrir la forme complète des requêtes

MCP `tools/list` inclut le JSON Schema imbriqué complet pour les dates, métriques, sources, pagination, plages de
périodes, agrégations et la `healthmd.query_request` avancée. Les outils typés incluent aussi des exemples concrets.
Un agent doit appeler directement l’outil typé correspondant plutôt qu’inspecter l’aide shell générique. En particulier,
les questions sur le sommeil utilisent `healthmd_sleep_sessions` ; `healthmd extract` produit une projection canonique
différente de données sources.

L’aperçu portable permet d’inspecter localement le même schéma sans ouvrir d’écouteur réseau ni contacter l’iPhone. Pour l’utilitaire Mac publié, utilisez tools/list de MCP.

```bash
healthmd mcp schema healthmd_sleep_sessions
healthmd mcp schema healthmd_metric_chart
healthmd mcp schema # complete fixed catalog
```

Un appel sommeil minimal a cette forme (résolvez les dates inclusives pour la requête réelle) :

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-22",
      "end_date": "2026-07-28"
    }
  },
  "all_pages": true
}
```

Les métriques de sommeil canoniques et le détail de session sans perte sont fournis automatiquement par
`healthmd_sleep_sessions`.

## Analyser et représenter les données

Appelez d’abord `healthmd_doctor` et résolvez les ID de métriques avec `healthmd_metrics`. Dans la topologie Mac publiée, les outils de requête typés lisent le contexte Mac chiffré ; ils ne contactent pas implicitement l’iPhone. Pour obtenir des données actuelles, appelez l’outil d’actualisation avec des dates, métriques et sources explicites, attendez la fin de sa tâche persistante, puis représentez la même portée :

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-01",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps", "resting_heart_rate"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "all_pages": true
}
```

Passez cet objet à `healthmd_metric_chart`. La vue interactive utilise de petits graphiques multiples qui ne mélangent pas les unités. Un point manquant ou partiel interrompt la ligne au lieu de devenir zéro.

Les outils typés Mac publiés évaluent le contexte local chiffré et renvoient des pages bornées avec couverture, données manquantes, preuves et limites. Seule une actualisation explicite contacte l’iPhone connecté au premier plan et remplace la portée de contexte demandée. L’aperçu portable évalue chaque requête typée directement sur son iPhone jumelé au premier plan.

## Lancer un export de fichiers générés

Sélectionnez et conservez d’abord un dossier de destination accessible en écriture dans Health.md for Mac. Une fois que l’hôte affiche les arguments complets et que l’utilisateur approuve, appelez `healthmd_export_files` :

```json
{
  "date_selection": "explicit_range",
  "date_range": {
    "start": "2026-07-01",
    "end": "2026-07-07"
  },
  "settings_policy": "requested_dates_only",
  "categories": ["Sleep"],
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

Utilisez `date_selection: "all_available"` sans `date_range` pour l’historique complet. Les paramètres facultatifs `metric_ids`, `categories` ou `all_metrics` réduisent l’acquisition iPhone sans modifier les réglages enregistrés. `detail_level` s’applique uniquement lorsqu’une de ces sélections est présente. `all_metrics` ne peut pas être combiné avec des listes explicites de métriques/catégories.

Pour exécuter plutôt un profil enregistré, réglez `settings_policy` sur `"profile"` et passez `profile_reference` avec son UUID stable. Dans le protocole public, le `name` facultatif fournit un contexte d’affichage et d’erreur. Les implémentations actuelles du téléphone peuvent le consulter après l’échec de recherche de l’ID, mais ce comportement ne résiste pas aux changements de nom ; l’automatisation doit traiter l’UUID comme identité stable :

```json
{
  "date_selection": "explicit_range",
  "date_range": { "start": "2026-07-01", "end": "2026-07-07" },
  "settings_policy": "profile",
  "profile_reference": { "profileID": "11111111-2222-4333-8444-555555555555" }
}
```

Le profil possède la portée des réglages : `profile_reference` ne se combine pas avec `metric_ids`, `categories`, `all_metrics` ni avec la politique de réglages enregistrés, et une référence impossible à résoudre échoue avec une erreur typée au lieu de revenir aux réglages actifs.

Les exemples ci-dessus utilisent la destination du Mac intégré. Avec le MCP direct portable, chaque demande de fichiers exige aussi un dossier absolu existant sur l’ordinateur dans `destination` ; le profil du téléphone fournit les réglages de sortie, pas ce chemin hôte :

```json
{
  "date_selection": "explicit_range",
  "date_range": { "start": "2026-07-01", "end": "2026-07-07" },
  "settings_policy": "profile",
  "profile_reference": { "profileID": "11111111-2222-4333-8444-555555555555" },
  "destination": "/absolute/existing/HealthVault",
  "wait_timeout_seconds": 300
}
```

Le mode direct portable rejette une destination absente, relative, inexistante ou symbolique avant de lancer la tâche sur le téléphone.

Inspectez :

- `status` et le `state` de la tâche persistante ;
- `job_id` ;
- les jours traités/totaux et la progression ;
- les fichiers ou Daily Notes écrits ;
- la destination validée sur l’ordinateur ;
- les partitions et octets validés ;
- la raison de pause/échec et l’expiration.

Un délai d’expiration ou la fin d’une attente MCP n’annule pas la tâche persistante. Vérifiez `healthmd_export_job_status` avant de reprendre après un résultat inconnu. Seule une demande d’annulation explicite met fin à la tâche.

Le transport brut et source canonique peut contenir des gigaoctets d’itinéraires, de texte clinique, de pièces jointes et d’enregistrements sources. Health.md ne place délibérément pas ces corps dans une conversation MCP. Utilisez la CLI de streaming validée pour une sortie structurée comme la source :

```bash
healthmd extract --metric workouts --last 30 --detail lossless --output workouts.json
healthmd export --iphone --all --raw --output health-corpus.json
```

L’analyse MCP reste une vue factuelle dérivée ; les exports de fichiers générés continuent d’utiliser le contrat public `healthmd.health_data` via les exportateurs de production.

## Pagination et exhaustivité

Les outils de requête/preuve exposent `all_pages: true` lorsqu’il est pris en charge. L’utilitaire suit des curseurs opaques avec détection de cycles et plafonds globaux d’octets/pages, en conservant chaque réponse versionnée sous `healthmd.mcp_query_pages` v1. Si un plafond de parcours automatique est atteint, l’enveloppe partielle réussie fixe `receipt.traversal_complete` à `false` et renvoie le `receipt.next_cursor` exact pour une continuation sans perte. L’iPhone conserve un instantané compact paginé pendant dix minutes d’inactivité au premier plan et l’efface lors d’un parcours terminal ou d’un passage en arrière-plan. Une requête possède une garde de contexte compact encodé de 366,000 jours et 64 MiB ; `query_scope_too_large` signifie qu’il faut répartir les dates ou les ID de métriques entre plusieurs appels, pas que l’historique logique est indisponible. Les pages bornent les listes d’intervalles manquants et de descripteurs de sources avec des champs explicites de nombre/troncature et de limites.

La réussite du transport n’est pas l’exhaustivité. Inspectez toujours :

- l’état de la portée demandée et du corpus ;
- la couverture et les intervalles manquants ;
- les limites et les preuves ;
- `next_cursor` ou le reçu de parcours ;
- les omissions sans rapport ;
- le schéma source et sa version.

La MCP App affiche ces champs au lieu de les masquer. Si le parcours automatique atteint son plafond de sécurité, réduisez la portée ou continuez manuellement.

## Limites de sécurité et de confidentialité

L’utilitaire ne propose ni invites, ni racines, ni échantillonnage, ni shell, ni SQL, ni lecture arbitraire de fichiers, ni récupération d’URL arbitraires, ni écritures HealthKit, ni service HTTP en boucle locale, ni point de terminaison MCP distant. Sa seule ressource MCP est le document App intégré. Les écritures de fichiers générés sont une opération fixe soumise à approbation. L’utilitaire Mac publié utilise le dossier sélectionné dans Health.md for Mac ; l’aperçu portable exige une destination existante explicite qu’il valide et lie durablement avant le transfert.

La confiance directe est stockée dans Keychain, Secret Service ou Windows Credential Manager. Le jumelage utilise le protocole chiffré authentifié existant ; l’iPhone doit être au premier plan et explicitement connecté à l’adresse LAN ou Tailscale de l’ordinateur. Les pages de requête sont bornées aux limites d’octets/d’éléments négociées, et l’agrégation automatique de toutes les pages possède des plafonds d’octets/pages supplémentaires. Les corps bruts non bornés restent sur le chemin CLI de streaming validé.

Health.md rapporte des observations factuelles avec unités, provenance, couverture et données manquantes. Il ne diagnostique pas, ne recommande pas de traitement, n’infère pas de causalité et ne qualifie pas une direction de meilleure ou pire.

## Dépannage

| Symptôme | Action |
|---|---|
| L’hôte ne peut pas démarrer l’utilitaire | Utilisez le chemin absolu installé `healthmd` ou `.exe` avec les arguments `mcp serve` |
| L’utilitaire attend lorsqu’il est lancé dans Terminal | Attendu ; un hôte MCP doit envoyer du JSON-RPC sur stdin |
| `healthmd_not_paired` | Exécutez `healthmd direct pair` et terminez le jumelage sur l’iPhone |
| `healthmd_unavailable` | Déverrouillez Health.md et placez-la au premier plan sur l’iPhone, activez Direct CLI Access et connectez-vous à l’ordinateur |
| `query_scope_too_large` | Répartissez les dates ou ID de métriques entre plusieurs appels ; le corpus logique reste disponible entre requêtes |
| Aucun graphique interactif | Mettez à jour l’hôte ; le serveur renvoie toujours le JSON exact et un repli PNG de graphique métrique |
| Destination d’export indisponible | Mac : resélectionnez le dossier enregistré dans Health.md. Aperçu portable : créez et passez un répertoire existant sur l’ordinateur, absolu et sans lien symbolique. |
| L’attente d’export expire | Inspectez la tâche persistante d’export par ID avant de reprendre |
| Le résultat contient `next_cursor` | Définissez `all_pages: true` ou continuez le curseur manuellement |

## Pages associées

<div class="related">
  <a href="/fr/docs/agents/"><span>Architecture</span>Agents locaux, contexte chiffré, portée de requête et preuves.</a>
  <a href="/fr/docs/agent-queries/"><span>Analyse</span>Recettes de requêtes typées pour les métriques, le sommeil, les entraînements, la comparaison et la couverture.</a>
  <a href="/fr/docs/cli-extract/"><span>Données sources</span>Extraction canonique validée pour les grands résultats structurés comme la source.</a>
  <a href="/fr/docs/reference/evidence-packets/"><span>Contrats</span>Valeurs typées, données manquantes, preuves et identités de paquets.</a>
</div>
