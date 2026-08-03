---
title: Bien démarrer avec Health.md
description: Exportez des données d’Apple Health ou de Health Connect, connectez l’utilitaire Mac signé à un agent local et développez à partir des contrats versionnés de Health.md.
---

<div class="docs-hero" data-strand-stage>
  <canvas class="docs-dna" data-three-strand aria-hidden="true"></canvas>
  <div class="docs-hero-copy">
    <p class="docs-eyebrow">Disponible maintenant · utilitaire Mac signé</p>
    <p>Exportez les données de santé de votre téléphone, connectez un agent local à l’aide des utilitaires Mac signés ou développez à partir de contrats versionnés. Les lectures HealthKit restent sur l’iPhone et les lectures Health Connect sur Android.</p>
    <div class="docs-command" aria-label="Commande intégrée de vérification de Health.md"><span aria-hidden="true">$</span> "/Applications/Health.md.app/Contents/Helpers/healthmd" doctor</div>
    <p class="docs-command-note">L’application est installée ailleurs ? Copiez le chemin de l’utilitaire intégré depuis <strong>Health.md for Mac → CLI</strong>.</p>
    <div class="docs-actions">
      <a class="docs-button" href="/fr/docs/iphone-first-export/">Premier export depuis l’iPhone</a>
      <a class="docs-button-secondary" href="/fr/docs/configuration/">Connecter un agent</a>
      <a class="docs-button-secondary" href="/fr/docs/reference/">Parcourir les contrats</a>
    </div>
  </div>
</div>

<div class="agent-path" aria-label="Choisissez un objectif Health.md">
  <a href="/fr/docs/iphone-first-export/"><span>01 · Exporter</span><strong>Commencez sur l’iPhone</strong>Autorisez Apple Health, choisissez un dossier, prévisualisez le résultat et lancez un premier export.</a>
  <a href="/fr/docs/configuration/"><span>02 · Interroger</span><strong>Connectez un agent local</strong>Utilisez l’utilitaire MCP Mac signé avec Codex, Claude ou un autre client stdio.</a>
  <a href="/fr/docs/reference/"><span>03 · Développer</span><strong>Utilisez des contrats stables</strong>Intégrez des schémas, des enregistrements, des preuves, des fixtures générées et des enveloppes exactes.</a>
</div>

<div class="reference-stats">
<div><strong>21</strong><span>outils MCP Mac intégrés</span></div>
<div><strong>4</strong><span>formats d’export</span></div>
<div><strong>v7</strong><span>schéma public d’export</span></div>
<div><strong>0</strong><span>passage obligatoire par un cloud Health.md</span></div>
</div>

<p class="docs-section-kicker">Disponible maintenant · macOS</p>

## Démarrage rapide d’un agent local en cinq minutes

Ouvrez Health.md sur le Mac, puis Health.md sur l’iPhone jumelé, et attendez que la connexion soit établie. L’utilitaire intégré vérifie que tout est prêt sans renvoyer de valeurs de santé, répertorie les métriques de sommeil et exécute une requête sur une journée :

```bash
HMD="/Applications/Health.md.app/Contents/Helpers/healthmd"
"$HMD" doctor
"$HMD" metrics list --category Sleep
"$HMD" query --category Sleep --yesterday
```

Lorsque tout est prêt, le résultat de `doctor` utilise le schéma `healthmd.cli_doctor` et indique les étapes suivantes si la configuration est incomplète. Pour Codex ou Claude, poursuivez avec [Configurer votre agent](/fr/docs/configuration/) et dirigez le client vers l’utilitaire signé distinct `healthmd-mcp`.

<p class="docs-section-kicker">Choisissez selon votre objectif</p>

## Configurer et connecter

<div class="related">
  <a href="/fr/docs/configuration/"><span>Disponible maintenant · Mac</span>Configuration — connectez Codex, Claude ou un autre client stdio à l’utilitaire MCP signé.</a>
  <a href="/fr/docs/mcp/"><span>Disponible maintenant · Mac</span>Serveur MCP et App — découvrez les 21 outils intégrés, affichez des visualisations privées et comprenez l’aperçu portable.</a>
  <a href="/fr/docs/cli/"><span>Disponible maintenant · Mac</span>CLI Health.md — installez l’utilitaire intégré, vérifiez son état, interrogez les données et distinguez l’aperçu portable.</a>
  <a href="/fr/docs/agents/"><span>Architecture</span>Contexte de l’agent — découvrez la portée des requêtes, la confiance locale, le contexte chiffré, les preuves, la conservation et la confidentialité.</a>
</div>

<p class="docs-section-kicker">Opérations courantes</p>

## Interroger, extraire et automatiser

<div class="related">
  <a href="/fr/docs/agent-queries/"><span>Requêtes typées</span>Interrogez les métriques, les sessions de sommeil, les entraînements, les comparaisons, la couverture et les preuves factuelles.</a>
  <a href="/fr/docs/cli-direct/"><span>Aperçu · CLI portable</span>Accès direct à l’iPhone — découvrez le jumelage par Manual IP ou Tailscale avant la publication du paquet autonome.</a>
  <a href="/fr/docs/cli-extract/"><span>Données sources</span>Extraction canonique — récupérez les jours sélectionnés au schéma v7, les enregistrements sources, les projections ou le JSONL.</a>
  <a href="/fr/docs/cli-jobs/"><span>Exécutions fiables</span>Tâches persistantes — gérez en toute sécurité les délais d’attente, les résultats incertains, la reprise, l’annulation et les résultats partiels.</a>
  <a href="/fr/docs/agent-api/"><span>Bas niveau</span>API en boucle locale — utilisez les routes exactes de requête, de preuve, de curseur, d’actualisation et de tâches persistantes.</a>
  <a href="/fr/docs/reference/integration-recipes/"><span>Modèles</span>Recettes d’intégration — analysez et validez les résultats Health.md sans affaiblir leurs contrats.</a>
</div>

<p class="docs-section-kicker">Interfaces stables</p>

## Contrats et structures de données

<div class="related">
  <a href="/fr/docs/reference/"><span>Carte des contrats</span>Référence des exports — parcourez les schémas, métriques, formats, enregistrements et fixtures d’interopérabilité.</a>
  <a href="/fr/docs/reference/api-and-cli/"><span>Automatisation</span>Contrats API et CLI — examinez les enveloppes, les routes, le comportement de sortie et les exemples générés.</a>
  <a href="/fr/docs/reference/evidence-packets/"><span>Résultats de l’agent</span>Requêtes et preuves — valeurs typées, couverture, données manquantes, opérations et identités déterministes.</a>
  <a href="/fr/docs/reference/daily-records/"><span>Schéma v7</span>Enregistrements quotidiens — comprenez le document source public et ses règles de propriété.</a>
  <a href="/fr/docs/shared-metric-registry/"><span>Vocabulaire</span>Registre des métriques — utilisez des ID de métriques, catégories, unités et métadonnées de profil stables sur toutes les plateformes.</a>
  <a href="/fr/docs/reference/generated/"><span>Lisible par machine</span>Artefacts générés — consultez les champs canoniques, fixtures, inventaires de messages et contrats CLI.</a>
</div>

<p class="docs-section-kicker">Flux de travail du produit</p>

## Applications et exports

<div class="related">
  <a href="/fr/docs/iphone-first-export/"><span>Commencez ici · iPhone</span>Premier export — autorisez Apple Health, choisissez un dossier, prévisualisez le résultat et vérifiez les fichiers écrits.</a>
  <a href="/fr/docs/android/"><span>Android</span>Health Connect — choisissez un dossier de fournisseur de documents et configurez l’automatisation de la plateforme.</a>
  <a href="/fr/docs/export/"><span>Fichiers</span>Export — exécutez des plages de dates explicites au format Markdown, CSV, JSON ou Obsidian Bases.</a>
  <a href="/fr/docs/format/"><span>Structure</span>Personnalisation du format — contrôlez les unités, les dates, le frontmatter, les noms de fichiers et le comportement d’écriture.</a>
  <a href="/fr/docs/scheduling/"><span>Arrière-plan</span>Planification — comprenez le comportement des exports quotidiens et hebdomadaires ainsi que les limites de chaque plateforme.</a>
  <a href="/fr/docs/shortcuts/"><span>Automatisation</span>Shortcuts et App Intents — déclenchez des exports, des résumés et des vérifications d’état depuis les flux de travail Apple.</a>
</div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:12px; font-family:var(--sl-font-mono);">Structure de la documentation mise à jour le 2026-08-02</p>
