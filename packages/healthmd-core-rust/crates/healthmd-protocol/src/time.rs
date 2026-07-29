//! Swift-compatible whole-second ISO-8601 timestamps.

use chrono::{DateTime, SecondsFormat, Utc};
use serde::{Deserialize, Deserializer, Serializer, de::Error as _};

/// Serialize a timestamp exactly as Swift's whole-second ISO-8601 strategy.
///
/// # Errors
///
/// Returns the serializer's error if the timestamp string cannot be emitted.
pub fn serialize<S>(value: &DateTime<Utc>, serializer: S) -> Result<S::Ok, S::Error>
where
    S: Serializer,
{
    serializer.serialize_str(&value.to_rfc3339_opts(SecondsFormat::Secs, true))
}

/// Decode an RFC 3339/ISO-8601 timestamp and normalize it to UTC.
///
/// # Errors
///
/// Returns a deserialization error when the input is not a valid RFC 3339 timestamp.
pub fn deserialize<'de, D>(deserializer: D) -> Result<DateTime<Utc>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = String::deserialize(deserializer)?;
    DateTime::parse_from_rfc3339(&value)
        .map(|date| date.with_timezone(&Utc))
        .map_err(D::Error::custom)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::{Deserialize, Serialize};

    #[derive(Debug, Deserialize, Serialize)]
    struct Fixture {
        #[serde(with = "super")]
        date: DateTime<Utc>,
    }

    #[test]
    fn serializes_whole_seconds_with_z_suffix() {
        let fixture = Fixture {
            date: "2026-07-24T10:11:12Z".parse().unwrap(),
        };
        assert_eq!(
            serde_json::to_string(&fixture).unwrap(),
            r#"{"date":"2026-07-24T10:11:12Z"}"#
        );
    }
}
