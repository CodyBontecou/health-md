---
title: "Shortcuts et App Intents"
description: "Sept App Intents permettent de déclencher des exports, d’obtenir des résumés et d’activer la planification depuis Siri, l’app Shortcuts, les filtres de concentration, les automatisations et tout hôte compatible AppIntent."
---

## App Intents disponibles
<div class="options">
<div class="option"><strong>Export Yesterday's Health Data</strong><p>Raccourci sans paramètre. La méthode rapide pour exporter simplement les données d’hier. Utilise le même moteur que l’export manuel. Paramètre facultatif <em>Profil</em> (voir <a href="#profiles">Profils d'export</a>).</p></div>
<div class="option"><strong>Export Health Data for a Date</strong><p>Un paramètre <em>Date</em>. L’heure est ignorée. Utile dans les automatisations pilotées par un calendrier. Paramètre facultatif <em>Profil</em>.</p></div>
<div class="option"><strong>Export Health Data for Date Range</strong><p>Paramètres <em>Start Date</em> et <em>End Date</em>, bornes incluses. À utiliser pour récupérer un historique. Paramètre facultatif <em>Profil</em>.</p></div>
<div class="option"><strong>Export Last N Days of Health Data</strong><p>Paramètre <em>Number of Days</em> (1–366). La période se termine hier. Valeur par défaut : 7. Adapté aux automatisations du type « chaque dimanche, exporter les 7 derniers jours ». Paramètre facultatif <em>Profil</em>.</p></div>
<div class="option"><strong>Get Health Summary for a Date</strong><p>Renvoie un instantané structuré — nombre de pas, calories actives, sommeil, fréquence cardiaque — sans rien écrire dans le coffre. Utilisez-le dans Shortcuts pour transmettre des valeurs à d’autres apps.</p></div>
<div class="option"><strong>Get Last Export Status</strong><p>Renvoie l’horodatage, l’état de réussite, le nombre de jours et le motif éventuel d’échec du dernier export enregistré. Une demande effectuée lorsque l’appareil est verrouillé reste en attente jusqu’à une nouvelle tentative et n’est donc pas renvoyée comme état actuel.</p></div>
<div class="option"><strong>Turn Scheduled Export On or Off</strong><p>Paramètre booléen. Suspendez la planification, par exemple avec le mode de concentration Vacances, puis reprenez-la.</p></div>
</div>

<a id="profiles"></a>
## Profils d'export
<p>Créez et gérez des profils d'export enregistrés dans Health.md sur iPhone ou Android. Sur les plateformes Apple, la gestion des profils est actuellement documentée uniquement pour l'iPhone ; aucune disponibilité sur iPad ou macOS n'est revendiquée.</p>
<p>Les quatre intents d'export acceptent un paramètre facultatif <em>Profil</em>. Dès que des profils existent, laisser le paramètre vide utilise le profil actif ; en mode historique sans profil, les réglages d'export actuels de l'app sont utilisés. Indiquez le nom d'un profil enregistré pour exécuter la configuration figée de ce profil — sélection de métriques, formats et destination — quel que soit l'état actuel de l'app.</p>
<div class="callout">
<strong>Avertissement pour les raccourcis existants sans paramètre.</strong>
<p style="margin-top:6px;">Dès que vous créez votre premier profil d'export dans l'app, un raccourci sans <em>Profil</em> défini exporte avec les réglages enregistrés du profil <em>actif</em> plutôt qu'avec les réglages actifs de l'app. Si vous comptez sur l'ancien comportement, épinglez le raccourci sur un profil précis (ou n'utilisez aucun profil) pour rester explicite. Un nom de profil qui n'existe plus échoue avec une erreur claire au lieu d'exporter la mauvaise chose.</p>
</div>
## Où les trouver
<p>Ouvrez l’app Shortcuts sur iOS ou macOS. Touchez <em>+</em> pour créer un raccourci, puis recherchez « Health.md » ou l’un des titres ci-dessus. Ils figurent dans la catégorie <em>Health</em>.</p>
<p>La plupart des intentions définissent <code>openAppWhenRun = false</code> et s’exécutent donc sans interface : aucun lancement d’app ni clignotement. Elles fonctionnent depuis les automatisations, les filtres de concentration, la commande « Dis Siri » et le bouton Action.</p>

<div class="callout"><strong>L’exécution lorsque l’iPhone est verrouillé ne déverrouille pas HealthKit.</strong><p style="margin-top:6px;">Apple protège les données HealthKit lorsque l’iPhone est verrouillé et <a href="https://support.apple.com/guide/security/protecting-access-to-users-health-data-sec88be9900f/web">retire l’accès aux apps environ dix minutes après le verrouillage</a>. <em>Allow Running When Locked</em> autorise Shortcuts à lancer l’action, mais ne contourne pas la protection des données HealthKit. L’autorisation d’accès au contenu Health.md dans Shortcuts ne la contourne pas non plus.</p><p>Si HealthKit est indisponible, Health.md conserve les dates demandées en attente et publie une notification <em>Health Export Needs Attention</em>. Déverrouillez l’iPhone, puis touchez la notification ou ouvrez Health.md pour réessayer. Un export entièrement autonome ne peut être garanti tant que le téléphone reste verrouillé.</p></div>

<a id="recipe-nightly-export-with-confirmation"></a>
## Recette : export quotidien avec confirmation
<ol><li><strong>Automatisation personnelle</strong> → <em>Heure de la journée</em> → choisissez une heure à laquelle votre iPhone est généralement déverrouillé, par exemple 8:00 AM.</li><li>Intention <em>Export Yesterday's Health Data</em>.</li><li>Intention <em>Get Last Export Status</em>.</li><li><em>Afficher une notification</em> avec le résultat.</li></ol>
<p><strong>Remarque sur l’état en attente :</strong> <em>Get Last Export Status</em> lit la dernière entrée enregistrée dans l’historique. Si HealthKit était verrouillé, il peut encore afficher l’export précédent jusqu’à la nouvelle tentative. La notification de reprise de Health.md est l’indicateur de référence pour les tâches en attente.</p>

## Recette : récupération ponctuelle d’un historique
<ol><li>Créez un raccourci.</li><li><em>Export Health Data for Date Range</em> avec start = 2024-01-01, end = 2024-12-31.</li><li>Lancez-le depuis Shortcuts. Il parcourt l’année et écrit un fichier par jour. Une année complète peut demander quelques minutes.</li></ol>

## Recette : suspendre la planification pendant les vacances
<ol><li><strong>Filtre de concentration</strong> : lorsque le mode <em>Vacances</em> s’active, exécutez <em>Turn Scheduled Export On or Off</em> avec Enabled = false.</li><li>Lorsqu’il se désactive, relancez l’intention avec Enabled = true.</li></ol>
<div class="callout"><strong>Autorisation requise.</strong><p style="margin-top:6px;">Les App Intents héritent de l’autorisation HealthKit et du coffre sélectionné dans l’app. Elles échouent avec un message clair si l’app n’a pas été ouverte et configurée au moins une fois sur cet appareil.</p></div>

## Pages associées
<div class="related"><a href="/fr/docs/scheduling/"><span>Source</span>Planification — équivalent dans l’app de l’intention d’activation.</a><a href="/fr/docs/export/"><span>Source</span>Export — équivalent dans l’app des intentions par plage de dates.</a></div>
