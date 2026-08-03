---
title: "App macOS"
description: "Utilisez Health.md for Mac comme destination d’export de l’iPhone, hôte local de CLI et MCP, stockage chiffré du contexte de santé, visualiseur d’historique et autorité des dossiers."
---

Health.md for Mac remplit deux rôles locaux :

1. recevoir les tâches d’export de l’iPhone et écrire les fichiers dans le dossier choisi ;
2. héberger la CLI en boucle locale, l’API de requête, le contexte de santé chiffré et l’adaptateur MCP utilisés par les agents locaux.

Apple Health reste sur l’iPhone. L’app Mac ne lit pas directement HealthKit.

## Zones principales
<div class="options">
<div class="option"><strong>Synchronisation</strong><p>Indique si le Mac peut être découvert et recevoir les tâches d’export de l’iPhone.</p></div>
<div class="option"><strong>Dossier de destination</strong><p>Conserve un signet à portée de sécurité pour les sorties Markdown, JSON, CSV, Bases, consolidées, ZIP et Notes quotidiennes.</p></div>
<div class="option"><strong>Planification</strong><p>Affiche la planification et l’état de préparation côté Mac. L’iPhone fournit toujours les données HealthKit.</p></div>
<div class="option"><strong>Historique</strong><p>Suit les résultats, la progression persistante, les erreurs et les informations nécessaires à une nouvelle tentative des fichiers écrits sur le bureau.</p></div>
<div class="option"><strong>Réglages</strong><p>Affiche l’état de la destination, les contrôles de conservation du contexte chiffré et la configuration de la CLI locale.</p></div>
<div class="option"><strong>Barre des menus</strong><p>Donne rapidement accès à l’état, aux réglages et à l’app pendant que Health.md reste disponible localement.</p></div>
<div class="option"><strong>CLI</strong><p>Installe les utilitaires intégrés <code>healthmd</code> et <code>healthmd-mcp</code>, copie les invites de configuration, installe la compétence facultative pour agents et présente des commandes testées.</p></div>
</div>

## Configurer une destination Mac
1. Installez et ouvrez Health.md sur Mac.
2. Choisissez un dossier sur le disque local, iCloud Drive ou dans un coffre Obsidian.
3. Sur l’iPhone, activez la connectivité Mac dans l’onglet Synchronisation.
4. Sur l’iPhone, choisissez Mac connecté comme destination.
5. Configurez l’export et touchez Export.

L’iPhone recueille les données HealthKit et l’instantané des réglages effectifs. Les pairs actuels transfèrent des partitions de taille limitée, validées par somme de contrôle. Le Mac utilise les exportateurs de production et écrit les fichiers demandés.
<div class="callout"><strong>Limite de HealthKit.</strong><p style="margin-top:6px;">Le Mac ne peut pas interroger Apple Health seul. Les nouveaux exports et le contexte des agents nécessitent que l’app iPhone connectée soit ouverte. Les requêtes chiffrées en cache peuvent s’exécuter sans nouvelle connexion si la couverture enregistrée suffit.</p></div>

## Configuration de la CLI et des agents
Dans la zone **CLI** de l’app Mac, vous pouvez :
- voir les chemins exacts des utilitaires signés dans le bundle ;
- copier des alias ou des commandes de liens symboliques vers `~/.local/bin` ;
- copier une invite de configuration assistée par un agent ;
- installer la compétence facultative `healthmd-cli` dans le dossier choisi ;
- consulter les commandes actuelles d’état, de diagnostic, d’extraction, de requête, de sommeil, d’entraînement, de séance, de couverture et d’export ;
- examiner les erreurs courantes de préparation.

L’app ne modifie jamais les fichiers de démarrage du shell et n’installe rien dans un dossier système sans action de votre part.

Commencez par :
```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --category Sleep --yesterday
```
Consultez [CLI Health.md](/fr/docs/cli/) pour le choix du back-end et [Agents locaux](/fr/docs/agents/) pour l’architecture des requêtes.

## Contexte de santé chiffré
Les nouvelles demandes de requête et de preuve utilisent un mode dédié d’acquisition du contexte. L’iPhone lit précisément la métrique, la source, la date et le niveau de détail demandés. Il ne crée pas de fichiers d’export et ne modifie pas les préférences enregistrées.

Le Mac stocke chaque journée de référence compacte dans un bloc AES-256-GCM authentifié séparément. Un élément du Trousseau limité à cet appareil et accessible une fois déverrouillé contient la clé aléatoire. Les noms de fichiers sont aléatoires et ne révèlent ni dates ni métriques.

Réglages indique le nombre de journées chiffrées et leur plage de dates. Deux actions indépendantes contrôlent la conservation :
- **Delete Older Context** supprime les journées strictement antérieures à la limite choisie ;
- **Delete All Encrypted Context** supprime tous les fichiers de contexte et la clé dédiée du Trousseau.

La conservation du contexte ne supprime jamais les données Apple Health, les fichiers d’export, les signets de destination Mac ni les identifiants des fournisseurs connectés.

## Limites de l’API en boucle locale
L’app Mac écoute sur `127.0.0.1` et `::1`, port `17645`, pour les routes locales d’état, d’export, de requête, de preuve, d’actualisation et de tâches persistantes.

Il n’existe ni jeton bearer ni inscription d’agent. Tout processus local peut appeler l’API lorsque l’app est ouverte. N’exposez, ne proxifiez et ne tunnelisez jamais ce port vers une autre machine.

L’utilitaire `healthmd-mcp`, exécuté dans un bac à sable, n’accepte que les points de terminaison HTTP canoniques en boucle locale et fournit des outils sans shell, fichiers arbitraires, SQL, récupération d’URL, ressources, invites, racines ni échantillonnage.

## Direct CLI Access est distinct
Le réglage **Direct CLI Access** de l’iPhone crée une relation de confiance distincte entre une CLI compatible et l’iPhone. Il peut contourner l’app Mac pour l’export brut, l’extraction canonique, les fichiers générés, l’état, la reprise et l’annulation.

Le mode direct n’utilise pas le contexte chiffré de l’app Mac. La commande portable `healthmd mcp serve` exécute plutôt de nouvelles requêtes typées directement sur l’iPhone au premier plan, avec la même identité d’exécutable que lors du jumelage. Consultez [CLI directe pour iPhone](/fr/docs/cli-direct/) pour le jumelage et les plateformes compatibles.

## Pages associées
<div class="related">
<a href="/fr/docs/sync/"><span>Destination</span>Synchronisation Mac : associez iPhone et Mac pour les exports locaux.</a>
<a href="/fr/docs/cli/"><span>Terminal</span>CLI Health.md : installez les utilitaires, choisissez un back-end et exécutez les commandes.</a>
<a href="/fr/docs/agents/"><span>Contexte local</span>Agents : acquisition ciblée, stockage chiffré, preuves et conservation.</a>
<a href="/fr/docs/mcp/"><span>Outils</span>Serveur MCP local : configuration, catalogue d’outils et limites du bac à sable.</a>
<a href="/fr/docs/scheduling/"><span>Flux</span>Planification : automatisez les exports récurrents.</a>
</div>
