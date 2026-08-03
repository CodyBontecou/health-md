---
title: "Planification"
description: "Lancez automatiquement des exports, chaque jour ou chaque semaine, à l’heure choisie. Utilise les tâches d’arrière-plan iOS et, si l’appareil est verrouillé, une notification locale planifiée comme solution de repli."
---

## L’onglet Planification
<p>Il s’agit d’un écran d’état, pas d’un panneau de réglages. Il indique en un coup d’œil :</p>
<ul>
<li>si la planification est activée ou non ;</li>
<li>la prochaine exécution planifiée, le cas échéant ;</li>
<li>le résultat de la dernière exécution.</li>
</ul>
<p>Un seul bouton, <em>Configurer la planification</em> (ou <em>Gérer la planification</em>), ouvre la vue détaillée.</p>

## Réglages de planification
<div class="options">
<div class="option"><strong>Activer les exports planifiés</strong><p>Interrupteur principal en haut. Lorsqu’il est désactivé, il n’y a ni exécution en arrière-plan ni notification.</p></div>
<div class="option"><strong>Fréquence</strong><p>Quotidienne, hebdomadaire ou mensuelle. Les exports quotidiens couvrent la veille, les exports hebdomadaires les 7 jours précédents et les exports mensuels les 30 jours précédents.</p></div>
<div class="option"><strong>Heure</strong><p>Heure et minute. Pour iOS, ce réglage est une indication et non une garantie ; consultez l’encadré sur les limites ci-dessous.</p></div>
</div>

## Historique des exports
<p>La liste au bas de l’écran Planification consigne chaque exécution planifiée et son résultat. Touchez une ligne pour afficher les détails. Les échecs comportent un bouton <em>Réessayer</em> qui relance précisément la plage de dates concernée.</p>

## Fonctionnement réel de la planification iOS
<div class="doc-diagram">
  <div class="flow-steps" aria-label="Flux de repli d’un export planifié">
    <span><strong>1. Heure cible</strong>Health.md demande à iOS de réveiller l’app autour de l’heure choisie.</span>
    <span><strong>2. Tentative en arrière-plan</strong>Si l’appareil est disponible, iOS exécute une tâche d’actualisation en arrière-plan.</span>
    <span><strong>3. Repli si verrouillé</strong>Si HealthKit est indisponible, Health.md affiche une notification.</span>
    <span><strong>4. Toucher pour terminer</strong>L’ouverture de la notification permet à l’app de lire HealthKit et d’exporter.</span>
  </div>
</div>

<div class="callout">
<strong>Limites d’iOS à connaître.</strong>
<p style="margin-top:6px;">Les données HealthKit ne sont pas lisibles lorsque l’appareil est verrouillé. Les exports planifiés utilisent <code>BGAppRefreshTask</code>, qu’iOS programme de manière opportuniste selon les habitudes d’utilisation : l’heure définie est une cible, pas un engagement. Comme solution de repli, l’app affiche une notification locale à l’heure prévue si l’appareil est verrouillé ; touchez-la pour lancer l’export.</p>
</div>
<ul>
<li>L’heure planifiée est approximative. iOS peut exécuter la tâche plus tôt ou plus tard, voire l’ignorer si l’appareil est éteint ou déconnecté.</li>
<li>Les exports planifiés fonctionnent mieux si le téléphone est régulièrement branché et déverrouillé à peu près à la même heure chaque jour.</li>
<li>Si l’export échoue parce que l’appareil était verrouillé, touchez la notification : l’export sera alors lancé avec l’accès à HealthKit.</li>
</ul>

## Contrôle par programmation
<p>Vous pouvez activer ou désactiver la planification depuis Shortcuts à l’aide de l’App Intent <em>Turn Scheduled Export On or Off</em>. <a href="/fr/docs/shortcuts/">Voir Shortcuts</a> pour des exemples.</p>

## Pages associées
<div class="related">
  <a href="/fr/docs/export/"><span>Manuel</span>Export — pour des plages de dates ponctuelles.</a>
  <a href="/fr/docs/shortcuts/"><span>Automatiser</span>Shortcuts — activez ou désactivez la planification depuis des automatisations.</a>
  <a href="/fr/docs/sync/"><span>Plusieurs appareils</span>Synchronisation Mac — planifiez également sur Mac.</a>
</div>
