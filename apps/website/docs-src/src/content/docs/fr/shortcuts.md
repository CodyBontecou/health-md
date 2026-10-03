---
title: "Raccourcis et App Intents"
description: "Utilisez sept actions publiées et deux actions de contexte Mac du code en développement dans Raccourcis et Siri."
---

<div class="availability preview"><strong>Sept actions publiées · neuf dans le code actuel</strong><p>Les deux actions de contexte Mac exigent des builds iPhone/Mac compatibles. Vérifiez les notes de la version exacte.</p></div>

## Actions

- exporter hier, une date, une plage ou les N derniers jours ;
- obtenir un résumé santé ou le dernier état d’exportation ;
- activer ou suspendre la planification ;
- **Refresh Mac Health Context** (développement) : mise à jour chiffrée durable liée à un profil ;
- **Get Mac Context Refresh Status** (développement) : état et job ID.

Les quatre actions d’exportation acceptent un **Profil** facultatif. Un nom inconnu échoue sans repli. Les exportations ordinaires écrivent dans le dossier iPhone et ne basculent pas silencieusement vers API Endpoint ou Connected Mac.

Autoriser l’exécution verrouillée ne déverrouille pas HealthKit. Health.md conserve la demande et affiche **Health Export Needs Attention**.

### Automatisation du matin

1. Créer une automatisation horaire.
2. Ajouter **Export Yesterday's Health Data**.
3. Ajouter **Get Last Export Status** et une notification.

Hier inclut le sommeil dont la nuit a commencé hier. Voir [Dates du sommeil](/fr/docs/sleep-date-attribution/).

<div class="related"><a href="/fr/docs/export-profiles/"><span>Profils</span>Identités stables.</a><a href="/fr/docs/release-status/"><span>Compatibilité</span>Versions qualifiées.</a></div>
