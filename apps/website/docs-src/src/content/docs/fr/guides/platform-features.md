---
title: Fonctionnalités par plateforme
description: Ce que Health.md offre sur iPhone, iPad, Mac, Android, Wear OS et la CLI — fonctions communes et différences de plateforme assumées.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Vue d’ensemble des plateformes</p>
  <p>Ce que fait Health.md sur iPhone, iPad, Mac, Android, Wear OS et la CLI — commun partout où les plateformes le permettent, honnête là où elles diffèrent.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://apps.apple.com/us/app/health-md/id6757763969" target="_blank" rel="noopener">iPhone et Mac</a>
    <a class="docs-button-secondary" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Android</a>
  </div>
</div>

**Les entrées Wear OS sont des fonctions prévues, absentes de la version Google Play actuelle.**

Légende : ✓ disponible · ◐ disponible avec des différences de plateforme indiquées dans la ligne · △ prévu ou en phase de tests · ? disponibilité non revendiquée · — indisponible sur cette plateforme.

La CLI n’est pas une colonne de plateforme de données de santé distincte : les fonctions de la CLI apparaissent dans les lignes d’automatisation et conservent la sémantique de leur source iPhone ou Android.

## Configuration et autorisations

| Fonctionnalité | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Autorisations de données de santé (choisissez exactement ce qui est lu) | ✓ types Apple Health | ◐ lit via l’iPhone jumelé / destination Mac | ✓ catégories Health Connect | — |
| Choisir la destination d’export | ✓ coffre Obsidian, iCloud Drive, Fichiers | ✓ dossiers locaux | ✓ tout fournisseur de dossiers Android (Drive, OneDrive, Syncthing, Obsidian Sync…) | — |
| Configuration initiale avec aperçu d’exemple | ✓ | ✓ | ✓ | — |
| Share My Setup (transférer les préférences entre appareils) | △ en QA | △ en QA | △ en QA | — |

## Lecture et export

| Fonctionnalité | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Exports quotidiens vers Markdown, Obsidian Bases, JSON, CSV | ✓ | ✓ (les fichiers arrivent depuis l’iPhone) | ✓ | — |
| 225+ métriques Apple Health / 106 métriques Health Connect | ✓ | ✓ | ✓ | — |
| Aperçu avant écriture | ✓ | ✓ | ✓ | — |
| Profils d’export enregistrés avec réglages indépendants | ✓ gestion sur l’iPhone ; ? gestion sur iPad non revendiquée | ? gestion non revendiquée | ✓ gestion sur Android | — |
| Synthèses hebdomadaires / mensuelles / annuelles | ✓ | ✓ | △ prévu ; nécessite un profil de schéma Android revu séparément (v4/v5 actuelles inchangées) | — |
| Historique d’export et nouvelle tentative | ✓ | ✓ | ✓ | — |
| Arrêter ou annuler l’exécution en cours sans désactiver sa planification | ✓ dates terminées conservées ; dates non résolues réessayables | ✓ | ✓ dates terminées conservées ; dates non résolues réessayables | — |
| Archive ZIP d’une seule exécution | ✓ | ✓ | — | — |
| Détail de données du résumé | ✓ | ✓ | ✓ | — |
| Série chronologique détaillée pour les métriques sélectionnées | ✓ | ✓ | ✓ | — |
| Archive canonique des enregistrements sources des Dossiers de santé sans perte | ✓ `healthmd.healthkit_records` | ✓ | — réservé à Apple ; voir les instantanés d’API brutes à la place | — |
| Export d’instantanés d’API brutes (JSON/NDJSON immuable) | — | — | ✓ Health Connect + Fitbit, Oura, WHOOP, Withings | — |

## Données avancées

| Fonctionnalité | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Suivi individuel des entrées (séances d’entraînement, phases de sommeil, constantes) | ✓ | ✓ | ✓ | — |
| Détails des séances avec graphiques complets et parcours lorsque disponibles | ✓ | ✓ | ✓ | — |
| Export d’humeur / State of Mind | ✓ | ✓ | — (pas d’équivalent Health Connect) | — |
| Événements de doses de médicaments | ✓ | ✓ | — (pas d’équivalent Health Connect) | — |
| Mesures de tension, de glucose, d’oxygène et de température | ✓ | ✓ | ✓ | — |
| Données de fournisseurs tiers | ◐ section WHOOP dans l’export (bêta) | ◐ | ✓ instantanés bruts natifs du fournisseur | — |

Certaines données ne sont volontairement **pas traitées comme équivalentes** selon les plateformes : la variabilité de la fréquence cardiaque est SDNN sur Apple et RMSSD sur Android et WHOOP — Health.md les conserve comme des métriques distinctes au lieu de les fusionner. La température du poignet de l’Apple Watch et la température cutanée de Health Connect sont également maintenues séparées.

## Automatiser et intégrer

| Fonctionnalité | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Exports récurrents planifiés | ✓ notifications + repli APNs | ✓ | ✓ WorkManager (+ alarme exacte en option), reprise après redémarrage | — |
| Automatisation système | ✓ Raccourcis / Siri / App Intents | — | ✓ Tasker, adb, intents de diffusion explicites | — |
| Envoyer les exports vers votre propre point de terminaison d’API HTTP(S) | ✓ | — | ✓ avec stockage chiffré des en-têtes | — |
| Jumelage avec la CLI autonome (`healthmd`) | ✓ service direct au premier plan | ✓ intégrée + autonome | ✓ jumelage par code à 20 chiffres | — |
| Réveil pour les requêtes CLI directes | ✓ attente limitée + APNs sur adhésion | ✓ initiateur CLI | ◐ attente limitée ; FCM prévu | — |
| Serveur MCP pour agents IA | ◐ intégré via le Mac ; le MCP direct typé et portable est réservé à l’iPhone | ✓ intégré en tant que `healthmd-mcp` | — MCP direct typé non pris en charge | — |

## Appareils et surfaces d’un coup d’œil

| Fonctionnalité | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Widgets d’écran d’accueil | ✓ résumé, anneaux d’activité, plage cardiaque, sommeil | — | ✓ résumé, activité, plage cardiaque, sommeil (les pas remplacent les heures debout) | — |
| Progression de l’export en Activité en direct | ✓ | — | — | — |
| Surfaces de la montre | ✓ app montre + 10 complications | — | — | △ prévu pour 1.10.0 |
| Mac comme destination d’export (transfert local chiffré) | ✓ l’iPhone envoie | ✓ reçoit | — | — |

## Achat et confidentialité

| Fonctionnalité | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Offre gratuite | ✓ 10 actions d’export manuelles ou planifiées | — | ✓ 10 actions d’export manuelles | — |
| Déverrouillage | ✓ achat à vie unique (individuel / familial) | ◐ même déverrouillage Apple | ✓ achat à vie unique, planification incluse | — |
| Confidentialité à traitement local | ✓ aucun cloud de données de santé Health.md | ✓ | ✓ | △ prévu |
| Rapport clinicien (un PDF pour les rendez-vous) | ✓ | — | ✓ | — |

Health.md n’exploite aucun cloud de données de santé. Les données de santé peuvent exister dans les destinations de votre choix, dans un contexte local chiffré et dans un état de transfert privé limité. Chaque dossier, Mac, point de terminaison API ou destination CLI est configuré explicitement. Les profils et planifications restent locaux à l’appareil où ils ont été créés. Pour le déroulé de chaque plateforme, voir les [profils d’export](/fr/docs/export-profiles/), le [guide Android](/fr/docs/android/) et le [guide d’export iPhone](/fr/docs/export/).
