---
title: "Exporter"
description: "Exportez vos données Apple Health maintenant ou selon une planification. Vérifiez que tout est prêt dans Archives, choisissez une plage dans Exporter maintenant et définissez la destination de chaque automatisation."
---

<p>Sur iPhone, Health.md compte trois onglets, <strong>Archives</strong>, <strong>Automatisations</strong> et <strong>Réglages</strong>, ainsi qu’un bouton rond <strong>Exporter maintenant</strong>. Sur iPad, les onglets passent dans une barre latérale.</p>

## Vérifier que tout est prêt dans Archives
<p>Le calendrier d’<strong>Archives</strong> montre les dates de santé couvertes par chaque automatisation. Quand quelque chose bloque les exportations, la carte <strong>À vérifier</strong> en haut l’indique :</p>
<div class="options">
<div class="option"><strong>Apple Health</strong><p>Health.md affiche l’état de configuration de l’app, pas un accès en lecture confirmé à chaque catégorie. HealthKit ne révèle pas les autorisations de lecture refusées. Vérifiez les catégories dans Apple Health. Un résultat vide peut signifier un accès refusé ou l’absence de données. <a href="/fr/docs/troubleshooting/">Résoudre les données manquantes</a>.</p></div>
<div class="option"><strong>Dossier</strong><p>Choisissez ou rechoisissez le dossier dans <strong>Réglages → Dossier</strong>. Si iOS perd l’accès après le déplacement d’un dossier, Health.md vous demande de le choisir à nouveau ; rien n’est supprimé.</p></div>
</div>

## Choisir la destination d’une automatisation
<p>Chaque automatisation a sa propre destination. Ouvrez <strong>Automatisations</strong>, choisissez l’automatisation, puis <strong>Sortie</strong> :</p>

<div class="options">
<div class="option"><strong>Dossier local</strong><p>Écrit directement dans le dossier ou le coffre Obsidian choisi sur cet appareil.</p></div>
<div class="option"><strong>Mac connecté</strong><p>Envoie les données quotidiennes capturées et un instantané exact des réglages à l’app Mac à proximité. L’iPhone lit HealthKit ; le Mac génère les formats choisis et écrit les fichiers.</p></div>
<div class="option"><strong>Point de terminaison de l’API</strong><p>Envoie par POST une enveloppe JSON directement depuis l’iPhone vers un point de terminaison HTTP(S) que vous configurez. <a href="/fr/docs/api-endpoint/">Voir Point de terminaison de l’API</a>.</p></div>
<div class="option"><strong>Passerelle Agent Data</strong><p>Envoie chaque fichier exporté, sans modification, au point d’ingestion de votre passerelle.</p></div>
</div>

## Choisir une plage dans Exporter maintenant
<p>Touchez <strong>Exporter maintenant</strong>, choisissez l’automatisation si vous en avez plusieurs, puis une plage :</p>

<div class="options">
<div class="option"><strong>Hier</strong><p>Le choix le plus sûr pour une exportation quotidienne, car la journée est terminée.</p></div>
<div class="option"><strong>7 jours / 30 jours</strong><p>La dernière semaine ou le dernier mois, jusqu’à hier. À partir de 30 jours, Health.md demande une confirmation.</p></div>
<div class="option"><strong>Personnalisé</strong><p>Choisissez les dates de début et de fin d’une plage précise.</p></div>
</div>
<p><strong>Sera écrit</strong> indique la destination et, approximativement, combien de fichiers et de jours couvre l’exportation. <strong>Résumé de la plage de dates uniquement</strong> écrit un seul fichier de synthèse au lieu de fichiers quotidiens. Aujourd’hui et Tout l’historique restent disponibles dans <strong>Automatisations → Tous les réglages d’exportation</strong>.</p>

## Aperçu ou exportation
<div class="options">
<div class="option"><strong>Aperçu</strong><p>Montre les fichiers et contenus qui seront générés avant toute écriture.</p></div>
<div class="option"><strong>Exporter</strong><p>Lance l’exportation, affiche la progression au-dessus de la barre d’onglets avec un bouton Annuler et enregistre le résultat dans l’historique et le calendrier d’Archives.</p></div>
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

Un profil enregistré fige ses réglages et sa destination pour l’exécution. Les lignes d’historique des exportations planifiées et des automatisations qui connaissent le profil conservent le profil utilisé, et l’historique garde une étiquette respectueuse de la vie privée pour la destination réellement employée. Une ligne d’exportation manuelle peut omettre le nom du profil. Les renommages et changements de destination ultérieurs ne réécrivent pas l’historique existant. Si un profil référencé est introuvable, l’opération échoue sans utiliser d’autres réglages. Voir [Profils d’exportation](/fr/docs/export-profiles/).

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
