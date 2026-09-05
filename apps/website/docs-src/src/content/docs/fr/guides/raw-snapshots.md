---
title: Instantanés d’API brutes
description: Exportez des instantanés JSON ou NDJSON immuables et versionnés d’enregistrements Health Connect et de réponses des fournisseurs Fitbit, Oura, WHOOP et Withings, avec manifestes par type et sommes de contrôle.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Android · export de qualité archivistique</p>
  <p>Raw API Snapshot est un produit d’export distinct de Health.md pour Android, conçu pour les workflows de migration et d’archivage : un artefact JSON ou NDJSON immuable et versionné par plage sélectionnée, qui préserve les enregistrements natifs.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Disponible sur Google Play</a>
    <a class="docs-button-secondary" href="/fr/docs/android/">Guide de l’app Android</a>
  </div>
</div>

## Ce qu’est un instantané brut

Les exports de compatibilité convertissent les enregistrements Health Connect en résumés quotidiens lisibles de `HealthData`. Un instantané brut saute entièrement cette conversion :

- **Les instantanés Health Connect** préservent chaque champ exposé par l’API AndroidX épinglée, y compris identité et métadonnées natives, horodatages en nanosecondes, décalages sources nullables, valeurs d’énum brutes, échantillons imbriqués, étapes, parcours et structures d’entraînements planifiés.
- **Les instantanés Fitbit, Oura, WHOOP et Withings** préservent les octets exacts des réponses réussies du fournisseur et révèlent la pagination du point de terminaison et l’agrégation côté serveur. Les fournisseurs non pris en charge sont signalés au lieu d’être normalisés ou remplacés silencieusement par des données Health Connect.
- Chaque artefact se termine par un **manifeste** contenant l’état, les problèmes, les décomptes et les sommes de contrôle par type. Les exports de dossier reçoivent aussi un fichier annexe `.sha256`.

Un instantané brut est complet vis-à-vis de l’API fournisseur épinglée de l’app ; ce n’est pas une sauvegarde transactionnelle de la base de données du fournisseur. Il ne peut pas récupérer des enregistrements inaccessibles, des unités d’origine que l’API n’expose pas, des enregistrements supprimés ou des champs inconnus du SDK installé.

## Aperçu avant destination

Les instantanés bruts peuvent être prévisualisés sans destination configurée. L’aperçu effectue la lecture native complète du fournisseur vers un stockage privé sans sauvegarde, ne garde en mémoire qu’un texte de tête et de queue borné, puis supprime l’artefact temporaire sans rien téléverser.

## Règles de livraison

Les téléversements d’API brute sont volontairement plus stricts que les exports d’API de compatibilité :

| Règle | Raison |
|---|---|
| HTTPS uniquement | L’artefact diffusé ne voyage jamais en clair |
| Redirections rejetées | L’artefact et les identifiants ne peuvent jamais être rejoués vers une autre origine |
| En-têtes de schéma, d’export et de somme de contrôle | Le point de terminaison receveur peut vérifier ce qu’il a accepté |
| Artefact privé temporaire supprimé après la tentative | Aucune copie ne subsiste sur l’appareil |

## Archives incrémentales

Le backend `healthmd.raw-changes`, versionné séparément, utilise des jetons de changement Health Connect et des marqueurs de suppression (tombstones) pour de futurs workflows d’archivage incrémental, si bien qu’un instantané complet n’a pas à être la seule stratégie d’archivage.

## Prérequis

- Health.md pour Android avec le produit Raw API Snapshot.
- Des autorisations Health Connect pour les types d’enregistrements sélectionnés, ou un compte Fitbit, Oura, WHOOP ou Withings connecté pour les instantanés de fournisseur.
- Un point de terminaison HTTPS si vous téléversez des instantanés ; l’export local vers un dossier n’a aucune exigence de transport.

## Pour aller plus loin

- [Contrat d’instantané brut v1](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-snapshot-v1.md)
- [Contrat d’enregistrement brut v1](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-record-v1.md)
- [Contrat de changements bruts v1](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-changes-v1.md)
