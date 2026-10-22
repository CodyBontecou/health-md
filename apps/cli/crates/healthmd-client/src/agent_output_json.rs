//! Private aggregate journal encoding. Public wire messages retain their independent 2MiB codec.
use super::private;
use crate::ClientError;
use serde::{Serialize, de::DeserializeOwned};
use serde_json::Value;

pub(super) const MAX_BYTES: usize = 64 * 1024 * 1024;
const MAX_NODES: usize = 1_048_576;
const MAX_DEPTH: usize = 64;

pub(super) fn encode<T: Serialize>(value: &T) -> Result<Vec<u8>, ClientError> {
    let mut tree = serde_json::to_value(value).map_err(private::unavailable)?;
    let mut nodes = 0;
    order(&mut tree, 0, &mut nodes)?;
    let mut bytes = BoundedBytes(Vec::new());
    serde_json::to_writer(&mut bytes, &tree).map_err(private::unavailable)?;
    Ok(bytes.0)
}
pub(super) fn decode<T: DeserializeOwned + Serialize>(bytes: &[u8]) -> Result<T, ClientError> {
    if bytes.is_empty() || bytes.len() > MAX_BYTES {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    let value: T = serde_json::from_slice(bytes).map_err(private::unavailable)?;
    // Issuer writes canonical private bytes. Requiring exact re-encoding also rejects
    // duplicates/coercions/null omission that a generic typed decoder might discard.
    if encode(&value)? != bytes {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    Ok(value)
}
fn order(value: &mut Value, depth: usize, nodes: &mut usize) -> Result<(), ClientError> {
    *nodes += 1;
    if depth > MAX_DEPTH || *nodes > MAX_NODES {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    match value {
        Value::Object(object) => {
            let mut entries = std::mem::take(object).into_iter().collect::<Vec<_>>();
            entries.sort_by(|left, right| left.0.cmp(&right.0));
            for (key, mut value) in entries {
                if key.chars().count() > 65_536 {
                    return Err(ClientError::AgentAuthorityUnavailable);
                }
                order(&mut value, depth + 1, nodes)?;
                object.insert(key, value);
            }
        }
        Value::Array(values) => {
            for value in values {
                order(value, depth + 1, nodes)?;
            }
        }
        Value::Number(number) if !number.is_i64() && !number.is_u64() => {
            return Err(ClientError::AgentAuthorityUnavailable);
        }
        Value::String(value) if value.chars().count() > 65_536 => {
            return Err(ClientError::AgentAuthorityUnavailable);
        }
        _ => {}
    }
    Ok(())
}
struct BoundedBytes(Vec<u8>);
impl std::io::Write for BoundedBytes {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        if bytes.len() > MAX_BYTES.saturating_sub(self.0.len()) {
            return Err(std::io::ErrorKind::InvalidData.into());
        }
        self.0.extend_from_slice(bytes);
        Ok(bytes.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn aggregate_private_metadata_exceeds_one_wire_envelope_without_changing_wire_codec() {
        let value = serde_json::json!({"items":vec!["x".repeat(65_536);40]});
        assert!(healthmd_protocol::v4::canonical_json(&value).is_err());
        let bytes = encode(&value).unwrap();
        assert!(bytes.len() > 2 * 1024 * 1024);
        assert_eq!(decode::<Value>(&bytes).unwrap(), value);
    }
    #[test]
    fn private_canonical_decoder_rejects_ambiguous_raw_bytes_and_floats() {
        assert!(decode::<Value>(br#"{"a":1,"a":1}"#).is_err());
        assert!(decode::<Value>(br#"{ "a":1}"#).is_err());
        assert!(encode(&serde_json::json!({"a":1.5})).is_err());
        let value = serde_json::json!({"z":[1,u64::MAX],"a":"é/"});
        assert_eq!(
            encode(&value).unwrap(),
            healthmd_protocol::v4::canonical_json(&value).unwrap()
        );
    }
}
