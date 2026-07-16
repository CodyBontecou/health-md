# Generated frontmatter field and type inventory

This inventory is derived from the complete generated frontmatter, including nested workout objects and arrays. Types describe the YAML representation emitted by `IndividualEntryExporter.previewEntryContent` for fixed synthetic fixtures.

| Field path | Observed YAML type | Generated documents |
|---|---|---|
| `activity_type` | `string` | `workout.md` |
| `aggregation` | `string` | `legacy-aggregate`, `summary-only` |
| `ascent_m` | `integer` | `workout.md` |
| `associations` | `array<string>` | `state-of-mind.md` |
| `cadence_avg_rpm` | `integer` | `workout.md` |
| `calories` | `integer` | `workout.md` |
| `canonical_metric_id` | `string` | `category.md`, `quantity.md` |
| `canonical_record_json` | `string` | `blood-pressure.md`, `category.md`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `workout.md` |
| `category_raw_value` | `integer` | `category.md` |
| `category_symbolic_value` | `string` | `category.md` |
| `component_uuids` | `array<string>` | `blood-pressure.md` |
| `date` | `date` | `blood-pressure.md`, `category.md`, `legacy-aggregate`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `summary-only`, `workout.md` |
| `datetime` | `timestamp` | `blood-pressure.md`, `category.md`, `legacy-aggregate`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `summary-only`, `workout.md` |
| `descent_m` | `integer` | `workout.md` |
| `device_json` | `string` | `blood-pressure.md`, `category.md`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `workout.md` |
| `diastolic` | `number` | `blood-pressure.md` |
| `distance_km` | `number` | `workout.md` |
| `distance_m` | `integer` | `workout.md` |
| `distance_mi` | `number` | `workout.md` |
| `dose_quantity` | `number` | `medication-dose.md` |
| `dose_unit` | `string` | `medication-dose.md` |
| `duration` | `string` | `workout.md` |
| `duration_sec` | `integer` | `workout.md` |
| `end_datetime` | `string` | `blood-pressure.md`, `category.md`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `workout.md` |
| `entry_kind` | `string` | `blood-pressure.md`, `category.md`, `legacy-aggregate`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `summary-only`, `workout.md` |
| `event_id` | `string` | `medication-dose.md` |
| `feeling` | `string` | `state-of-mind.md` |
| `has_undetermined_duration` | `boolean` | `blood-pressure.md`, `category.md`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `workout.md` |
| `healthkit_activity_type` | `string` | `workout.md` |
| `healthkit_activity_type_raw_value` | `integer` | `workout.md` |
| `heart_rate_zones` | `object` | `workout.md` |
| `heart_rate_zones.zone1` | `object` | `workout.md` |
| `heart_rate_zones.zone1.duration` | `null` | `workout.md` |
| `heart_rate_zones.zone1.label` | `string` | `workout.md` |
| `heart_rate_zones.zone1.range` | `string` | `workout.md` |
| `heart_rate_zones.zone1.seconds` | `integer` | `workout.md` |
| `heart_rate_zones.zone2` | `object` | `workout.md` |
| `heart_rate_zones.zone2.duration` | `string` | `workout.md` |
| `heart_rate_zones.zone2.label` | `string` | `workout.md` |
| `heart_rate_zones.zone2.range` | `string` | `workout.md` |
| `heart_rate_zones.zone2.seconds` | `integer` | `workout.md` |
| `heart_rate_zones.zone3` | `object` | `workout.md` |
| `heart_rate_zones.zone3.duration` | `string` | `workout.md` |
| `heart_rate_zones.zone3.label` | `string` | `workout.md` |
| `heart_rate_zones.zone3.range` | `string` | `workout.md` |
| `heart_rate_zones.zone3.seconds` | `integer` | `workout.md` |
| `heart_rate_zones.zone4` | `object` | `workout.md` |
| `heart_rate_zones.zone4.duration` | `string` | `workout.md` |
| `heart_rate_zones.zone4.label` | `string` | `workout.md` |
| `heart_rate_zones.zone4.range` | `string` | `workout.md` |
| `heart_rate_zones.zone4.seconds` | `integer` | `workout.md` |
| `heart_rate_zones.zone5` | `object` | `workout.md` |
| `heart_rate_zones.zone5.duration` | `string` | `workout.md` |
| `heart_rate_zones.zone5.label` | `string` | `workout.md` |
| `heart_rate_zones.zone5.range` | `string` | `workout.md` |
| `heart_rate_zones.zone5.seconds` | `integer` | `workout.md` |
| `hr_avg` | `integer` | `workout.md` |
| `hr_max` | `integer` | `workout.md` |
| `hr_min` | `integer` | `workout.md` |
| `included_because` | `string` | `blood-pressure.md`, `category.md`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `workout.md` |
| `is_indoor` | `boolean` | `workout.md` |
| `labels` | `array<string>` | `state-of-mind.md` |
| `laps` | `array<object>` | `workout.md` |
| `laps[]` | `object` | `workout.md` |
| `laps[].cadence_avg_rpm` | `integer` | `workout.md` |
| `laps[].distance_km` | `number` | `workout.md` |
| `laps[].distance_m` | `integer` | `workout.md` |
| `laps[].distance_mi` | `number` | `workout.md` |
| `laps[].duration` | `string` | `workout.md` |
| `laps[].end` | `timestamp` | `workout.md` |
| `laps[].hr_avg` | `integer` | `workout.md` |
| `laps[].hr_max` | `integer` | `workout.md` |
| `laps[].lap` | `integer` | `workout.md` |
| `laps[].power_avg_w` | `integer` | `workout.md` |
| `laps[].rate` | `string` | `workout.md` |
| `laps[].rate_label` | `string` | `workout.md` |
| `laps[].speed_kmh` | `number` | `workout.md` |
| `laps[].speed_kmh_formatted` | `string` | `workout.md` |
| `laps[].speed_mph` | `number` | `workout.md` |
| `laps[].speed_mph_formatted` | `string` | `workout.md` |
| `laps[].start` | `timestamp` | `workout.md` |
| `laps[].time_sec` | `integer` | `workout.md` |
| `laps_count` | `integer` | `workout.md` |
| `location_type` | `string` | `workout.md` |
| `medication` | `string` | `medication-dose.md` |
| `medication_concept_identifier` | `string` | `medication-dose.md` |
| `medication_name` | `string` | `medication-dose.md` |
| `metadata_json` | `string` | `blood-pressure.md`, `category.md`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `workout.md` |
| `metric` | `string` | `blood-pressure.md`, `category.md`, `legacy-aggregate`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `summary-only`, `workout.md` |
| `metric_attribution_json` | `string` | `blood-pressure.md`, `category.md`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `workout.md` |
| `object_type_identifier` | `string` | `blood-pressure.md`, `category.md`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `workout.md` |
| `original_uuid` | `string` | `blood-pressure.md`, `category.md`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `workout.md` |
| `payload_json` | `string` | `blood-pressure.md`, `category.md`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `workout.md` |
| `power_avg_w` | `integer` | `workout.md` |
| `power_max_w` | `integer` | `workout.md` |
| `quantity_value` | `number` | `quantity.md` |
| `raw_record_schema` | `string` | `blood-pressure.md`, `category.md`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `workout.md` |
| `raw_record_schema_version` | `integer` | `blood-pressure.md`, `category.md`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `workout.md` |
| `record_kind` | `string` | `blood-pressure.md`, `category.md`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `workout.md` |
| `relationships_json` | `string` | `blood-pressure.md`, `category.md`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `workout.md` |
| `route_points` | `integer` | `workout.md` |
| `sample_counts` | `object` | `workout.md` |
| `sample_counts.altitude` | `integer` | `workout.md` |
| `sample_counts.cadence` | `integer` | `workout.md` |
| `sample_counts.ground_contact` | `integer` | `workout.md` |
| `sample_counts.heart_rate` | `integer` | `workout.md` |
| `sample_counts.power` | `integer` | `workout.md` |
| `sample_counts.speed` | `integer` | `workout.md` |
| `sample_counts.stride_length` | `integer` | `workout.md` |
| `sample_counts.vertical_oscillation` | `integer` | `workout.md` |
| `schedule_type` | `string` | `medication-dose.md` |
| `scheduled_datetime` | `string` | `medication-dose.md` |
| `scheduled_dose_quantity` | `integer` | `medication-dose.md` |
| `selected_metric_ids` | `array<string>` | `blood-pressure.md`, `category.md`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `workout.md` |
| `source` | `string` | `blood-pressure.md`, `category.md`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `workout.md` |
| `source_revision_json` | `string` | `blood-pressure.md`, `category.md`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `workout.md` |
| `speed_kmh` | `number` | `workout.md` |
| `speed_kmh_formatted` | `string` | `workout.md` |
| `speed_mph` | `number` | `workout.md` |
| `speed_mph_formatted` | `string` | `workout.md` |
| `splits` | `array<object>` | `workout.md` |
| `splits[]` | `object` | `workout.md` |
| `splits[].cadence_avg_rpm` | `integer` | `workout.md` |
| `splits[].distance_km` | `number` | `workout.md` |
| `splits[].distance_m` | `integer` | `workout.md` |
| `splits[].distance_mi` | `number` | `workout.md` |
| `splits[].duration` | `string` | `workout.md` |
| `splits[].end` | `timestamp` | `workout.md` |
| `splits[].hr_avg` | `integer` | `workout.md` |
| `splits[].hr_max` | `integer` | `workout.md` |
| `splits[].power_avg_w` | `integer` | `workout.md` |
| `splits[].rate` | `string` | `workout.md` |
| `splits[].rate_label` | `string` | `workout.md` |
| `splits[].speed_kmh` | `number` | `workout.md` |
| `splits[].speed_kmh_formatted` | `string` | `workout.md` |
| `splits[].speed_mph` | `number` | `workout.md` |
| `splits[].speed_mph_formatted` | `string` | `workout.md` |
| `splits[].split` | `integer` | `workout.md` |
| `splits[].start` | `timestamp` | `workout.md` |
| `splits[].time_sec` | `integer` | `workout.md` |
| `splits_count` | `integer` | `workout.md` |
| `sport` | `string` | `workout.md` |
| `start_datetime` | `string` | `blood-pressure.md`, `category.md`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `workout.md` |
| `state_of_mind_kind` | `string` | `state-of-mind.md` |
| `status` | `string` | `medication-dose.md` |
| `status_display` | `string` | `medication-dose.md` |
| `systolic` | `number` | `blood-pressure.md` |
| `tags` | `array<string>` | `workout.md` |
| `time` | `string` | `blood-pressure.md`, `category.md`, `legacy-aggregate`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `summary-only`, `workout.md` |
| `type` | `string` | `blood-pressure.md`, `category.md`, `legacy-aggregate`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `summary-only`, `workout.md` |
| `unit` | `string` | `blood-pressure.md`, `legacy-aggregate`, `medication-dose.md`, `quantity.md`, `summary-only` |
| `valence` | `number` | `state-of-mind.md` |
| `valence_classification` | `string` | `state-of-mind.md` |
| `value` | `number | string` | `blood-pressure.md`, `category.md`, `legacy-aggregate`, `medication-dose.md`, `quantity.md`, `state-of-mind.md`, `summary-only` |
