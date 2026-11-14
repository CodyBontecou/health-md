use serde::Serialize;
use serde_json::{Map, Number, Value};

use super::{Error, shape};

const MAX_BYTES: usize = 2 * 1024 * 1024;
pub(super) const MAX_DEPTH: usize = 24;
pub(super) const MAX_NODES: usize = 262_144;
pub(super) const MAX_STRING_SCALARS: usize = 65_536;

/// Strict bounded integer-only JSON parser. Object keys are checked before insertion.
/// Integer `-0` is accepted and canonicalized to `0`; decimal/exponent negative zero
/// is rejected like every other floating-point token. Integers span `i64::MIN..u64::MAX`.
///
/// # Errors
/// Returns only `invalid_request`, including UTF-8/scalar, duplicate and budget failures.
pub fn parse_strict(raw: &[u8]) -> Result<Value, Error> {
    shape(!raw.is_empty() && raw.len() <= MAX_BYTES)?;
    // Validate the entire byte stream, including bytes outside strings.
    std::str::from_utf8(raw).map_err(|_| Error::InvalidRequest)?;
    let mut parser = Parser {
        raw,
        position: 0,
        nodes: 0,
    };
    let value = parser.value(0)?;
    parser.whitespace();
    shape(parser.position == raw.len())?;
    Ok(value)
}

struct Parser<'a> {
    raw: &'a [u8],
    position: usize,
    nodes: usize,
}

impl Parser<'_> {
    fn whitespace(&mut self) {
        while matches!(
            self.raw.get(self.position),
            Some(b' ' | b'\n' | b'\r' | b'\t')
        ) {
            self.position += 1;
        }
    }
    fn node(&mut self, depth: usize) -> Result<(), Error> {
        self.nodes += 1;
        shape(depth <= MAX_DEPTH && self.nodes <= MAX_NODES)
    }
    fn take(&mut self, byte: u8) -> Result<(), Error> {
        self.whitespace();
        shape(self.raw.get(self.position) == Some(&byte))?;
        self.position += 1;
        Ok(())
    }
    fn value(&mut self, depth: usize) -> Result<Value, Error> {
        self.node(depth)?;
        self.whitespace();
        match self.raw.get(self.position).copied() {
            Some(b'{') => {
                self.position += 1;
                self.whitespace();
                let mut object = Map::new();
                if self.raw.get(self.position) != Some(&b'}') {
                    loop {
                        self.node(depth + 1)?;
                        let key = self.string()?;
                        shape(!object.contains_key(&key) && object.len() < 512)?;
                        self.take(b':')?;
                        let value = self.value(depth + 1)?;
                        object.insert(key, value);
                        self.whitespace();
                        if self.raw.get(self.position) != Some(&b',') {
                            break;
                        }
                        self.position += 1;
                    }
                }
                self.take(b'}')?;
                Ok(Value::Object(object))
            }
            Some(b'[') => {
                self.position += 1;
                self.whitespace();
                let mut array = Vec::new();
                if self.raw.get(self.position) != Some(&b']') {
                    loop {
                        shape(array.len() < 4096)?;
                        array.push(self.value(depth + 1)?);
                        self.whitespace();
                        if self.raw.get(self.position) != Some(&b',') {
                            break;
                        }
                        self.position += 1;
                    }
                }
                self.take(b']')?;
                Ok(Value::Array(array))
            }
            Some(b'"') => self.string().map(Value::String),
            Some(b'-' | b'0'..=b'9') => self.integer(),
            Some(b't') => self.literal(b"true", Value::Bool(true)),
            Some(b'f') => self.literal(b"false", Value::Bool(false)),
            Some(b'n') => self.literal(b"null", Value::Null),
            _ => Err(Error::InvalidRequest),
        }
    }
    fn literal(&mut self, bytes: &[u8], value: Value) -> Result<Value, Error> {
        let end = self.position + bytes.len();
        shape(self.raw.get(self.position..end) == Some(bytes))?;
        self.position = end;
        Ok(value)
    }
    fn string(&mut self) -> Result<String, Error> {
        self.whitespace();
        let start = self.position;
        shape(self.raw.get(start) == Some(&b'"'))?;
        self.position += 1;
        loop {
            match self.raw.get(self.position) {
                Some(b'"') => {
                    self.position += 1;
                    break;
                }
                Some(b'\\') => {
                    self.position += 2;
                    shape(self.position <= self.raw.len())?;
                }
                Some(_) => self.position += 1,
                None => return Err(Error::InvalidRequest),
            }
        }
        // serde's string decoder checks escapes, controls and paired Unicode surrogates.
        let value: String = serde_json::from_slice(&self.raw[start..self.position])
            .map_err(|_| Error::InvalidRequest)?;
        shape(value.chars().count() <= MAX_STRING_SCALARS)?;
        Ok(value)
    }
    fn integer(&mut self) -> Result<Value, Error> {
        let start = self.position;
        let negative = self.raw.get(start) == Some(&b'-');
        if negative {
            self.position += 1;
        }
        match self.raw.get(self.position) {
            Some(b'0') => self.position += 1,
            Some(b'1'..=b'9') => {
                while matches!(self.raw.get(self.position), Some(b'0'..=b'9')) {
                    self.position += 1;
                }
            }
            _ => return Err(Error::InvalidRequest),
        }
        shape(!matches!(
            self.raw.get(self.position),
            Some(b'.' | b'e' | b'E' | b'0'..=b'9')
        ))?;
        let token = std::str::from_utf8(&self.raw[start..self.position])
            .map_err(|_| Error::InvalidRequest)?;
        let number = if negative {
            Number::from(token.parse::<i64>().map_err(|_| Error::InvalidRequest)?)
        } else {
            Number::from(token.parse::<u64>().map_err(|_| Error::InvalidRequest)?)
        };
        Ok(Value::Number(number))
    }
}

/// Canonical tree/DTO encoding only (not semantic validation or stored authorization).
/// Recursive Unicode-codepoint key order, unescaped Unicode/slash, no normalization/LF.
///
/// # Errors
/// Rejects floats and the same raw resource bounds as the parser.
pub fn canonical_json<T: Serialize + ?Sized>(value: &T) -> Result<Vec<u8>, Error> {
    super::integers::check(value)?;
    let mut raw = BoundedBytes(Vec::new());
    serde_json::to_writer(&mut raw, value).map_err(|_| Error::InvalidRequest)?;
    let raw = raw.0;
    let tree = parse_strict(&raw)?;
    let mut output = Vec::with_capacity(raw.len());
    write(&tree, &mut output)?;
    Ok(output)
}

// This writer is only a bounded in-memory sink, not filesystem/network I/O.
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

fn write(value: &Value, output: &mut Vec<u8>) -> Result<(), Error> {
    match value {
        Value::Object(object) => {
            output.push(b'{');
            let mut entries: Vec<_> = object.iter().collect();
            // UTF-8 lexicographic ordering agrees with Unicode scalar/codepoint ordering.
            entries.sort_by(|(left, _), (right, _)| left.cmp(right));
            for (index, (key, value)) in entries.into_iter().enumerate() {
                if index != 0 {
                    output.push(b',');
                }
                serde_json::to_writer(&mut *output, key).map_err(|_| Error::InvalidRequest)?;
                output.push(b':');
                write(value, output)?;
            }
            output.push(b'}');
        }
        Value::Array(array) => {
            output.push(b'[');
            for (index, value) in array.iter().enumerate() {
                if index != 0 {
                    output.push(b',');
                }
                write(value, output)?;
            }
            output.push(b']');
        }
        _ => serde_json::to_writer(output, value).map_err(|_| Error::InvalidRequest)?,
    }
    Ok(())
}
