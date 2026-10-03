---
title: "API Endpoint"
description: "Envoyez les données JSON Apple Health sélectionnées directement depuis l’iPhone vers votre propre point de terminaison HTTP(S)."
---

<p>API Endpoint est une destination d’export destinée aux utilisateurs qui souhaitent transmettre les données Health.md à leur propre serveur, webhook, base de données, tableau de bord ou automatisation. L’iPhone lit toujours Apple Health ; au lieu d’écrire des fichiers, il envoie le JSON par POST au point de terminaison configuré.</p>

<div class="callout">
<strong>Rappel de confidentialité.</strong>
<p style="margin-top:6px;">Cette destination envoie volontairement les données de santé sélectionnées à l’URL que vous saisissez. Utilisez un point de terminaison que vous contrôlez ou auquel vous faites confiance, privilégiez HTTPS et limitez les métriques aux seuls besoins de votre service.</p>
</div>

## Configurer la cible

<ol>
<li>Ouvrez Health.md sur iPhone.</li>
<li>Accédez à <strong>Export</strong>.</li>
<li>Dans <strong>Export Target</strong>, choisissez <strong>API Endpoint</strong>.</li>
<li>Saisissez une URL comme <code>https://api.example.com/healthmd/ingest</code>.</li>
<li>Facultatif : saisissez un bearer token. Health.md le stocke dans Keychain.</li>
<li>Touchez <strong>Done</strong>, choisissez votre plage de dates et vos métriques, puis touchez <strong>Export</strong>.</li>
</ol>

<p>Si vous saisissez un jeton simple, Health.md l’envoie comme <code>Authorization: Bearer &lt;token&gt;</code>. Si la valeur commence déjà par <code>Bearer </code> ou <code>Basic </code>, Health.md l’envoie telle quelle.</p>

## Structure de la charge utile

<p>Health.md envoie une requête POST par export. Le corps est une enveloppe d’API <code>healthmd.api_export</code>, dont la version évolue indépendamment, contenant des enregistrements quotidiens publics <code>healthmd.health_data</code> au schéma v8. L’enveloppe d’API v1 transporte les enregistrements quotidiens ; la v2 peut aussi transporter des fichiers annexes de fournisseurs sans modifier le schéma des enregistrements quotidiens.</p>

<div class="options">
<div class="option"><strong><code>records</code></strong><p>Objets quotidiens complets au schéma v8 conservés pour la plage demandée, y compris les enregistrements complets mais vides dont le manifeste de requête sert de preuve.</p></div>
<div class="option"><strong><code>failed_date_details</code></strong><p>Dates ayant échoué avant qu’un document quotidien puisse être conservé.</p></div>
<div class="option"><strong><code>daily_record_schema_version</code></strong><p>Version du schéma quotidien contenu dans <code>records</code>. Elle évolue indépendamment de la version de l’enveloppe d’API.</p></div>
<div class="option"><strong>Fichiers annexes de fournisseurs</strong><p>Enregistrements externes v2 facultatifs, avec leurs propres règles de schéma et d’identité, lorsqu’un fournisseur connecté est activé.</p></div>
</div>

<p>Consultez l’<a href="/docs/reference/generated/automation/api-export-v1.json">enveloppe d’API v1</a> complète générée en production et l’<a href="/docs/reference/generated/automation/api-export-v2-provider-sidecar.json">enveloppe d’API v2 avec fichier annexe de fournisseur</a>. Le <a href="/fr/docs/reference/api-and-cli/">contrat API et CLI</a> documente chaque champ, limite de version et règle d’acceptation.</p>

## Exigences du point de terminaison

<div class="options">
<div class="option"><strong>Méthode</strong><p>Acceptez <code>POST</code>.</p></div>
<div class="option"><strong>Type de contenu</strong><p>Acceptez <code>application/json</code>.</p></div>
<div class="option"><strong>Réussite</strong><p>Renvoyez n’importe quel état <code>2xx</code> après acceptation sûre de la charge utile.</p></div>
<div class="option"><strong>Échecs</strong><p>Renvoyez <code>4xx</code> ou <code>5xx</code> pour les requêtes rejetées. Health.md affiche un court aperçu de la réponse lorsqu’il est disponible.</p></div>
</div>

<p>Pour fiabiliser l’ingestion, rendez votre point de terminaison idempotent par date. Un utilisateur peut relancer la même plage d’export après avoir modifié les métriques ou corrigé une erreur du serveur.</p>

## Conseils

<ul>
<li>Testez avec une journée avant d’importer un long historique.</li>
<li>Gardez Lossless Health Records activé lorsque l’exhaustivité des sources est importante ; réduisez la plage de dates pour les itinéraires denses, les documents cliniques, les ECG ou les pièces jointes.</li>
<li>Validez le jeton côté serveur avant de stocker une charge utile.</li>
<li>Utilisez <code>records[].date</code> comme clé principale par jour.</li>
<li>Renvoyez un corps d’erreur concis ; Health.md n’affiche qu’un court aperçu.</li>
</ul>

## Dépannage

| Problème | Signifie généralement | Correctif |
|---|---|---|
| La cible API n’est pas prête | L’URL est vide ou invalide | Rouvrez les réglages API Endpoint et saisissez une URL HTTP(S) valide. |
| HTTP 401 ou 403 | Jeton manquant ou rejeté | Mettez à jour le jeton ou les règles d’authentification du serveur. |
| HTTP 404 | Le chemin d’URL est incorrect | Vérifiez la route sur votre serveur. |
| HTTP 413 | La charge utile est trop volumineuse | Exportez moins de jours ; utilisez une sortie résumé seul uniquement lorsque votre récepteur n’exige pas les enregistrements sources canoniques. |
| Certaines dates sont manquantes | Aucune donnée HealthKit activée pour ces dates | Vérifiez <code>failed_date_details</code> et votre sélection de métriques. |

## Pages associées

<div class="related">
  <a href="/fr/docs/export/"><span>Source</span>Export — choisissez des cibles, des plages de dates et lancez des exports manuels.</a>
  <a href="/fr/docs/reference/api-and-cli/"><span>Schéma</span>Référence API et CLI — enveloppes exactes, versions, comportement d’échec et exemples générés.</a>
  <a href="/fr/docs/format/"><span>Sortie</span>Personnalisation du format — JSON, CSV, Markdown, unités et champs.</a>
</div>
