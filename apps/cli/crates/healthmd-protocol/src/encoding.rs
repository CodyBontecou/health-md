//! Foundation-compatible wire encoding helpers.

use std::fmt;

use base64::{Engine as _, engine::general_purpose::STANDARD};
use chrono::{DateTime, Duration, TimeZone as _, Utc};
use serde::{Deserialize, Deserializer, Serialize, Serializer, de::Error as _};
use uuid::Uuid;

/// UUID text as emitted by Foundation's `UUID: Codable` implementation.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub struct SwiftUuid(pub Uuid);

impl SwiftUuid {
    #[must_use]
    pub const fn into_inner(self) -> Uuid {
        self.0
    }
}

impl From<Uuid> for SwiftUuid {
    fn from(value: Uuid) -> Self {
        Self(value)
    }
}

impl From<SwiftUuid> for Uuid {
    fn from(value: SwiftUuid) -> Self {
        value.0
    }
}

impl fmt::Display for SwiftUuid {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            formatter,
            "{}",
            self.0.hyphenated().to_string().to_uppercase()
        )
    }
}

impl Serialize for SwiftUuid {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str(&self.to_string())
    }
}

impl<'de> Deserialize<'de> for SwiftUuid {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        Uuid::parse_str(&value).map(Self).map_err(D::Error::custom)
    }
}

/// Serde adapter for Swift `Data`'s padded standard-base64 JSON representation.
pub mod data {
    use super::*;

    /// Encode bytes as standard padded base64.
    ///
    /// # Errors
    ///
    /// Returns the serializer's error if the string cannot be emitted.
    pub fn serialize<S>(value: &[u8], serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str(&STANDARD.encode(value))
    }

    /// Decode standard padded base64 into bytes.
    ///
    /// # Errors
    ///
    /// Returns a deserialization error for malformed base64.
    pub fn deserialize<'de, D>(deserializer: D) -> Result<Vec<u8>, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        STANDARD.decode(value).map_err(D::Error::custom)
    }
}

/// Serde adapter for optional Swift `Data`.
pub mod optional_data {
    use super::*;

    /// Encode optional bytes as standard padded base64.
    ///
    /// # Errors
    ///
    /// Returns the serializer's error if the value cannot be emitted.
    pub fn serialize<S>(value: &Option<Vec<u8>>, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        value
            .as_ref()
            .map(|bytes| STANDARD.encode(bytes))
            .serialize(serializer)
    }

    /// Decode optional standard padded base64.
    ///
    /// # Errors
    ///
    /// Returns a deserialization error for malformed base64.
    pub fn deserialize<'de, D>(deserializer: D) -> Result<Option<Vec<u8>>, D::Error>
    where
        D: Deserializer<'de>,
    {
        Option::<String>::deserialize(deserializer)?
            .map(|value| STANDARD.decode(value).map_err(D::Error::custom))
            .transpose()
    }
}

/// Swift's default JSON `Date` representation: seconds since 2001-01-01 UTC.
pub mod apple_reference_date {
    use super::*;

    fn epoch() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2001, 1, 1, 0, 0, 0)
            .single()
            .expect("the Apple reference epoch is valid")
    }

    /// Encode a timestamp as seconds from Apple's reference date.
    ///
    /// # Errors
    ///
    /// Returns the serializer's error if the number cannot be emitted.
    #[allow(clippy::cast_precision_loss)]
    pub fn serialize<S>(value: &DateTime<Utc>, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let delta = value.signed_duration_since(epoch());
        let seconds = delta.num_microseconds().map_or_else(
            || delta.num_seconds() as f64,
            |micros| micros as f64 / 1_000_000.0,
        );
        serializer.serialize_f64(seconds)
    }

    /// Decode seconds from Apple's reference date.
    ///
    /// # Errors
    ///
    /// Returns a deserialization error for non-finite or out-of-range values.
    #[allow(clippy::cast_possible_truncation)]
    pub fn deserialize<'de, D>(deserializer: D) -> Result<DateTime<Utc>, D::Error>
    where
        D: Deserializer<'de>,
    {
        let seconds = f64::deserialize(deserializer)?;
        if !seconds.is_finite() {
            return Err(D::Error::custom("Apple reference date must be finite"));
        }
        let whole = seconds.trunc() as i64;
        let nanos = ((seconds.fract()) * 1_000_000_000.0).round() as i64;
        epoch()
            .checked_add_signed(Duration::seconds(whole) + Duration::nanoseconds(nanos))
            .ok_or_else(|| D::Error::custom("Apple reference date is out of range"))
    }
}

/// Produce deterministic sorted-key JSON matching the Foundation protocol encoder.
///
/// # Errors
///
/// Returns a JSON encoding error if the value cannot be represented.
pub fn canonical_json<T: Serialize>(value: &T) -> Result<Vec<u8>, serde_json::Error> {
    // serde_json::Map is key-sorted unless its optional preserve_order feature is enabled.
    let tree = serde_json::to_value(value)?;
    serde_json::to_vec(&tree)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn swift_uuid_is_uppercase_on_encode_and_case_insensitive_on_decode() {
        let id = Uuid::parse_str("abcdefab-cdef-4abc-8def-abcdefabcdef").unwrap();
        assert_eq!(
            serde_json::to_string(&SwiftUuid(id)).unwrap(),
            r#""ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF""#
        );
        assert_eq!(
            serde_json::from_str::<SwiftUuid>(r#""abcdefab-cdef-4abc-8def-abcdefabcdef""#)
                .unwrap()
                .0,
            id
        );
    }

    #[test]
    fn canonical_json_sorts_nested_keys() {
        #[derive(Serialize)]
        struct Value {
            z: u8,
            a: u8,
        }
        assert_eq!(
            canonical_json(&Value { z: 1, a: 2 }).unwrap(),
            br#"{"a":2,"z":1}"#
        );
    }

    #[test]
    fn apple_reference_epoch_matches_foundation() {
        #[derive(Deserialize, Serialize)]
        struct Value {
            #[serde(with = "apple_reference_date")]
            date: DateTime<Utc>,
        }
        let value = Value {
            date: "2001-01-01T00:00:00Z".parse().unwrap(),
        };
        assert_eq!(serde_json::to_string(&value).unwrap(), r#"{"date":0.0}"#);
    }
}
