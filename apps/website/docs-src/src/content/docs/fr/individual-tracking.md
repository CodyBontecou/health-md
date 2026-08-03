---
title: "Suivi des entrées individuelles"
description: "Vous pouvez créer un fichier Markdown par entrée horodatée : chaque entraînement, mesure de tension et humeur dispose alors de son propre fichier, dont le nom contient l’horodatage."
---

## Quand l’utiliser
<p>Les exports quotidiens produisent un fichier de résumés par jour. Le <em>suivi individuel</em> sert lorsque vous souhaitez <em>citer un événement précis</em> : créer depuis une note de journal un lien vers un entraînement particulier ou un backlink d’une humeur vers un bilan hebdomadaire.</p>
<p>Il complète l’export quotidien, sans le remplacer. Lorsque les deux sont activés, vous obtenez les deux types de fichiers.</p>

## Configuration en deux étapes
<p>La configuration comprend volontairement deux étapes :</p>
<ol><li><strong>Interrupteur principal.</strong> Activez la fonctionnalité globalement.</li><li><strong>Sélection par métrique.</strong> Choisissez <em>les métriques</em> qui produisent des fichiers individuels. La plupart des utilisateurs ne veulent pas un fichier par mesure de fréquence cardiaque (10,000 / jour), mais souhaitent un fichier par entraînement (~1 / jour).</li></ol>

## Actions rapides
<div class="options">
<div class="option"><strong>Activer les métriques suggérées</strong><p>Sélectionne par défaut l’humeur, les symptômes, les entraînements, la tension artérielle et la glycémie : les métriques pour lesquelles un fichier par entrée est pertinent.</p></div>
<div class="option"><strong>Activer toutes les métriques</strong><p>Tout. Attention : cela peut produire des milliers de fichiers par jour.</p></div>
<div class="option"><strong>Désactiver toutes les métriques</strong><p>Efface la sélection par métrique sans désactiver l’interrupteur principal.</p></div>
</div>

## Structure des dossiers
<div class="options"><div class="option"><strong>Dossier des entrées</strong><p>Chemin relatif au coffre où sont écrits les fichiers individuels. Valeur par défaut : <code>entries</code>.</p></div><div class="option"><strong>Organiser par catégorie</strong><p>Si l’option est activée, les entrées sont classées dans des sous-dossiers par catégorie (<code>entries/workouts/</code>, <code>entries/symptoms/</code>). Sinon, elles se trouvent toutes dans un même dossier.</p></div></div>

## Modèle de nom de fichier
<p>Valeur par défaut : <code>{date}_{time}_{metric}</code>. Variables disponibles : <code>{date}</code>, <code>{time}</code>, <code>{metric}</code>, <code>{category}</code>. Exemple :</p>
<div class="doc-diagram folder-tree" aria-label="Exemple d’arborescence de fichiers d’entrées individuelles">
<span>{vault}/entries/</span>
<span>├─ workouts/2026_07_14_0920_workouts_workouts_71000000-0000-0000-0000-000000000008.md</span>
<span>├─ symptoms/2026_07_14_0916_symptom_headache_symptom_headache_71000000-0000-0000-0000-000000000002.md</span>
<span>└─ vitals/2026_07_14_0918_blood_pressure_blood_pressure_71000000-0000-0000-0000-000000000004.md</span>
</div>
<p>Les entrées canoniques liées à une source ajoutent la métrique sélectionnée et l’UUID HealthKit en minuscules après le nom configuré. Le même enregistrement source reste ainsi stable entre les exécutions et évite les collisions au cours d’une même minute. Les entrées de compatibilité sans UUID conservent l’ancien nom plus court.</p>
<div class="callout"><strong>Attention.</strong><p style="margin-top:6px;">Seules les catégories contenant au moins une métrique activée dans <em>Métriques de santé</em> apparaissent ici. Activez-y d’abord une métrique, puis revenez choisir son suivi par entrée. Consultez le <a href="/fr/docs/reference/individual-entry-tracking/">contrat d’identité des enregistrements sources</a> et la <a href="/fr/docs/reference/generated/individual/filename-path-matrix/">matrice des noms de fichiers</a> générée avant d’automatiser des chemins.</p></div>

## Pages associées
<div class="related">
<a href="/fr/docs/metrics/"><span>Prérequis</span>Métriques de santé — activez d’abord les métriques.</a>
<a href="/fr/docs/format/"><span>Sortie</span>Format — s’applique aussi aux fichiers d’entrée.</a>
<a href="/fr/docs/daily-notes/"><span>Autre méthode</span>Injection dans les notes quotidiennes — une autre façon d’associer des métriques aux notes.</a>
<a href="/fr/docs/reference/individual-entry-tracking/"><span>Contrat</span>Référence des entrées individuelles — identité UUID, frontmatter, entrées spécialisées et mécanismes de compatibilité.</a>
</div>
