//! Canonical successor API records. Local native documents are not conversion authority.

use std::collections::BTreeMap;

use serde_json::Value;

use crate::{
    registry::{MetricRegistryProfile, metric_registry_snapshot},
    render::{
        OrderedJsonEntry, OrderedJsonValue, RenderDay, RenderError, RenderSessionConfig,
        UnitSystem, format,
    },
    semantic::{SemanticResult, SemanticValue, target_internal_unit},
};

pub(super) fn render(
    config: &RenderSessionConfig,
    day: &RenderDay,
    semantic: &SemanticResult,
) -> Result<Vec<u8>, RenderError> {
    let canonical_day = canonical_day(config, day, semantic)?;
    if let Some(root) = &day.profile_documents.json_root {
        return native_record(config, &canonical_day, root);
    }
    let mut canonical = config.clone();
    canonical.unit_system = UnitSystem::Metric;
    let mut entries = format::public_json_entries(&canonical, &canonical_day, config.profile)?;
    if !config.profile.is_apple() {
        entries.retain(|(key, _)| key != "units");
        entries.push((
            "units".to_owned(),
            Value::Object(
                canonical_units(config, &canonical_day)
                    .into_iter()
                    .map(|(key, value)| (key, Value::String(value)))
                    .collect(),
            ),
        ));
    }
    if config.profile.is_apple() {
        format::foundation_compact_json(&entries)
    } else {
        format::kotlin_pretty_json(&entries)
    }
}

fn canonical_day(
    config: &RenderSessionConfig,
    day: &RenderDay,
    semantic: &SemanticResult,
) -> Result<RenderDay, RenderError> {
    let registry = metric_registry_snapshot(
        if config.profile.is_apple() {
            MetricRegistryProfile::AppleHealthDataV10
        } else {
            MetricRegistryProfile::AndroidSleepV6
        },
        config.registry_version,
    )
    .map_err(|_| RenderError::InvalidConfig)?;
    let accepted = semantic
        .days
        .iter()
        .find(|value| value.owner_date == day.owner_date)
        .ok_or(RenderError::InvalidSemanticResult)?;
    let mut canonical = day.clone();
    for metric in &mut canonical.metrics {
        let output = registry
            .outputs
            .iter()
            .find(|output| output.key == metric.output_key)
            .ok_or(RenderError::InvalidSemanticResult)?;
        let value = accepted
            .values
            .iter()
            .find(|value| value.output_key == metric.output_key)
            .ok_or(RenderError::InvalidSemanticResult)?;
        let unit = if output.unit.is_empty() {
            let units = registry
                .metrics
                .iter()
                .filter(|selection| output.selection_ids.contains(&selection.selection_id))
                .map(|selection| selection.unit.as_str())
                .collect::<std::collections::BTreeSet<_>>();
            if units.len() != 1 {
                return Err(RenderError::InvalidSemanticResult);
            }
            units
                .first()
                .copied()
                .ok_or(RenderError::InvalidSemanticResult)?
                .to_owned()
        } else {
            output.unit.clone()
        };
        // The bound public number is already canonical. A pretty/native display unit is not.
        // Use exact profile units only where the semantic unit proves their equivalence.
        if let SemanticValue::Number {
            unit: canonical_unit,
            ..
        } = &value.value
        {
            if target_internal_unit(&unit) != Some(canonical_unit.id.as_str()) {
                return Err(RenderError::InvalidSemanticResult);
            }
        }
        metric.unit = unit;
    }
    Ok(canonical)
}

fn canonical_units(config: &RenderSessionConfig, day: &RenderDay) -> BTreeMap<String, String> {
    format::sorted_metrics(day)
        .into_iter()
        .filter(|metric| !metric.unit.is_empty())
        .map(|metric| {
            (
                if config.profile.is_apple() {
                    metric.frontmatter_key.clone()
                } else {
                    metric.output_key.clone()
                },
                metric.unit.clone(),
            )
        })
        .collect()
}

fn native_record(
    config: &RenderSessionConfig,
    day: &RenderDay,
    root: &OrderedJsonValue,
) -> Result<Vec<u8>, RenderError> {
    let value: Value = serde_json::from_slice(&format::kotlin_ordered_json(root)?)
        .map_err(|_| RenderError::PresentationMismatch)?;
    super::validate_document_identity(config, &value)?;
    // No local -> UTC relabeling, imperial -> metric metadata swap, or owner-date reinterpretation.
    // Native producers must supply a prepared canonical document while retaining exact instants.
    if value["time_context"]["timestamp_timezone"] != "UTC"
        || value["unit_system"] != "metric"
        || value["date"] != day.owner_date
    {
        return Err(RenderError::PresentationMismatch);
    }
    for metric in &day.metrics {
        let mut presented = &value;
        for key in &metric.json_path {
            presented = presented
                .get(key)
                .ok_or(RenderError::PresentationMismatch)?;
        }
        if presented != &metric.public_value {
            return Err(RenderError::PresentationMismatch);
        }
    }
    let units = native_units(config, day, &value)?;
    let OrderedJsonValue::Object { entries } = root else {
        return Err(RenderError::PresentationMismatch);
    };
    let mut entries = entries.clone();
    let units = OrderedJsonValue::Object {
        entries: units
            .into_iter()
            .map(|(key, value)| OrderedJsonEntry {
                key,
                value: OrderedJsonValue::String { value },
            })
            .collect(),
    };
    if let Some(entry) = entries.iter_mut().find(|entry| entry.key == "units") {
        entry.value = units;
    } else {
        entries.push(OrderedJsonEntry {
            key: "units".to_owned(),
            value: units,
        });
    }
    let root = OrderedJsonValue::Object { entries };
    if config.profile.is_apple() {
        format::foundation_ordered_json(&root)
    } else {
        format::kotlin_ordered_json(&root)
    }
}

fn native_units(
    config: &RenderSessionConfig,
    day: &RenderDay,
    root: &Value,
) -> Result<BTreeMap<String, String>, RenderError> {
    let mut units = match root.get("units") {
        Some(Value::Object(units)) => units
            .iter()
            .map(|(key, value)| {
                Ok((
                    key.clone(),
                    value
                        .as_str()
                        .ok_or(RenderError::PresentationMismatch)?
                        .to_owned(),
                ))
            })
            .collect::<Result<BTreeMap<_, _>, RenderError>>()?,
        None => BTreeMap::new(),
        Some(Value::String(value)) if value == "metric" => BTreeMap::new(),
        _ => return Err(RenderError::PresentationMismatch),
    };
    for metric in &day.metrics {
        for alias in [&metric.output_key, &metric.frontmatter_key] {
            if let Some(unit) = units.get(alias) {
                if unit != &metric.unit
                    && target_internal_unit(&metric.unit)
                        .is_none_or(|expected| target_internal_unit(unit) != Some(expected))
                {
                    return Err(RenderError::PresentationMismatch);
                }
            }
        }
    }
    // Keep units for native-only payloads; only replace attested projection entries.
    units.extend(canonical_units(config, day));
    Ok(units)
}
