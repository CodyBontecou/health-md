---
title: "Corpus público e autorizado completo"
description: "Exporte pela CLI todos os tipos públicos compatíveis e autorizados de um iPhone ou Android, com evidência de completude."
---

<div class="availability preview"><strong>Prévia de desenvolvimento · ausente no alpha.7</strong><p>Não automatize até que uma versão posterior <code>healthmd-cli/v&lt;version&gt;</code> publique o recurso explicitamente.</p></div>

`--full-corpus` solicita cada tipo exposto pela API pública, compatível com o build instalado e autorizado pelo usuário. Não lê bancos privados da Apple, Google ou provedor.

```bash
healthmd export --all --raw --full-corpus --output apple-health-corpus.json
healthmd export --all --raw --full-corpus --provider health_connect \
  --raw-format ndjson --output health-connect-corpus.ndjson
```

A Apple mantém documentos v8 e registros HealthKit canônicos. O Android mantém o snapshot nativo do Health Connect. Verifique `exported`, `empty`, `permission_not_granted`, `unsupported`, `feature_unavailable`, `skipped`, `partial` e `read_error`. Omissão não prova vazio.

Os trabalhos podem ser retomados por sete dias:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
```

Timeout não cancela. Guarde o corpus em arquivo privado: ele pode conter horários exatos, rotas, texto clínico, medicamentos ou anexos. As duas ferramentas MCP atuais existem apenas no perfil stdio local completo.

<div class="related"><a href="/pt-br/docs/cli-jobs/"><span>Recuperação</span>Retome sem duplicar.</a><a href="/pt-br/docs/guides/raw-snapshots/"><span>Android</span>Snapshots nativos.</a></div>
