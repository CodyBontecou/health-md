---
title: Application Android
description: Configurez Health.md for Android et exportez les données Health Connect vers Markdown, Obsidian Bases, JSON et CSV, choisissez des dossiers avec Storage Access Framework, planifiez des exports et automatisez-les avec Tasker ou adb.
---

<div class="docs-hero">
  <p class="docs-eyebrow">De Health Connect aux fichiers privés</p>
  <p>Health.md for Android lit Health Connect sur l’appareil et écrit des fichiers Markdown, Obsidian Bases, JSON ou CSV dans les dossiers de votre choix. Aucun compte Health.md, aucun cloud de données de santé et aucun abonnement.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Disponible sur Google Play</a>
    <a class="docs-button-secondary" href="/fr/docs/export/">Lire la documentation sur les exports</a>
  </div>
</div>

<div class="reference-stats">
<div><strong>106</strong><span>métriques Health Connect sélectionnables</span></div>
<div><strong>4</strong><span>formats d’export</span></div>
<div><strong>10</strong><span>actions gratuites d’export manuel</span></div>
<div><strong>0</strong><span>compte cloud Health.md requis</span></div>
</div>

## Fonctionnement de l’application Android

Health.md for Android transforme les données Health Connect en journal de santé local. Choisissez les métriques qui vous intéressent, prévisualisez le résultat, puis exportez des fichiers propres vers un dossier local, un coffre Obsidian, un dossier de fournisseur synchronisé ou tout fournisseur de documents Android qui accorde un accès en écriture.

<div class="options">
  <div class="option"><strong>Source Health Connect</strong><p>Lit l’activité, le sommeil, les données cardiaques, les signes vitaux, les mesures corporelles, la nutrition, les entraînements et d’autres catégories au moyen des API Health Connect intégrées à Android.</p></div>
  <div class="option"><strong>Sortie native pour Obsidian</strong><p>Écrit des notes quotidiennes, du YAML/frontmatter, des notes adaptées à Obsidian Bases, des entrées individuelles et du JSON compatible avec l’extension Obsidian de Health.md.</p></div>
  <div class="option"><strong>Stockage natif Android</strong><p>Utilise Storage Access Framework afin que vous puissiez choisir des dossiers proposés par le stockage local, Obsidian, Google Drive, OneDrive, Syncthing ou un autre fournisseur.</p></div>
</div>

## Prérequis

- Android 9 / API 28 ou version ultérieure.
- Un appareil ou émulateur compatible avec Health Connect.
- Des données Health Connect provenant d’applications Android, d’appareils portables ou de services qui écrivent dans Health Connect.
- Un dossier ou un fournisseur de documents qui autorise l’écriture des exports.

## Premier export

1. Installez Health.md depuis Google Play.
2. Ouvrez la configuration de **Health Connect** et accordez uniquement l’accès aux catégories que Health.md doit exporter.
3. Choisissez la destination d’export avec le sélecteur de dossiers d’Android.
4. Choisissez les formats : Markdown, Obsidian Bases, JSON, CSV ou toute combinaison de ces formats.
5. Sélectionnez les métriques et la plage de dates.
6. Prévisualisez le résultat.
7. Lancez l’export et vérifiez les fichiers générés dans votre dossier ou votre coffre.

L’offre gratuite comprend 10 actions d’export manuel, ce qui vous permet de tester les autorisations, l’accès au dossier, les formats et votre flux de travail Obsidian avant de débloquer les exports illimités.

## Destinations sur Android

Android n’utilise pas la destination sur le réseau local iPhone → Mac. Il s’appuie plutôt sur Storage Access Framework d’Android.

| Destination | Prise en charge sur Android |
|---|---|
| Dossier local de l’appareil | Pris en charge par le sélecteur de dossiers |
| Coffre Obsidian | Pris en charge lorsque le dossier du coffre est proposé par le sélecteur Android |
| Google Drive, OneDrive, Syncthing, Obsidian Sync et fournisseurs similaires | Pris en charge lorsque le fournisseur propose des dossiers accessibles en écriture |
| Destination sur le réseau local iPhone/Mac | Spécifique aux plateformes Apple ; non utilisée par Android |

Si un fournisseur ne propose pas de dossiers accessibles en écriture dans le sélecteur Android, Health.md ne peut pas y écrire directement en toute sécurité. Choisissez un dossier de fournisseur qui accorde un accès persistant en écriture, ou exportez localement et synchronisez avec l’outil de votre choix.

## Formats

Comme l’application Apple, l’application Android produit des fichiers dans des formats courants :

| Format | Utilisation |
|---|---|
| Markdown | Résumés de santé quotidiens lisibles, modèles et notes |
| Obsidian Bases | Notes axées sur le frontmatter, interrogeables dans les vues de base de données Obsidian |
| JSON | Charges utiles quotidiennes structurées pour les scripts, tableaux de bord, notebooks et l’extension Obsidian de Health.md |
| CSV | Flux de travail de tableur et d’analyse |

Les exports JSON d’Android sont conçus pour être compatibles avec les visualisations Health.md dans Obsidian. Les exports Markdown et Bases utilisent le même flux de travail axé sur le frontmatter que celui décrit dans le [guide des formats](/fr/docs/format/).

## Planification et automatisation

Les exports planifiés exigent l’achat à vie unique. Lorsque vous accordez l’accès Alarmes et rappels d’Android, les exports planifiés utilisent une alarme exacte à déclenchement unique, avec une tâche WorkManager persistante comme solution de secours. Sans accès aux alarmes exactes, WorkManager devient le planificateur principal : l’heure choisie est donc un objectif, et non une garantie stricte. Health.md enregistre l’historique des exports, peut récupérer les dates planifiées manquées et vous permet de réessayer les exécutions échouées.

Pour Tasker, adb ou d’autres outils d’automatisation, Health.md expose des intents de diffusion qui doivent toujours être explicites. Les appelants externes doivent cibler directement le composant récepteur :

```text
com.healthmd.android/com.healthmd.automation.AutomationReceiver
```

Exemples :

```bash
adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_YESTERDAY

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_LAST_DAYS \
  --ei com.healthmd.android.extra.DAYS 7

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_RANGE \
  --es com.healthmd.android.extra.START_DATE 2026-03-01 \
  --es com.healthmd.android.extra.END_DATE 2026-03-07
```

L’automatisation utilise par défaut le profil actif avec sa destination, ses formats, ses métriques, sa comptabilisation et son historique figés. Un extra `PROFILE` peut sélectionner un profil stable par identifiant ou nom ; une référence inconnue échoue de façon sûre au lieu d’utiliser les réglages actuels. Les exécutions planifiées restent aussi liées à leur profil. Voir [Profils d’exportation](/fr/docs/export-profiles/).

### Conditions d’arrière-plan et annulation planifiée

- Autorisez les lectures Health Connect en arrière-plan pour les exports sans surveillance ; sinon, ouvrez Health.md pour terminer la lecture.
- Gardez les notifications actives pour afficher le travail, le service au premier plan et les invites de reprise.
- Accordez Alarmes et rappels uniquement pour une alarme exacte. Sans cet accès, le travail reste persistant mais l’heure est approximative.
- Annuler une exécution planifiée arrête seulement cette tentative. Les dates terminées restent acquises, les autres sont réessayables et la récurrence reste active.

## Sources de santé

Health Connect est la source utilisée par défaut pour les exports locaux. L’application Android comprend également un espace de configuration des sources de santé pour des écosystèmes tels que Samsung Health, Huawei Health, Fitbit, Garmin, Withings, Oura, Polar et WHOOP. Lorsque ces écosystèmes écrivent dans Health Connect, Health.md peut exporter les enregistrements Health Connect obtenus. Les imports directs depuis des fournisseurs cloud nécessitent l’autorisation du fournisseur et peuvent imposer des contraintes supplémentaires de configuration ou de disponibilité.

Google Fit est volontairement exclu des fournisseurs pris en charge, car Health Connect est la couche de données de santé recommandée sur Android.

### Pas quotidiens locaux exacts

Les pas quotidiens utilisent les limites exactes du jour local avec fuseau horaire. Health.md découpe les intervalles Health Connect à minuit local avant agrégation ; voyages et changements d’heure ne déplacent donc pas les pas.

## Tarification et restauration

- L’application Android comprend 10 actions gratuites d’export manuel.
- Les exports illimités et l’automatisation planifiée se débloquent par un achat à vie unique avec Google Play Billing.
- Il n’y a ni abonnement ni frais récurrents.
- Google Play affiche le prix local en vigueur avant l’achat.
- La restauration de l’achat utilise le compte Google ayant servi à acheter Premium.

Après une déconnexion temporaire de Google Play Billing, Health.md se reconnecte et actualise automatiquement le droit. Premium ne disparaît pas définitivement ; utilisez Restaurer l’achat seulement si le compte reste non résolu après le retour du réseau.

## Modèle de confidentialité

Health.md for Android traite les données en priorité sur l’appareil :

- Les enregistrements Health Connect sont lus sur votre appareil Android.
- Les exports sont écrits directement dans les dossiers de votre choix.
- Health.md n’exploite pas de service cloud pour les données de santé.
- Les paramètres et l’historique des exports restent sur l’appareil.
- La facturation est gérée par Google Play.
- Les dossiers associés à un fournisseur se synchronisent selon les conditions propres à ce fournisseur.

Pour la configuration locale la plus stricte, effectuez des exports manuels vers un dossier local de l’appareil et laissez désactivés les exports planifiés et la synchronisation avec un fournisseur.

## Documentation associée

<div class="related">
  <a href="/fr/docs/export-profiles/"><span>Profils</span>Enregistrez des destinations, réglages de sortie, planifications et identifiants d’automatisation stables indépendants.</a>
  <a href="/fr/docs/export/"><span>Export</span>Flux d’export manuel, plages de dates, aperçus, historique et fichiers produits.</a>
  <a href="/fr/docs/metrics/"><span>Métriques</span>Fonctionnement de la sélection des métriques et des catégories dans Health.md.</a>
  <a href="/fr/docs/format/"><span>Formats</span>Markdown, Bases, JSON, CSV, unités, noms de fichiers et frontmatter.</a>
  <a href="/fr/docs/visualizations-roadmap/"><span>Obsidian</span>Comment les fichiers JSON et Markdown exportés alimentent les visualisations Health.md.</a>
</div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">Dernière mise à jour : 2026-08-31</p>
