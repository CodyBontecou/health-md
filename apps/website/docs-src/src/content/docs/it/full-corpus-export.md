---
title: "Corpus pubblico e autorizzato completo"
description: "Esporta con la CLI tutti i tipi pubblici supportati e autorizzati da iPhone o Android, conservando la prova di completezza."
---

<div class="availability preview"><strong>Anteprima di sviluppo · assente da alpha.7</strong><p>Non automatizzare finché una versione successiva <code>healthmd-cli/v&lt;version&gt;</code> non la pubblica esplicitamente.</p></div>

`--full-corpus` richiede ogni tipo esposto dall’API pubblica, supportato dalla build installata e autorizzato dall’utente. Non legge database privati Apple, Google o del provider.

```bash
healthmd export --all --raw --full-corpus --output apple-health-corpus.json
healthmd export --all --raw --full-corpus --provider health_connect \
  --raw-format ndjson --output health-connect-corpus.ndjson
```

Apple conserva documenti v8 e record HealthKit canonici. Android conserva lo snapshot Health Connect nativo. Controlla `exported`, `empty`, `permission_not_granted`, `unsupported`, `feature_unavailable`, `skipped`, `partial` e `read_error`. L’omissione non dimostra “vuoto”.

I job restano recuperabili per sette giorni:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
```

Un timeout non annulla. Conserva il corpus in un file privato: può contenere orari esatti, percorsi, testo clinico, farmaci o allegati. I due strumenti MCP attuali appartengono solo al profilo stdio locale completo.

<div class="related"><a href="/it/docs/cli-jobs/"><span>Ripresa</span>Evita duplicati.</a><a href="/it/docs/guides/raw-snapshots/"><span>Android</span>Snapshot nativi.</a></div>
