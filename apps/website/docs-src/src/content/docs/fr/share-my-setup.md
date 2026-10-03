---
title: "Partager ma configuration"
description: "Examinez le transfert de profils v2 réservé au développement, sans données de santé, identifiants, achats ni confiance d’appareil."
---

<div class="availability preview"><strong>Aperçu de développement · non qualifié pour publication</strong><p>Le contrat v2 reste pré-canonique et planifié jusqu’aux validations d’interopérabilité et d’accessibilité sur appareils. Ne l’utilisez pas en production.</p></div>

Share My Setup regroupe un ou plusieurs profils. Il transfère métriques, formats, nommage, organisation et intention de destination. Il n’inclut jamais données de santé, jetons, accès réel aux dossiers, associations, achats, historique ou tâches.

1. Sur la source, ouvrir **Réglages → Share My Setup** et exporter le fichier v2.
2. L’ouvrir sur la cible et examiner chaque profil.
3. Choisir **Ajouter** ou **Remplacer**.
4. Relier localement dossier, API avec identifiants ou Mac.
5. Appliquer et tester une petite exportation.

La transaction est atomique et propose une seule action **Annuler**. Les profils restent bloqués jusqu’à la liaison de destination ; les planifications sont désactivées. Le code de développement actuel écrit uniquement `healthmd.shared_setup` v2 ; v1 est refusé.

<div class="related"><a href="/fr/docs/export-profiles/"><span>Profils</span>Réglages figés.</a><a href="/fr/docs/guides/platform-features/"><span>État</span>Qualification par plateforme.</a></div>
