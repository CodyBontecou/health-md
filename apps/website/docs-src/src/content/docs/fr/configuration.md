---
title: Configurer votre agent
description: Choisissez l’interface MCP ou CLI de Health.md, configurez Codex, Claude ou un autre client local, puis connectez un iPhone jumelé sans faire transiter HealthKit par un service cloud.
---

L’application Mac publiée comprend deux utilitaires locaux signés : `healthmd-mcp` pour les outils d’agent typés et `healthmd` pour les flux de travail CLI explicites. La CLI multiplateforme distincte avec MCP direct pour iPhone est distribuée publiquement comme aperçu explicitement non qualifié ; les tests de publication sur appareils physiques restent obligatoires pour la première version stable.

<div class="callout">
<strong>HealthKit reste sur l’iPhone.</strong>
<p style="margin-top:6px;">La configuration permet à un client local d’accéder aux interfaces à portée limitée de Health.md. Elle ne donne pas à l’ordinateur ou à l’agent un accès direct à HealthKit et ne téléverse pas votre base de données source vers un cloud Health.md.</p>
</div>

## Choisissez une interface

| Objectif | Commencez avec | Poursuivez avec |
|---|---|---|
| Permettre à Codex ou Claude d’interroger et de représenter graphiquement les données de santé sur Mac | `healthmd-mcp` intégré sur stdio | [Serveur MCP et outils](/fr/docs/mcp/) |
| Exporter du JSON canonique ou des fichiers générés dans un script Mac | CLI `healthmd` intégrée | [CLI](/fr/docs/cli/) |
| Se connecter directement à un iPhone ouvert sans l’application Mac | CLI directe portable (**aperçu**) | [Accès direct à l’iPhone](/fr/docs/cli-direct/) |
| Développer à partir d’enveloppes de requête et de réponse exactes | API en boucle locale ou contrats publics | [API en boucle locale](/fr/docs/agent-api/) |
| Analyser des schémas, des enregistrements, des preuves ou des fixtures générées | Référence versionnée | [Contrats de données](/fr/docs/reference/) |

Les choix de back-end et de transport sont explicites ; Health.md ne bascule pas silencieusement de l’accès direct à l’iPhone vers l’application Mac.

## Codex avec l’application Mac

<div class="availability available">
<strong>Disponible maintenant · utilitaire Mac signé</strong>
<p>Installez Health.md for Mac, ouvrez son écran <strong>CLI</strong> et copiez le chemin MCP intégré affiché si l’application ne se trouve pas dans <code>/Applications</code>.</p>
</div>

Ajoutez l’utilitaire signé distinct `healthmd-mcp` à `~/.codex/config.toml` :

```toml
[mcp_servers.healthmd]
command = "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
args = []
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"
```

Redémarrez Codex, appelez `healthmd_doctor`, résolvez les ID avec `healthmd_metrics`, acquérez explicitement une petite portée avec l’outil d’actualisation, puis interrogez-la avec un outil typé tel que `healthmd_metric_chart`. Le serveur intégré expose 21 outils, notamment pour vérifier l’état du Mac, gérer les tâches d’actualisation du contexte chiffré, fournir des preuves et créer des visualisations.

## Claude Desktop ou Claude Code sur Mac

Ajoutez l’utilitaire intégré à la configuration MCP de Claude Desktop ou à un fichier `.mcp.json` de confiance de Claude Code :

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

Redémarrez le client après avoir modifié sa configuration. Pour les configurations limitées au projet, vous devez toujours approuver explicitement l’espace de travail et le serveur. Gardez les applications Mac et iPhone ouvertes lorsqu’un outil a besoin de données HealthKit récentes.

## Tout client MCP stdio sur Mac

Configurez un seul processus local :

```text
command: /Applications/Health.md.app/Contents/Helpers/healthmd-mcp
arguments: none
transport: stdio
```

L’hôte contrôle l’entrée standard et le cycle de vie du processus. Ne lancez pas l’utilitaire comme une commande interactive ordinaire et ne l’enveloppez pas dans un shell qui modifie la sortie JSON-RPC. Utilisez `tools/list` de MCP pour découvrir les schémas exacts exposés par l’application installée.

## Configuration directe portable

<div class="availability preview">
<strong>Aperçu public · pas encore qualifié comme stable</strong>
<p>La CLI Rust multiplateforme, <code>healthmd setup codex</code>, le serveur <code>healthmd mcp serve</code> dans le même binaire et le jumelage direct sous Linux/Windows sont distribués publiquement comme aperçu explicitement non qualifié.</p>
</div>

Sous macOS ou Linux, installez avec <code>brew install CodyBontecou/tap/healthmd</code>. Ensuite, `healthmd setup codex` configure Codex de manière idempotente et lance le jumelage direct avec l’iPhone. Utilisez le build mobile exact indiqué par les preuves de publication ; publier le paquet ne prouve pas la compatibilité mobile. La page [CLI directe pour iPhone](/fr/docs/cli-direct/) décrit le transport et le protocole.

## Flux de travail CLI explicites

Pour une extraction canonique ou une automatisation axée sur les fichiers, invoquez directement `healthmd` au lieu de demander à un hôte MCP de transporter un corps source volumineux :

```bash
healthmd status
healthmd extract --category Sleep --last 7 --output sleep.json
healthmd export --last 7 --destination "$HOME/Documents/HealthVault"
```

La disponibilité et la grammaire diffèrent entre l’utilitaire Mac intégré et la CLI multiplateforme autonome. Consultez [Health.md CLI](/fr/docs/cli/) avant de copier des commandes dans une automatisation sans surveillance.

## Jumelage portable et vérification de l’état

<div class="availability preview">
<strong>Aperçu · flux de travail directs portables</strong>
<p>Il s’agit des flux portables actuellement proposés dans le paquet public. Le parcours MCP Mac intégré continue d’utiliser la connexion existante de l’app Mac à l’iPhone.</p>
</div>

Les flux de travail directs MCP et CLI nécessitent un jumelage unique avec un appareil de confiance dans Health.md sur iPhone. Le jumelage utilise un canal chiffré authentifié et le stockage natif des identifiants sous macOS, Linux ou Windows.

1. Activez **Accès Direct CLI** dans Health.md sur l’iPhone.
2. Lancez le jumelage depuis `healthmd setup codex` ou `healthmd direct pair`.
3. Approuvez la demande de jumelage à portée limitée sur l’iPhone.
4. Gardez Health.md au premier plan au démarrage d’une requête ou d’un export.
5. Appelez `healthmd_doctor` dans MCP ou `healthmd status` dans la CLI portable avant une opération plus importante.

Consultez [Accès direct à l’iPhone](/fr/docs/cli-direct/) pour en savoir plus sur Manual IP, Tailscale, le port, les appareils de confiance, l’exécution au premier plan et la récupération.

## Limites de la configuration

La configuration d’un agent local **n’accorde pas** :

- de lectures ou écritures HealthKit arbitraires ;
- d’accès arbitraire au système de fichiers ;
- d’URL, de commandes shell, d’invites, de racines ou d’échantillonnage arbitraires par MCP ;
- l’autorisation de masquer les données manquantes, la couverture, les unités, les preuves ou les limites ;
- l’autorisation de reprendre, d’annuler ou d’écraser les fichiers générés sans l’approbation requise.

Pour obtenir un résultat complet, examinez la portée demandée, la couverture, la pagination, les limites et le schéma source, et pas seulement la réussite du processus.

## Poursuivre

<div class="related">
  <a href="/fr/docs/mcp/"><span>Interface des outils</span>Découvrez les 21 outils Mac publiés, l’aperçu portable à 19 outils, MCP Apps, les schémas, la pagination, les exports et les limites du bac à sable.</a>
  <a href="/fr/docs/agent-queries/"><span>Premières questions</span>Exécutez des flux de travail typés pour les métriques, le sommeil, les entraînements, les comparaisons, la couverture et les preuves.</a>
  <a href="/fr/docs/cli-extract/"><span>Données canoniques</span>Extrayez des documents sélectionnés au schéma v8 et des enregistrements sources sans placer de corps volumineux dans la discussion.</a>
  <a href="/fr/docs/reference/"><span>Contrats</span>Parcourez les structures de données versionnées, les inventaires de champs, les fixtures générées et les recettes d’intégration.</a>
</div>
