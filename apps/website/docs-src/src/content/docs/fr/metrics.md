---
title: "Métriques de santé"
description: "Faites votre choix dans le catalogue actuel des métriques Apple Health de Health.md. Recherchez une métrique, activez des catégories entières ou réglez chaque métrique séparément."
---

<div class="callout"><strong>Remarque concernant Android.</strong><p style="margin-top:6px;">Cette page décrit le sélecteur de métriques Apple Health et la référence de données HealthKit générée. L’app Android propose 106 métriques Health Connect ; consultez le <a href="/fr/docs/android/">guide Android</a> pour la configuration de Health Connect et les comportements propres à la plateforme.</p></div>

## Présentation
<div class="options">
<div class="option"><strong>En-tête des totaux</strong><p>Affiche en temps réel le nombre de métriques et de catégories activées. Maintenez le doigt dessus pour copier l’état exact de la sélection dans le presse-papiers.</p></div>
<div class="option"><strong>Toutes les métriques activées</strong><p>Interrupteur principal qui active ou désactive toutes les catégories. Bon point de départ : activez tout, puis désactivez ce qui ne vous intéresse pas.</p></div>
<div class="option"><strong>Recherche</strong><p>Filtre instantanément les noms et identifiants de métriques. Essayez « heart », « sleep », « vo2 ».</p></div>
</div>

## Catégories
<p>Le sélecteur regroupe les résumés ordinaires et les définitions d’enregistrements sources en catégories telles que Sommeil, Activité, Cœur, Respiration, Signes vitaux, Mensurations, Mobilité, Cyclisme, Nutrition, Pleine conscience, Santé reproductive, Symptômes, Médicaments, enregistrements spécialisés et Entraînements. Chaque ligne indique l’état et le nombre actuel de définitions activées. Le <a href="/fr/docs/reference/generated/core/metric-catalog/">catalogue de métriques</a> généré en production est l’inventaire actuel faisant autorité.</p>
<p>Touchez une catégorie pour afficher ses métriques. Chacune possède son propre interrupteur et identifiant HealthKit. La couleur du point indique si HealthKit contient actuellement des données pour cette métrique sur l’appareil.</p>

## Portée de la sélection
<p>Votre sélection de métriques s’applique à <em>toutes</em> les fonctions suivantes :</p>
<ul><li>Exports quotidiens — seules les métriques activées figurent dans le fichier</li><li>Suivi individuel — seules les métriques activées produisent des fichiers par entrée</li><li>Injection dans les notes quotidiennes — seules les métriques activées sont fusionnées dans le frontmatter</li><li>Shortcuts — les exports par plage de dates utilisent la même sélection</li></ul>
<div class="callout"><strong>Conseil.</strong><p style="margin-top:6px;">Commencez modestement. Activez Sommeil, Activité et Cœur, puis lancez un export et examinez le fichier. Ajoutez ensuite d’autres catégories. Il est plus rapide d’en ajouter ensuite que de parcourir un fichier de 50 lignes rempli de métriques dont vous n’avez pas besoin.</p></div>

## Pages associées
<div class="related">
<a href="/fr/docs/reference/"><span>Référence</span>Référence des exports — chaque métrique Apple, clé, unité, définition d’enregistrement source et structure d’export.</a>
<a href="/fr/docs/android/"><span>Android</span>App Android — configuration, métriques, destinations et automatisation de Health Connect.</a>
<a href="/fr/docs/format/"><span>Comment</span>Format — modifiez la façon dont les métriques sont écrites.</a>
<a href="/fr/docs/individual-tracking/"><span>Détaillé</span>Suivi individuel — écrivez aussi un fichier par entrée horodatée.</a>
<a href="/fr/docs/daily-notes/"><span>Obsidian</span>Injection dans les notes quotidiennes — ajoutez ces métriques à vos notes.</a>
</div>
