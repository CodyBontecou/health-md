//! Read successor public binary64 decimals with the standard correctly rounded parser.
//! Do not change `serde_json` features or the historical handoff parser/number semantics.

use super::super::{RenderBatch, RenderError};
use serde::Deserialize;
use serde_json::{Number, Value, value::RawValue};

#[derive(Deserialize)]
struct RawBatch<'a> {
    #[serde(borrow)]
    days: Vec<RawDay<'a>>,
}

#[derive(Deserialize)]
struct RawDay<'a> {
    #[serde(borrow)]
    metrics: Vec<RawMetric<'a>>,
}

#[derive(Deserialize)]
struct RawMetric<'a> {
    #[serde(borrow)]
    public_value: &'a RawValue,
}

/// The primary typed parser already enforces grammar, duplicate fields, and input bounds.
/// Re-read only decimal public numbers; ordinary `serde_json` parsing can lose one binary64 ULP.
/// Exact semantic binding is still required afterwards, without epsilon or value substitution.
pub(in crate::render) fn parse_exact_public_numbers(
    bytes: &[u8],
    batch: &mut RenderBatch,
) -> Result<(), RenderError> {
    let raw: RawBatch<'_> = serde_json::from_slice(bytes).map_err(|_| RenderError::InvalidBatch)?;
    for (day, raw_day) in batch.days.iter_mut().zip(raw.days) {
        for (metric, raw_metric) in day.metrics.iter_mut().zip(raw_day.metrics) {
            let decimal = raw_metric.public_value.get();
            if metric.public_value.is_number() && decimal.contains(['.', 'e', 'E']) {
                let value = decimal
                    .parse::<f64>()
                    .ok()
                    .and_then(Number::from_f64)
                    .ok_or(RenderError::InvalidBatch)?;
                metric.public_value = Value::Number(value);
            }
        }
    }
    Ok(())
}
