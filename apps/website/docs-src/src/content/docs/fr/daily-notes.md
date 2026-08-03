---
title: "Injection dans les notes quotidiennes"
description: "Intégrez les métriques de santé sélectionnées au frontmatter YAML et, si vous le souhaitez, au corps de vos notes quotidiennes dans Obsidian ou toute autre app Markdown."
---

## Fonctionnement
<p>Si vous tenez des notes quotidiennes (par ex. <code>Daily/2026-04-28.md</code>), activez cette option afin que l’app <em>intègre</em>, à chaque export, les métriques sélectionnées à leur frontmatter YAML, sans modifier le reste de leur contenu.</p>
<div class="doc-diagram merge-preview" aria-label="Frontmatter d’une note quotidienne avant et après la fusion Health.md">
<div class="merge-card"><strong>Avant</strong>
<pre><code>---
title: Tuesday note
mood: focused
---

Wrote launch notes...</code></pre>
</div>
<div class="merge-card"><strong>Après l’export</strong>
<pre><code>---
title: Tuesday note
mood: focused
steps: 12642
sleep_total_hours: 7.31
workout_count: 1
---

Wrote launch notes...</code></pre>
</div></div>
<p>L’app peut aussi injecter des sections Markdown (Sommeil, Activité, Cœur, etc.) dans le corps de la note. Ces sections sont <em>gérées par l’app</em> : elles sont remplacées proprement à chaque export. Les titres que vous rédigez restent intacts.</p>

## Emplacement
<div class="options">
<div class="option"><strong>Dossier</strong><p>Chemin relatif au coffre vers le dossier des notes quotidiennes. Valeur par défaut : <code>Daily</code>. Laissez vide pour cibler la racine du coffre. Exemples : <code>Daily</code>, <code>Journal/Daily</code>.</p></div>
<div class="option"><strong>Nom du fichier</strong><p>Motif du nom de la note sans extension. La valeur par défaut <code>{date}</code> devient <code>2026-04-28</code>.</p></div>
</div>

## Variables du nom de fichier
<p>Vous pouvez les combiner librement :</p>
<ul><li><code>{date}</code> — date ISO complète (<code>2026-04-28</code>)</li><li><code>{year}</code>, <code>{month}</code>, <code>{day}</code></li><li><code>{weekday}</code> — nom court (<code>Tue</code>)</li><li><code>{monthName}</code> — nom long (<code>April</code>)</li><li><code>{quarter}</code> — Q1 / Q2 / Q3 / Q4</li></ul>
<p>Exemple : <code>{year}/{monthName}/{date}-{weekday}</code> → <code>2026/April/2026-04-28-Tue.md</code>. La ligne d’aperçu sous le champ affiche immédiatement le chemin obtenu.</p>

## Options
<div class="options">
<div class="option"><strong>Créer la note si elle manque</strong><p>Crée une note si aucune note quotidienne n’existe à la date concernée. Désactivez cette option si vous créez vos notes avec Obsidian Templater ou une extension similaire.</p></div>
<div class="option"><strong>Injecter les sections de métriques</strong><p>Ajoute aussi les titres Sommeil, Activité, Cœur, etc. au corps de la note. Ces sections, gérées par l’app, sont proprement remplacées à chaque export. Option désactivée par défaut.</p></div>
</div>

## Métriques injectées
<p>L’app injecte les métriques sélectionnées dans <em>Métriques de santé</em>. Il n’existe pas de sélecteur distinct ici : toute modification de cette sélection s’applique à l’injection.</p>

## Aperçu du frontmatter
<p>Le bas de l’écran présente un aperçu dynamique du frontmatter qui sera fusionné. Il s’actualise lorsque vous modifiez les métriques ou les champs du frontmatter dans la personnalisation du format.</p>
<div class="callout"><strong>Fonctionnement de la fusion.</strong><p style="margin-top:6px;">Si la note possède déjà un frontmatter, l’app conserve vos clés et n’ajoute ou ne met à jour que celles qu’elle gère. Les sections du corps gérées par l’app sont encadrées de commentaires HTML afin que chaque nouvelle exécution produise le même résultat sans dupliquer le contenu.</p></div>

## Pages associées
<div class="related">
<a href="/fr/docs/metrics/"><span>Prérequis</span>Métriques de santé — choisissez les données à injecter.</a>
<a href="/fr/docs/format/"><span>Format</span>Éditeur des champs du frontmatter — renommez les clés et ajoutez des champs personnalisés.</a>
<a href="/fr/docs/individual-tracking/"><span>Détaillé</span>Suivi individuel — autre méthode de suivi par événement.</a>
</div>
