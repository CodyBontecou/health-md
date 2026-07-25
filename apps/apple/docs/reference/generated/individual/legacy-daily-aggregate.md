# Summary-only and legacy aggregate fallback

This generated note uses fixed synthetic values. It records the compatibility boundary enforced by `IndividualEntryExporter.extractIndividualSamples`.

| Capture state | Canonical archive present | Extracted entries | Result |
|---|---:|---:|---|
| `not_requested` | no | 1 | A daily aggregate is emitted with `entry_kind: daily_aggregate`. |
| `legacy_unavailable` | no | 1 | A daily aggregate is emitted with `entry_kind: daily_aggregate`. |
| `partial` | no | 0 | No aggregate is substituted for requested canonical capture. |

Summary-only exports and legacy records may use aggregate fallback because source-event identity is unavailable by design. When canonical capture was requested, an empty, failed, unsupported, skipped, or partial canonical query is not replaced by a daily summary that could look like a source event.

## Summary-only generated entry

```markdown
---
date: 2026-07-14
time: "00:00"
datetime: 2026-07-14T00:00:00Z
type: body_measurements
metric: weight
value: 70.25
unit: kg
aggregation: daily_latest
entry_kind: daily_aggregate
---
```

## Legacy generated entry

```markdown
---
date: 2026-07-14
time: "00:00"
datetime: 2026-07-14T00:00:00Z
type: body_measurements
metric: weight
value: 71.50
unit: kg
aggregation: daily_latest
entry_kind: daily_aggregate
---
```
