---
title: "Personnalisation du format"
description: "Contrôlez la mise en forme des sorties sans modifier les données recueillies. Choisissez un format de fichier, les conventions de date, d’heure et d’unités, personnalisez le frontmatter YAML et sélectionnez un modèle Markdown."
---

## Formats de sortie
<div class="options">
<div class="option"><strong>Markdown (.md)</strong><p>Format par défaut. Un fichier par jour. Frontmatter YAML (facultatif), puis sections avec titres pour chaque catégorie.</p></div>
<div class="option"><strong>Obsidian Bases</strong><p>Markdown avec un frontmatter structuré et optimisé pour l’extension <a href="https://help.obsidian.md/Plugins/Bases">Bases</a> d’Obsidian. Les propriétés numériques restent des nombres et les dates restent des dates.</p></div>
<div class="option"><strong>JSON</strong><p>Un fichier JSON par jour. Les résumés quotidiens du schéma v7 peuvent intégrer l’archive v1 faisant autorité <code>healthmd.healthkit_records</code> lorsque Lossless Health Records est activé.</p></div>
<div class="option"><strong>CSV</strong><p>Un fichier CSV par jour avec l’en-tête <code>Date,Category,Metric,Value,Unit,Timestamp</code>. Les lignes de résumé de compatibilité comportent cinq champs et omettent la colonne d’horodatage ; les lignes horodatées et celles des enregistrements canoniques en comportent six.</p></div>
</div>
<div class="callout"><strong>Besoin du contrat exact ?</strong><p style="margin-top:6px;">Consultez la <a href="/fr/docs/reference/export-formats/">référence des formats</a> issue de la production, les <a href="/fr/docs/reference/generated/core/csv-row-contracts/">contrats des lignes CSV</a> et les fixtures complètes téléchargeables.</p></div>

## Date et heure
<p>Choisissez le format de date (par ex. <code>YYYY-MM-DD</code>, <code>MMM d, yyyy</code>) et celui de l’heure (sur 12 ou 24 heures). Le bloc d’aperçu au bas de l’écran s’actualise à mesure que vous modifiez les réglages.</p>

## Système d’unités
<p>Basculez entre <em>Métrique</em> et <em>Impérial</em>. Ce réglage concerne notamment la distance (m/km ou ft/mi), le poids (kg ou lb) et la température (°C ou °F). HealthKit conserve toujours les unités canoniques ; la conversion intervient lors de l’export.</p>

## Champs du frontmatter
<p>Touchez <em>Champs du frontmatter</em> pour ouvrir un éditeur dédié :</p>
<ul><li>activez ou désactivez les champs intégrés (date, weekday, totalSteps, etc.) ;</li><li>renommez un champ si votre configuration Obsidian attend d’autres clés ;</li><li>ajoutez des champs personnalisés avec des valeurs statiques (par ex. <code>type: health</code>) ;</li><li>ajoutez des champs substituables résolus lors de l’export (par ex. <code>weather: {weather}</code>).</li></ul>

## Modèle Markdown
<p>Touchez <em>Modèle Markdown</em> pour ouvrir un éditeur proposant plusieurs styles intégrés (Compact, Sections, Detailed) et un mode entièrement personnalisé. Le bloc d’aperçu affiche le résultat avec les données du jour.</p>

## Aperçu
<p>Au bas de l’écran Format, un aperçu dynamique affiche les données du jour avec vos réglages actuels. C’est le moyen le plus rapide d’affiner le résultat : modifiez une option, consultez l’aperçu, puis recommencez.</p>

## Pages associées
<div class="related">
<a href="/fr/docs/metrics/"><span>Quoi</span>Métriques de santé — choisissez d’abord les données.</a>
<a href="/fr/docs/individual-tracking/"><span>Détaillé</span>Suivi individuel — une sortie entièrement différente, avec un fichier par entrée.</a>
<a href="/fr/docs/daily-notes/"><span>Obsidian</span>Injection dans les notes quotidiennes — utilise les mêmes champs de frontmatter.</a>
<a href="/fr/docs/reference/export-formats/"><span>Contrat</span>Formats d’export — comportement exact de JSON, CSV, Markdown et Bases.</a>
</div>
