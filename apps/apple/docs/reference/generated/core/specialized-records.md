# Specialized canonical records

Every object below is serialized by `HealthKitRecordArchiveSerializer` from a deterministic fixture that represents a production adapter domain.

## Workout and route

### Canonical object 1

```json
{"device":{"firmware_version":"2.0","hardware_version":"1.0","local_identifier":"fixture-local-device","manufacturer":"Example Manufacturer","model":"Synthetic Model","name":"Fixture Watch","software_version":"26.0.1","udi_device_identifier":"fixture-udi-device"},"end_date":"2026-03-15T00:07:10.750000000Z","has_undetermined_duration":false,"included_because":"selected_metric","metadata":{"fixture_index":{"type":"signed_integer","value":4}},"metric_attribution":{"dependency_metric_ids":[],"direct_metric_ids":["workouts"]},"object_type_identifier":"HKWorkoutTypeIdentifier","original_uuid":"00000000-0000-0000-0000-000000000004","payload":{"fields":{"activity_type":{"type":"unsigned_integer","value":37},"duration_seconds":{"type":"floating_point","value":3600},"indoor":{"type":"bool","value":false}},"kind":"workout","type":"structured"},"record_kind":"workout","relationships":[],"selected_metric_ids":["workouts"],"source_revision":{"bundle_identifier":"com.example.fixture-health","name":"Fixture Health","operating_system_version":{"major_version":26,"minor_version":0,"patch_version":1},"product_type":"WatchFixture1,1","version":"6.0"},"start_date":"2026-03-15T00:06:40.125000000Z"}
```

### Canonical object 2

```json
{"device":{"firmware_version":"2.0","hardware_version":"1.0","local_identifier":"fixture-local-device","manufacturer":"Example Manufacturer","model":"Synthetic Model","name":"Fixture Watch","software_version":"26.0.1","udi_device_identifier":"fixture-udi-device"},"end_date":"2026-03-15T00:08:50.750000000Z","has_undetermined_duration":false,"included_because":"relationship_dependency","metadata":{"fixture_index":{"type":"signed_integer","value":5}},"metric_attribution":{"dependency_metric_ids":["workouts"],"direct_metric_ids":[]},"object_type_identifier":"HKWorkoutRouteTypeIdentifier","original_uuid":"00000000-0000-0000-0000-000000000005","payload":{"fields":{"locations":{"type":"array","value":[{"type":"dictionary","value":{"latitude":{"type":"floating_point","value":21.3069},"longitude":{"type":"floating_point","value":-157.8583},"timestamp":{"type":"date","value":"2026-03-15T00:08:20.000000000Z"}}}]}},"kind":"workoutRoute","type":"structured"},"record_kind":"workout_route","relationships":[],"selected_metric_ids":["workouts"],"source_revision":{"bundle_identifier":"com.example.fixture-health","name":"Fixture Health","operating_system_version":{"major_version":26,"minor_version":0,"patch_version":1},"product_type":"WatchFixture1,1","version":"6.0"},"start_date":"2026-03-15T00:08:20.125000000Z"}
```

### Observed structured field paths and types

| JSON path | Observed type or types |
|---|---|
| `$[]["payload"]` | object |
| `$[]["payload"]["fields"]` | object |
| `$[]["payload"]["fields"]["activity_type"]` | object |
| `$[]["payload"]["fields"]["activity_type"]["type"]` | string |
| `$[]["payload"]["fields"]["activity_type"]["value"]` | number |
| `$[]["payload"]["fields"]["duration_seconds"]` | object |
| `$[]["payload"]["fields"]["duration_seconds"]["type"]` | string |
| `$[]["payload"]["fields"]["duration_seconds"]["value"]` | number |
| `$[]["payload"]["fields"]["indoor"]` | object |
| `$[]["payload"]["fields"]["indoor"]["type"]` | string |
| `$[]["payload"]["fields"]["indoor"]["value"]` | boolean |
| `$[]["payload"]["fields"]["locations"]` | object |
| `$[]["payload"]["fields"]["locations"]["type"]` | string |
| `$[]["payload"]["fields"]["locations"]["value"]` | array |
| `$[]["payload"]["fields"]["locations"]["value"][]` | object |
| `$[]["payload"]["fields"]["locations"]["value"][]["type"]` | string |
| `$[]["payload"]["fields"]["locations"]["value"][]["value"]` | object |
| `$[]["payload"]["fields"]["locations"]["value"][]["value"]["latitude"]` | object |
| `$[]["payload"]["fields"]["locations"]["value"][]["value"]["latitude"]["type"]` | string |
| `$[]["payload"]["fields"]["locations"]["value"][]["value"]["latitude"]["value"]` | number |
| `$[]["payload"]["fields"]["locations"]["value"][]["value"]["longitude"]` | object |
| `$[]["payload"]["fields"]["locations"]["value"][]["value"]["longitude"]["type"]` | string |
| `$[]["payload"]["fields"]["locations"]["value"][]["value"]["longitude"]["value"]` | number |
| `$[]["payload"]["fields"]["locations"]["value"][]["value"]["timestamp"]` | object |
| `$[]["payload"]["fields"]["locations"]["value"][]["value"]["timestamp"]["type"]` | string |
| `$[]["payload"]["fields"]["locations"]["value"][]["value"]["timestamp"]["value"]` | string |
| `$[]["payload"]["kind"]` | string |
| `$[]["payload"]["type"]` | string |

## ECG

### Canonical object 1

```json
{"device":{"firmware_version":"2.0","hardware_version":"1.0","local_identifier":"fixture-local-device","manufacturer":"Example Manufacturer","model":"Synthetic Model","name":"Fixture Watch","software_version":"26.0.1","udi_device_identifier":"fixture-udi-device"},"end_date":"2026-03-15T00:20:30.750000000Z","has_undetermined_duration":false,"included_because":"selected_metric","metadata":{"fixture_index":{"type":"signed_integer","value":12}},"metric_attribution":{"dependency_metric_ids":[],"direct_metric_ids":["electrocardiograms"]},"object_type_identifier":"HKDataTypeIdentifierElectrocardiogram","original_uuid":"00000000-0000-0000-0000-000000000012","payload":{"fields":{"average_heart_rate":{"type":"floating_point","value":72},"classification":{"type":"string","value":"sinus_rhythm"},"voltage_measurements":{"type":"array","value":[{"type":"floating_point","value":0.12},{"type":"floating_point","value":0.18}]}},"kind":"electrocardiogram","type":"structured"},"record_kind":"electrocardiogram","relationships":[],"selected_metric_ids":["electrocardiograms"],"source_revision":{"bundle_identifier":"com.example.fixture-health","name":"Fixture Health","operating_system_version":{"major_version":26,"minor_version":0,"patch_version":1},"product_type":"WatchFixture1,1","version":"6.0"},"start_date":"2026-03-15T00:20:00.125000000Z"}
```

### Observed structured field paths and types

| JSON path | Observed type or types |
|---|---|
| `$[]["payload"]` | object |
| `$[]["payload"]["fields"]` | object |
| `$[]["payload"]["fields"]["average_heart_rate"]` | object |
| `$[]["payload"]["fields"]["average_heart_rate"]["type"]` | string |
| `$[]["payload"]["fields"]["average_heart_rate"]["value"]` | number |
| `$[]["payload"]["fields"]["classification"]` | object |
| `$[]["payload"]["fields"]["classification"]["type"]` | string |
| `$[]["payload"]["fields"]["classification"]["value"]` | string |
| `$[]["payload"]["fields"]["voltage_measurements"]` | object |
| `$[]["payload"]["fields"]["voltage_measurements"]["type"]` | string |
| `$[]["payload"]["fields"]["voltage_measurements"]["value"]` | array |
| `$[]["payload"]["fields"]["voltage_measurements"]["value"][]` | object |
| `$[]["payload"]["fields"]["voltage_measurements"]["value"][]["type"]` | string |
| `$[]["payload"]["fields"]["voltage_measurements"]["value"][]["value"]` | number |
| `$[]["payload"]["kind"]` | string |
| `$[]["payload"]["type"]` | string |

## Heartbeat series

### Canonical object 1

```json
{"device":{"firmware_version":"2.0","hardware_version":"1.0","local_identifier":"fixture-local-device","manufacturer":"Example Manufacturer","model":"Synthetic Model","name":"Fixture Watch","software_version":"26.0.1","udi_device_identifier":"fixture-udi-device"},"end_date":"2026-03-15T00:10:30.750000000Z","has_undetermined_duration":false,"included_because":"selected_metric","metadata":{"fixture_index":{"type":"signed_integer","value":6}},"metric_attribution":{"dependency_metric_ids":[],"direct_metric_ids":["heartbeat_series"]},"object_type_identifier":"HKDataTypeIdentifierHeartbeatSeries","original_uuid":"00000000-0000-0000-0000-000000000006","payload":{"fields":{"measurements":{"type":"array","value":[{"type":"dictionary","value":{"preceded_by_gap":{"type":"bool","value":false},"time_since_series_start":{"type":"floating_point","value":0.42}}}]}},"kind":"heartbeatSeries","type":"structured"},"record_kind":"heartbeat_series","relationships":[],"selected_metric_ids":["heartbeat_series"],"source_revision":{"bundle_identifier":"com.example.fixture-health","name":"Fixture Health","operating_system_version":{"major_version":26,"minor_version":0,"patch_version":1},"product_type":"WatchFixture1,1","version":"6.0"},"start_date":"2026-03-15T00:10:00.125000000Z"}
```

### Observed structured field paths and types

| JSON path | Observed type or types |
|---|---|
| `$[]["payload"]` | object |
| `$[]["payload"]["fields"]` | object |
| `$[]["payload"]["fields"]["measurements"]` | object |
| `$[]["payload"]["fields"]["measurements"]["type"]` | string |
| `$[]["payload"]["fields"]["measurements"]["value"]` | array |
| `$[]["payload"]["fields"]["measurements"]["value"][]` | object |
| `$[]["payload"]["fields"]["measurements"]["value"][]["type"]` | string |
| `$[]["payload"]["fields"]["measurements"]["value"][]["value"]` | object |
| `$[]["payload"]["fields"]["measurements"]["value"][]["value"]["preceded_by_gap"]` | object |
| `$[]["payload"]["fields"]["measurements"]["value"][]["value"]["preceded_by_gap"]["type"]` | string |
| `$[]["payload"]["fields"]["measurements"]["value"][]["value"]["preceded_by_gap"]["value"]` | boolean |
| `$[]["payload"]["fields"]["measurements"]["value"][]["value"]["time_since_series_start"]` | object |
| `$[]["payload"]["fields"]["measurements"]["value"][]["value"]["time_since_series_start"]["type"]` | string |
| `$[]["payload"]["fields"]["measurements"]["value"][]["value"]["time_since_series_start"]["value"]` | number |
| `$[]["payload"]["kind"]` | string |
| `$[]["payload"]["type"]` | string |

## Audiogram

### Canonical object 1

```json
{"device":{"firmware_version":"2.0","hardware_version":"1.0","local_identifier":"fixture-local-device","manufacturer":"Example Manufacturer","model":"Synthetic Model","name":"Fixture Watch","software_version":"26.0.1","udi_device_identifier":"fixture-udi-device"},"end_date":"2026-03-15T00:18:50.750000000Z","has_undetermined_duration":false,"included_because":"selected_metric","metadata":{"fixture_index":{"type":"signed_integer","value":11}},"metric_attribution":{"dependency_metric_ids":[],"direct_metric_ids":["audiograms"]},"object_type_identifier":"HKDataTypeIdentifierAudiogram","original_uuid":"00000000-0000-0000-0000-000000000011","payload":{"fields":{"sensitivity_points":{"type":"array","value":[{"type":"dictionary","value":{"frequency_hz":{"type":"floating_point","value":1000},"left_db_hl":{"type":"floating_point","value":10},"right_db_hl":{"type":"floating_point","value":12}}}]}},"kind":"audiogram","type":"structured"},"record_kind":"audiogram","relationships":[],"selected_metric_ids":["audiograms"],"source_revision":{"bundle_identifier":"com.example.fixture-health","name":"Fixture Health","operating_system_version":{"major_version":26,"minor_version":0,"patch_version":1},"product_type":"WatchFixture1,1","version":"6.0"},"start_date":"2026-03-15T00:18:20.125000000Z"}
```

### Observed structured field paths and types

| JSON path | Observed type or types |
|---|---|
| `$[]["payload"]` | object |
| `$[]["payload"]["fields"]` | object |
| `$[]["payload"]["fields"]["sensitivity_points"]` | object |
| `$[]["payload"]["fields"]["sensitivity_points"]["type"]` | string |
| `$[]["payload"]["fields"]["sensitivity_points"]["value"]` | array |
| `$[]["payload"]["fields"]["sensitivity_points"]["value"][]` | object |
| `$[]["payload"]["fields"]["sensitivity_points"]["value"][]["type"]` | string |
| `$[]["payload"]["fields"]["sensitivity_points"]["value"][]["value"]` | object |
| `$[]["payload"]["fields"]["sensitivity_points"]["value"][]["value"]["frequency_hz"]` | object |
| `$[]["payload"]["fields"]["sensitivity_points"]["value"][]["value"]["frequency_hz"]["type"]` | string |
| `$[]["payload"]["fields"]["sensitivity_points"]["value"][]["value"]["frequency_hz"]["value"]` | number |
| `$[]["payload"]["fields"]["sensitivity_points"]["value"][]["value"]["left_db_hl"]` | object |
| `$[]["payload"]["fields"]["sensitivity_points"]["value"][]["value"]["left_db_hl"]["type"]` | string |
| `$[]["payload"]["fields"]["sensitivity_points"]["value"][]["value"]["left_db_hl"]["value"]` | number |
| `$[]["payload"]["fields"]["sensitivity_points"]["value"][]["value"]["right_db_hl"]` | object |
| `$[]["payload"]["fields"]["sensitivity_points"]["value"][]["value"]["right_db_hl"]["type"]` | string |
| `$[]["payload"]["fields"]["sensitivity_points"]["value"][]["value"]["right_db_hl"]["value"]` | number |
| `$[]["payload"]["kind"]` | string |
| `$[]["payload"]["type"]` | string |

## GAD-7

### Canonical object 1

```json
{"device":{"firmware_version":"2.0","hardware_version":"1.0","local_identifier":"fixture-local-device","manufacturer":"Example Manufacturer","model":"Synthetic Model","name":"Fixture Watch","software_version":"26.0.1","udi_device_identifier":"fixture-udi-device"},"end_date":"2026-03-15T00:27:10.750000000Z","has_undetermined_duration":false,"included_because":"selected_metric","metadata":{"fixture_index":{"type":"signed_integer","value":16}},"metric_attribution":{"dependency_metric_ids":[],"direct_metric_ids":["gad7_assessments"]},"object_type_identifier":"HKScoredAssessmentTypeIdentifierGAD7","original_uuid":"00000000-0000-0000-0000-000000000016","payload":{"fields":{"answers":{"type":"array","value":[{"type":"signed_integer","value":0},{"type":"signed_integer","value":1},{"type":"signed_integer","value":0}]},"risk":{"type":"string","value":"minimal"},"score":{"type":"signed_integer","value":1}},"kind":"scoredAssessment","type":"structured"},"record_kind":"scored_assessment","relationships":[],"selected_metric_ids":["gad7_assessments"],"source_revision":{"bundle_identifier":"com.example.fixture-health","name":"Fixture Health","operating_system_version":{"major_version":26,"minor_version":0,"patch_version":1},"product_type":"WatchFixture1,1","version":"6.0"},"start_date":"2026-03-15T00:26:40.125000000Z"}
```

### Observed structured field paths and types

| JSON path | Observed type or types |
|---|---|
| `$[]["payload"]` | object |
| `$[]["payload"]["fields"]` | object |
| `$[]["payload"]["fields"]["answers"]` | object |
| `$[]["payload"]["fields"]["answers"]["type"]` | string |
| `$[]["payload"]["fields"]["answers"]["value"]` | array |
| `$[]["payload"]["fields"]["answers"]["value"][]` | object |
| `$[]["payload"]["fields"]["answers"]["value"][]["type"]` | string |
| `$[]["payload"]["fields"]["answers"]["value"][]["value"]` | number |
| `$[]["payload"]["fields"]["risk"]` | object |
| `$[]["payload"]["fields"]["risk"]["type"]` | string |
| `$[]["payload"]["fields"]["risk"]["value"]` | string |
| `$[]["payload"]["fields"]["score"]` | object |
| `$[]["payload"]["fields"]["score"]["type"]` | string |
| `$[]["payload"]["fields"]["score"]["value"]` | number |
| `$[]["payload"]["kind"]` | string |
| `$[]["payload"]["type"]` | string |

## PHQ-9

### Canonical object 1

```json
{"device":{"firmware_version":"2.0","hardware_version":"1.0","local_identifier":"fixture-local-device","manufacturer":"Example Manufacturer","model":"Synthetic Model","name":"Fixture Watch","software_version":"26.0.1","udi_device_identifier":"fixture-udi-device"},"end_date":"2026-03-15T00:33:50.750000000Z","has_undetermined_duration":false,"included_because":"selected_metric","metadata":{"fixture_index":{"type":"signed_integer","value":20}},"metric_attribution":{"dependency_metric_ids":[],"direct_metric_ids":["phq9_assessments"]},"object_type_identifier":"HKScoredAssessmentTypeIdentifierPHQ9","original_uuid":"00000000-0000-0000-0000-000000000020","payload":{"fields":{"answers":{"type":"array","value":[{"type":"signed_integer","value":1},{"type":"signed_integer","value":0},{"type":"signed_integer","value":2}]},"risk":{"type":"string","value":"minimal"},"score":{"type":"signed_integer","value":3}},"kind":"phq9_assessment","type":"structured"},"record_kind":"scored_assessment","relationships":[],"selected_metric_ids":["phq9_assessments"],"source_revision":{"bundle_identifier":"com.example.fixture-health","name":"Fixture Health","operating_system_version":{"major_version":26,"minor_version":0,"patch_version":1},"product_type":"WatchFixture1,1","version":"6.0"},"start_date":"2026-03-15T00:33:20.125000000Z"}
```

### Observed structured field paths and types

| JSON path | Observed type or types |
|---|---|
| `$[]["payload"]` | object |
| `$[]["payload"]["fields"]` | object |
| `$[]["payload"]["fields"]["answers"]` | object |
| `$[]["payload"]["fields"]["answers"]["type"]` | string |
| `$[]["payload"]["fields"]["answers"]["value"]` | array |
| `$[]["payload"]["fields"]["answers"]["value"][]` | object |
| `$[]["payload"]["fields"]["answers"]["value"][]["type"]` | string |
| `$[]["payload"]["fields"]["answers"]["value"][]["value"]` | number |
| `$[]["payload"]["fields"]["risk"]` | object |
| `$[]["payload"]["fields"]["risk"]["type"]` | string |
| `$[]["payload"]["fields"]["risk"]["value"]` | string |
| `$[]["payload"]["fields"]["score"]` | object |
| `$[]["payload"]["fields"]["score"]["type"]` | string |
| `$[]["payload"]["fields"]["score"]["value"]` | number |
| `$[]["payload"]["kind"]` | string |
| `$[]["payload"]["type"]` | string |

## State of Mind

### Canonical object 1

```json
{"device":{"firmware_version":"2.0","hardware_version":"1.0","local_identifier":"fixture-local-device","manufacturer":"Example Manufacturer","model":"Synthetic Model","name":"Fixture Watch","software_version":"26.0.1","udi_device_identifier":"fixture-udi-device"},"end_date":"2026-03-15T00:23:50.750000000Z","has_undetermined_duration":true,"included_because":"selected_metric","metadata":{"fixture_index":{"type":"signed_integer","value":14}},"metric_attribution":{"dependency_metric_ids":[],"direct_metric_ids":["state_of_mind_entries"]},"object_type_identifier":"HKDataTypeStateOfMind","original_uuid":"00000000-0000-0000-0000-000000000014","payload":{"fields":{"associations":{"type":"array","value":[{"type":"string","value":"work"}]},"kind":{"type":"string","value":"momentary_emotion"},"labels":{"type":"array","value":[{"type":"string","value":"calm"}]},"valence":{"type":"floating_point","value":0.4}},"kind":"stateOfMind","type":"structured"},"record_kind":"state_of_mind","relationships":[],"selected_metric_ids":["state_of_mind_entries"],"source_revision":{"bundle_identifier":"com.example.fixture-health","name":"Fixture Health","operating_system_version":{"major_version":26,"minor_version":0,"patch_version":1},"product_type":"WatchFixture1,1","version":"6.0"},"start_date":"2026-03-15T00:23:20.125000000Z"}
```

### Observed structured field paths and types

| JSON path | Observed type or types |
|---|---|
| `$[]["payload"]` | object |
| `$[]["payload"]["fields"]` | object |
| `$[]["payload"]["fields"]["associations"]` | object |
| `$[]["payload"]["fields"]["associations"]["type"]` | string |
| `$[]["payload"]["fields"]["associations"]["value"]` | array |
| `$[]["payload"]["fields"]["associations"]["value"][]` | object |
| `$[]["payload"]["fields"]["associations"]["value"][]["type"]` | string |
| `$[]["payload"]["fields"]["associations"]["value"][]["value"]` | string |
| `$[]["payload"]["fields"]["kind"]` | object |
| `$[]["payload"]["fields"]["kind"]["type"]` | string |
| `$[]["payload"]["fields"]["kind"]["value"]` | string |
| `$[]["payload"]["fields"]["labels"]` | object |
| `$[]["payload"]["fields"]["labels"]["type"]` | string |
| `$[]["payload"]["fields"]["labels"]["value"]` | array |
| `$[]["payload"]["fields"]["labels"]["value"][]` | object |
| `$[]["payload"]["fields"]["labels"]["value"][]["type"]` | string |
| `$[]["payload"]["fields"]["labels"]["value"][]["value"]` | string |
| `$[]["payload"]["fields"]["valence"]` | object |
| `$[]["payload"]["fields"]["valence"]["type"]` | string |
| `$[]["payload"]["fields"]["valence"]["value"]` | number |
| `$[]["payload"]["kind"]` | string |
| `$[]["payload"]["type"]` | string |

## Medication dose and inventory

### Canonical object 1

```json
{"device":{"firmware_version":"2.0","hardware_version":"1.0","local_identifier":"fixture-local-device","manufacturer":"Example Manufacturer","model":"Synthetic Model","name":"Fixture Watch","software_version":"26.0.1","udi_device_identifier":"fixture-udi-device"},"end_date":"2026-03-15T00:25:30.750000000Z","has_undetermined_duration":false,"included_because":"selected_metric","metadata":{"fixture_index":{"type":"signed_integer","value":15}},"metric_attribution":{"dependency_metric_ids":[],"direct_metric_ids":["medications"]},"object_type_identifier":"HKMedicationDoseEventTypeIdentifierMedicationDoseEvent","original_uuid":"00000000-0000-0000-0000-000000000015","payload":{"fields":{"dose_quantity":{"type":"floating_point","value":1},"log_status":{"type":"string","value":"taken"},"medication_identifier":{"type":"string","value":"rxnorm:617314"},"unit":{"type":"string","value":"tablet"}},"kind":"medicationDoseEvent","type":"structured"},"record_kind":"medication_dose_event","relationships":[],"selected_metric_ids":["medications"],"source_revision":{"bundle_identifier":"com.example.fixture-health","name":"Fixture Health","operating_system_version":{"major_version":26,"minor_version":0,"patch_version":1},"product_type":"WatchFixture1,1","version":"6.0"},"start_date":"2026-03-15T00:25:00.125000000Z"}
```

### Canonical object 2

```json
{"display_name":"Levothyroxine 50 mcg","external_identifier":"rxnorm:617314","fields":{"archived":{"type":"bool","value":false},"form":{"type":"string","value":"tablet"},"refills":{"type":"unsigned_integer","value":3}},"included_because":"selected_metric","object_type_identifier":"HKDataTypeUserAnnotatedMedicationConcept","selected_metric_ids":["medications"]}
```

### Observed structured field paths and types

| JSON path | Observed type or types |
|---|---|
| `$[]["fields"]` | object |
| `$[]["fields"]["archived"]` | object |
| `$[]["fields"]["archived"]["type"]` | string |
| `$[]["fields"]["archived"]["value"]` | boolean |
| `$[]["fields"]["form"]` | object |
| `$[]["fields"]["form"]["type"]` | string |
| `$[]["fields"]["form"]["value"]` | string |
| `$[]["fields"]["refills"]` | object |
| `$[]["fields"]["refills"]["type"]` | string |
| `$[]["fields"]["refills"]["value"]` | number |
| `$[]["payload"]` | object |
| `$[]["payload"]["fields"]` | object |
| `$[]["payload"]["fields"]["dose_quantity"]` | object |
| `$[]["payload"]["fields"]["dose_quantity"]["type"]` | string |
| `$[]["payload"]["fields"]["dose_quantity"]["value"]` | number |
| `$[]["payload"]["fields"]["log_status"]` | object |
| `$[]["payload"]["fields"]["log_status"]["type"]` | string |
| `$[]["payload"]["fields"]["log_status"]["value"]` | string |
| `$[]["payload"]["fields"]["medication_identifier"]` | object |
| `$[]["payload"]["fields"]["medication_identifier"]["type"]` | string |
| `$[]["payload"]["fields"]["medication_identifier"]["value"]` | string |
| `$[]["payload"]["fields"]["unit"]` | object |
| `$[]["payload"]["fields"]["unit"]["type"]` | string |
| `$[]["payload"]["fields"]["unit"]["value"]` | string |
| `$[]["payload"]["kind"]` | string |
| `$[]["payload"]["type"]` | string |

## Activity summary

### Canonical object 1

```json
{"external_identifier":"activity-summary:2026-03-15","external_identity_kind":"activity_summary_date_components","fields":{"active_energy":{"type":"floating_point","value":520},"date":{"type":"string","value":"2026-03-15"}},"included_because":"selected_metric","object_type_identifier":"HKActivitySummary","record_kind":"activity_summary","relationships":[],"selected_metric_ids":["activity_summary"]}
```

### Observed structured field paths and types

| JSON path | Observed type or types |
|---|---|
| `$[]["fields"]` | object |
| `$[]["fields"]["active_energy"]` | object |
| `$[]["fields"]["active_energy"]["type"]` | string |
| `$[]["fields"]["active_energy"]["value"]` | number |
| `$[]["fields"]["date"]` | object |
| `$[]["fields"]["date"]["type"]` | string |
| `$[]["fields"]["date"]["value"]` | string |

## Characteristic

### Canonical object 1

```json
{"external_identifier":"characteristic:biological-sex","external_identity_kind":"characteristic_singleton","fields":{"value":{"type":"string","value":"female"}},"included_because":"selected_metric","object_type_identifier":"HKCharacteristicTypeIdentifierBiologicalSex","record_kind":"characteristic","relationships":[],"selected_metric_ids":["biological_sex"]}
```

### Observed structured field paths and types

| JSON path | Observed type or types |
|---|---|
| `$[]["fields"]` | object |
| `$[]["fields"]["value"]` | object |
| `$[]["fields"]["value"]["type"]` | string |
| `$[]["fields"]["value"]["value"]` | string |

## Clinical and FHIR

### Canonical object 1

```json
{"device":{"firmware_version":"2.0","hardware_version":"1.0","local_identifier":"fixture-local-device","manufacturer":"Example Manufacturer","model":"Synthetic Model","name":"Fixture Watch","software_version":"26.0.1","udi_device_identifier":"fixture-udi-device"},"end_date":"2026-03-15T00:15:30.750000000Z","has_undetermined_duration":false,"included_because":"selected_metric","metadata":{"fixture_index":{"type":"signed_integer","value":9}},"metric_attribution":{"dependency_metric_ids":[],"direct_metric_ids":["clinical_lab_result_records"]},"object_type_identifier":"HKClinicalTypeIdentifierLabResultRecord","original_uuid":"00000000-0000-0000-0000-000000000009","payload":{"fields":{"fhir_resource":{"type":"data","value":"eyJyZXNvdXJjZVR5cGUiOiJPYnNlcnZhdGlvbiJ9"},"stable_content_identity":{"type":"string","value":"fhir:Observation:fixture-001"}},"kind":"clinical","type":"structured"},"record_kind":"clinical","relationships":[],"selected_metric_ids":["clinical_lab_result_records"],"source_revision":{"bundle_identifier":"com.example.fixture-health","name":"Fixture Health","operating_system_version":{"major_version":26,"minor_version":0,"patch_version":1},"product_type":"WatchFixture1,1","version":"6.0"},"start_date":"2026-03-15T00:15:00.125000000Z"}
```

### Observed structured field paths and types

| JSON path | Observed type or types |
|---|---|
| `$[]["payload"]` | object |
| `$[]["payload"]["fields"]` | object |
| `$[]["payload"]["fields"]["fhir_resource"]` | object |
| `$[]["payload"]["fields"]["fhir_resource"]["type"]` | string |
| `$[]["payload"]["fields"]["fhir_resource"]["value"]` | string |
| `$[]["payload"]["fields"]["stable_content_identity"]` | object |
| `$[]["payload"]["fields"]["stable_content_identity"]["type"]` | string |
| `$[]["payload"]["fields"]["stable_content_identity"]["value"]` | string |
| `$[]["payload"]["kind"]` | string |
| `$[]["payload"]["type"]` | string |

## CDA document

### Canonical object 1

```json
{"device":{"firmware_version":"2.0","hardware_version":"1.0","local_identifier":"fixture-local-device","manufacturer":"Example Manufacturer","model":"Synthetic Model","name":"Fixture Watch","software_version":"26.0.1","udi_device_identifier":"fixture-udi-device"},"end_date":"2026-03-15T00:28:50.750000000Z","has_undetermined_duration":false,"included_because":"selected_metric","metadata":{"fixture_index":{"type":"signed_integer","value":17}},"metric_attribution":{"dependency_metric_ids":[],"direct_metric_ids":["cda_documents"]},"object_type_identifier":"HKDocumentTypeIdentifierCDA","original_uuid":"00000000-0000-0000-0000-000000000017","payload":{"fields":{"author_name":{"type":"string","value":"Fixture Clinic"},"document_data":{"type":"data","value":"PENsaW5pY2FsRG9jdW1lbnQvPg=="},"title":{"type":"string","value":"Fixture CDA"}},"kind":"document","type":"structured"},"record_kind":"document","relationships":[],"selected_metric_ids":["cda_documents"],"source_revision":{"bundle_identifier":"com.example.fixture-health","name":"Fixture Health","operating_system_version":{"major_version":26,"minor_version":0,"patch_version":1},"product_type":"WatchFixture1,1","version":"6.0"},"start_date":"2026-03-15T00:28:20.125000000Z"}
```

### Observed structured field paths and types

| JSON path | Observed type or types |
|---|---|
| `$[]["payload"]` | object |
| `$[]["payload"]["fields"]` | object |
| `$[]["payload"]["fields"]["author_name"]` | object |
| `$[]["payload"]["fields"]["author_name"]["type"]` | string |
| `$[]["payload"]["fields"]["author_name"]["value"]` | string |
| `$[]["payload"]["fields"]["document_data"]` | object |
| `$[]["payload"]["fields"]["document_data"]["type"]` | string |
| `$[]["payload"]["fields"]["document_data"]["value"]` | string |
| `$[]["payload"]["fields"]["title"]` | object |
| `$[]["payload"]["fields"]["title"]["type"]` | string |
| `$[]["payload"]["fields"]["title"]["value"]` | string |
| `$[]["payload"]["kind"]` | string |
| `$[]["payload"]["type"]` | string |

## Verifiable clinical record

### Canonical object 1

```json
{"device":{"firmware_version":"2.0","hardware_version":"1.0","local_identifier":"fixture-local-device","manufacturer":"Example Manufacturer","model":"Synthetic Model","name":"Fixture Watch","software_version":"26.0.1","udi_device_identifier":"fixture-udi-device"},"end_date":"2026-03-15T00:17:10.750000000Z","has_undetermined_duration":false,"included_because":"selected_metric","metadata":{"fixture_index":{"type":"signed_integer","value":10}},"metric_attribution":{"dependency_metric_ids":[],"direct_metric_ids":["verifiable_clinical_records"]},"object_type_identifier":"HKVerifiableClinicalRecordTypeIdentifier","original_uuid":"00000000-0000-0000-0000-000000000010","payload":{"fields":{"issuer_identifier":{"type":"string","value":"https://issuer.example.invalid"},"record_data":{"type":"data","value":"Zml4dHVyZSB2ZXJpZmlhYmxlIHJlY29yZA=="}},"kind":"verifiableClinicalRecord","type":"structured"},"record_kind":"verifiable_clinical_record","relationships":[],"selected_metric_ids":["verifiable_clinical_records"],"source_revision":{"bundle_identifier":"com.example.fixture-health","name":"Fixture Health","operating_system_version":{"major_version":26,"minor_version":0,"patch_version":1},"product_type":"WatchFixture1,1","version":"6.0"},"start_date":"2026-03-15T00:16:40.125000000Z"}
```

### Observed structured field paths and types

| JSON path | Observed type or types |
|---|---|
| `$[]["payload"]` | object |
| `$[]["payload"]["fields"]` | object |
| `$[]["payload"]["fields"]["issuer_identifier"]` | object |
| `$[]["payload"]["fields"]["issuer_identifier"]["type"]` | string |
| `$[]["payload"]["fields"]["issuer_identifier"]["value"]` | string |
| `$[]["payload"]["fields"]["record_data"]` | object |
| `$[]["payload"]["fields"]["record_data"]["type"]` | string |
| `$[]["payload"]["fields"]["record_data"]["value"]` | string |
| `$[]["payload"]["kind"]` | string |
| `$[]["payload"]["type"]` | string |

## Vision prescription

### Canonical object 1

```json
{"device":{"firmware_version":"2.0","hardware_version":"1.0","local_identifier":"fixture-local-device","manufacturer":"Example Manufacturer","model":"Synthetic Model","name":"Fixture Watch","software_version":"26.0.1","udi_device_identifier":"fixture-udi-device"},"end_date":"2026-03-15T00:22:10.750000000Z","has_undetermined_duration":false,"included_because":"selected_metric","metadata":{"fixture_index":{"type":"signed_integer","value":13}},"metric_attribution":{"dependency_metric_ids":[],"direct_metric_ids":["vision_prescriptions"]},"object_type_identifier":"HKVisionPrescriptionTypeIdentifier","original_uuid":"00000000-0000-0000-0000-000000000013","payload":{"fields":{"expiration_date":{"type":"date","value":"2027-03-15T00:00:00.000000000Z"},"prescription_type":{"type":"string","value":"glasses"},"right_eye_sphere":{"type":"floating_point","value":-1.25}},"kind":"visionPrescription","type":"structured"},"record_kind":"vision_prescription","relationships":[],"selected_metric_ids":["vision_prescriptions"],"source_revision":{"bundle_identifier":"com.example.fixture-health","name":"Fixture Health","operating_system_version":{"major_version":26,"minor_version":0,"patch_version":1},"product_type":"WatchFixture1,1","version":"6.0"},"start_date":"2026-03-15T00:21:40.125000000Z"}
```

### Observed structured field paths and types

| JSON path | Observed type or types |
|---|---|
| `$[]["payload"]` | object |
| `$[]["payload"]["fields"]` | object |
| `$[]["payload"]["fields"]["expiration_date"]` | object |
| `$[]["payload"]["fields"]["expiration_date"]["type"]` | string |
| `$[]["payload"]["fields"]["expiration_date"]["value"]` | string |
| `$[]["payload"]["fields"]["prescription_type"]` | object |
| `$[]["payload"]["fields"]["prescription_type"]["type"]` | string |
| `$[]["payload"]["fields"]["prescription_type"]["value"]` | string |
| `$[]["payload"]["fields"]["right_eye_sphere"]` | object |
| `$[]["payload"]["fields"]["right_eye_sphere"]["type"]` | string |
| `$[]["payload"]["fields"]["right_eye_sphere"]["value"]` | number |
| `$[]["payload"]["kind"]` | string |
| `$[]["payload"]["type"]` | string |

## Attachment

### Canonical object 1

```json
{"external_identifier":"attachment:fixture-001","external_identity_kind":"attachment_identifier","fields":{"bytes_available":{"type":"bool","value":true},"data":{"type":"data","value":"AH//"},"filename":{"type":"string","value":"fixture-record.bin"},"sha256":{"type":"string","value":"ae4b3280e56e2faf83f414a6e3dabe9d5fbe18976544c05fed121accb85b53fc"}},"included_because":"selected_metric","metric_attribution":{"dependency_metric_ids":["workouts"],"direct_metric_ids":["heart_rate_avg"]},"object_type_identifier":"HKAttachment","record_kind":"attachment","relationships":[{"kind":"attachment_parent","role":"parent","target":{"type":"uuid","value":"00000000-0000-0000-0000-000000000001"}}],"selected_metric_ids":["heart_rate_avg","workouts"]}
```

### Observed structured field paths and types

| JSON path | Observed type or types |
|---|---|
| `$[]["fields"]` | object |
| `$[]["fields"]["bytes_available"]` | object |
| `$[]["fields"]["bytes_available"]["type"]` | string |
| `$[]["fields"]["bytes_available"]["value"]` | boolean |
| `$[]["fields"]["data"]` | object |
| `$[]["fields"]["data"]["type"]` | string |
| `$[]["fields"]["data"]["value"]` | string |
| `$[]["fields"]["filename"]` | object |
| `$[]["fields"]["filename"]["type"]` | string |
| `$[]["fields"]["filename"]["value"]` | string |
| `$[]["fields"]["sha256"]` | object |
| `$[]["fields"]["sha256"]["type"]` | string |
| `$[]["fields"]["sha256"]["value"]` | string |

## Scheduled WorkoutKit plan

### Canonical object 1

```json
{"external_identifier":"workoutkit:schedule-001","external_identity_kind":"workoutkit_schedule_identity","fields":{"representation":{"type":"data","value":"Zml4dHVyZSB3b3Jrb3V0IHBsYW4="}},"included_because":"selected_metric","object_type_identifier":"WorkoutKit.WorkoutPlan","record_kind":"scheduled_workout_plan","relationships":[],"selected_metric_ids":["scheduled_workout_plans"]}
```

### Observed structured field paths and types

| JSON path | Observed type or types |
|---|---|
| `$[]["fields"]` | object |
| `$[]["fields"]["representation"]` | object |
| `$[]["fields"]["representation"]["type"]` | string |
| `$[]["fields"]["representation"]["value"]` | string |
