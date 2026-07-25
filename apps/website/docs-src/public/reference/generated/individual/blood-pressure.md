---
date: 2026-07-14
time: "09:18"
datetime: 2026-07-14T09:18:33.500000000Z
type: vitals
metric: blood_pressure
value: "122.50/78.25"
unit: mmHg
source: "Health.md Documentation Fixture"
canonical_record_json: "{\"device\":{\"firmware_version\":\"1.0\",\"hardware_version\":\"1\",\"local_identifier\":\"fixture-device\",\"manufacturer\":\"Health.md\",\"model\":\"Documentation Model\",\"name\":\"Synthetic Fixture Device\",\"software_version\":\"1.0\",\"udi_device_identifier\":\"fixture-udi\"},\"end_date\":\"2026-07-14T09:18:36.000000000Z\",\"has_undetermined_duration\":false,\"included_because\":\"selected_metric\",\"metadata\":{\"fixture\":{\"type\":\"bool\",\"value\":true},\"fixturePurpose\":{\"type\":\"string\",\"value\":\"Deterministic Individual Entry Tracking documentation\"}},\"metric_attribution\":{\"dependency_metric_ids\":[],\"direct_metric_ids\":[\"blood_pressure_diastolic\",\"blood_pressure_systolic\"]},\"object_type_identifier\":\"HKCorrelationTypeIdentifierBloodPressure\",\"original_uuid\":\"71000000-0000-0000-0000-000000000004\",\"payload\":{\"component_uuids\":[\"71000000-0000-0000-0000-000000000005\",\"71000000-0000-0000-0000-000000000006\"],\"type\":\"correlation\"},\"record_kind\":\"correlation\",\"relationships\":[{\"kind\":\"component\",\"role\":\"diastolic\",\"target\":{\"type\":\"uuid\",\"value\":\"71000000-0000-0000-0000-000000000006\"}},{\"kind\":\"component\",\"role\":\"systolic\",\"target\":{\"type\":\"uuid\",\"value\":\"71000000-0000-0000-0000-000000000005\"}}],\"selected_metric_ids\":[\"blood_pressure_diastolic\",\"blood_pressure_systolic\"],\"source_revision\":{\"bundle_identifier\":\"tech.isolated.healthmd.documentation-fixture\",\"name\":\"Health.md Documentation Fixture\",\"operating_system_version\":{\"major_version\":1,\"minor_version\":0,\"patch_version\":0},\"product_type\":\"FixtureDevice1,1\",\"version\":\"1.0.0\"},\"start_date\":\"2026-07-14T09:18:33.500000000Z\"}"
component_uuids:
  - 71000000-0000-0000-0000-000000000005
  - 71000000-0000-0000-0000-000000000006
device_json: "{\"firmware_version\":\"1.0\",\"hardware_version\":\"1\",\"local_identifier\":\"fixture-device\",\"manufacturer\":\"Health.md\",\"model\":\"Documentation Model\",\"name\":\"Synthetic Fixture Device\",\"software_version\":\"1.0\",\"udi_device_identifier\":\"fixture-udi\"}"
diastolic: 78.25
end_datetime: "2026-07-14T09:18:36.000000000Z"
entry_kind: healthkit_record
has_undetermined_duration: false
included_because: selected_metric
metadata_json: "{\"fixture\":{\"type\":\"bool\",\"value\":true},\"fixturePurpose\":{\"type\":\"string\",\"value\":\"Deterministic Individual Entry Tracking documentation\"}}"
metric_attribution_json: "{\"dependency_metric_ids\":[],\"direct_metric_ids\":[\"blood_pressure_diastolic\",\"blood_pressure_systolic\"]}"
object_type_identifier: HKCorrelationTypeIdentifierBloodPressure
original_uuid: 71000000-0000-0000-0000-000000000004
payload_json: "{\"component_uuids\":[\"71000000-0000-0000-0000-000000000005\",\"71000000-0000-0000-0000-000000000006\"],\"type\":\"correlation\"}"
raw_record_schema: healthmd.healthkit_records
raw_record_schema_version: 1
record_kind: correlation
relationships_json: "[{\"kind\":\"component\",\"role\":\"diastolic\",\"target\":{\"type\":\"uuid\",\"value\":\"71000000-0000-0000-0000-000000000006\"}},{\"kind\":\"component\",\"role\":\"systolic\",\"target\":{\"type\":\"uuid\",\"value\":\"71000000-0000-0000-0000-000000000005\"}}]"
selected_metric_ids:
  - blood_pressure_diastolic
  - blood_pressure_systolic
source_revision_json: "{\"bundle_identifier\":\"tech.isolated.healthmd.documentation-fixture\",\"name\":\"Health.md Documentation Fixture\",\"operating_system_version\":{\"major_version\":1,\"minor_version\":0,\"patch_version\":0},\"product_type\":\"FixtureDevice1,1\",\"version\":\"1.0.0\"}"
start_datetime: "2026-07-14T09:18:33.500000000Z"
systolic: 122.50
---
