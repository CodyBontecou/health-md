---
title: "Profils d’exportation"
description: "Enregistrez ensemble les réglages d’exportation et une destination, puis exécutez ou planifiez cette configuration sur iPhone, Android, avec Raccourcis, la CLI, Tasker ou adb."
---

Les profils d’exportation regroupent une configuration reproductible. Gérez-les dans Health.md sur iPhone ou Android. Sur les plateformes Apple, le parcours de gestion actuel est documenté et testé uniquement sur iPhone ; aucune interface de gestion sur iPad ou Mac n’est revendiquée.

## Gérer et modifier les profils

Ouvrez **Réglages → Profils d’exportation**. La liste indique le profil actif et permet de créer, renommer, dupliquer, supprimer, activer ou consulter les profils. Ouvrez la fiche d’un profil pour copier son identifiant stable. Le dernier profil ne peut pas être supprimé.

L’onglet Exporter modifie le profil actif. Activez-en un autre avant de changer les réglages si vous ne souhaitez pas mettre à jour le profil actuel.

Chaque profil fige les choix nécessaires pour reproduire une exécution :

- métriques sélectionnées, détail des données, formats, modèles, noms de fichiers, unités et mode d’écriture ;
- son propre dossier de destination et sous-dossier, un endpoint d’API ou un Mac connecté lorsque la plateforme le prend en charge ;
- notes quotidiennes, entrées individuelles, synthèses et autres options de sortie prises en charge par la plateforme.

Une planification est liée séparément à l’identité stable du profil. Changer de profil actif ne redirige pas cette planification. Une exécution utilise l’instantané enregistré au lieu d’emprunter les réglages modifiés d’un autre profil.

## Exécuter et planifier en toute sécurité

- Un profil peut disposer de sa propre planification récurrente, y compris la cadence personnalisée proposée par l’app.
- Les droits de chaque plateforme s’appliquent toujours : l’allocation gratuite Apple peut inclure des actions planifiées, tandis que la planification Android exige l’achat à vie.
- Health.md avertit lorsque des profils pourraient écrire les mêmes chemins générés vers la même destination. L’avertissement ne modifie silencieusement ni profil ni planification.
- Arrêter ou annuler ne concerne que la tentative en cours. Les dates terminées restent acquises, les dates non résolues restent réessayables et la planification demeure activée.
- Si le profil demandé manque, Health.md échoue de façon sûre. L’app ne se rabat jamais sur le profil actif ni sur une autre destination.

## Noms, identifiants stables et automatisation

Le nom affiché est destiné aux personnes et peut changer. L’identifiant stable permet une automatisation qui résiste aux changements de nom. Copiez-le dans **Réglages → Profils d’exportation → ID du profil**.

- Raccourcis Apple sélectionne un profil par son nom affiché ; un paramètre de profil vide utilise le profil actif.
- Les diffusions Tasker et adb sur Android peuvent fournir l’extra `PROFILE` avec un identifiant stable ou un nom. Préférez l’identifiant pour les flux qui doivent résister aux changements de nom.
- La CLI directe accepte `--profile PROFILE_ID` pour les tâches de fichiers générés compatibles. Le profil fournit ses réglages de sortie figés ; le paramètre `--destination` obligatoire sélectionne toujours le dossier existant sur l’ordinateur.

Consultez le guide d’automatisation de la plateforme avant d’activer un flux sans surveillance.

## Historique, récupération et confidentialité

Les lignes d’historique des exécutions planifiées et automatisées liées à un profil enregistrent le profil utilisé. L’historique conserve aussi un libellé respectueux de la confidentialité pour la destination réelle. Une exécution manuelle depuis l’onglet Exporter peut ne pas joindre le nom du profil, même si elle utilise les réglages du profil actif. Renommer ensuite un profil, changer sa destination ou en sélectionner un autre ne réécrit pas l’historique existant.

Un nouvel essai lancé depuis l’historique des exportations utilise les réglages et la destination actuellement configurés, puis crée une nouvelle ligne indiquant ce qui a réellement été utilisé. Il ne prétend pas que le profil d’origine a gouverné l’essai. En revanche, la récupération ou la reprise d’une tentative planifiée non résolue conserve ses dates, réglages et destination exacts.

Les profils et leurs planifications sont des réglages locaux à l’appareil. Ils ne sont pas synchronisés entre iPhone, iPad, Mac et Android. Recréez la configuration voulue sur chaque appareil et vérifiez sa destination avant d’activer l’automatisation.

## Voir aussi

<div class="related">
  <a href="/fr/docs/export/"><span>Exporter</span>Choisissez le détail, prévisualisez la sortie et exportez une plage de dates.</a>
  <a href="/fr/docs/scheduling/"><span>Planification</span>Comprenez les cadences, la récupération et les limites horaires des plateformes.</a>
  <a href="/fr/docs/shortcuts/"><span>Raccourcis</span>Sélectionnez un profil enregistré dans les automatisations Apple.</a>
  <a href="/fr/docs/android/"><span>Automatisation Android</span>Utilisez les actions Tasker et adb liées aux profils.</a>
  <a href="/fr/docs/cli-direct/"><span>CLI directe</span>Exécutez les réglages enregistrés du profil dans un dossier explicite de l’ordinateur.</a>
</div>
