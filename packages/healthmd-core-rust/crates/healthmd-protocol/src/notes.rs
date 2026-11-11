//! Independently negotiated policy for capture-scoped personal-note writes.

use chrono::NaiveDate;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ScopedDailyNotePolicy {
    pub version: u16,
    pub record_profile: String,
    pub owner_date: String,
    pub calendar_timezone: String,
    pub create_if_missing: bool,
    pub inject_sections: bool,
}

impl ScopedDailyNotePolicy {
    /// Structural admission only; the receiver must also bind the actual capture
    /// and accepted source platform, dates and frozen clock before any write.
    #[must_use]
    pub fn is_valid(&self) -> bool {
        self.version == 1
            && matches!(
                self.record_profile.as_str(),
                "apple-v8"
                    | "apple-v11"
                    | "android-frozen-v4"
                    | "android-analytical-v5"
                    | "android-sleep-v6"
            )
            && self.owner_date.len() == 10
            && !self.owner_date.starts_with("0000")
            && NaiveDate::parse_from_str(&self.owner_date, "%Y-%m-%d")
                .is_ok_and(|date| date.format("%Y-%m-%d").to_string() == self.owner_date)
            && self.calendar_timezone.len() <= 128
            && self.calendar_timezone.parse::<chrono_tz::Tz>().is_ok()
    }
}

/// Unknown and absent versions never imply the implemented v1 semantics.
#[must_use]
pub fn negotiate_scoped_daily_notes(local: Option<&[i32]>, remote: Option<&[i32]>) -> Option<i32> {
    (local.is_some_and(|versions| versions.contains(&1))
        && remote.is_some_and(|versions| versions.contains(&1)))
    .then_some(1)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn note_negotiation_requires_bilateral_implemented_support() {
        for local in [
            None,
            Some(&[][..]),
            Some(&[1][..]),
            Some(&[2][..]),
            Some(&[1, 2][..]),
        ] {
            for remote in [
                None,
                Some(&[][..]),
                Some(&[1][..]),
                Some(&[2][..]),
                Some(&[1, 2][..]),
            ] {
                assert_eq!(
                    negotiate_scoped_daily_notes(local, remote),
                    (local.is_some_and(|v| v.contains(&1))
                        && remote.is_some_and(|v| v.contains(&1)))
                    .then_some(1)
                );
            }
        }
    }

    #[test]
    fn note_policy_rejects_unknown_authority_and_invalid_calendar_identifiers() {
        let valid = ScopedDailyNotePolicy {
            version: 1,
            record_profile: "apple-v11".into(),
            owner_date: "2026-03-08".into(),
            calendar_timezone: "America/New_York".into(),
            create_if_missing: false,
            inject_sections: true,
        };
        assert!(valid.is_valid());
        for (field, value) in [
            ("version", serde_json::json!(2)),
            ("record_profile", serde_json::json!("unverified")),
            ("owner_date", serde_json::json!("2026-02-30")),
            ("owner_date", serde_json::json!("2026-3-8")),
            ("calendar_timezone", serde_json::json!("Invalid/Zone")),
        ] {
            let mut json = serde_json::to_value(&valid).unwrap();
            json[field] = value;
            assert!(
                !serde_json::from_value::<ScopedDailyNotePolicy>(json)
                    .unwrap()
                    .is_valid()
            );
        }
        let mut json = serde_json::to_value(&valid).unwrap();
        json["unknown"] = serde_json::json!(true);
        assert!(serde_json::from_value::<ScopedDailyNotePolicy>(json).is_err());
    }
}
