---
title: "Synchronisation Mac"
description: "Utilisez l’app macOS comme destination locale. Votre iPhone recueille les données HealthKit et les réglages, puis le Mac génère et écrit les fichiers demandés."
---

## Présentation
<p>La synchronisation Mac permet à votre Mac de produire des exports sans accéder directement à HealthKit. L’iPhone reste la source de référence des données Apple Health : il recueille les données quotidiennes sélectionnées et un instantané exact des réglages, puis confie la tâche au Mac. Celui-ci utilise les exportateurs partagés pour planifier les chemins, générer les formats demandés et écrire les fichiers dans le dossier choisi.</p>
<div class="doc-diagram"><div class="flow-steps" aria-label="Flux d’export de la synchronisation Mac">
<span><strong>iPhone</strong>Recueille les données HealthKit et prend un instantané des réglages effectifs.</span>
<span><strong>Réseau local</strong>Transfère la tâche versionnée à l’app Mac à proximité.</span>
<span><strong>Mac</strong>Génère les formats sélectionnés et les écrit dans le dossier choisi.</span>
<span><strong>Coffre</strong>Obsidian, iCloud Drive ou tout dossier local reçoit l’export final.</span>
</div></div>

## Activation
<ol><li>Installez et ouvrez l’app macOS.</li><li>Sur le Mac, choisissez un dossier de destination afin que Health.md puisse y écrire.</li><li>Sur l’iPhone, ouvrez l’onglet Synchronisation et activez la connectivité Mac.</li><li>Revenez à l’onglet Export de l’iPhone, choisissez <em>Mac connecté</em>, configurez l’export et touchez Export.</li></ol>

## Données transférées
<ul><li>Une demande d’export versionnée qui décrit la plage de dates et les réglages effectifs</li><li>Des messages de progression et de capacité pendant la collecte HealthKit par l’iPhone</li><li>Des trames de taille limitée, validées par somme de contrôle, qui contiennent les données quotidiennes recueillies et l’instantané exact des réglages pour les tâches d’écriture de fichiers</li><li>Un résultat structuré : réussite, réussite partielle, échec, rejet ou indisponibilité</li></ul>
<p>Aucun compte ni cloud distant de données de santé n’est nécessaire. La synchronisation de proximité utilise Multipeer Connectivity chiffré ; Manual IP/Tailscale utilise un transport Network.framework chiffré et jumelé. Les deux appareils doivent pouvoir communiquer et l’iPhone reste le lecteur HealthKit.</p>

## Quand l’utiliser
<div class="options">
<div class="option"><strong>Coffres réservés au bureau</strong><p>Si votre coffre Obsidian se trouve uniquement sur le Mac, c’est le chemin direct de HealthKit sur iPhone vers les fichiers Mac.</p></div>
<div class="option"><strong>Historiques volumineux</strong><p>Conservez les fichiers finaux sur un disque de bureau tandis que l’iPhone assure la lecture HealthKit et la configuration.</p></div>
<div class="option"><strong>Archives locales</strong><p>Écrivez directement dans des dossiers sauvegardés, versionnés ou indexés sur macOS.</p></div>
</div>
<div class="callout"><strong>Réseau local requis.</strong><p style="margin-top:6px;">Les deux appareils doivent être à proximité et autorisés à utiliser le réseau local. Un iPhone connecté uniquement au réseau cellulaire ne peut pas découvrir de destination Mac. Si l’état indique que le Mac nécessite votre attention, rouvrez l’app Mac et sélectionnez de nouveau le dossier de destination.</p></div>

## La synchronisation Mac et Direct CLI Access sont deux fonctions distinctes
La synchronisation Mac associe l’iPhone à Health.md for Mac afin d’assurer les exports vers une destination et le contexte chiffré des agents. Direct CLI Access associe l’iPhone à une installation en ligne de commande dans un domaine de confiance distinct. Le mode direct peut exporter les données brutes ou des fichiers générés sans l’app Mac, mais ne peut utiliser ni l’index chiffré de requêtes du Mac ni MCP.

Consultez [CLI directe pour iPhone](/fr/docs/cli-direct/) avant d’activer le réglage distinct sur l’iPhone.

## Pages associées
<div class="related">
<a href="/fr/docs/macos/"><span>Bureau</span>App macOS — Export, Planification et Historique sur Mac.</a>
<a href="/fr/docs/scheduling/"><span>Flux</span>Planification — automatisez les exports récurrents.</a>
<a href="/fr/docs/cli-direct/"><span>Confiance distincte</span>CLI directe pour iPhone — associez une CLI sans passer par l’app Mac.</a>
<a href="/fr/docs/reference/connected-mac-iphone-protocol/"><span>Protocole</span>Référence Mac–iPhone connecté — capacités, demandes, transfert limité et résultats.</a>
</div>
