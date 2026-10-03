---
title: "Vollständiger öffentlicher und autorisierter Datenbestand"
description: "Exportiere mit der CLI alle öffentlichen, unterstützten und freigegebenen Datentypen eines iPhone oder Android-Geräts."
---

<div class="availability preview"><strong>Entwicklungsvorschau · nicht in alpha.7</strong><p>Automatisiere diese Funktion erst, wenn eine spätere <code>healthmd-cli/v&lt;version&gt;</code>-Veröffentlichung sie ausdrücklich nennt.</p></div>

`--full-corpus` fordert jeden Typ an, den die öffentliche Plattform-API anbietet, der installierte Build unterstützt und der Benutzer freigegeben hat. Private Apple-, Google- oder Anbieterdatenbanken bleiben unzugänglich.

```bash
healthmd export --all --raw --full-corpus --output apple-health-corpus.json
healthmd export --all --raw --full-corpus --provider health_connect \
  --raw-format ndjson --output health-connect-corpus.ndjson
```

Apple behält v8-Dokumente und kanonische HealthKit-Datensätze. Android behält den nativen Health Connect-Snapshot. Prüfe `exported`, `empty`, `permission_not_granted`, `unsupported`, `feature_unavailable`, `skipped`, `partial` und `read_error`. Auslassung beweist nicht „leer“.

Jobs bleiben sieben Tage fortsetzbar:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
```

Ein Timeout bricht nicht ab. Speichere den Datenbestand privat; er kann genaue Zeiten, Routen, klinische Texte, Medikamente oder Anhänge enthalten. Die beiden MCP-Corpus-Werkzeuge im Entwicklungsstand gehören nur zum vollständigen lokalen stdio-Profil.

<div class="related"><a href="/de/docs/cli-jobs/"><span>Wiederaufnahme</span>Unbekannte Ergebnisse sicher behandeln.</a><a href="/de/docs/guides/raw-snapshots/"><span>Android</span>Native Snapshots.</a></div>
