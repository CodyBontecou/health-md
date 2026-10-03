---
title: "Corpus public et autorisé complet"
description: "Exportez avec la CLI tous les types publics pris en charge et autorisés d’un iPhone ou Android, avec preuve de complétude."
---

<div class="availability preview"><strong>Aperçu de développement · absent d’alpha.7</strong><p>N’automatisez pas cette fonction avant qu’une version ultérieure <code>healthmd-cli/v&lt;version&gt;</code> ne la publie explicitement.</p></div>

`--full-corpus` demande chaque type exposé par l’API publique, pris en charge par le build installé et autorisé par l’utilisateur. Il n’accède pas à une base privée Apple, Google ou fournisseur.

```bash
healthmd export --all --raw --full-corpus --output apple-health-corpus.json
healthmd export --all --raw --full-corpus --provider health_connect \
  --raw-format ndjson --output health-connect-corpus.ndjson
```

Apple conserve les documents v8 et enregistrements HealthKit canoniques. Android conserve le snapshot Health Connect natif. Examinez `exported`, `empty`, `permission_not_granted`, `unsupported`, `feature_unavailable`, `skipped`, `partial` et `read_error`. Une omission ne prouve pas l’absence de données.

Les tâches restent récupérables sept jours :

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
```

Un délai dépassé n’annule pas la tâche. Conservez le corpus dans un fichier privé : il peut contenir heures exactes, itinéraires, données cliniques, médicaments ou pièces jointes. Les deux outils MCP du code actuel sont réservés au profil stdio local complet.

<div class="related"><a href="/fr/docs/cli-jobs/"><span>Reprise</span>Éviter les doublons.</a><a href="/fr/docs/guides/raw-snapshots/"><span>Android</span>Snapshots natifs.</a></div>
