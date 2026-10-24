---
title: "Raccourcis et App Intents"
description: "Utilisez sept actions Health.md dans Raccourcis et Siri. Les actions d’actualisation du contexte Mac sont proposées, pas disponibles."
---

<div class="availability preview"><strong>Sept actions enregistrées dans le code</strong><p>Refresh Mac Health Context et Get Mac Context Refresh Status sont proposées, non implémentées et non disponibles en développement. Suivez le <a href="https://github.com/CodyBontecou/health-md/issues/173">ticket #173</a> ; leur disponibilité exige une implémentation, une qualification et les notes d’une version Apple exacte.</p></div>

## Actions

- exporter hier, une date, une plage ou les N derniers jours ;
- obtenir un résumé santé ou le dernier état d’exportation ;
- activer ou suspendre la planification.

### Actions de contexte Mac proposées (non disponibles)

L’action demandée **Refresh Mac Health Context** utiliserait une portée explicite de profil et de dates, des appareils compatibles authentifiés et une acquisition durable du contexte sans fichiers d’exportation ni consommation du quota d’exportation de fichiers. **Get Mac Context Refresh Status** signalerait l’état en attente/terminé/échoué avec une identité de tâche récupérable. Il s’agit d’exigences, pas de noms d’actions, paramètres ou résultats pris en charge dans l’application actuelle.

L’actualisation MCP depuis l’ordinateur ne fournit pas une automatisation personnelle iOS. N’utilisez pas les raccourcis d’exportation ordinaires comme substitut : ils conservent la destination dossier iPhone. Aucune automatisation ne peut promettre de réveiller un Mac endormi ni de contourner les données protégées de HealthKit. La vérification d’une automatisation après réveil sur un iPhone physique reste nécessaire avant de qualifier cette fonction.

Les quatre actions d’exportation acceptent un **Profil** facultatif. Un nom inconnu échoue sans repli. Les exportations ordinaires écrivent dans le dossier iPhone et ne basculent pas silencieusement vers API Endpoint ou Connected Mac.

Autoriser l’exécution verrouillée ne déverrouille pas HealthKit. Health.md conserve la demande et affiche **Health Export Needs Attention**.

### Automatisation du matin

1. Créer une automatisation horaire.
2. Ajouter **Export Yesterday's Health Data**.
3. Ajouter **Get Last Export Status** et une notification.

Hier inclut le sommeil dont la nuit a commencé hier. Voir [Dates du sommeil](/fr/docs/sleep-date-attribution/).

<div class="related"><a href="/fr/docs/export-profiles/"><span>Profils</span>Identités stables.</a><a href="/fr/docs/release-status/"><span>Compatibilité</span>Versions qualifiées.</a></div>
