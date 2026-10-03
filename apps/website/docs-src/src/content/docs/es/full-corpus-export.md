---
title: "Corpus público y autorizado completo"
description: "Exporta mediante la CLI todos los tipos públicos compatibles y autorizados de un iPhone o Android, conservando evidencia de integridad."
---

<div class="availability preview"><strong>Vista previa de desarrollo · no incluida en alpha.7</strong><p>No automatices esta función hasta que una versión posterior <code>healthmd-cli/v&lt;version&gt;</code> la publique expresamente.</p></div>

`--full-corpus` solicita cada tipo que la API pública expone, la versión instalada de Health.md admite y el usuario autorizó. No accede a una base privada de Apple, Google o un proveedor.

```bash
healthmd export --all --raw --full-corpus --output apple-health-corpus.json
healthmd export --all --raw --full-corpus --provider health_connect \
  --raw-format ndjson --output health-connect-corpus.ndjson
```

Apple conserva documentos v8 y registros HealthKit canónicos. Android conserva el snapshot nativo de Health Connect. Revisa `exported`, `empty`, `permission_not_granted`, `unsupported`, `feature_unavailable`, `skipped`, `partial` y `read_error`. Omitir un tipo no demuestra que esté vacío.

El trabajo es duradero durante siete días:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
```

Un timeout no cancela el trabajo. Guarda el corpus en un archivo privado: puede contener fechas exactas, rutas, datos clínicos, medicamentos, estado de ánimo o adjuntos.

Las dos herramientas MCP de corpus del código actual solo existen en el perfil stdio local completo. Usa la CLI para transferencias completas.

<div class="related"><a href="/es/docs/cli-jobs/"><span>Recuperación</span>Reanuda sin duplicar trabajo.</a><a href="/es/docs/guides/raw-snapshots/"><span>Android</span>Snapshots nativos.</a></div>
