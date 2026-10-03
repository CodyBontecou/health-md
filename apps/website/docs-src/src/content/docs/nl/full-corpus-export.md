---
title: "Volledig openbaar en geautoriseerd corpus"
description: "Exporteer met de CLI alle openbare, ondersteunde en geautoriseerde typen van iPhone of Android met volledigheidsbewijs."
---

<div class="availability preview"><strong>Ontwikkelpreview · niet in alpha.7</strong><p>Automatiseer pas wanneer een latere <code>healthmd-cli/v&lt;version&gt;</code>-release dit expliciet publiceert.</p></div>

`--full-corpus` vraagt elk type dat de openbare API aanbiedt, de geïnstalleerde build ondersteunt en de gebruiker heeft toegestaan. Het leest geen private Apple-, Google- of providerdatabase.

```bash
healthmd export --all --raw --full-corpus --output apple-health-corpus.json
healthmd export --all --raw --full-corpus --provider health_connect \
  --raw-format ndjson --output health-connect-corpus.ndjson
```

Apple behoudt v8-documenten en canonieke HealthKit-records. Android behoudt de provider-native Health Connect-snapshot. Controleer `exported`, `empty`, `permission_not_granted`, `unsupported`, `feature_unavailable`, `skipped`, `partial` en `read_error`. Weglaten bewijst niet leegte.

Jobs blijven zeven dagen hervatbaar:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
```

Een time-out annuleert niet. Bewaar het corpus privé; het kan exacte tijden, routes, klinische tekst, medicatie of bijlagen bevatten. De twee huidige MCP-corpustools horen alleen bij het volledige lokale stdio-profiel.

<div class="related"><a href="/nl/docs/cli-jobs/"><span>Herstel</span>Hervat zonder dubbel werk.</a><a href="/nl/docs/guides/raw-snapshots/"><span>Android</span>Native snapshots.</a></div>
