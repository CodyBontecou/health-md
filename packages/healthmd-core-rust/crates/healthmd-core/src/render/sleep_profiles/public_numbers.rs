//! Read successor public binary64 decimals with the standard correctly rounded parser.
//! Do not change `serde_json` features or the historical handoff parser/number semantics.

use super::super::{OrderedJsonValue, RenderBatch, RenderError};
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
            if metric.public_value.is_number()
                && (decimal.contains(['.', 'e', 'E']) || decimal == "-0")
            {
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

/// Read an already validated successor native document without a lossy JSON reparse.
/// Original ordered lexemes still own output bytes; this value is only for exact attestation.
pub(in crate::render) fn exact_ordered_value(
    value: &OrderedJsonValue,
) -> Result<Value, RenderError> {
    Ok(match value {
        OrderedJsonValue::Null => Value::Null,
        OrderedJsonValue::Boolean { value } => Value::Bool(*value),
        OrderedJsonValue::String { value } => Value::String(value.clone()),
        OrderedJsonValue::Number { decimal } => {
            let number = if !decimal.contains(['.', 'e', 'E']) && decimal != "-0" {
                decimal
                    .parse::<i64>()
                    .ok()
                    .map(Number::from)
                    .or_else(|| decimal.parse::<u64>().ok().map(Number::from))
            } else {
                None
            };
            Value::Number(
                number
                    .or_else(|| decimal.parse::<f64>().ok().and_then(Number::from_f64))
                    .ok_or(RenderError::PresentationMismatch)?,
            )
        }
        OrderedJsonValue::Array { items } => Value::Array(
            items
                .iter()
                .map(exact_ordered_value)
                .collect::<Result<_, _>>()?,
        ),
        OrderedJsonValue::Object { entries } => Value::Object(
            entries
                .iter()
                .map(|entry| Ok((entry.key.clone(), exact_ordered_value(&entry.value)?)))
                .collect::<Result<_, RenderError>>()?,
        ),
    })
}

/// Native numeric attestation retains the sign bit of binary64 zero too.
pub(in crate::render) fn exact_value_matches(left: &Value, right: &Value) -> bool {
    match (left, right) {
        (Value::Number(left), Value::Number(right)) if left.is_f64() && right.is_f64() => {
            left.as_f64().map(f64::to_bits) == right.as_f64().map(f64::to_bits)
        }
        _ => left == right,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn native_negative_zero_lexemes_retain_the_sign_and_reject_positive_zero() {
        for decimal in ["-0", "-0.0", "-0e0"] {
            let value = exact_ordered_value(&OrderedJsonValue::Number {
                decimal: decimal.to_owned(),
            })
            .unwrap();
            assert_eq!(value.as_f64().unwrap().to_bits(), (-0.0_f64).to_bits());
            assert!(exact_value_matches(&value, &Value::from(-0.0)));
            assert!(!exact_value_matches(&value, &Value::from(0.0)));
        }
    }
}
