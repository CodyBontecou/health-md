---
date: 2026-07-14
time: "09:19"
datetime: 2026-07-14T09:19:34.625000000Z
type: medications
metric: medications
value: 1.5
unit: tablet
source: "Health.md Documentation Fixture"
canonical_record_json: "{\"device\":{\"firmware_version\":\"1.0\",\"hardware_version\":\"1\",\"local_identifier\":\"fixture-device\",\"manufacturer\":\"Health.md\",\"model\":\"Documentation Model\",\"name\":\"Synthetic Fixture Device\",\"software_version\":\"1.0\",\"udi_device_identifier\":\"fixture-udi\"},\"end_date\":\"2026-07-14T09:20:19.625000000Z\",\"has_undetermined_duration\":false,\"included_because\":\"selected_metric\",\"metadata\":{\"fixture\":{\"type\":\"bool\",\"value\":true},\"fixturePurpose\":{\"type\":\"string\",\"value\":\"Deterministic Individual Entry Tracking documentation\"}},\"metric_attribution\":{\"dependency_metric_ids\":[],\"direct_metric_ids\":[\"medications\"]},\"object_type_identifier\":\"HKMedicationDoseEventTypeIdentifierMedicationDoseEvent\",\"original_uuid\":\"71000000-0000-0000-0000-000000000007\",\"payload\":{\"fields\":{\"doseQuantity\":{\"type\":\"floating_point\",\"value\":1.5},\"logStatus\":{\"type\":\"dictionary\",\"value\":{\"rawValue\":{\"type\":\"signed_integer\",\"value\":1},\"symbolicValue\":{\"type\":\"string\",\"value\":\"taken\"}}},\"medicationConceptIdentifier\":{\"type\":\"string\",\"value\":\"fixture-medication-concept\"},\"medicationName\":{\"type\":\"string\",\"value\":\"Synthetic Fixture Medication\"},\"scheduleType\":{\"type\":\"dictionary\",\"value\":{\"rawValue\":{\"type\":\"signed_integer\",\"value\":2},\"symbolicValue\":{\"type\":\"string\",\"value\":\"scheduled\"}}},\"scheduledDate\":{\"type\":\"date\",\"value\":\"2026-07-14T09:14:34.625000000Z\"},\"scheduledDoseQuantity\":{\"type\":\"floating_point\",\"value\":2},\"unit\":{\"type\":\"string\",\"value\":\"tablet\"}},\"kind\":\"medicationDoseEvent\",\"type\":\"structured\"},\"record_kind\":\"medication_dose_event\",\"relationships\":[],\"selected_metric_ids\":[\"medications\"],\"source_revision\":{\"bundle_identifier\":\"tech.isolated.healthmd.documentation-fixture\",\"name\":\"Health.md Documentation Fixture\",\"operating_system_version\":{\"major_version\":1,\"minor_version\":0,\"patch_version\":0},\"product_type\":\"FixtureDevice1,1\",\"version\":\"1.0.0\"},\"start_date\":\"2026-07-14T09:19:34.625000000Z\"}"
device_json: "{\"firmware_version\":\"1.0\",\"hardware_version\":\"1\",\"local_identifier\":\"fixture-device\",\"manufacturer\":\"Health.md\",\"model\":\"Documentation Model\",\"name\":\"Synthetic Fixture Device\",\"software_version\":\"1.0\",\"udi_device_identifier\":\"fixture-udi\"}"
dose_quantity: 1.50
dose_unit: tablet
end_datetime: "2026-07-14T09:20:19.625000000Z"
entry_kind: healthkit_record
event_id: 71000000-0000-0000-0000-000000000007
has_undetermined_duration: false
included_because: selected_metric
medication: Synthetic Fixture Medication
medication_concept_identifier: fixture-medication-concept
medication_name: Synthetic Fixture Medication
metadata_json: "{\"fixture\":{\"type\":\"bool\",\"value\":true},\"fixturePurpose\":{\"type\":\"string\",\"value\":\"Deterministic Individual Entry Tracking documentation\"}}"
metric_attribution_json: "{\"dependency_metric_ids\":[],\"direct_metric_ids\":[\"medications\"]}"
object_type_identifier: HKMedicationDoseEventTypeIdentifierMedicationDoseEvent
original_uuid: 71000000-0000-0000-0000-000000000007
payload_json: "{\"fields\":{\"doseQuantity\":{\"type\":\"floating_point\",\"value\":1.5},\"logStatus\":{\"type\":\"dictionary\",\"value\":{\"rawValue\":{\"type\":\"signed_integer\",\"value\":1},\"symbolicValue\":{\"type\":\"string\",\"value\":\"taken\"}}},\"medicationConceptIdentifier\":{\"type\":\"string\",\"value\":\"fixture-medication-concept\"},\"medicationName\":{\"type\":\"string\",\"value\":\"Synthetic Fixture Medication\"},\"scheduledDate\":{\"type\":\"date\",\"value\":\"2026-07-14T09:14:34.625000000Z\"},\"scheduledDoseQuantity\":{\"type\":\"floating_point\",\"value\":2},\"scheduleType\":{\"type\":\"dictionary\",\"value\":{\"rawValue\":{\"type\":\"signed_integer\",\"value\":2},\"symbolicValue\":{\"type\":\"string\",\"value\":\"scheduled\"}}},\"unit\":{\"type\":\"string\",\"value\":\"tablet\"}},\"kind\":\"medicationDoseEvent\",\"type\":\"structured\"}"
raw_record_schema: healthmd.healthkit_records
raw_record_schema_version: 1
record_kind: medication_dose_event
relationships_json: "[]"
schedule_type: scheduled
scheduled_datetime: "2026-07-14T09:14:34.625000000Z"
scheduled_dose_quantity: 2
selected_metric_ids:
  - medications
source_revision_json: "{\"bundle_identifier\":\"tech.isolated.healthmd.documentation-fixture\",\"name\":\"Health.md Documentation Fixture\",\"operating_system_version\":{\"major_version\":1,\"minor_version\":0,\"patch_version\":0},\"product_type\":\"FixtureDevice1,1\",\"version\":\"1.0.0\"}"
start_datetime: "2026-07-14T09:19:34.625000000Z"
status: taken
status_display: taken
---
