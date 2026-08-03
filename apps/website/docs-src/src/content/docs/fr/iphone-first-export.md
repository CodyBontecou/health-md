---
title: "Premier export depuis l’iPhone"
description: "Autorisez Apple Health, choisissez une destination dans Fichiers, prévisualisez le résultat de Health.md, lancez un premier export limité depuis l’iPhone et vérifiez les fichiers écrits."
---

Suivez ce guide pour créer un export limité et vérifiable avant de modifier les métriques, le format ou l’automatisation. Health.md lit uniquement les catégories Apple Health autorisées par iOS et écrit les fichiers générés dans le dossier de votre choix.

<div class="availability available">
<strong>Disponible maintenant · Health.md for iPhone</strong>
<p>Le premier export est compris dans le quota gratuit. Vous pourrez configurer plus tard la planification et les autres fonctionnalités payantes.</p>
</div>

## Avant de commencer

Vous avez besoin des éléments suivants :

- Health.md installé sur un iPhone contenant des données Apple Health ;
- l’autorisation de lire au moins une catégorie Apple Health ;
- une destination accessible en écriture dans Fichiers, comme iCloud Drive, Sur mon iPhone ou un coffre Obsidian.

Pour que le premier essai soit aussi court que possible, conservez les métriques par défaut et le format Markdown. Commencez par **Hier** ou une autre plage d’une seule journée plutôt que par tout l’historique disponible.

## 1. Terminez la configuration de l’iPhone

Au premier lancement, touchez **Start Setup** (« Commencer la configuration ») et suivez les sept étapes de prise en main. Autorisez les catégories de santé souhaitées, examinez l’exemple de résultat, choisissez un dossier dans Fichiers et poursuivez jusqu’à l’étape **Ready** (« Prêt »). Lorsque l’étape de déverrouillage apparaît, vous pouvez continuer avec le quota gratuit.

Si vous avez déjà terminé la prise en main, ouvrez l’onglet **Exporter** et vérifiez qu’Apple Health et le dossier local sont prêts. Utilisez le sélecteur de dossier pour remplacer une destination manquante ou inaccessible.

<div class="docs-screenshot-grid">
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/onboarding-start.webp" target="_blank" rel="noopener" aria-label="Ouvrir la capture d’écran d’intégration en taille réelle">
    <img src="/docs/assets/docs/iphone-first-export/onboarding-start.webp" width="1206" height="2622" loading="lazy" alt="Écran d’intégration Health.md pour la locale française à l’étape 1 sur 7 ; le contenu au premier plan et le bouton Start Setup restent en anglais." />
  </a>
  <figcaption>L’écran d’intégration, dont le texte est encore en anglais, présente l’archive locale, les notes planifiées et le modèle de dossiers avant de demander l’accès.</figcaption>
</figure>
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/export-setup-required.webp" target="_blank" rel="noopener" aria-label="Ouvrir la capture d’écran indiquant que la configuration est requise en taille réelle">
    <img src="/docs/assets/docs/iphone-first-export/export-setup-required.webp" width="1206" height="2622" loading="lazy" alt="Onglet Export de Health.md en anglais avec Health déconnecté, le choix de dossier disponible, le dossier local de l’iPhone sélectionné et les boutons de plage de dates." />
  </a>
  <figcaption>Les indicateurs d’état signalent clairement la configuration manquante de Health et du dossier. Cette capture de référence en anglais montre volontairement les deux prérequis comme incomplets.</figcaption>
</figure>
</div>

## 2. Choisissez un export limité

Dans l’onglet Exporter :

1. Sélectionnez **Dossier local de l’iPhone** comme destination.
2. Choisissez **Hier** ou une plage personnalisée d’une seule journée.
3. Conservez la sélection de métriques par défaut pour le premier essai.
4. Gardez **Markdown** sélectionné. Vous pourrez ajouter CSV, JSON ou Obsidian Bases lorsque le parcours de base fonctionnera.

Une plage courte facilite l’identification des problèmes d’autorisation, de catégories vides ou de destination. Elle évite aussi de confondre la durée d’une première requête avec un échec d’export.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/fr/iphone-first-export/metric-selection.webp" target="_blank" rel="noopener" aria-label="Ouvrir la capture d’écran de sélection des métriques en taille réelle">
    <img src="/docs/assets/docs/fr/iphone-first-export/metric-selection.webp" width="1206" height="2622" loading="lazy" alt="Écran français Indicateurs de santé affichant 217 métriques activées sur 219, l’interrupteur des indicateurs standard, le champ de recherche et les catégories Sommeil, Activité et Cœur." />
  </a>
  <figcaption>Le nombre total de métriques dépend de la version installée de l’application et des autorisations. Cette capture française en affiche 217 d’activées ; il n’est pas nécessaire d’atteindre ce total pour effectuer le premier export.</figcaption>
</figure>

## 3. Prévisualisez avant d’écrire

Touchez **Aperçu**. L’aperçu nécessite l’accès à Apple Health, mais pas de dossier local accessible en écriture. Il permet donc de distinguer un problème d’autorisation de lecture d’un problème lié à Fichiers.

Vérifiez que l’aperçu affiche :

- la date demandée ;
- les noms et unités de métriques attendus ;
- l’indication explicite des valeurs manquantes ou indisponibles, plutôt que des zéros inventés ;
- le format et la structure de nom de fichier sélectionnés.

Revenez à l’onglet Exporter si vous devez ajuster les dates, les métriques ou le format.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/fr/iphone-first-export/export-preview.webp" target="_blank" rel="noopener" aria-label="Ouvrir la capture d’écran de l’aperçu de l’export en taille réelle">
    <img src="/docs/assets/docs/fr/iphone-first-export/export-preview.webp" width="1206" height="2622" loading="lazy" alt="Aperçu de l’export Health.md affichant l’estimation d’un export Markdown sur une journée, les périodes récapitulatives, la destination et le nom de fichier généré." />
  </a>
  <figcaption>L’aperçu sépare l’examen du résultat de son écriture. Cette capture française montre quatre formats et le coffre de test TestVault ; pour le parcours minimal, conservez uniquement Markdown et votre dossier local.</figcaption>
</figure>

## 4. Exportez et vérifiez

Touchez **Exporter les données**. Si la configuration est incomplète, Health.md indique l’autorisation Health ou le dossier manquant au lieu de commencer silencieusement une écriture partielle.

Une fois l’opération terminée :

1. Consultez dans l’application le nombre de fichiers écrits, ignorés ou en échec.
2. Ouvrez l’application Fichiers et accédez au dossier sélectionné.
3. Ouvrez un fichier généré et vérifiez sa date, ses unités et son frontmatter.
4. Conservez les détails du résultat pour le dépannage ; ne concluez pas à la réussite de l’opération simplement parce que le bouton est redevenu inactif.

<div class="callout">
<strong>Aucune donnée pour le jour sélectionné ?</strong>
<p style="margin-top:6px;">Essayez un jour qui contient, à votre connaissance, des données d’activité ou de sommeil, puis vérifiez les autorisations Health et la sélection des métriques. Une plage autorisée mais vide est différente d’un échec de transfert ou d’écriture.</p>
</div>

## Étapes suivantes

<div class="related">
  <a href="/fr/docs/metrics/"><span>Choisir les données</span>Recherchez les métriques Apple Health et ajustez les catégories ou les autorisations spéciales.</a>
  <a href="/fr/docs/format/"><span>Structurer le résultat</span>Configurez les formats, les dates, les unités, le frontmatter, les modèles et les noms de fichiers.</a>
  <a href="/fr/docs/scheduling/"><span>Automatiser</span>Planifiez des exports récurrents après avoir vérifié une exécution manuelle.</a>
  <a href="/fr/docs/folder-vault/"><span>Corriger une destination</span>Comprenez les fournisseurs Fichiers, l’accès aux dossiers et la récupération.</a>
</div>
