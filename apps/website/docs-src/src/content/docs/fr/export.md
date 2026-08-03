---
title: "Export"
description: "L’onglet Export est l’espace de travail principal. Il indique si HealthKit et votre coffre sont connectés, vous permet de choisir une destination et lance des exports ponctuels pour la plage de dates choisie."
---

<p>L’onglet Export s’organise autour de trois décisions simples : vérifier que tout est prêt, choisir une destination, puis sélectionner la plage de dates avant l’aperçu ou l’export.</p>

## Lire les badges d’état
<div class="options">
<div class="option"><strong>Badge Santé</strong><p>Point vert = HealthKit autorisé. Rouge = autorisation refusée. Touchez-le pour réessayer d’afficher la feuille d’autorisation iOS (cela ne fonctionne que la première fois par installation ; ensuite, iOS ne fait rien et vous devez corriger le réglage dans Réglages → Confidentialité et sécurité → Santé).</p></div>
<div class="option"><strong>Badge Coffre</strong><p>Point vert = un dossier de coffre est sélectionné. Touchez-le pour choisir de nouveau le coffre ou en changer. Le libellé affiche le nom du dossier.</p></div>
</div>
<p>L’action <em>Export</em> reste désactivée tant que HealthKit, le format de sortie et la destination sélectionnée ne sont pas prêts. Cela évite l’échec le plus courant : tenter un export sans destination.</p>

## Choisir une destination d’export
<p>La fiche Destination de l’export détermine où vont les données :</p>
<div class="options">
<div class="option"><strong>Dossier local de l’iPhone</strong><p>Écrit directement dans le dossier ou le coffre Obsidian choisi sur cet appareil.</p></div>
<div class="option"><strong>Mac connecté</strong><p>Envoie les données quotidiennes recueillies et un instantané exact des réglages à l’app Mac à proximité. L’iPhone lit HealthKit ; le Mac génère les formats sélectionnés et écrit les fichiers.</p></div>
<div class="option"><strong>Point de terminaison API</strong><p>Envoie par POST une enveloppe d’API JSON directement depuis l’iPhone vers un point de terminaison HTTP(S) configuré par l’utilisateur. <a href="/fr/docs/api-endpoint/">Voir Point de terminaison API</a>.</p></div>
</div>

## Choisir une plage de dates
<p>Les préréglages couvrent les cas courants :</p>
<div class="options">
<div class="option"><strong>Aujourd’hui</strong><p>Exporte la journée en cours. Utile pour tester la mise en forme.</p></div>
<div class="option"><strong>Hier</strong><p>Le choix le plus sûr pour un export quotidien, car la journée est terminée.</p></div>
<div class="option"><strong>Toute la période</strong><p>Récupère l’historique depuis les premières données HealthKit que Health.md peut trouver.</p></div>
<div class="option"><strong>Personnalisée</strong><p>Choisissez les dates de début et de fin d’une période précise.</p></div>
</div>

## Aperçu ou export
<div class="options">
<div class="option"><strong>Aperçu</strong><p>Affiche les fichiers et leur contenu avant toute écriture.</p></div>
<div class="option"><strong>Export</strong><p>Lance l’export, affiche sa progression sur l’écran principal et consigne le résultat dans l’historique.</p></div>
</div>

## Ce que fait réellement l’export
<ol>
<li>Pour chaque jour de la plage, recueille les projections récapitulatives sélectionnées et, lorsque Lossless Health Records est activé, leurs enregistrements sources canoniques et diagnostics de requête.</li>
<li>Applique le format choisi (Markdown, Bases, JSON ou CSV) et le modèle.</li>
<li>Écrit un fichier par jour dans <code>{vault}/{subfolder}/</code>, transfère les fichiers via le flux Mac connecté ou envoie par POST une enveloppe d’API JSON versionnée à votre point de terminaison API.</li>
<li>Si <em>Suivi individuel</em> est activé, dérive de l’archive canonique les fichiers Markdown sélectionnés par entrée pour les destinations basées sur des fichiers.</li>
<li>Si <em>Injection dans les notes quotidiennes</em> est activée, fusionne les champs récapitulatifs sélectionnés dans vos notes quotidiennes.</li>
</ol>
<p>JSON et CSV peuvent préserver les enregistrements canoniques. Markdown et Bases restent lisibles et présentent des diagnostics de collecte concis au lieu d’intégrer l’archive. Consultez la <a href="/fr/docs/reference/">référence complète des exports</a> pour les schémas exacts et les règles d’omission.</p>

## Barre d’onglets
<p>Les quatre onglets au bas de l’écran — Export, Planification, Synchronisation, Réglages — couvrent toute l’app. Tout le reste se trouve à un ou deux niveaux dans Réglages.</p>
<div class="callout"><strong>Comportement du déverrouillage.</strong><p style="margin-top:6px;">Full Access déverrouille les exports illimités, les exports planifiés, les destinations Mac et Shortcuts. <a href="/fr/docs/paywall/">Consultez la page Paywall</a> pour en savoir plus.</p></div>

## Pages associées
<div class="related">
<a href="/fr/docs/scheduling/"><span>Au quotidien</span>Planification — automatisez l’opération pour ne plus avoir à toucher Export.</a>
<a href="/fr/docs/api-endpoint/"><span>Intégrer</span>Point de terminaison API — envoyez le JSON sélectionné directement à votre service.</a>
<a href="/fr/docs/format/"><span>Personnaliser</span>Personnalisation du format — modifiez l’apparence de chaque fichier.</a>
<a href="/fr/docs/shortcuts/"><span>Puissance</span>Shortcuts — déclenchez des exports depuis Siri, des automatisations ou d’autres apps.</a>
<a href="/fr/docs/reference/"><span>Référence</span>Référence des exports — schémas, enregistrements canoniques, diagnostics et exemples générés.</a>
</div>
