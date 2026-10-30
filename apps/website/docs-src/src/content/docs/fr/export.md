---
title: "Exporter"
description: "Utilisez l'onglet Exporter pour vérifier HealthKit et les connexions au coffre-fort. Sélectionnez une destination et exportez une plage de dates."
---

<p> L'onglet Exporter est organisé en trois petites décisions : confirmer l'état de préparation, choisir une destination, puis choisir la plage de dates avant de prévisualiser ou d'exporter. </p>

## Lire les badges d'état
 <div class="options">
 <div class="option"> <strong> Badge Santé </strong> <p> Un point vert signifie que HealthKit est autorisé. Un point rouge signifie que l'accès n'est pas accordé. Appuyez pour réessayer la feuille d'autorisation iOS. La feuille n'apparaît qu'une seule fois par installation. Après cela, ouvrez Paramètres → Confidentialité et confidentialité. Sécurité → Santé. </p> </div>
 <div class="option"> <strong> Badge du coffre-fort </strong> <p> Point vert = un dossier du coffre-fort est sélectionné. Appuyez pour choisir à nouveau ou modifier le coffre-fort. L'étiquette indique le nom du dossier. </p> </div>
 </div>
 <p> L'action <em> Export </em> reste désactivée jusqu'à ce que HealthKit , le format de sortie et la destination sélectionnée soient prêts. Cela évite le mode d’échec le plus courant : tenter d’exporter sans destination. </p>

## Choisissez une cible d'exportation
 <p> La carte Export Target décide où les données vont : </p>

<div class="options">
 <div class="option"> <strong> Local iPhone Dossier </strong> <p> Écrit directement dans le dossier ou le coffre-fort Obsidian que vous avez choisi sur cet appareil. </p> </div>
 <div class="option"> <strong> Mac connecté </strong> <p> Envoie les données quotidiennes capturées et un instantané des paramètres exacts à l'application Mac à proximité. Le iPhone lit HealthKit . Le Mac restitue les formats sélectionnés et écrit les fichiers. </p> </div>
 <div class="option"> <strong> Point de terminaison API </strong> <p> POST une enveloppe JSON directement de iPhone vers un point de terminaison HTTP(S) configuré par l'utilisateur. <a href="/fr/docs/api-endpoint/"> Voir le point de terminaison de l'API </a> . </p> </div>
 </div>

## Choisissez une plage de dates
 <p> Les préréglages de date couvrent les chemins courants : </p>

<div class="options">
 <div class="option"> <strong> Aujourd'hui </strong> <p> Exporte le jour en cours. Utile pour tester le formatage de la sortie. </p> </div>
 <div class="option"> <strong> Hier </strong> <p> Le choix d'exportation quotidien le plus sûr car la journée est terminée. </p> </div>
 <div class="option"> <strong> Tous les temps </strong> <p> Remplissez à partir des premières données HealthKit Health.md peut trouver. </p> </div>
 <div class="option"> <strong> Personnalisé </strong> <p> Choisissez les dates de début et de fin pour une plage spécifique. </p> </div>
 </div>

## Aperçu ou exportation
 <div class="options">
 <div class="option"> <strong> Aperçu </strong> <p> Affiche les fichiers et le contenu qui seront générés avant que quoi que ce soit ne soit écrit. </p> </div>
 <div class="option"> <strong> Exporter </strong> <p> Exécute l'exportation, affiche la progression sur l'écran principal et enregistre le résultat dans l'historique. </p> </div>
 </div>

## Choisissez le niveau de détail des données

<div class="options">
 <div class="option"> <strong> Résumé </strong> <p> Compactez les totaux quotidiens et les cumuls pour la lecture, les notes et les tableaux de bord. </p> </div>
 <div class="option"> <strong> Série chronologique détaillée </strong> <p> Échantillons et intervalles horodatés sélectionnés. Ce niveau est disponible sur Apple et Android lorsque la métrique choisie expose des détails appropriés. </p> </div>
 <div class="option"> <strong> Dossiers de santé sans perte </strong> <p> L'archive canonique d'enregistrements sources HealthKit . Ce niveau est réservé à Apple. Android ne transforme pas les enregistrements Health Connect en archive HealthKit . </p> </div>
 </div>

## Ce que fait réellement « l'exportation »
 <ol>
 <li> Pour chaque jour de la plage, capturez les projections récapitulatives sélectionnées. Ajoutez des échantillons compatibles pour les séries chronologiques détaillées. Et, pour les dossiers de santé sans perte, ajoutez des enregistrements sources canoniques et des diagnostics de requête. </li>
 <li> Appliquez le format et le modèle choisis ( Markdown , Bases, JSON ou CSV). </li>
 <li> Écrivez un fichier par jour dans <code>{vault}/{subfolder}/</code> , transférez des fichiers via le flux de travail Mac connecté ou POSTez une enveloppe JSON versionnée sur votre point de terminaison API. </li>
 <li> Si <em> Suivi individuel </em> est activé, dérivez les fichiers Markdown sélectionnés par entrée de l'archive canonique pour les cibles basées sur des fichiers. </li>
 <li> Si <em> Injection de notes quotidiennes </em> est activée, fusionnez les champs de résumé sélectionnés dans vos notes quotidiennes. </li>
 </ol>

<p> JSON et CSV peuvent conserver les enregistrements canoniques. Markdown et Bases restent lisibles et exposent des diagnostics de capture compacts plutôt que d'intégrer l'archive. Consultez la référence d'exportation complète <a href="/fr/docs/reference/"> </a> pour connaître les schémas exacts et les règles d'omission. </p>

## Arrêtez, annulez et réessayez

L'arrêt ou l'annulation met fin uniquement à la tentative en cours. Les fichiers et les dates déjà terminés restent terminés, tandis que les dates non résolues restent disponibles pour une nouvelle tentative. L'annulation d'une tentative planifiée ne désactive pas sa planification récurrente.

## Profils et historique fiable

Un profil enregistré gèle ses paramètres et sa destination pour l'exécution. Les lignes de l'historique planifié et d'automatisation prenant en compte le profil conservent le profil d'exécution, tandis que l'historique conserve une étiquette de confidentialité pour la destination réellement utilisée. Une ligne de l'onglet Exportation manuelle peut omettre le nom du profil. Les changements de nom et de destination ultérieurs ne réécrivent pas l’historique existant. Les références de profil manquantes échouent au lieu de revenir en arrière. Voir [Exporter les profils](/fr/docs/export-profiles/).

## Barre d'onglets

<p> Les quatre onglets en bas de l'écran, Exportation, Planification, Synchronisation, Paramètres, couvrent toute la surface de l'application. Tout le reste réside dans une ou deux couches au plus profond des paramètres. </p>

<div class="callout">
 <strong> Comportement de déverrouillage. </strong>
 <p style="margin-top:6px;"> Les versions de téléphone iPhone / iPad et Google Play avec abonnement nécessitent un essai actif, un abonnement, une durée de vie ou un accès permanent préservé pour les exportations et la planification. Il ne reste aucune allocation locale de libre exportation. Le compagnon Mac et la version à accès inclus F-Droid conservent leurs exceptions documentées. <a href="/fr/docs/paywall/"> Consultez la page Paywall </a> pour les détails de l'achat Apple. </p>
 </div>

## En rapport

<div class="related">
 <a href="/fr/docs/export-profiles/"> <span> Configurations répétables </span> Exportez les profils, enregistrez les paramètres indépendants, les destinations, les horaires et les identifiants d'automatisation stables. </a>
 <a href="/fr/docs/scheduling/"> <span> Utilisation quotidienne </span> Planification, automatisez-la pour ne plus jamais appuyer sur Exporter. </a>
 <a href="/fr/docs/api-endpoint/"> <span> Intégrez </span> API Endpoint, envoyez le JSON sélectionné directement à votre propre service. </a>
 <a href="/fr/docs/format/"> <span> Personnaliser </span> Personnalisation du format, modifiez l'apparence de chaque fichier. </a>
 <a href="/fr/docs/shortcuts/"> <span> Alimentation </span> Shortcuts , déclenchez des exportations depuis Siri , des automatisations ou d'autres applications. </a>
 <a href="/fr/docs/reference/"> <span> Référence </span> Référence d'exportation, schémas, enregistrements canoniques, diagnostics et exemples générés. </a>
 </div>
