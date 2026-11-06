---
title: "Premier export depuis l’iPhone"
description: "Autorisez Apple Health, choisissez une destination dans Fichiers, prévisualisez le résultat de Health.md, lancez un premier export limité depuis l’iPhone et vérifiez les fichiers écrits."
---

Suivez ce guide pour créer un export limité et vérifiable avant de modifier les métriques, le format ou l’automatisation. Health.md lit uniquement les catégories Apple Health autorisées par iOS et écrit les fichiers générés dans le dossier de votre choix.

<div class="availability available">
<strong>Disponible maintenant · Health.md pour iPhone</strong>
<p>Les exportations nécessitent un essai actif, un abonnement ou un accès Lifetime. Vous pourrez configurer des planifications et d’autres automatisations plus tard.</p>
</div>

## Avant de commencer

Avant de commencer, vérifiez que vous disposez :

- de [Health.md sur l’App Store](https://apps.apple.com/app/health-md/id6757763969), installé sur un iPhone contenant des données Apple Health
- de l’autorisation de lire au moins une catégorie Apple Health
- d’un dossier accessible en écriture dans Fichiers : iCloud Drive, Sur mon iPhone ou un coffre Obsidian.

Conservez les métriques par défaut et le format Markdown. Sélectionnez **Hier** pour une plage d’un jour.

## 1. Terminer la configuration de l’iPhone

Health.md propose cinq étapes de configuration. Aucune n’est bloquante : l’accès à Apple Health et le dossier peuvent être ignorés puis réglés plus tard.

Au premier lancement, touchez **Connecter Apple Health**. Autorisez les catégories de santé souhaitées, vérifiez l’exemple de sortie, choisissez un dossier dans Fichiers et continuez jusqu’à la dernière étape.

Après la configuration, l’app s’ouvre sur **Archives**. Si Apple Health ou le dossier demande une action, la carte **À vérifier** en haut indique quoi corriger.

<div class="docs-screenshot-grid">
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/onboarding-start.webp" target="_blank" rel="noopener" aria-label="Ouvrir la capture de la configuration en taille réelle">
    <img src="/docs/assets/docs/iphone-first-export/onboarding-start.webp" width="1206" height="2622" loading="lazy" alt="Configuration de Health.md à l’étape 1 sur 5 listant trois étapes, avec le bouton pour connecter Apple Health." />
  </a>
  <figcaption>La configuration explique ce que lit Health.md et où vont les fichiers avant de demander l’accès. L'interface de cette capture reste en anglais.</figcaption>
</figure>
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/export-now.webp" target="_blank" rel="noopener" aria-label="Ouvrir la capture d’Exporter maintenant en taille réelle">
    <img src="/docs/assets/docs/iphone-first-export/export-now.webp" width="1206" height="2622" loading="lazy" alt="Feuille Exporter maintenant de Health.md avec Hier sélectionné, un interrupteur de résumé de la plage uniquement, un récapitulatif d’un fichier pour un jour et un bouton d’exportation." />
  </a>
  <figcaption>Exporter maintenant indique ce qui sera écrit avant de commencer. Cette capture de référence conserve aussi l'interface en anglais.</figcaption>
</figure>
</div>

## 2. Choisir une petite exportation

Touchez le bouton rond **Exporter maintenant** à côté de la barre d’onglets. Ensuite :

1. Sélectionnez **Hier**.
2. Laissez **Résumé de la plage de dates uniquement** désactivé.
3. Vérifiez que **Sera écrit** indique votre dossier et environ un fichier pour un jour.

L’automatisation par défaut garde la sélection de métriques par défaut et **Markdown**. Pour les modifier, ouvrez **Automatisations**, choisissez l’automatisation, puis **Métriques** ou **Formats**. Ajoutez CSV, JSON ou Obsidian Bases une fois cette exportation réussie. Une plage courte facilite le repérage des problèmes d’autorisation, de données vides et de dossier.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/fr/iphone-first-export/metric-selection.webp" target="_blank" rel="noopener" aria-label="Ouvrir la capture de la sélection des métriques en taille réelle">
    <img src="/docs/assets/docs/fr/iphone-first-export/metric-selection.webp" width="1206" height="2622" loading="lazy" alt="Page Métriques de Health.md avec le nombre de métriques activées, les boutons Recommandé, Tout sélectionner et Tout désélectionner, un champ de recherche et des catégories avec leurs nombres." />
  </a>
  <figcaption>Le nombre de métriques dépend de la version de l’app et des autorisations. Cette capture localisée montre 217 métriques activées sur 219.</figcaption>
</figure>

## 3. Vérifier l’aperçu avant l’écriture

Dans **Exporter maintenant**, touchez **Aperçu**. L’aperçu nécessite l’accès à Apple Health, mais pas de dossier accessible en écriture.

Utilisez l’aperçu pour repérer un problème d’autorisation Apple Health avant de tester le dossier.

Vérifiez que l’aperçu affiche :

- la date demandée
- les noms de métriques et les unités attendus
- des valeurs manquantes ou indisponibles plutôt que de faux zéros
- le format choisi et la structure du nom de fichier.

Fermez l’aperçu et modifiez les réglages de l’automatisation si vous devez changer les métriques ou les formats.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/fr/iphone-first-export/export-preview.webp" target="_blank" rel="noopener" aria-label="Ouvrir la capture de l’aperçu en taille réelle">
    <img src="/docs/assets/docs/fr/iphone-first-export/export-preview.webp" width="1206" height="2622" loading="lazy" alt="Aperçu de l’exportation Health.md avec la plage de sommeil, l’estimation d’un jour en Markdown, la période de synthèse, le dossier de destination et le nom de fichier généré." />
  </a>
  <figcaption>Cet exemple utilise des données de santé fictives.</figcaption>
</figure>

## 4. Exporter et vérifier

Touchez **Exporter hier**. Si la configuration est incomplète, Health.md indique ce qui manque côté Apple Health ou dossier.

Une fois l’exportation terminée :

1. Consultez le résultat pour les fichiers écrits, ignorés ou en échec. Le jour apparaît dans le calendrier d’**Archives**.
2. Ouvrez l’app Fichiers et le dossier choisi.
3. Ouvrez un fichier généré et vérifiez sa date, ses unités et son frontmatter.
4. Conservez les détails du résultat si vous devez examiner un problème.

Un jour couvert dans le calendrier est un résumé ; touchez le jour pour voir l’état de chaque automatisation à cette date.

<div class="callout">
<strong>Aucune donnée pour le jour choisi ?</strong>
<p style="margin-top:6px;">Choisissez un jour avec des données d’activité ou de sommeil. Vérifiez ensuite l’autorisation Apple Health et la sélection des métriques. Une plage vide n’est pas une erreur d’écriture.</p>
</div>

## Étapes suivantes

<div class="related">
  <a href="/fr/docs/metrics/"><span>Choisir les données</span>Recherchez les métriques Apple Health et ajustez les catégories ou les autorisations spéciales.</a>
  <a href="/fr/docs/format/"><span>Structurer le résultat</span>Configurez les formats, les dates, les unités, le frontmatter, les modèles et les noms de fichiers.</a>
  <a href="/fr/docs/scheduling/"><span>Automatiser</span>Planifiez des exports récurrents après avoir vérifié une exécution manuelle.</a>
  <a href="/fr/docs/folder-vault/"><span>Corriger une destination</span>Comprenez les fournisseurs Fichiers, l’accès aux dossiers et la récupération.</a>
</div>
