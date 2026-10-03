---
title: "Build a private Apple Health webhook with Health.md."
description: "Send selected schema-v8 Apple Health records from iPhone to an endpoint you control, with authentication, idempotency, and explicit failure handling."
lead: "API Endpoint replaces the folder destination with one deliberate POST to your service; the iPhone remains the Apple Health source."
date: "2026-09-22T14:00:00.000Z"
updated: "2026-09-22T14:00:00.000Z"
category: "Workflow guide"
draft: false
tags:
  - healthmd
  - api
  - webhooks
  - apple-health
  - privacy
---

A private webhook is useful when you own the receiver: a home server, encrypted personal database, private dashboard, or automation that should not scrape files from a phone.

Health.md's **API Endpoint** target sends selected Apple Health JSON directly from the iPhone to the URL you configure. It does not proxy the payload through a Health.md health-data cloud.

## Configure a narrow first request

On iPhone, open **Export**, choose **API Endpoint**, enter an HTTP(S) URL, and optionally add an authorization value. A plain token is sent as `Authorization: Bearer <token>`. Values already beginning with `Bearer ` or `Basic ` are used as entered. Health.md stores the credential in Keychain.

Start with one day and one or two metrics. Expand only after the receiver validates and stores that request correctly.

Health.md sends one POST per export action. The body is a versioned `healthmd.api_export` envelope containing schema-v8 `healthmd.health_data` daily records. Version 2 may also carry provider sidecars, whose schema and identity remain separate from the daily-record schema.

## Make the receiver boring

A safe receiver should:

- require TLS on any non-local deployment;
- authenticate before reading or storing the body;
- enforce a request-size limit;
- validate envelope and daily schema versions;
- write atomically;
- use the date and export identity for idempotency;
- return a `2xx` only after durable acceptance;
- avoid logging headers or health payloads.

A minimal handler shape looks like this:

```js
export async function POST(request) {
  if (request.headers.get("authorization") !== `Bearer ${process.env.TOKEN}`) {
    return new Response("Unauthorized", { status: 401 });
  }

  const body = await request.json();
  if (body.schema !== "healthmd.api_export" ||
      body.daily_record_schema !== "healthmd.health_data" ||
      body.daily_record_schema_version !== 8) {
    return new Response("Unsupported schema", { status: 422 });
  }

  await storeIdempotently(body); // Do not log body.
  return new Response(null, { status: 204 });
}
```

Production code also needs bounded parsing, explicit accepted envelope versions, secret rotation, storage encryption, retention, access control, and audit behavior appropriate to its environment.

## Treat retries as normal

A user may repeat an export after changing metrics, fixing a server error, or filling a late-synchronized date. The receiver should update or version the date rather than blindly append a duplicate.

Return `4xx` for a request that must be corrected and `5xx` for a temporary server failure. Keep the response body concise because Health.md shows only a bounded preview.

## Preserve evidence

Do not reduce every absent value to zero. Store `failed_date_details`, capture status, query manifests, coverage, units, and sidecar limitations alongside records. A complete-empty day is valid evidence; a failed day is not the same result.

For dense routes, clinical documents, ECGs, or attachments, shorten the date range and verify that your server permits the payload size. If a workflow needs a provider-native Android archive, use the separately documented Raw API Snapshot path rather than pretending the iPhone webhook has cross-platform semantics.

<div class="cta-row">
<a class="button" href="/docs/api-endpoint/">Read the API Endpoint guide</a>
<a class="button secondary" href="/docs/reference/integration-recipes/">See integration recipes</a>
</div>
