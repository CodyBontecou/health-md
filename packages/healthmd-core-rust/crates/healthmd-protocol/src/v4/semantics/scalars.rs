use crate::v4::{Error, ValidateShape, shape};
use chrono::{Datelike as _, NaiveDate, NaiveDateTime, Timelike as _};
use serde::{Deserialize, Serialize};

macro_rules! scalar {
    ($name:ident, $check:expr) => {
        #[derive(Clone, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
        #[serde(transparent)]
        pub struct $name(pub String);
        impl ValidateShape for $name {
            fn validate_shape(&self) -> Result<(), Error> {
                shape(($check)(&self.0))
            }
        }
    };
}
scalar!(ControlUuid, |s: &str| valid_uuid(s, true));
scalar!(SemanticId, valid_semantic_id);
scalar!(Digest, |s: &str| valid_lower_hex(s, 64));
scalar!(CivilDate, |s: &str| civil(s).is_ok());
scalar!(UtcTimestamp, |s: &str| utc(s).is_ok());
scalar!(NativeTypeId, |s: &str| {
    (1..=256).contains(&s.len())
        && s.as_bytes()
            .first()
            .is_some_and(|b| b.is_ascii_alphabetic() || *b == b'_')
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"_.:$-".contains(&b))
});
scalar!(CalendarZone, |s: &str| !s.is_empty()
    && s.chars().count() <= 128);
scalar!(RelativePath, |s: &str| s.chars().count() <= 4096);
scalar!(FilenameTemplate, |s: &str| !s.is_empty()
    && s.chars().count() <= 255);

/// Required nullable original source offset; never inferred from calendar timezone.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(transparent)]
pub struct NullableOffset(pub Option<i64>);
impl ValidateShape for NullableOffset {
    fn validate_shape(&self) -> Result<(), Error> {
        shape(self.0.is_none_or(|n| (-64_800..=64_800).contains(&n)))
    }
}

pub(crate) fn valid_lower_hex(s: &str, size: usize) -> bool {
    s.len() == size
        && s.bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}
pub(crate) fn valid_pointer(s: &str) -> bool {
    s.starts_with('/')
        && s.bytes()
            .skip(1)
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_' || b == b'/')
}
pub(crate) fn valid_uuid(s: &str, version4: bool) -> bool {
    s.len() == 36
        && s.bytes().enumerate().all(|(i, b)| {
            if [8, 13, 18, 23].contains(&i) {
                b == b'-'
            } else {
                b.is_ascii_digit() || (b'a'..=b'f').contains(&b)
            }
        })
        && (!version4 || s.as_bytes()[14] == b'4' && b"89ab".contains(&s.as_bytes()[19]))
}
fn valid_semantic_id(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 128
        && s.as_bytes()[0].is_ascii_lowercase()
        && s.split(['.', '_', '-']).all(|part| {
            !part.is_empty()
                && part
                    .bytes()
                    .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit())
        })
}
pub(crate) fn civil(s: &str) -> Result<NaiveDate, Error> {
    shape(
        s.len() == 10
            && s.bytes().enumerate().all(|(i, b)| {
                if i == 4 || i == 7 {
                    b == b'-'
                } else {
                    b.is_ascii_digit()
                }
            }),
    )?;
    let date = NaiveDate::parse_from_str(s, "%Y-%m-%d").map_err(|_| Error::InvalidRequest)?;
    shape((1..=9999).contains(&date.year()))?;
    Ok(date)
}
pub(crate) fn utc(s: &str) -> Result<NaiveDateTime, Error> {
    shape(
        s.len() == 20
            && s.bytes().enumerate().all(|(i, b)| match i {
                4 | 7 => b == b'-',
                10 => b == b'T',
                13 | 16 => b == b':',
                19 => b == b'Z',
                _ => b.is_ascii_digit(),
            }),
    )?;
    civil(&s[..10])?;
    let time = NaiveDateTime::parse_from_str(s, "%Y-%m-%dT%H:%M:%SZ")
        .map_err(|_| Error::InvalidRequest)?;
    shape(time.nanosecond() == 0)?; // no leap-second coercion
    Ok(time)
}
impl UtcTimestamp {
    /// Parse a whole-second UTC timestamp without consulting a clock.
    /// # Errors
    /// Returns `invalid_request` for invalid date/time grammar.
    pub fn seconds(&self) -> Result<i64, Error> {
        Ok(utc(&self.0)?.and_utc().timestamp())
    }
}
