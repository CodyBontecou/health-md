# Health.md Raw Record v1 Contract

Status: v1 normative record contract. Structural schema: [schemas/healthmd.raw_record.v1.schema.json](schemas/healthmd.raw_record.v1.schema.json). Snapshot semantics: [raw-snapshot-v1.md](raw-snapshot-v1.md).

## 1. Record envelope

The v1 envelope is additive: old Health Connect readers may treat absent `recordKind`/`source` as `health_connect_record` and `health_connect_api_projected`. Current producers emit all members. Structural nullable members are emitted as explicit JSON `null`.

| Member | Contract |
|---|---|
| `wireType` | Stable Health.md type. Cloud native pages use `provider_payload`; endpoint identity is in `providerPayload.endpointKey`. |
| `nativeIdentity` | Non-empty deterministic provider identity selected before hashing. |
| `recordKind` | `health_connect_record` (v1 default) or `provider_payload`. |
| `source` | Provider ID, fidelity level, and nullable logical endpoint key; never a URL. |
| `startTime` | Full-resolution UTC instant or `null` only for non-temporal medical resources. |
| `endTime` | Full-resolution UTC instant for interval records; `null` for instant and medical records. |
| `startZoneOffsetSeconds` | Original source offset in whole seconds, or explicit `null` when the source omitted it/record is non-temporal. It is metadata, not an alternate instant. |
| `endZoneOffsetSeconds` | Original interval end offset, or explicit `null`. Instant records do not copy start offset here. |
| `metadata` | Provider record metadata, or explicit `null` for PHR resources because Health Connect exposes no `Record.metadata` for them. |
| `fields` | Explicit Health Connect record-type object; `{}` for provider payload pages. Additive fields are allowed. |
| `providerPayload` | Exact cloud response envelope, or `null` for Health Connect. |
| `hash` | Health Connect canonical-record hash, or authoritative exact response-byte SHA-256 for `provider_payload`. |

An instant is `{epochSecond,nano,epochSecondExact}`. `epochSecondExact` MUST be the exact base-10 string for `epochSecond`, allowing Int64 values to survive JavaScript clients. Nanos MUST be retained exactly; producers MUST NOT reduce to milliseconds or render an ISO string in place of this object. An offset MUST NOT be inferred from device timezone, current timezone, or UTC when absent.

### 1.1 Provider-native cloud page

A `provider_payload` record MUST contain one complete successful response page without normalization. `providerPayload.responseBytesBase64` is standard RFC 4648 base64 of the exact HTTP entity bytes and is authoritative. `responseSha256` and `record.hash` MUST both equal SHA-256 of those decoded bytes. `responseText` is the exact decoded text only when the declared/default charset decoded valid JSON; it is never reconstructed from parsed JSON. Parsing is permitted solely for pagination tokens and fan-out IDs.

The page also carries provider ID, stable logical endpoint key, opaque endpoint digest, positive page ordinal, fetch instant, 2xx status, sanitized content type/charset, allowlisted response headers, sanitized query metadata, and `serverAggregation`. It MUST NOT contain OAuth/access/refresh tokens, Authorization, cookies, secret query/cursor values, arbitrary response headers/errors, stack traces, or a full URL. Tokens/cursors can drive a later request but are omitted from query metadata. Identity is `cloud:<provider>:<endpointKey>:<pageOrdinal>:<responseSha256>`; no random ID or normalized `HealthData` serialization is allowed.

## 2. Null versus absent

V1 distinguishes three states:

1. a required envelope member is always present;
2. an applicable source field with no source value is present as JSON `null` (for example `nutrition.energy`, `metadata.clientRecordId`, exercise lap `length`, or PHR `source.lastDataUpdateTime`);
3. an inapplicable or intentionally excluded payload member is absent (for example `route` when `includeExerciseRoutes=false`, interval `fields` on an instant type, or future SDK fields unknown to this pinned mapper).

Empty native collections are `[]`, not `null`. Marker records such as `intermenstrual_bleeding` and `menstruation_period` use `{}`. Empty string is preserved as a string and MUST NOT be changed to null. Consumers MUST tolerate additive members inside `fields`; they MUST NOT reinterpret an absent known field as zero, false, empty, or permission denial.

## 3. Identity and metadata

Identity precedence is deterministic:

1. non-blank `metadata.id` → `hc:<id>`;
2. otherwise non-blank `metadata.clientRecordId` → `client:<dataOriginPackageName>:<clientRecordId>:<clientRecordVersion>`;
3. provider mapper identity (PHR uses `medical:<dataSourceId>:<raw-fhir-type>:<fhirResourceId>`);
4. `synthetic:<sha256>` over the canonical record with blank identity and hash, only when no native identity exists.

Values are concatenated exactly; they are not case-folded or URL-decoded. Provider adapters SHOULD namespace delimiter-bearing values unambiguously in a later version; current v1 concatenation is a known collision risk. Duplicate resolution uses the final identity.

Health Connect `metadata` is:

```json
{
  "id": "provider record id",
  "clientRecordId": null,
  "clientRecordVersion": 0,
  "clientRecordVersionExact": "0",
  "lastModifiedTime": {"epochSecond": 0, "nano": 0, "epochSecondExact": "0"},
  "dataOriginPackageName": "source.package",
  "recordingMethod": {"raw": 2, "label": "automatically_recorded"},
  "device": {
    "type": {"raw": 1, "label": "watch"},
    "manufacturer": null,
    "model": null
  }
}
```

`id`, client ID/version, modification nanos, origin package, recording method, and exposed device fields MUST be copied without fabrication. `clientRecordVersionExact` is the exact base-10 representation of the Int64 version. `device` is null when omitted by Health Connect.

## 4. Enums and labels

Every SDK integer enum is encoded as `{"raw": <integer>, "label": <string>}`. `raw` is the fidelity value and MUST be preserved even when unknown. `label` is a stable lowercase snake-case convenience label pinned to the SDK mapper. An unmapped value is `unknown_<raw>`; it MUST NOT fail export or be collapsed to the SDK’s nominal unknown constant. Consumers MUST use `raw` for lossless round-trip and treat labels as descriptive, not authoritative.

This applies to recording method, device type, sleep stage, exercise/segment/phase, blood-pressure body position/location, blood-glucose specimen/meal relation, temperature location, VO2 measurement method, reproductive-health values, mindfulness/intensity values, medical resource type, and FHIR resource type. The mapper’s explicit label table is part of the v1 implementation; adding a label for a formerly unknown raw integer is additive and does not change identity.

## 5. Canonical numbers, quantities, durations, and units

A converted SDK quantity is:

```json
{"number": 1.25, "decimal": "1.25", "type": "Length", "unit": "m"}
```

* `number` is a finite JSON number in the canonical unit.
* `decimal` is a locale-independent, round-trippable decimal representation of the same binary SDK value. It MUST NOT contain a unit or grouping separators.
* `type` names the SDK quantity family; `unit` is exact and case-sensitive.
* The source unit is not exposed by the SDK record and is not claimed preserved (`preservesSourceUnits=false`). Conversion MUST use SDK unit accessors, not hand-written factors.

Unit-bearing scalar objects omit `type` but retain `number`, `decimal`, and `unit` (respiratory rate, HRV, and VO2). Counts and enum raw values are JSON integers. Finite raw doubles such as floors, latitude, cadence, and rate remain JSON numbers. Durations are `{seconds: integer, nano: 0..999999999}`. NaN and infinities are invalid.

Canonical units are: length/elevation/accuracy `m`; speed `m/s`; energy `kcal`; power/BMR `W`; pressure `mmHg`; blood glucose `mmol/L`; percentage `%`; absolute and delta temperature `degC`; body mass `kg`; nutrient mass `g`; hydration `L`; respiratory rate `breaths/min`; HRV `ms`; VO2 `mL/(min*kg)`.

## 6. Native field inventory

Notation: `Q(unit,type)` is the quantity object; `E` is raw+label enum; `I` is instant; `D` is duration. Nullable fields are marked `?` and MUST be present as null when omitted by the source.

| `wireType` | Exact `fields` members |
|---|---|
| `steps` | `count` integer. |
| `heart_rate` | `samples[]` ordered by `time`: `{time:I, beatsPerMinute:integer}`. |
| `sleep_session` | `title?`, `notes?`, `stages[]` ordered by start: `{startTime:I,endTime:I,stage:E}`. |
| `exercise_session` | `exerciseType:E`, `title?`, `notes?`, `plannedExerciseSessionId?`, `segments[]`, `laps[]`, and route rules in §7. |
| `distance` | `distance:Q(m,Length)`. |
| `active_calories_burned` | `energy:Q(kcal,Energy)`. |
| `total_calories_burned` | `energy:Q(kcal,Energy)`. |
| `basal_metabolic_rate` | `basalMetabolicRate:Q(W,Power)`. |
| `blood_pressure` | `systolic:Q(mmHg,Pressure)`, `diastolic:Q(mmHg,Pressure)`, `bodyPosition:E`, `measurementLocation:E`. |
| `blood_glucose` | `level:Q(mmol/L,BloodGlucose)`, `specimenSource:E`, `mealType:E`, `relationToMeal:E`. |
| `body_fat` | `percentage:Q(%,Percentage)`. |
| `body_temperature` | `temperature:Q(degC,Temperature)`, `measurementLocation:E`. |
| `height` | `height:Q(m,Length)`. |
| `weight` | `weight:Q(kg,Mass)`. |
| `oxygen_saturation` | `percentage:Q(%,Percentage)`. |
| `respiratory_rate` | `rate:{number,decimal,unit:"breaths/min"}`. |
| `heart_rate_variability_rmssd` | `heartRateVariabilityMillis:{number,decimal,unit:"ms"}`. |
| `nutrition` | §8. |
| `hydration` | `volume:Q(L,Volume)`. |
| `floors_climbed` | `floors` finite number. |
| `lean_body_mass` | `mass:Q(kg,Mass)`. |
| `resting_heart_rate` | `beatsPerMinute` integer. |
| `speed` | `samples[]` by time: `{time:I,speed:Q(m/s,Velocity)}`. |
| `vo2_max` | `vo2MillilitersPerMinuteKilogram:{number,decimal,unit:"mL/(min*kg)"}`, `measurementMethod:E`. |
| `elevation_gained` | `elevation:Q(m,Length)`. |
| `wheelchair_pushes` | `count` integer. |
| `power` | `samples[]` by time: `{time:I,power:Q(W,Power)}`. |
| `basal_body_temperature` | `temperature:Q(degC,Temperature)`, `measurementLocation:E`. |
| `body_water_mass` | `mass:Q(kg,Mass)`. |
| `bone_mass` | `mass:Q(kg,Mass)`. |
| `skin_temperature` | `baseline?:Q(degC,Temperature)`, `measurementLocation:E`, `deltas[]` by time: `{time:I,delta:Q(degC,TemperatureDelta)}`. |
| `cervical_mucus` | `appearance:E`, `sensation:E`. |
| `intermenstrual_bleeding` | Empty object. |
| `menstruation_flow` | `flow:E`. |
| `menstruation_period` | Empty object; interval is in envelope. |
| `ovulation_test` | `result:E`. |
| `sexual_activity` | `protectionUsed:E`. |
| `cycling_pedaling_cadence` | `samples[]` by time: `{time:I,revolutionsPerMinute:number}`. |
| `steps_cadence` | `samples[]` by time: `{time:I,rate:number}`. |
| `mindfulness_session` | `mindfulnessSessionType:E`, `title?`, `notes?`. |
| `planned_exercise_session` | §9. |
| `activity_intensity` | `activityIntensityType:E`. |
| `medical_resource` | §10. |

## 7. Exercise nested fields and route privacy

`segments[]` entries are `{startTime:I,endTime:I,segmentType:E,repetitions:integer}`. `laps[]` entries are `{startTime:I,endTime:I,length:Q(m,Length)|null}`.

When routes are included, `route` is always one of:

* `{"state":"consent_required","locations":[]}`;
* `{"state":"no_data","locations":[]}`;
* `{"state":"data","locations":[...]}` where each ordered location is `{time:I,latitude:number,longitude:number,horizontalAccuracy:Q(m,Length)|null,verticalAccuracy:Q(m,Length)|null,altitude:Q(m,Length)|null}`.

The state is not an enum object because it models the SDK sealed result, not an integer enum. `consent_required` MUST NOT be represented as no data. When `includeExerciseRoutes=false`, the entire `route` key is absent and the record hash is recomputed. Routes and free-text exercise notes are high-sensitivity data.

## 8. Nutrition fields

`name` is nullable text and `mealType` is an enum. Every nutrient below is present and nullable. Energy fields are `Q(kcal,Energy)`; all others are `Q(g,Mass)`:

`biotin`, `caffeine`, `calcium`, `energy`, `energyFromFat`, `chloride`, `cholesterol`, `chromium`, `copper`, `dietaryFiber`, `folate`, `folicAcid`, `iodine`, `iron`, `magnesium`, `manganese`, `molybdenum`, `monounsaturatedFat`, `niacin`, `pantothenicAcid`, `phosphorus`, `polyunsaturatedFat`, `potassium`, `protein`, `riboflavin`, `saturatedFat`, `selenium`, `sodium`, `sugar`, `thiamin`, `totalCarbohydrate`, `totalFat`, `transFat`, `unsaturatedFat`, `vitaminA`, `vitaminB12`, `vitaminB6`, `vitaminC`, `vitaminD`, `vitaminE`, `vitaminK`, `zinc`.

No missing nutrient is converted to zero. Canonical grams can produce small decimal values; consumers MUST retain the provided decimal/number pair.

## 9. Planned exercise nested fields

The object contains `hasExplicitTime:boolean`, `exerciseType:E`, nullable `completedExerciseSessionId`, `title`, and `notes`, plus provider-ordered `blocks[]`:

```text
block = { repetitions: integer, description: string|null, steps: [step...] }
step  = { exerciseType:E, exercisePhase:E, completionGoal:goal,
          performanceTargets:[target...], description:string|null }
```

Every goal/target has a lowercase discriminator `type` and only the listed variant members:

* goals: `distance` + `distance:Q(m,Length)`; `distance_and_duration` + distance and `duration:D`; `steps` + integer; `duration` + D; `repetitions` + integer; `total_calories` + `totalCalories:Q(kcal,Energy)`; `active_calories` + `activeCalories:Q(kcal,Energy)`; `manual_completion` with no extra member; or `unknown` with no extra member;
* targets: `power` + min/max `Q(W,Power)`; `speed` + min/max `Q(m/s,Velocity)`; `cadence` + min/max numbers; `heart_rate` + min/max numbers; `weight` + `mass:Q(kg,Mass)`; `rpe` + integer `rpe`; `amrap`; or `unknown`.

Unknown sealed subclasses in a newer SDK MUST result in a type `read_error`/mapper issue, not `toString`, reflection, or silent omission, until the pinned mapper is upgraded.

## 10. PHR/FHIR medical resource

Medical records have `startTime`, `endTime`, offsets, and metadata set to null. `fields` is:

```json
{
  "medicalResourceType": {"raw": 1, "label": "vaccines"},
  "medicalResourceId": {
    "dataSourceId": "exact",
    "fhirResourceType": {"raw": 1, "label": "immunization"},
    "fhirResourceId": "exact"
  },
  "dataSourceId": "exact",
  "fhirVersion": {"major": 4, "minor": 0, "patch": 1},
  "fhirResource": {
    "type": {"raw": 1, "label": "immunization"},
    "id": "exact",
    "fhirResourceJson": "{ exact provider string }",
    "checksumSha256": "64 lowercase hex"
  },
  "source": {
    "id": "exact",
    "packageName": "exact",
    "fhirBaseUri": "exact SDK URI string",
    "displayName": "exact",
    "fhirVersion": {"major": 4, "minor": 0, "patch": 1},
    "lastDataUpdateTime": {"epochSecond": 0, "nano": 0}
  }
}
```

`source` is null when the provider did not expose a matching data source. The resource is still exported, with a category-scoped `medical_source_missing` issue and `read_error` type report rather than failing other resources or categories. `lastDataUpdateTime` is nullable.

**Preserve exact FHIR string.** `fhirResourceJson` MUST equal the SDK-provided string character-for-character: no parsing, reserialization, whitespace normalization, key sorting, Unicode normalization, newline conversion, redaction, or numeric rewriting. Its checksum is over exact UTF-8 bytes. The containing snapshot’s canonical JSON escaping does not change the decoded string. The outer FHIR ID/type and JSON content MAY disagree; preserve both and emit an issue rather than “correcting” either. PHR resources are non-temporal and are not filtered to the requested range.

## 11. Completeness and limitations

Cloud page records preserve endpoint response bytes, including provider JSON whitespace, ordering, unknown fields, and native units. They do not claim each response is record-level: endpoints marked `serverAggregation=true` are provider summaries and remain labeled as such. Fitbit and Withings plans explicitly have no endpoint pagination; Oura and WHOOP use capped, cycle-detected next-token paging. WHOOP recovery pages are deterministic fan-out requests whose IDs are discovered only from captured cycle pages.


The v1 mapper is explicit and pinned. It preserves known SDK-exposed native fields, nested structures, metadata, nanoseconds, offsets, raw enum integers, and exact FHIR strings. It does not preserve a source unit unavailable after SDK conversion, unknown fields introduced after the pinned SDK, provider database bytes, deleted records, transaction revisions, or implicit semantics not exposed by Health Connect. The header MUST declare `preservesSourceUnits=false` and `preservesUnknownSdkFields=false` for this implementation.

`fields` permits additive members so a pinned-SDK audit can add newly exposed fields without making old consumers reject records. This permission is not a license to rename/remove fields, change canonical units, alter null semantics, or replace raw values with labels. Such changes require a new schema version.
