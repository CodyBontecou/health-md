---
title: "Planifier les exports Apple Health et résoudre les exécutions manquées"
description: "Vérifiez un export planifié, sa période rétrospective et sa reprise. iOS ne garantit pas l’heure ; Réessayer dans l’historique utilise les réglages actuels."
---

Cette page décrit la planification sur iPhone. Android a d’autres autorisations en arrière-plan et conditions d’achat ; consultez [l’automatisation Android](/fr/docs/android/).

## Vérifier le premier export planifié

1. Activez le profil prévu. Vérifiez mesures, formats, niveau de détail, mode d’écriture et destination. Exportez manuellement une journée terminée et contrôlez le fichier ou le résultat du point de terminaison avant d’automatiser.
2. Ouvrez Planification, puis Configurer ou Gérer la planification. Activez-la, choisissez quotidienne, hebdomadaire ou personnalisée, réglez l’heure et commencez par une journée terminée. Autorisez les notifications pour les rappels locaux de reprise.
3. Vérifiez l’activation, la prochaine occurrence et le dernier résultat. Après un essai, examinez l’historique et la destination réelle ; une date prévue ou une notification ne prouve pas une écriture.
4. Contrôlez dates, unités, couverture et données manquantes. Un fichier enregistré ne prouve pas, à lui seul, une capture complète.

Sur Apple, une demande planifiée exportant au moins une date partage les cinq actions gratuites avec les exports manuels et les autres actions comptabilisées. Full Access supprime cette limite commune. Consultez [le déverrouillage et les achats](/fr/docs/paywall/).

## Comprendre la fenêtre des journées terminées

Les fréquences quotidienne, hebdomadaire et personnalisée peuvent inclure une période rétrospective. La cadence personnalisée répète tous les N jours, semaines ou mois depuis sa date de départ. Chaque nouvelle occurrence réexporte toute la fenêtre configurée, y compris des dates déjà exportées. Trois jours couvrent hier et les deux jours précédents ; un retard ne déplace pas l’ancrage du jour prévu.

L’actualisation du jour est indépendante et ne remplace pas cette fenêtre. Vérifiez chemins et mode d’écriture en cas de chevauchement ; plusieurs instantanés d’une journée ne sont pas de nouvelles mesures.

## Choisir la bonne reprise

- **Demande planifiée en attente :** déverrouillez l’iPhone, ouvrez Health.md et examinez la demande. Elle conserve ses dates exactes non résolues, réglages et destination. Les dates terminées le restent ; la reprise n’étend pas la période.
- **Réessayer depuis l’historique :** lance une nouvelle exécution pour cette période avec les réglages et la destination actuels et crée une nouvelle ligne. Vérifiez la configuration active avant de réessayer. Ce n’est pas la reprise de la demande figée.
- **Destination modifiée ou inaccessible :** rétablissez l’accès ou examinez le profil en attente. Une ancienne reprise API sur iPhone ne doit pas adopter silencieusement un autre point de terminaison ou identifiant. Ne multipliez pas les tentatives tant que l’original reste non résolu.

Consultez [les profils d’export](/fr/docs/export-profiles/) pour les règles de reprise, d’identité et de destination.

## Ce qu’iOS garantit ou non

L’heure est une cible, pas une fin garantie. iOS décide du temps d’exécution en arrière-plan et le verrouillage peut empêcher la lecture HealthKit. Les demandes et notifications silencieuses ne contournent pas cette protection.

Les rappels locaux nécessitent l’autorisation de notification et ne garantissent pas une livraison à l’heure prévue. Si un rappel arrive, déverrouillez l’appareil et ouvrez-le pour tenter la reprise. Sinon, ouvrez Health.md et vérifiez les demandes et l’historique. Contrôlez le résultat plutôt que déduire la réussite d’une alerte ou du temps écoulé.

## Contrôle par programmation
<p>Vous pouvez activer ou désactiver la planification depuis Shortcuts à l’aide de l’App Intent <em>Turn Scheduled Export On or Off</em>. <a href="/fr/docs/shortcuts/">Voir Shortcuts</a> pour des exemples.</p>

## Planifications par profil et annulation

- Chaque profil conserve sa propre planification, y compris une cadence personnalisée ; changer le profil actif ne redirige pas une autre planification.
- Un avertissement de collision apparaît lorsque des profils pourraient écrire les mêmes chemins générés vers la même destination. Vérifiez-le avant d’activer des planifications concurrentes ; Health.md ne modifie aucun profil en silence.
- Arrêter ou Annuler termine seulement la tentative en cours. Les dates terminées restent acquises, les autres sont réessayables et la planification reste active.
- Chaque ligne d’historique reste liée au profil d’exécution et au libellé confidentiel de la destination réellement utilisée.

Gérez réglages figés et destination dans [Profils d’exportation](/fr/docs/export-profiles/).

## Pages associées
<div class="related">
  <a href="/fr/docs/export-profiles/"><span>Profils</span>Gérez des planifications et destinations indépendantes.</a>
  <a href="/fr/docs/export/"><span>Manuel</span>Export — pour des plages de dates ponctuelles.</a>
  <a href="/fr/docs/shortcuts/"><span>Automatiser</span>Shortcuts — activez ou désactivez la planification depuis des automatisations.</a>
  <a href="/fr/docs/sync/"><span>Plusieurs appareils</span>Synchronisation Mac — planifiez également sur Mac.</a>
</div>
