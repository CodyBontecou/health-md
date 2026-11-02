---
title: "Application Android"
description: "Configurez Health.md pour Android. Exportez les données Health Connect , sélectionnez les dossiers Storage Access Framework, planifiez les exportations et automatisez avec Tasker ou adb."
---

<div class="docs-hero">
 <p class="docs-eyebrow"> Health Connect dans des fichiers privés </p>
 <p> Health.md pour Android lit Health Connect sur l'appareil et écrit Markdown , Obsidian Bases, JSON ou CSV dans les dossiers de votre choix. Ce workflow d'exportation de dossiers ne nécessite aucun compte Health.md . Les options d'accès Google Play et l'accès inclus F-Droid sont décrites ci-dessous. </p>
 <div class="docs-actions">
 <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener"> Continuer Google Play </a>
 <a class="docs-button-secondary" href="#distribution-status"> F-Droid statut de publication </a>
 <a class="docs-button-secondary" href="/fr/docs/export/"> Lire les documents d'exportation </a>
 </div>
 <p id="distribution-status"> F-Droid la publication du catalogue est en attente. Obtenez la version actuelle d'Android sur Google Play . </p>
 </div>

<div class="reference-stats">
 <div> <strong> 106 </strong> <span> métriques Health Connect sélectionnables </span> </div>
 <div> <strong> 4 </strong> <span> formats d'exportation </span> </div>
 <div> <strong> 2 </strong> <span> Canaux de distribution Android </span> </div>
 <div> <strong> 0 </strong> <span> Health.md comptes cloud requis </span> </div>
 </div>

## Que fait l'application Android

Health.md pour Android transforme Health Connect en un premier journal de santé local. Choisissez les métriques dont vous avez besoin et prévisualisez le résultat. Exportez ensuite les fichiers vers un dossier local, un coffre-fort Obsidian , un dossier de fournisseur synchronisé ou un fournisseur de documents Android inscriptibles.

<div class="options">
 <div class="option"> <strong> Health Connect source </strong> <p> Lit l'activité, le sommeil, le cœur, les signes vitaux, les mensurations corporelles, la nutrition, les entraînements et d'autres catégories via les API Health Connect d'Android sur l'appareil. </p> </div>
 <div class="option"> <strong> Obsidian -sortie native </strong> <p> Écrit des notes quotidiennes, YAML/frontmatter, Obsidian Notes conviviales pour les bases, entrées individuelles et JSON compatible avec le plugin Health.md Obsidian . </p> </div>
 <div class="option"> <strong> Stockage natif Android </strong> <p> Utilise le Storage Access Framework afin que vous puissiez choisir les dossiers exposés par le stockage local, Obsidian , Google Drive, OneDrive, Syncthing ou un autre fournisseur. </p> </div>
 </div>

## Exigences

- Android 9/API 28 ou version ultérieure.
- Un appareil ou un émulateur compatible Health Connect .
- Health Connect données provenant d'applications, d'appareils portables ou de services Android qui écrivent sur Health Connect .
- Un fournisseur de dossier ou de document qui autorise l'accès en écriture pour les exportations.

## Première exportation

1. Installez la version actuelle Health.md à partir de Google Play .
2. Ouvrez la configuration ** Health Connect ** et accordez uniquement les catégories que vous souhaitez que Health.md exporte.
3. Choisissez la destination d'exportation via le sélecteur de dossiers d'Android.
4. Choisissez les formats : Markdown , Obsidian Bases, JSON, CSV ou toute combinaison.
5. Sélectionnez les mesures et la plage de dates.
6. Prévisualisez la sortie.
7. Appuyez sur Exporter et vérifiez les fichiers générés dans votre dossier ou votre coffre-fort.

La version du téléphone Google Play compatible avec l'abonnement nécessite un essai actif, un abonnement, un accès à vie ou un accès permanent préservé pour les exportations manuelles. Les abonnements éligibles incluent un essai de 7 jours ; La vie n’a pas d’épreuve. La version F-Droid inclut un accès illimité sans flux d'achat ni de restauration.

## Destinations sur Android

Android n'utilise pas la destination de réseau local iPhone → Mac. Au lieu de cela, il s'appuie sur le framework d'accès au stockage d'Android.

| Destination | Statut Android |
| --- | --- |
| Dossier de périphérique local | Pris en charge via le sélecteur de dossiers |
| coffre-fort Obsidian | Pris en charge lorsque le dossier du coffre-fort est exposé au sélecteur d'Android |
| Google Drive, OneDrive, Syncthing, Obsidian Sync et fournisseurs similaires | Pris en charge lorsque le fournisseur expose des dossiers inscriptibles |
| iPhone /Destination réseau local Mac | Spécifique à la plateforme Apple ; non utilisé par Android |

Si un fournisseur n'expose pas les dossiers inscriptibles via le sélecteur d'Android, Health.md ne peut pas y écrire directement en toute sécurité. Choisissez un dossier fournisseur qui accorde un accès en écriture persistant ou exportez localement et synchronisez avec votre outil préféré.

## ##Formats

L'application Android partage les mêmes objectifs de fichiers simples que l'application Apple :

| Format | Utilisez-le pour |
| --- | --- |
| Markdown | Résumés, modèles et notes de santé quotidiens lisibles |
| Obsidian Bases | Notes de première ligne qui peuvent être interrogées dans les vues de la base de données Obsidian |
| JSON | Charges utiles quotidiennes structurées pour les scripts, les tableaux de bord, les blocs-notes et le plugin Health.md Obsidian |
| CSV | Workflows de feuilles de calcul et d’analyse |

Les exportations Android JSON sont conçues pour être compatibles avec les visualisations Obsidian de Health.md . Les exportations Markdown et Bases utilisent le même flux de travail axé sur le sujet documenté dans le [guide des formats](/fr/docs/format/).

## Planification et automatisation

Dans la version du téléphone Google Play compatible avec l'abonnement, les exportations planifiées nécessitent un essai actif, un abonnement, une durée de vie ou un accès permanent préservé ; ils sont inclus dans la version F-Droid . Ils utilisent une alarme exacte ponctuelle lorsque vous accordez l'accès aux alarmes et aux rappels d'Android, avec un travail durable WorkManager comme sauvegarde. Sans accès à l'alarme exacte, WorkManager devient le planificateur principal, de sorte que l'heure sélectionnée est un objectif plutôt qu'une garantie ferme. Health.md enregistre l'historique des exportations, peut récupérer les dates planifiées manquées et vous permet de réessayer les exécutions ayant échoué.

Pour Tasker, adb ou d'autres outils d'automatisation, Health.md expose les intentions de diffusion explicites uniquement. Les appelants externes doivent s'adresser directement au composant récepteur :

```text
com.healthmd.android/com.healthmd.automation.AutomationReceiver
```

Exemples :

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

L'automatisation utilise le profil actif par défaut, y compris sa destination gelée, ses formats, ses métriques, sa comptabilité et son historique. Un supplément `PROFILE` fourni peut sélectionner un identifiant ou un nom de profil stable. Une référence inconnue échoue à la fermeture au lieu d'utiliser les paramètres actuels. Les exécutions planifiées restent également liées à leur profil. Voir [Exporter les profils](/fr/docs/export-profiles/).

### Préparation en arrière-plan et annulation programmée

- Autoriser les lectures Health Connect en arrière-plan pour les exportations sans surveillance. Sinon, ouvrez Health.md pour terminer la lecture des données de santé.
- Gardez les notifications activées afin qu'Android puisse afficher le travail actif, l'état du service de premier plan, les résultats et les actions de récupération.
- Accordez des alarmes et des rappels uniquement lorsque vous souhaitez une planification exacte des alarmes. Sans cela, un travail durable WorkManager reste disponible mais la durée choisie est approximative.
- L'annulation d'une exécution planifiée arrête uniquement cette tentative. Les dates terminées restent terminées, les dates non résolues peuvent être réessayées et la planification récurrente reste activée.

## Sources de santé

Health Connect est le chemin d'exportation local dans les deux canaux. La version Google Play comprend également une zone de configuration des sources de santé pour des écosystèmes tels que Samsung Health, Huawei Health, Fitbit, Garmin, Withings, Oura, Polar et WHOOP. Lorsque ces écosystèmes écrivent dans Health Connect , l'une ou l'autre des versions peut exporter les enregistrements Health Connect résultants. Les importations directes du fournisseur de cloud et les rappels OAuth sont uniquement en lecture. Le catalogue du fournisseur F-Droid contient uniquement Health Connect .

Google Fit est intentionnellement exclu de la surface du fournisseur pris en charge, car Health Connect est la couche de données de santé préférée d'Android.

### Étapes exactes du jour local

Les totaux quotidiens des étapes utilisent les limites exactes du jour local et du zonage. Avant l'agrégation, Health.md coupe et divise les intervalles Health Connect qui se chevauchent à minuit local. Ainsi, les changements de déplacement et d’heure d’été ne déplacent pas les étapes vers le mauvais jour.

## Distribution, tarification et commutation

- ** Google Play :** la version téléphonique avec abonnement propose des abonnements individuels hebdomadaires/annuels et à vie. Les nouveaux abonnés éligibles bénéficient d'un essai de 7 jours, puis renouvellent automatiquement au prix affiché jusqu'à annulation via Google Play . La durée de vie est facturée une fois immédiatement, sans essai. Il ne reste aucune allocation locale de libre exportation. L'accès permanent existant est conservé. Restaurer l'achat utilise le compte Google d'achat ; la suppression de l'application ou l'achat de Lifetime n'annule pas un abonnement. Les versions plus anciennes peuvent afficher l'allocation précédente. La version actuelle est uniquement disponible sur téléphone. Le compagnon Wear OS est reporté à un cycle de qualification ultérieur.
- ** F-Droid :** l'accès illimité est inclus. Il n’y a pas de compteur gratuit, de dépendance de facturation, de paywall, d’achat ou de restauration.
- ** Portée F-Droid :** Health Connect uniquement, sans intégration Wear OS, OAuth direct du fournisseur de cloud, examen Play, attribution ou télémétrie d'intégration Health.md .
- **Résultat partagé :** les deux canaux utilisent la même capture Health Connect , les mêmes exportateurs, schémas, actions d'automatisation et protocole de périphérique direct.
- **Changement :** Google Play et F-Droid utilisent des clés de signature différentes, donc pour changer de chaîne, il faut d'abord désinstaller l'application.

Un changement de canal ne migre pas les achats, les paramètres, l'historique, les informations d'identification ou l'état du transfert privé. Les fichiers exportés restent dans la destination que vous avez choisie.

Si Google Play Billing se déconnecte de manière transitoire, la version Play se reconnecte et actualise automatiquement l’état des droits. Une perte de service temporaire ne supprime pas définitivement Premium. Utilisez Restaurer l'achat uniquement si le compte n'est toujours pas résolu après le retour de la connectivité.

## Modèle de confidentialité

Health.md pour Android est d'abord local :

- Les enregistrements -  Health Connect sont lus sur votre appareil Android.
- Les exportations sont écrites directement dans les dossiers que vous choisissez.
- Les exportations de dossiers principaux et les requêtes directes sur les périphériques ne créent pas de copie du serveur Health.md par défaut.
- Les paramètres et l'historique des exportations restent sur l'appareil.
- La facturation est gérée par Google Play dans la version Play. F-Droid inclut un accès illimité sans facturation et ne contient aucun code de télémétrie Health.md ni identité/état de télémétrie.
- Les dossiers sauvegardés par le fournisseur sont synchronisés selon les propres conditions de ce fournisseur.

Si vous souhaitez la configuration locale la plus stricte, exécutez des exportations manuelles vers un dossier de périphérique local et laissez les exportations planifiées et la synchronisation sauvegardée par le fournisseur désactivées.

Le pilote Health.md Cloud, distinct et facultatif, est réservé à un seul propriétaire et conserve uniquement les exports API envoyés volontairement. Il n’y a pas d’inscription publique ni de synchronisation automatique des appareils ; ce flux de dossiers n’envoie rien au pilote. La [politique de confidentialité](/privacy-policy.html) décrit la conservation, la suppression, le quota et les risques de perte sans sauvegarde.

## Documents associés

<div class="related">
 <a href="/fr/docs/export-profiles/"> <span> Profils </span> Enregistrez des destinations indépendantes, des paramètres de sortie, des programmes et des ID d'automatisation stables. </a>
 <a href="/fr/docs/export/"> <span> Exportation </span> Flux d'exportation manuel, plages de dates, aperçus, historique et sortie de fichier. </a>
 <a href="/fr/docs/metrics/"> <span> Métriques </span> Comment fonctionnent la sélection et les catégories de métriques dans Health.md . </a>
 <a href="/fr/docs/format/"> <span> Formats </span> Markdown , bases, JSON, CSV, unités, noms de fichiers et frontmatter. </a>
 <a href="/fr/docs/visualizations-roadmap/"> <span> Obsidian </span> Comment JSON exporté et Markdown alimentent les visualisations Health.md . </a>
 </div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;"> Dernière mise à jour le 04/10/2026 </p>
