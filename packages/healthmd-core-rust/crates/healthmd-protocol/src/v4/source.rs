use super::NativeIdentityAppleHealthIdentityKind as Kind;
use super::NativeIdentityHealthConnectMetadataStatusClientRecordId as IdStatus;
use super::NativeIdentityHealthConnectMetadataStatusClientRecordVersion as Status;
use super::semantics::scalars::{valid_lower_hex, valid_uuid};
use super::{Error, ExactTime, NativeIdentity, ValidateShape, shape};

/// Exact IEEE-754 rational decoding, multiplied by integer 1e9 and rounded
/// nearest/ties-even. No floating-point multiplication or lossy integer conversion.
/// Negative zero bits are valid and preserved by the DTO; their normalized view is zero.
///
/// # Errors
/// Rejects malformed/nonfinite bits and views outside years 0001..9999.
pub fn binary64_nanosecond_view(bits: &str) -> Result<(i64, u64), Error> {
    shape(valid_lower_hex(bits, 16))?;
    let bits = u64::from_str_radix(bits, 16).map_err(|_| Error::InvalidRequest)?;
    let exponent = (bits >> 52) & 0x7ff;
    shape(exponent != 0x7ff)?;
    let fraction = bits & ((1_u64 << 52) - 1);
    let (mantissa, shift) = if exponent == 0 {
        (fraction, -1074)
    } else {
        (
            (1_u64 << 52) | fraction,
            i32::try_from(exponent).map_err(|_| Error::InvalidRequest)? - 1075,
        )
    };
    let numerator = u128::from(mantissa) * 1_000_000_000;
    let magnitude = if shift >= 0 {
        let shift = u32::try_from(shift).map_err(|_| Error::InvalidRequest)?;
        // checked_shl checks only the shift amount; also check bits shifted out.
        shape(shift < 128 && numerator <= (u128::MAX >> shift))?;
        numerator << shift
    } else {
        let divisor_shift = shift.unsigned_abs();
        if divisor_shift >= 128 {
            0
        } else {
            let quotient = numerator >> divisor_shift;
            let remainder = numerator & ((1_u128 << divisor_shift) - 1);
            let half = 1_u128 << (divisor_shift - 1);
            quotient + u128::from(remainder > half || remainder == half && quotient & 1 == 1)
        }
    };
    let mut total = i128::try_from(magnitude).map_err(|_| Error::InvalidRequest)?;
    if bits >> 63 != 0 {
        total = -total;
    }
    let second =
        i64::try_from(total.div_euclid(1_000_000_000)).map_err(|_| Error::InvalidRequest)?;
    let nano = u64::try_from(total.rem_euclid(1_000_000_000)).map_err(|_| Error::InvalidRequest)?;
    shape((-62_135_596_800..=253_402_300_799).contains(&second))?;
    Ok((second, nano))
}

/// Check representation precision and the normalized nanosecond view.
/// # Errors
/// Returns a fixed error on precision mismatch; never reconstructs an offset.
pub fn validate_exact_time(time: &ExactTime) -> Result<(), Error> {
    time.validate_shape()?;
    match time {
        ExactTime::SourceMilliseconds { nanosecond, .. } => shape(nanosecond % 1_000_000 == 0),
        ExactTime::SourceSeconds { nanosecond, .. } => shape(*nanosecond == 0),
        ExactTime::SourceBinary64Seconds {
            source_binary64_bits,
            epoch_second,
            nanosecond,
            ..
        } => shape(binary64_nanosecond_view(source_binary64_bits)? == (*epoch_second, *nanosecond)),
        ExactTime::SourceNanoseconds { .. } => Ok(()),
    }
}

/// Source-specific metadata checks. Missing/unexposed values stay omitted;
/// actual version zero and positive signed-long values above 2^53 are retained.
/// # Errors
/// Returns a fixed code for fabricated metadata/parent/time semantics.
pub fn validate_native_identity(identity: &NativeIdentity) -> Result<(), Error> {
    identity.validate_shape()?;
    match identity {
        NativeIdentity::AppleHealth {
            identity_kind,
            record_id,
            parent_record_id,
            parent_record_type,
            ..
        } => {
            parent(
                identity_kind,
                parent_record_id.as_deref(),
                parent_record_type.as_ref(),
            )?;
            if *identity_kind == Kind::Native {
                shape(valid_uuid(record_id, false))?;
            }
        }
        NativeIdentity::HealthConnect {
            identity_kind,
            client_record_id,
            client_record_version,
            last_modified,
            metadata_status,
            parent_record_id,
            parent_record_type,
            ..
        } => {
            parent(
                identity_kind,
                parent_record_id.as_deref(),
                parent_record_type.as_ref(),
            )?;
            shape(
                (metadata_status.client_record_id == IdStatus::Available)
                    == client_record_id.is_some(),
            )?;
            shape(
                (metadata_status.client_record_version == Status::Available)
                    == client_record_version.is_some(),
            )?;
            shape((metadata_status.last_modified == Status::Available) == last_modified.is_some())?;
            if *identity_kind == Kind::DerivedChild {
                shape(
                    metadata_status.client_record_id == IdStatus::NotExposedBySource
                        && metadata_status.client_record_version == Status::NotExposedBySource
                        && metadata_status.last_modified == Status::NotExposedBySource,
                )?;
            } else if *identity_kind == Kind::Native {
                shape(
                    metadata_status.client_record_version != Status::NotExposedBySource
                        && metadata_status.last_modified != Status::NotExposedBySource,
                )?;
                if let Some(time) = last_modified {
                    shape(matches!(time, ExactTime::SourceNanoseconds { .. }))?;
                }
            }
            if let Some(time) = last_modified {
                validate_exact_time(time)?;
            }
        }
        NativeIdentity::ProviderNative {
            identity_kind,
            client_record_id,
            client_record_version,
            last_modified,
            metadata_status,
            parent_record_id,
            parent_record_type,
            ..
        } => {
            parent(
                identity_kind,
                parent_record_id.as_deref(),
                parent_record_type.as_ref(),
            )?;
            shape(
                (metadata_status.client_record_id == IdStatus::Available)
                    == client_record_id.is_some(),
            )?;
            shape(
                (metadata_status.client_record_version == Status::Available)
                    == client_record_version.is_some(),
            )?;
            shape((metadata_status.last_modified == Status::Available) == last_modified.is_some())?;
            if *identity_kind == Kind::DerivedChild {
                shape(
                    metadata_status.client_record_id == IdStatus::NotExposedBySource
                        && metadata_status.client_record_version == Status::NotExposedBySource
                        && metadata_status.last_modified == Status::NotExposedBySource,
                )?;
            }
            if let Some(time) = last_modified {
                validate_exact_time(time)?;
            }
        }
    }
    Ok(())
}

fn parent(
    kind: &super::NativeIdentityAppleHealthIdentityKind,
    id: Option<&str>,
    record_type: Option<&super::NativeTypeId>,
) -> Result<(), Error> {
    if matches!(
        kind,
        super::NativeIdentityAppleHealthIdentityKind::DerivedChild
    ) {
        shape(id.is_some_and(|id| !id.is_empty()) && record_type.is_some())
    } else {
        shape(id.is_none() && record_type.is_none())
    }
}
