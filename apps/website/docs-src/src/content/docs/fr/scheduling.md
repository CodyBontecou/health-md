---
title: "Planifier les exportations Apple Health et résoudre les problèmes d'exécutions manquées"
description: "Vérifiez une exportation planifiée, comprenez l’analyse des jours terminés et récupérez les dates en attente. Le timing d'arrière-plan iPhone est le meilleur effort ; historique La nouvelle tentative utilise les paramètres actuels."
---

Cette page décrit la planification iPhone . Android a des autorisations d'arrière-plan et des exigences d'achat différentes ; voir [Automation Android](/fr/docs/android/).

## Vérifiez la première exportation planifiée

1. Activer le profil souhaité. Vérifiez ses métriques, ses formats, les détails des données, son comportement d'écriture et sa destination. Exécutez manuellement une journée complète et inspectez le fichier enregistré ou le résultat du point de terminaison avant d'activer l'automatisation.
2. Ouvrez le programme, puis configurez le programme ou gérez le programme. Activez le calendrier, choisissez Quotidien, Hebdomadaire ou Personnalisé, définissez l'heure et commencez par une rétrospective d'une journée terminée. Autorisez les notifications si vous souhaitez des rappels de récupération locaux.
3. Vérifiez si la planification est activée, la prochaine occurrence et le dernier résultat. Après une tentative, inspectez les détails de son historique et la destination réelle ; une étiquette ou une notification de prochaine exécution ne constitue pas une preuve que les données ont été écrites.
4. Vérifiez les dates exportées, les unités, la couverture et les données manquantes. Un fichier enregistré ne prouve pas en soi une capture complète de la source.

Dans la version téléphonique avec abonnement, les exportations planifiées et manuelles nécessitent un essai actif, un abonnement, un achat à vie ou un accès permanent préservé. Il n'existe pas d'autorisation locale de libre exportation. L’accès expiré doit être restauré avant que les travaux en attente puissent reprendre. Voir [déverrouillage et paywall](/fr/docs/paywall/).

## Comprendre la fenêtre d'une journée terminée

Les plannings quotidiens, hebdomadaires et personnalisés peuvent avoir un aperçu. La cadence personnalisée se répète tous les N jours, semaines ou mois à compter de sa date de début. Chaque nouvelle occurrence réexporte l'intégralité de la fenêtre de jour terminée configurée, y compris les dates exportées auparavant. Une analyse rétrospective de trois jours couvre hier et les deux jours précédents ; l'exécution retardée maintient la fenêtre ancrée au jour d'incendie prévu.

Today Refresh est un travail distinct de la journée en cours et ne remplace pas la fenêtre de la journée terminée. Inspectez les chemins et le comportement d'écriture avant de chevaucher les exportations ; n’ajoutez pas de clichés quotidiens répétés en tant que nouvelles mesures.

## Choisissez le bon chemin de récupération

- **En attente de récupération planifiée :** déverrouillez le iPhone , ouvrez Health.md et inspectez la tentative en attente. Il conserve ses dates exactes non résolues, ses paramètres enregistrés et sa destination. Les dates terminées restent terminées ; la reprise ne s’étend pas à une nouvelle rétrospective.
- **Réessayer depuis l'historique :** cela démarre une nouvelle exécution pour cette plage en utilisant les paramètres et la destination actuellement configurés et enregistre une nouvelle ligne d'historique. Vérifiez la configuration active avant d’appuyer sur Réessayer. Ce n’est pas la même chose que de reprendre une tentative en attente gelée.
- **Destination modifiée ou indisponible :** restaurez l'accès ou inspectez le profil en attente avant de réessayer. Une ancienne récupération d'API iPhone ne doit pas adopter silencieusement un point de terminaison ou des informations d'identification modifiés. Ne lancez pas de nouvelles tentatives à plusieurs reprises alors que la tentative d'origine n'est pas résolue.

Consultez les règles de récupération en attente, d'identité du profil et de destination dans [Exporter les profils](/fr/docs/export-profiles/).

## Ce que fait et ne garantit pas iOS

L'heure sélectionnée est un objectif et non une heure d'achèvement garantie. iOS contrôle l'exécution en arrière-plan et la protection des appareils verrouillés peut empêcher les lectures HealthKit . Les demandes en arrière-plan et les notifications de réveil silencieuses ne contournent pas cette protection.

Les notifications de récupération locale nécessitent une autorisation de notification et ne constituent pas une garantie de livraison à l'heure cible. Si vous en recevez un, déverrouillez l'appareil et ouvrez-le pour permettre à Health.md de tenter la récupération. Si aucune notification n'arrive, ouvrez Health.md et vérifiez le travail et l'historique en attente. Vérifiez le résultat plutôt que de supposer qu’une alerte ou le temps écoulé est synonyme de succès.

## Contrôle programmatique
 <p> Vous pouvez activer/désactiver la planification à partir de Shortcuts à l'aide de l'intention <em> Activer ou désactiver l'exportation programmée </em> . <a href="/fr/docs/shortcuts/"> Voir Shortcuts </a> pour des exemples. </p>

## Horaires et annulation des profils

- Chaque profil peut conserver son propre horaire, y compris une cadence personnalisée. Le changement de profil actif ne recible pas le planning d'un autre profil.
- Un avertissement de collision apparaît lorsque les profils peuvent écrire les mêmes chemins rendus à la même destination. Vérifiez-le avant d'activer des planifications concurrentes. Health.md ne modifie silencieusement aucun des deux profils.
- Stop ou Cancel met fin uniquement à la tentative en cours. Les dates terminées restent terminées, les dates non résolues peuvent être réessayées et la planification reste activée.
- Chaque ligne de l'historique reste épinglée au profil d'exécution et à l'étiquette de destination sécurisée réellement utilisée.

Gérez les paramètres gelés et la destination par profil dans [Exporter les profils](/fr/docs/export-profiles/).

## En rapport

<div class="related">
 <a href="/fr/docs/export-profiles/"> <span> Flux de travail multiples </span> Profils d'exportation, donnez à chaque configuration enregistrée sa propre destination et sa propre cadence. </a>
 <a href="/fr/docs/export/"> <span> Manuel </span> Exportation, pour des plages de dates uniques. </a>
 <a href="/fr/docs/shortcuts/"> <span> Automatiser </span> Shortcuts , basculer le calendrier des automatisations. </a>
 <a href="/fr/docs/sync/"> <span> Multi-appareils </span> Mac Sync, planifiez également sur Mac. </a>
 </div>
