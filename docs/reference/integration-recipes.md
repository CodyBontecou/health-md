# Integration recipes

These examples show how to consume Health.md exports without flattening source identity or hiding partial capture. Replace paths/endpoints with your own. The fixture paths point to deterministic generated examples.

## Validate a daily JSON record in Python

```python
import json
from pathlib import Path

record = json.loads(Path("2026-03-15.json").read_text())

if record.get("schema") != "healthmd.health_data":
    raise ValueError("unsupported daily schema")
if record.get("schema_version") != 6:
    raise ValueError("unsupported daily schema version")

status = record["raw_capture_status"]
if status in {"complete", "partial"}:
    archive = record.get("healthkit_record_archive")
    if archive is None:
        raise ValueError("capture status requires canonical archive")
    if archive.get("schema") != "healthmd.healthkit_records":
        raise ValueError("unsupported archive schema")
    if archive.get("schema_version") != 1:
        raise ValueError("unsupported archive version")
else:
    archive = None

print(record["date"], status, len(archive["records"]) if archive else 0)
```

Do not require a non-empty `records` array for complete capture. A successful empty archive is valid.

## Reject incomplete canonical queries

```python
incomplete_statuses = {"failure", "unsupported", "skipped", "cancelled"}

results = archive["query_manifest"]["results"]
incomplete = [result for result in results if result["status"] in incomplete_statuses]

if archive["capture_status"] == "complete" and incomplete:
    raise ValueError("archive claims complete despite incomplete query evidence")

for result in incomplete:
    print(result["identifier"], result["status"], result.get("error"))
```

Your application can accept partial data, but it should store the incomplete evidence with the retained records.

## Parse typed metadata in TypeScript

```typescript
type MetadataValue =
  | { type: "null" }
  | { type: "string"; value: string }
  | { type: "bool"; value: boolean }
  | { type: "signed_integer"; value: number }
  | { type: "unsigned_integer"; value: number }
  | { type: "floating_point"; value: number | string }
  | { type: "date"; value: string }
  | { type: "data"; value: string }
  | { type: "url"; value: string }
  | { type: "quantity"; value?: number; unit?: string; raw_description: string }
  | { type: "array"; value: MetadataValue[] }
  | { type: "dictionary"; value: Record<string, MetadataValue> }
  | { type: "unsupported"; type_name: string; description: string }
  | { type: string; [key: string]: unknown }; // preserve future tags

function decodeMetadata(value: MetadataValue): unknown {
  switch (value.type) {
    case "null": return null;
    case "array": return value.value.map(decodeMetadata);
    case "dictionary":
      return Object.fromEntries(
        Object.entries(value.value).map(([key, child]) => [key, decodeMetadata(child)])
      );
    case "data": return Uint8Array.from(atob(value.value), c => c.charCodeAt(0));
    case "unsupported": return value; // retain type name and description
    default: return "value" in value ? value.value : value;
  }
}
```

Do not stringify the entire metadata dictionary before storage. Preserve each tag and unknown object.

### JavaScript integer precision

Canonical signed/unsigned metadata can contain full 64-bit values. Standard `JSON.parse` converts JSON numbers to IEEE-754 `number` and cannot exactly represent every 64-bit integer. If exact metadata integers matter, parse the original JSON with a bigint-preserving library before coercion. Do not use a rounded JavaScript number as a deduplication key or checksum input.

## Index records and relationships

```python
from collections import defaultdict

records_by_uuid = {
    record["original_uuid"]: record
    for record in archive["records"]
}
external_by_id = {
    record["external_identifier"]: record
    for record in archive.get("external_records", [])
}

outgoing = defaultdict(list)
for record in archive["records"]:
    for relationship in record["relationships"]:
        target = relationship["target"]
        outgoing[record["original_uuid"]].append({
            "target_type": target["type"],
            "target_value": target["value"],
            "role": relationship["role"],
            "kind": relationship["kind"],
            "owner_date": relationship.get("target_owner_date"),
        })
```

If a UUID target is absent from the current day, use `target_owner_date` to locate the daily archive that owns it. Do not discard the edge.

## Read exact quantity payloads

```python
for record in archive["records"]:
    payload = record["payload"]
    if payload["type"] != "quantity":
        continue

    print(record["object_type_identifier"], payload["value"], payload["unit"])

    for point in payload.get("series", []):
        quantity = point["quantity"]
        interval = point["date_interval"]
        print(
            point["owning_sample_uuid"],
            interval["start_date"],
            quantity["value"],
            quantity["unit"],
        )
```

Use each payload's unit rather than a display preference. A canonical HealthKit microgram payload can say `mcg` while the summary dictionary says `µg`; both are micrograms, not milligrams.

## Stream CSV safely in Python

```python
import csv
import json

with open("2026-03-15.csv", newline="", encoding="utf-8") as handle:
    reader = csv.reader(handle)
    header = next(reader)
    if header != ["Date", "Category", "Metric", "Value", "Unit", "Timestamp"]:
        raise ValueError("unexpected CSV header")

    for row in reader:
        # Production v6 compatibility permits five-field aggregate rows.
        if len(row) == 5:
            row.append("")
        if len(row) != 6:
            raise ValueError(f"unexpected row width: {len(row)}")

        date, category, metric, value, unit, timestamp = row
        if unit == "json":
            value = json.loads(value)
        print(date, category, metric, timestamp, value)
```

`newline=""` matters because canonical JSON strings can contain line breaks inside quoted CSV fields.

## Verify JSON and CSV UUID parity

```python
import csv
import json
from pathlib import Path

daily = json.loads(Path("2026-03-15.json").read_text())
json_uuids = {
    source_record["original_uuid"]
    for source_record in daily["healthkit_record_archive"]["records"]
}

csv_uuids = set()
with open("2026-03-15.csv", newline="", encoding="utf-8") as handle:
    for row in csv.DictReader(handle):
        if row["Metric"] == "Raw HealthKit Record":
            csv_uuids.add(json.loads(row["Value"])["original_uuid"])

if json_uuids != csv_uuids:
    raise ValueError("JSON/CSV canonical record mismatch")
```

## Query JSON with `jq`

List incomplete queries:

```bash
jq '.healthkit_record_archive.query_manifest.results[] |
    select(.status != "success") |
    {identifier, status, record_count, error}' 2026-03-15.json
```

List directly selected records only:

```bash
jq '.healthkit_record_archive.records[] |
    select((.metric_attribution.direct_metric_ids | length) > 0) |
    {uuid: .original_uuid, kind: .record_kind,
     metrics: .metric_attribution.direct_metric_ids}' 2026-03-15.json
```

Extract quantity records:

```bash
jq '.healthkit_record_archive.records[] |
    select(.payload.type == "quantity") |
    [.start_date, .object_type_identifier, .payload.value, .payload.unit] |
    @tsv' 2026-03-15.json
```

## Import canonical CSV rows with DuckDB

```sql
CREATE TABLE healthmd AS
SELECT *
FROM read_csv(
  '2026-03-15.csv',
  header = true,
  columns = {
    'Date': 'VARCHAR',
    'Category': 'VARCHAR',
    'Metric': 'VARCHAR',
    'Value': 'VARCHAR',
    'Unit': 'VARCHAR',
    'Timestamp': 'VARCHAR'
  },
  null_padding = true
);

SELECT
  json_extract_string(Value, '$.original_uuid') AS original_uuid,
  json_extract_string(Value, '$.record_kind') AS record_kind,
  Timestamp
FROM healthmd
WHERE Metric = 'Raw HealthKit Record';
```

`null_padding = true` accommodates the production five-field aggregate compatibility rows.

## Receive API Endpoint exports

Pseudocode for a receiver:

```typescript
async function receive(request: Request): Promise<Response> {
  if (request.headers.get("content-type") !== "application/json") {
    return new Response("JSON required", { status: 415 });
  }

  const body = await request.json();
  if (body.schema !== "healthmd.api_export") {
    return new Response("Unsupported envelope", { status: 400 });
  }
  if (body.daily_record_schema !== "healthmd.health_data" ||
      body.daily_record_schema_version !== 6) {
    return new Response("Unsupported daily schema", { status: 422 });
  }

  for (const daily of body.records) {
    validateAndStoreIdempotently(daily);
  }
  await storeFailedDateDetails(body.failed_date_details ?? []);

  return Response.json({ accepted: body.record_count }, { status: 202 });
}
```

Do not automatically follow source URLs found inside records.

## Run strict raw export from a shell

```bash
set -euo pipefail
healthmd export --iphone --yesterday --raw > /tmp/healthmd-result.json
jq -e '.status == "success" and .raw_result.schema == "healthmd.raw_result"' \
  /tmp/healthmd-result.json >/dev/null
```

For an automation that intentionally accepts partial data:

```bash
healthmd export --iphone --last 7 --raw --allow-partial \
  > /tmp/healthmd-result.json
jq '.status, .raw_result.capture_summary, .raw_result.missing_dates' \
  /tmp/healthmd-result.json
```

`--allow-partial` changes exit behavior only. It does not convert partial evidence into complete capture.

## Read an Individual Entry note

A canonical entry's source identity is:

```text
(original_uuid, metric)
```

Parse `canonical_record_json` from frontmatter for exact source data. Flattened fields are presentation conveniences. Reject any workflow that treats `entry_kind: daily_aggregate` as an original HealthKit event.

## Roll up your own source archive

Health.md's built-in roll-ups operate on documented daily summary projections. If you need source-level analysis:

1. load canonical JSON/CSV records;
2. assign days using archive ownership;
3. choose record kinds/metrics explicitly;
4. preserve unit and provenance;
5. define your own deduplication/aggregation policy;
6. keep query completeness beside every result.

Do not mix summary values and source records in the same aggregation without documenting which layer won.
