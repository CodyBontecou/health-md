---
title: Compagnon Wear OS
description: Health.md pour Wear OS ajoute à votre montre des tuiles d’activité et de récupération ainsi que dix complications santé, le téléphone restant l’autorité Health Connect.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Android · Wear OS</p>
  <p>Health.md propose un compagnon Wear OS sous la même fiche Google Play que l’app du téléphone. Ajoutez des surfaces santé consultables d’un coup d’œil à votre montre tandis que votre téléphone reste l’unique autorité Health Connect.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Disponible sur Google Play</a>
    <a class="docs-button-secondary" href="/fr/docs/android/">Guide de l’app Android</a>
  </div>
</div>

## Ce que la montre affiche

| Surface | Ce que vous obtenez |
|---|---|
| Tuile Activité du jour | Le résumé d’activité du jour sous forme de tuile de cadran |
| Tuile Récupération | Le résumé de récupération du jour sous forme de tuile de cadran |
| Complications (10) | Activité, Récupération, Pas, Mouvement, Exercice, Sommeil, Fréquence cardiaque au repos, Fréquence cardiaque moyenne, VFC et Oxygène sanguin sous forme de complications de cadran |

Les complications peuvent être ajoutées à la plupart des cadrans depuis l’éditeur de cadran, et les tuiles apparaissent dans le carrousel de tuiles de la montre.

## Comment ça marche

- L’app montre est distribuée sous la même fiche Play et la même identité de signature que l’app téléphone.
- Les données de santé circulent du téléphone vers la montre via la couche de données Wear OS sous forme d’un instantané agrégé privé. La montre n’a **aucune détection directe de Health Connect ou de Health Services** ; le téléphone reste l’autorité pour chaque métrique.
- Les surfaces de la montre se rafraîchissent depuis le dernier instantané envoyé par l’app téléphone — pas de comptes, pas de cloud, et aucune donnée de santé ne quitte vos appareils.

## Prérequis

- Un téléphone Android avec Health.md installé et jumelé à une montre Wear OS.
- Des données Health Connect sur le téléphone pour les métriques que vous voulez voir.
- Installez Health.md sur la montre depuis le Play Store de la montre, ou depuis la fiche Play Store du téléphone compagnon.

## Configuration

1. Ouvrez le Play Store sur votre montre (ou la section montres du Play Store du téléphone) et installez Health.md.
2. Ouvrez une fois l’app du téléphone pour qu’un instantané puisse se synchroniser.
3. Appuyez longuement sur votre cadran → **Personnaliser** → ajoutez une complication Health.md, ou balayez jusqu’au carrousel de tuiles et épinglez une tuile Health.md.

## Confidentialité et validation

Le compagnon utilise un contrat de transport privé purement agrégé : aucun enregistrement brut n’est transmis à la montre. La qualité des versions est validée par des suites d’émulateur et par des preuves de batterie et de QA OEM sur appareils physiques jumelés avant la livraison des artefacts Wear OS. Consultez la [liste de contrôle d’implémentation Wear OS](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/features/wear-os-implementation.md) pour le runbook complet.
