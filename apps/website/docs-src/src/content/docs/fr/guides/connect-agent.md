---
title: "Connecter un agent en 10 minutes"
description: "Connectez l’utilitaire MCP Mac Health.md publié à Codex ou Claude, acquérez une portée explicite depuis l’iPhone, exécutez une requête bornée et vérifiez la complétude en toute sécurité."
---

<div class="availability available">
<strong>Disponible maintenant · Health.md for Mac</strong>
<p>Ce parcours utilise l’utilitaire <code>healthmd-mcp</code> signé fourni avec l’app Mac publiée. Il n’utilise ni l’aperçu portable de la CLI, ni Direct CLI Access, ni un code QR de jumelage, ni le port 17647.</p>
</div>

Vous allez connecter un hôte MCP local, vérifier la préparation sans lire de valeurs de santé, actualiser explicitement une petite portée depuis l’iPhone, puis interroger ce contexte Mac chiffré. Prévoyez une dizaine de minutes lorsque les deux apps sont déjà installées et sur le même réseau local.

## 1. Installer et ouvrir Health.md

[Téléchargez Health.md sur l’App Store](https://apps.apple.com/us/app/health-md/id6757763969) sur le Mac et sur l’iPhone. Ouvrez les deux apps.

HealthKit reste sur l’iPhone. L’app Mac héberge l’utilitaire MCP signé et un contexte de requête chiffré et jetable ; elle ne lit pas HealthKit directement.

## 2. Connecter l’iPhone et le Mac

1. Sur le Mac, laissez Health.md ouvert.
2. Sur l’iPhone, ouvrez **Health.md → Synchronisation** et activez la connectivité Mac.
3. Gardez les deux appareils sur le même réseau local accessible et laissez Health.md au premier plan sur l’iPhone pendant le démarrage d’un travail nouveau.
4. Confirmez que l’app Mac affiche la connexion iPhone voulue. Sinon, rouvrez les deux apps et consultez la [préparation de la synchronisation Mac](/fr/docs/sync/).

C’est la connexion Mac publiée. N’exécutez pas `healthmd direct pair` ; cette commande appartient à l’aperçu portable distinct.

## 3. Copier le chemin de l’utilitaire signé

Ouvrez **Health.md for Mac → CLI** et copiez le chemin de l’utilitaire MCP affiché. Une installation normale dans `/Applications` utilise :

```text
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

Utilisez le chemin affiché si l’app est installée ailleurs. Configurez l’utilitaire directement : ne l’enveloppez pas dans un shell et ne le lancez pas comme une commande interactive.

## 4. Configurer Codex ou Claude

### Codex

Ajoutez ceci à `~/.codex/config.toml`, en remplaçant le chemin de l’utilitaire si nécessaire :

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

Redémarrez Codex après avoir enregistré le fichier.

### Claude Desktop ou Claude Code

Ajoutez cette entrée stdio locale à la configuration MCP de Claude Desktop ou à un `.mcp.json` de confiance de Claude Code :

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

Redémarrez Claude Desktop, ou faites confiance à l’espace de travail Claude Code et approuvez le serveur. Laissez les demandes d’approbation activées pour les opérations d’actualisation, d’export, de reprise et d’annulation.

## 5. Vérifier la préparation

Appelez `healthmd_doctor`. Il ne lit que la préparation, sans aucune valeur de santé.

Un résultat prêt contient ces champs :

```json
{
  "schema": "healthmd.local_readiness",
  "schema_version": 1,
  "status": "ready"
}
```

Le résultat complet inclut aussi des vérifications et les actions suivantes. Résolvez chaque vérification bloquante avant de continuer. Un utilitaire connecté ne prouve **pas** que le contexte chiffré est à jour.

Ensuite, appelez `healthmd_metrics` et confirmez l’ID de métrique canonique et l’unité que vous comptez demander. Ce parcours utilise `steps` uniquement comme exemple.

## 6. Actualiser explicitement une petite portée

Déterminez les dates réellement voulues, puis appelez `healthmd_refresh` avec une plage exacte et inclusive. L’exemple demande une seule journée de données résumées :

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-14",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

Examinez les arguments, approuvez l’acquisition et laissez les deux apps ouvertes. L’actualisation n’écrit aucun fichier d’export et ne modifie pas les réglages d’export enregistrés de l’iPhone. Conservez le `job_id` renvoyé jusqu’à ce que la tâche atteigne un état terminal.

## 7. Exécuter la première requête bornée

Une fois l’actualisation terminée, appelez `healthmd_metric_chart` avec les mêmes dates, métrique, sélection de sources et niveau de détail :

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-14",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "all_pages": true
}
```

`all_pages: true` parcourt des curseurs opaques uniquement dans les limites agrégées de pages et d’octets de l’utilitaire. Pour le sommeil, appelez `healthmd_sleep_sessions` au lieu de remplacer l’extraction canonique.

## 8. Vérifier la complétude avant de répondre

Ne traitez pas la réussite d’un outil comme une preuve de couverture sanitaire complète. Vérifiez tout ce qui suit :

- l’actualisation a atteint un état terminal réussi pour les mêmes dates exactes, métriques, sources et niveau de détail ;
- le schéma et la version de la réponse sont reconnus ;
- la plage demandée et le fuseau horaire correspondent à la question ;
- chaque valeur énoncée conserve son ID de métrique canonique et son unité ;
- le statut de couverture, les jours considérés, les jours avec valeurs et chaque intervalle manquant sont signalés ;
- `complete_empty`, `partial`, `failed`, `unsupported`, `skipped` et `cancelled` ne sont pas convertis en zéro ;
- le parcours est terminé, ou tout curseur ou plafond agrégé restant est divulgué ;
- les descripteurs de preuves et de sources ainsi que les limites restent attachés à la réponse ;
- la direction factuelle n’est pas transformée en diagnostic, conseil de traitement, causalité ou langage de « mieux/pire ».

### Lire des résultats partiels sans écarter des données utiles

Une requête typée peut renvoyer un `healthmd.query_response` valide alors qu’une partie seulement de la portée demandée est terminée. Le [fixture de réponse partielle généré](/docs/reference/generated/automation/agent-query-response-partial.json) conserve un élément Pas disponible et signale séparément le jour en échec :

```json
{
  "schema": "healthmd.query_response",
  "schema_version": 1,
  "coverage": {
    "status": "partial",
    "days_considered": 2,
    "days_with_values": 1,
    "missing": [
      {
        "status": "failed",
        "range": {
          "start_date": "2026-03-16",
          "end_date": "2026-03-16"
        }
      }
    ]
  },
  "items": ["one retained typed item"],
  "limitations": ["one or more requested days did not complete"]
}
```

Les chaînes dans `items` et `limitations` ci-dessus sont des abréviations explicatives ; utilisez le fixture généré téléchargeable pour les champs et preuves exacts. Conservez ensemble l’élément retenu, l’intervalle en échec, les décomptes de couverture et la limite.

N’ajoutez pas `status: "partial_success"` à `healthmd.query_response`. Ce statut appartient aux enveloppes CLI et d’export de niveau supérieur quand l’acquisition, le parcours ou la génération de fichiers est incomplète. Un dépassement de délai est encore autre chose : c’est un résultat inconnu d’une tâche persistante, à inspecter par ID de tâche.

Les échecs structurés utilisent `healthmd.query_error` v1 plutôt qu’une réponse partielle. Consultez [agent-query-error.json](/docs/reference/generated/automation/agent-query-error.json) pour la forme de production générée, avec code stable, message, possibilité de nouvelle tentative et détails typés.

## 9. Se rétablir sûrement d’un dépassement de délai

Un dépassement de délai, un hôte fermé ou une attente MCP annulée n’annule pas une actualisation acceptée.

1. Conservez le `job_id` renvoyé.
2. Appelez `healthmd_job_status` avec cet ID.
3. Si la tâche immuable est reprenable, examinez et approuvez `healthmd_job_resume` avec le même ID et un délai d’attente fini.
4. Ne lancez une nouvelle actualisation qu’après que le statut prouve qu’aucune tâche acceptée ne peut encore se terminer.
5. Utilisez `healthmd_job_cancel` uniquement lorsque vous voulez terminer la tâche ; l’annulation n’est terminale qu’après accusé de réception de l’iPhone.

Ne réessayez jamais à l’aveugle après un résultat inconnu. Les tâches persistantes d’actualisation conservent la portée acceptée et le périmètre validé.

## Vous êtes connecté

Le premier flux en lecture seule est terminé lorsque le doctor est prêt, l’actualisation explicite est terminale, la requête bornée a un parcours complet et vous avez inspecté couverture, preuves, unités et limites.

Les exports de fichiers générés sont un flux distinct soumis à approbation. L’outil Mac publié écrit dans le dossier déjà sélectionné dans Health.md for Mac ; il n’accepte aucun argument de destination arbitraire.

<div class="related">
  <a href="/fr/docs/mcp/"><span>Catalogue d’outils</span>Passez en revue tous les outils Mac publiés, les schémas exacts, MCP Apps, la pagination et les limites de sécurité.</a>
  <a href="/fr/docs/configuration/"><span>Autres clients</span>Choisissez entre l’intégration Mac publiée et l’aperçu portable clairement signalé.</a>
  <a href="/fr/docs/agent-queries/"><span>Questions suivantes</span>Exécutez des flux typés de métriques, sommeil, entraînements, comparaisons, couverture et preuves.</a>
  <a href="/fr/docs/agents/"><span>Modèle de confiance</span>Comprenez le contexte chiffré, la portée des requêtes, la rétention, les preuves et les règles de compte rendu.</a>
</div>
