//! Public sleep attribution identity, independent of native capture and raw source ownership.

use serde_json::Value;
use thiserror::Error;

/// Native source whose independently versioned daily grammar is being read.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SleepSource {
    /// Apple Health daily grammar.
    Apple,
    /// Health Connect daily grammar.
    Android,
}

/// Stable owner-day choice shared by both native sources.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SleepDayAttribution {
    /// Historical clipped noon-to-noon journal window.
    NightBegins,
    /// Whole sessions assigned by their source end instant's calendar date.
    MorningEnds,
}

/// Validated public authority. This does not query or reinterpret source records.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PublicSleepContext {
    /// Validated owner-day choice, never inferred from values or timestamps.
    pub attribution: SleepDayAttribution,
    /// Captured owner-date timezone when the historical format declared one.
    pub calendar_timezone: Option<String>,
    /// Declared machine timestamp timezone when present.
    pub timestamp_timezone: Option<String>,
    /// Explicit native successor identity, absent for historical profiles.
    pub successor_profile: Option<String>,
}

/// Bounded, health-free failures shared by producers and readers.
#[derive(Clone, Copy, Debug, Eq, Error, PartialEq)]
pub enum SleepProfileError {
    /// The source/version/profile combination is unsupported.
    #[error("sleep export profile is unsupported")]
    UnsupportedProfile,
    /// The selected public identity contradicts the sleep authority.
    #[error("sleep attribution is incompatible with the export profile")]
    IncompatibleAttribution,
    /// Required successor metadata is absent or malformed.
    #[error("sleep attribution metadata is invalid")]
    InvalidMetadata,
    /// The exported clock authority is absent, invalid or inconsistent.
    #[error("sleep attribution timezone is invalid")]
    InvalidTimezone,
}

impl SleepProfileError {
    /// Stable public error code, with no parser details or rejected values.
    #[must_use]
    pub const fn code(self) -> &'static str {
        match self {
            Self::UnsupportedProfile => "unsupported_sleep_export_profile",
            Self::IncompatibleAttribution => "incompatible_sleep_attribution",
            Self::InvalidMetadata => "invalid_sleep_attribution_metadata",
            Self::InvalidTimezone => "invalid_sleep_attribution_timezone",
        }
    }
}

/// Reads the owner-day meaning of a self-describing public daily document.
///
/// The caller owns validation of the enclosing schema and source. This interface validates the
/// native daily version, explicit successor identity and atomic sleep/timezone metadata. Legacy
/// absence means only the shipped Night begins rule, never a mutable device preference.
///
/// # Errors
/// Returns a static, health-free failure for an unsupported profile, contradictory attribution,
/// malformed metadata or invalid clock authority.
pub fn read_public_sleep_context(
    source: SleepSource,
    schema_version: u32,
    schema_profile: Option<&str>,
    time_context: Option<&Value>,
) -> Result<PublicSleepContext, SleepProfileError> {
    let successor = match (source, schema_version) {
        (SleepSource::Apple, 10) => Some("apple-v10"),
        (SleepSource::Android, 6) => Some("android-sleep-v6"),
        _ => None,
    };
    let string_field = |key: &str| {
        time_context
            .and_then(|context| context.get(key))
            .and_then(Value::as_str)
            .map(str::to_owned)
    };
    if let Some(expected_profile) = successor {
        if schema_profile != Some(expected_profile) {
            return Err(SleepProfileError::UnsupportedProfile);
        }
        let context = time_context
            .filter(|value| value.is_object())
            .ok_or(SleepProfileError::InvalidMetadata)?;
        let expected_fields = [
            ("sleep_day_attribution", "morning_ends"),
            ("sleep_owner_day_rule", "session_end_date"),
            ("sleep_interval_clipping", "none"),
        ];
        for (key, expected) in expected_fields {
            match context.get(key).and_then(Value::as_str) {
                Some(value) if value == expected => {}
                Some(_) => return Err(SleepProfileError::IncompatibleAttribution),
                None => return Err(SleepProfileError::InvalidMetadata),
            }
        }
        let calendar =
            string_field("calendar_timezone").ok_or(SleepProfileError::InvalidTimezone)?;
        let timestamp =
            string_field("timestamp_timezone").ok_or(SleepProfileError::InvalidTimezone)?;
        if calendar.len() > 128
            || calendar.parse::<chrono_tz::Tz>().is_err()
            || (timestamp != "UTC" && timestamp != calendar)
            || (source == SleepSource::Apple && timestamp != "UTC")
        {
            return Err(SleepProfileError::InvalidTimezone);
        }
        return Ok(PublicSleepContext {
            attribution: SleepDayAttribution::MorningEnds,
            calendar_timezone: Some(calendar),
            timestamp_timezone: Some(timestamp),
            successor_profile: Some(expected_profile.to_owned()),
        });
    }

    let legacy_profile = match (source, schema_version) {
        (SleepSource::Apple, 5) => "apple-v5",
        (SleepSource::Apple, 6) => "apple-v6",
        (SleepSource::Apple, 7) => "apple-v7",
        (SleepSource::Apple, 8) => "apple-v8",
        (SleepSource::Android, 4) => "android-frozen-v4",
        (SleepSource::Android, 5) => "android-analytical-v5",
        _ => return Err(SleepProfileError::UnsupportedProfile),
    };
    if schema_profile.is_some_and(|profile| profile != legacy_profile) {
        return Err(SleepProfileError::UnsupportedProfile);
    }
    if time_context.is_some_and(|context| {
        [
            "sleep_day_attribution",
            "sleep_owner_day_rule",
            "sleep_interval_clipping",
        ]
        .iter()
        .any(|key| context.get(key).is_some())
    }) {
        return Err(SleepProfileError::IncompatibleAttribution);
    }
    Ok(PublicSleepContext {
        attribution: SleepDayAttribution::NightBegins,
        calendar_timezone: string_field("calendar_timezone"),
        timestamp_timezone: string_field("timestamp_timezone"),
        successor_profile: None,
    })
}
