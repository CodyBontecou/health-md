//! Read-only S3-compatible (`Cloudflare R2`) object store Agent Data backing.
//!
//! The third [`ArtifactStore`] backing: a BYO bucket prefix laid out like an export directory
//! (artifact files under their own file names) served with the identical Agent Data grant,
//! query, response, and MCP operation contracts. Recognition and parsing of export artifacts
//! are shared with the directory store through `data_backend::parse_artifact_bytes`; grant
//! evaluation, cursor mechanics, pagination, and chunking are shared through
//! `data_backend::execute_query`.
//!
//! The store is strictly read-only: only `ListObjectsV2`, `HEAD` object, and `GET` object
//! requests (optionally with `Range`) are ever issued. Request authentication is hand-written
//! AWS Signature Version 4 (`aws4_request`, service `s3`, `x-amz-content-sha256:
//! UNSIGNED-PAYLOAD`) over the existing `sha2`/`hmac` crates — no new dependencies. Object
//! addressing is path-style (`https://host/bucket/key`).
//!
//! Credentials are environment-only and never accepted as flags, so no secret material can
//! appear in `argv`, process listings, error text, logs, or receipts. This build's transport
//! speaks HTTP/1.1 over TCP for loopback endpoints (the documented local-testing affordance);
//! `https://` endpoints validate per the URL policy and fail health-free at transport time
//! until a TLS socket layer is wired in a later cycle.

use std::{
    collections::{BTreeSet, HashMap},
    fmt, fs,
    io::{Read as _, Write as _},
    net::{TcpStream, ToSocketAddrs as _},
    path::{Path, PathBuf},
    sync::Arc,
    time::Duration,
};

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use healthmd_operations::{
    AgentDataGrant, AgentDataQueryRequest, ArtifactStore, BackendCapabilities, BackendError,
    CallContext,
};
use hmac::{Hmac, Mac as _};
use serde_json::{Value, json};
use sha2::{Digest as _, Sha256};

use super::data_backend::{
    self, ArtifactByteSource, ArtifactEntry, ArtifactIndex, DataServeOptions, DataStoreOpenError,
    MAXIMUM_GRANT_BYTES, MAXIMUM_NDJSON_LINE_BYTES, MAXIMUM_SOURCE_FILES, RecordEntry,
    backend_failure, default_index_path, execute_query, finalize_index, parse_artifact_bytes,
    persist_index, prepare_private_directory, record_order, sha256_hex,
};

/// `SigV4` region used for the S3-compatible endpoint. Cloudflare R2 accepts `auto` for every
/// request; the value only participates in the signature scope.
const OBJECT_STORE_REGION: &str = "auto";
const ENV_ACCESS_KEY_ID: &str = "HEALTHMD_OBJECT_STORE_ACCESS_KEY_ID";
const ENV_SECRET_ACCESS_KEY: &str = "HEALTHMD_OBJECT_STORE_SECRET_ACCESS_KEY";
const SIGV4_ALGORITHM: &str = "AWS4-HMAC-SHA256";
const SIGV4_SERVICE: &str = "s3";
const SIGV4_TERMINATOR: &str = "aws4_request";
const UNSIGNED_PAYLOAD: &str = "UNSIGNED-PAYLOAD";
const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const IO_TIMEOUT: Duration = Duration::from_secs(30);
/// Bound for any single whole-object read (indexing and verified byte access). Objects larger
/// than this bound are counted invalid at index time instead of being fetched. The directory
/// store bounds JSON artifacts at the same 64 MiB value; the object store applies it to NDJSON
/// artifacts as well because every object read is a network fetch held in memory.
const MAXIMUM_OBJECT_BYTES: u64 = 64 * 1_048_576;
const MAXIMUM_RELATIVE_KEY_BYTES: usize = 4_096;
/// Loop guard for continuation-token paging; `10_000` pages bound any listing this store takes.
const MAXIMUM_LIST_PAGES: usize = 10_000;
/// Verified whole-object bytes cached per store instance before the cache resets. Bounded so
/// chunked artifact reads of a small set of artifacts avoid re-fetching identical bytes while
/// the store can never pin unbounded memory.
const MAXIMUM_VERIFIED_CACHE_ARTIFACTS: usize = 4;

// ---------------------------------------------------------------------------
// Endpoint URL policy and credentials
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ObjectStoreScheme {
    Https,
    Http,
}

#[derive(Clone, Debug)]
struct EndpointUrl {
    scheme: ObjectStoreScheme,
    /// Authority exactly as configured (`host` or `host:port`) — used as the `Host` header and
    /// `SigV4` signed host value.
    host_header: String,
    connect_host: String,
    connect_port: u16,
}

/// Parse and enforce the frozen endpoint URL policy.
///
/// `https://` is required for non-loopback hosts; `http://` is permitted only for loopback
/// hosts (`127.0.0.1`, `localhost`, `[::1]`) as the documented local-testing affordance. The
/// URL must be a bare endpoint: no path, query, fragment, or embedded credentials.
///
/// # Errors
///
/// Returns a stable health-free error describing the violated policy.
fn parse_endpoint_url(raw: &str) -> Result<EndpointUrl, DataStoreOpenError> {
    let malformed =
        || DataStoreOpenError::new("the object store URL must be an http:// or https:// endpoint");
    let Some((scheme, rest)) = raw.split_once("://") else {
        return Err(malformed());
    };
    let scheme = match scheme {
        "https" => ObjectStoreScheme::Https,
        "http" => ObjectStoreScheme::Http,
        _ => return Err(malformed()),
    };
    let authority_end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    let authority = &rest[..authority_end];
    let remainder = &rest[authority_end..];
    if !remainder.is_empty() && remainder != "/" {
        return Err(DataStoreOpenError::new(
            "the object store URL must be a bare endpoint without a path",
        ));
    }
    if authority.is_empty() || authority.contains('@') {
        return Err(malformed());
    }
    let (host_field, port) = if let Some(bracketed) = authority.strip_prefix('[') {
        let Some((host, after_bracket)) = bracketed.split_once(']') else {
            return Err(malformed());
        };
        let port = after_bracket
            .strip_prefix(':')
            .map(|text| parse_port(text).ok_or_else(malformed))
            .transpose()?;
        (host.to_owned(), port)
    } else if authority.matches(':').count() > 1 {
        return Err(malformed());
    } else {
        match authority.rsplit_once(':') {
            Some((host, port_text)) => (
                host.to_owned(),
                Some(parse_port(port_text).ok_or_else(malformed)?),
            ),
            None => (authority.to_owned(), None),
        }
    };
    if host_field.is_empty() {
        return Err(malformed());
    }
    let default_port = match scheme {
        ObjectStoreScheme::Https => 443,
        ObjectStoreScheme::Http => 80,
    };
    let connect_port = port.unwrap_or(default_port);
    let loopback = matches!(
        host_field.to_ascii_lowercase().as_str(),
        "127.0.0.1" | "localhost" | "::1"
    );
    if scheme == ObjectStoreScheme::Http && !loopback {
        return Err(DataStoreOpenError::new(
            "the object store URL must use https for non-loopback hosts; http:// is accepted only for loopback endpoints",
        ));
    }
    Ok(EndpointUrl {
        scheme,
        host_header: authority.to_owned(),
        connect_host: host_field,
        connect_port,
    })
}

fn parse_port(text: &str) -> Option<u16> {
    if text.is_empty() {
        return None;
    }
    text.parse::<u16>().ok()
}

#[derive(Clone)]
struct ObjectStoreCredentials {
    access_key_id: String,
    secret_access_key: String,
}

impl ObjectStoreCredentials {
    /// Load the object store credentials from the environment.
    ///
    /// Credentials are environment-only by design: flags would leak secret material into
    /// `argv` and process listings. Missing or empty values fail closed before any request.
    ///
    /// # Errors
    ///
    /// Returns a stable health-free error naming the required variables when either is absent.
    fn from_environment() -> Result<Self, DataStoreOpenError> {
        let access_key_id = std::env::var(ENV_ACCESS_KEY_ID).unwrap_or_default();
        let secret_access_key = std::env::var(ENV_SECRET_ACCESS_KEY).unwrap_or_default();
        if access_key_id.is_empty() || secret_access_key.is_empty() {
            return Err(DataStoreOpenError::new(
                "the object store credentials are not configured; set HEALTHMD_OBJECT_STORE_ACCESS_KEY_ID and HEALTHMD_OBJECT_STORE_SECRET_ACCESS_KEY",
            ));
        }
        Ok(Self {
            access_key_id,
            secret_access_key,
        })
    }
}

// ---------------------------------------------------------------------------
// AWS Signature Version 4 (hand-written over sha2/hmac)
// ---------------------------------------------------------------------------

fn hmac_sha256(key: &[u8], data: &[u8]) -> Vec<u8> {
    let mut mac =
        Hmac::<Sha256>::new_from_slice(key).expect("HMAC-SHA-256 accepts every key length");
    mac.update(data);
    mac.finalize().into_bytes().to_vec()
}

/// Percent-encode one string per the `SigV4` canonical-encoding rules. `keep_slash` preserves
/// `/` separators (path segments); query keys and values encode `/` as `%2F`.
fn aws_percent_encode(value: &str, keep_slash: bool) -> String {
    let mut encoded = String::with_capacity(value.len());
    for byte in value.as_bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => {
                encoded.push(char::from(*byte));
            }
            b'/' if keep_slash => encoded.push('/'),
            _ => {
                use std::fmt::Write as _;
                let _ = write!(encoded, "%{byte:02X}");
            }
        }
    }
    encoded
}

/// Build the canonical query string: encoded key/value pairs sorted by encoded key.
fn canonical_query(pairs: &[(String, String)]) -> String {
    let mut encoded: Vec<(String, String)> = pairs
        .iter()
        .map(|(key, value)| {
            (
                aws_percent_encode(key, false),
                aws_percent_encode(value, false),
            )
        })
        .collect();
    encoded.sort();
    encoded
        .iter()
        .map(|(key, value)| format!("{key}={value}"))
        .collect::<Vec<_>>()
        .join("&")
}

/// Assemble the `SigV4` canonical request. `headers` must already be lowercased and sorted.
fn canonical_request(
    method: &str,
    canonical_uri: &str,
    canonical_query: &str,
    headers: &[(String, String)],
    payload_hash: &str,
) -> String {
    let mut canonical_headers = String::new();
    for (name, value) in headers {
        canonical_headers.push_str(name);
        canonical_headers.push(':');
        canonical_headers.push_str(value);
        canonical_headers.push('\n');
    }
    let signed_headers = signed_header_list(headers);
    format!(
        "{method}\n{canonical_uri}\n{canonical_query}\n{canonical_headers}\n{signed_headers}\n{payload_hash}"
    )
}

/// The `SigV4` signed-header list: lowercased names in sorted order joined by `;`.
fn signed_header_list(headers: &[(String, String)]) -> String {
    headers
        .iter()
        .map(|(name, _)| name.as_str())
        .collect::<Vec<_>>()
        .join(";")
}

/// Compute the `SigV4` signature for one request.
///
/// The caller supplies the exact signed headers (`host`, `x-amz-content-sha256`, `x-amz-date`,
/// and any extras such as `range`), the payload hash constant, and the region; the function
/// returns the signed-header list, the credential scope, and the hex signature.
#[allow(clippy::too_many_arguments)]
fn sigv4_signature(
    method: &str,
    canonical_uri: &str,
    canonical_query: &str,
    signed_headers: &[(String, String)],
    amz_date: &str,
    payload_hash: &str,
    region: &str,
    secret_access_key: &str,
) -> (String, String, String) {
    let date_scope = &amz_date[..8];
    let scope = format!("{date_scope}/{region}/{SIGV4_SERVICE}/{SIGV4_TERMINATOR}");
    let canonical = canonical_request(
        method,
        canonical_uri,
        canonical_query,
        signed_headers,
        payload_hash,
    );
    let string_to_sign = format!(
        "{SIGV4_ALGORITHM}\n{amz_date}\n{scope}\n{}",
        sha256_hex(canonical.as_bytes())
    );
    let key = hmac_sha256(
        format!("AWS4{secret_access_key}").as_bytes(),
        date_scope.as_bytes(),
    );
    let key = hmac_sha256(&key, region.as_bytes());
    let key = hmac_sha256(&key, SIGV4_SERVICE.as_bytes());
    let key = hmac_sha256(&key, SIGV4_TERMINATOR.as_bytes());
    let signature = data_backend::hex_digest(hmac_sha256(&key, string_to_sign.as_bytes()));
    (signed_header_list(signed_headers), scope, signature)
}

/// The sorted signed-header set for one store request (optionally including `range`).
fn request_signed_headers(
    host: &str,
    payload_hash: &str,
    amz_date: &str,
    range: Option<&str>,
) -> Vec<(String, String)> {
    let mut headers = vec![
        ("host".to_owned(), host.to_owned()),
        ("x-amz-content-sha256".to_owned(), payload_hash.to_owned()),
        ("x-amz-date".to_owned(), amz_date.to_owned()),
    ];
    if let Some(range) = range {
        headers.push(("range".to_owned(), range.to_owned()));
    }
    headers.sort_by(|left, right| left.0.cmp(&right.0));
    headers
}

/// Render the complete HTTP/1.1 request text (request line through the blank line) exactly as
/// sent on the wire. Shared by the transport and the unit tests so the tested artifact is the
/// shipped artifact.
#[allow(clippy::too_many_arguments)]
fn signed_request_text(
    method: &str,
    path_and_query: &str,
    host: &str,
    amz_date: &str,
    range: Option<&str>,
    access_key_id: &str,
    secret_access_key: &str,
    payload_hash: &str,
    region: &str,
) -> String {
    let (path, query) = match path_and_query.split_once('?') {
        Some((path, query)) => (path, query),
        None => (path_and_query, ""),
    };
    let signed_headers = request_signed_headers(host, payload_hash, amz_date, range);
    let (header_list, scope, signature) = sigv4_signature(
        method,
        path,
        query,
        &signed_headers,
        amz_date,
        payload_hash,
        region,
        secret_access_key,
    );
    let mut request = format!("{method} {path_and_query} HTTP/1.1\r\nHost: {host}\r\n");
    if let Some(range) = range {
        let _ = std::fmt::Write::write_fmt(&mut request, format_args!("Range: {range}\r\n"));
    }
    let _ = std::fmt::Write::write_fmt(
        &mut request,
        format_args!(
            "x-amz-content-sha256: {payload_hash}\r\nx-amz-date: {amz_date}\r\nAuthorization: {SIGV4_ALGORITHM} Credential={access_key_id}/{scope}, SignedHeaders={header_list}, Signature={signature}\r\nConnection: close\r\n\r\n"
        ),
    );
    request
}

// ---------------------------------------------------------------------------
// Minimal HTTP/1.1 transport and the frozen S3 subset
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, Debug)]
enum ObjectStoreError {
    /// `https://` egress: this build carries no TLS socket layer.
    TlsUnavailable,
    /// Connect, read, write, or timeout failure.
    Transport,
    /// `401`/`403` from the endpoint.
    AccessDenied,
    /// `404` for one object.
    NotFound,
    /// Malformed HTTP, unexpected status, or an unparseable listing page.
    InvalidResponse,
    /// The listing exceeds the supported candidate bound.
    TooManyObjects,
}

struct S3HttpResponse {
    status: u16,
    headers: Vec<(String, String)>,
    body: Vec<u8>,
}

impl S3HttpResponse {
    fn header(&self, name: &str) -> Option<&str> {
        let lower = name.to_ascii_lowercase();
        self.headers
            .iter()
            .find(|(key, _)| *key == lower)
            .map(|(_, value)| value.as_str())
    }
}

#[derive(Clone)]
struct S3Client {
    endpoint: EndpointUrl,
    bucket: String,
    prefix: String,
    credentials: ObjectStoreCredentials,
}

impl S3Client {
    /// The full object key for one artifact's store-relative path.
    fn object_key(&self, relative: &str) -> String {
        format!("{}{}", self.prefix, relative)
    }

    /// URL-encoded path-style object URL: `/bucket/key` with each path segment encoded once.
    fn object_path(bucket: &str, key: &str) -> String {
        format!(
            "/{}/{}",
            aws_percent_encode(bucket, true),
            aws_percent_encode(key, true)
        )
    }

    fn perform(
        &self,
        method: &str,
        path_and_query: &str,
        range: Option<&str>,
    ) -> Result<S3HttpResponse, ObjectStoreError> {
        if self.endpoint.scheme == ObjectStoreScheme::Https {
            return Err(ObjectStoreError::TlsUnavailable);
        }
        let amz_date = Utc::now().format("%Y%m%dT%H%M%SZ").to_string();
        let request = signed_request_text(
            method,
            path_and_query,
            &self.endpoint.host_header,
            &amz_date,
            range,
            &self.credentials.access_key_id,
            &self.credentials.secret_access_key,
            UNSIGNED_PAYLOAD,
            OBJECT_STORE_REGION,
        );
        let mut stream = self.connect()?;
        stream
            .set_write_timeout(Some(IO_TIMEOUT))
            .map_err(|_| ObjectStoreError::Transport)?;
        stream
            .set_read_timeout(Some(IO_TIMEOUT))
            .map_err(|_| ObjectStoreError::Transport)?;
        stream
            .write_all(request.as_bytes())
            .map_err(|_| ObjectStoreError::Transport)?;
        stream.flush().map_err(|_| ObjectStoreError::Transport)?;
        read_response(&mut stream, method == "HEAD")
    }

    fn connect(&self) -> Result<TcpStream, ObjectStoreError> {
        (
            self.endpoint.connect_host.as_str(),
            self.endpoint.connect_port,
        )
            .to_socket_addrs()
            .map_err(|_| ObjectStoreError::Transport)?
            .map(|address| TcpStream::connect_timeout(&address, CONNECT_TIMEOUT))
            .find_map(Result::ok)
            .ok_or(ObjectStoreError::Transport)
    }

    /// One `ListObjectsV2` page under the configured prefix.
    fn list_objects_page(&self, continuation: Option<&str>) -> Result<ListPage, ObjectStoreError> {
        let mut pairs = vec![
            ("list-type".to_owned(), "2".to_owned()),
            ("prefix".to_owned(), self.prefix.clone()),
        ];
        if let Some(token) = continuation {
            pairs.push(("continuation-token".to_owned(), token.to_owned()));
        }
        let path_and_query = format!(
            "/{}?{}",
            aws_percent_encode(&self.bucket, true),
            canonical_query(&pairs)
        );
        let response = self.perform("GET", &path_and_query, None)?;
        map_status(response.status)?;
        let body = String::from_utf8_lossy(&response.body).into_owned();
        extract_list_page(&body).map_err(|()| ObjectStoreError::InvalidResponse)
    }

    /// Every object under the configured prefix, following continuation tokens.
    fn list_objects(&self) -> Result<Vec<ListedObject>, ObjectStoreError> {
        let mut objects = Vec::new();
        let mut continuation = None;
        for _ in 0..MAXIMUM_LIST_PAGES {
            let page = self.list_objects_page(continuation.as_deref())?;
            objects.extend(page.objects);
            match (page.truncated, page.next_token) {
                (false, _) => return Ok(objects),
                (true, Some(token)) => continuation = Some(token),
                (true, None) => return Err(ObjectStoreError::InvalidResponse),
            }
        }
        Err(ObjectStoreError::TooManyObjects)
    }

    /// `HEAD` one object and return its `Content-Length`.
    fn head_object(&self, key: &str) -> Result<u64, ObjectStoreError> {
        let path = Self::object_path(&self.bucket, key);
        let response = self.perform("HEAD", &path, None)?;
        match response.status {
            200 => response
                .header("content-length")
                .and_then(|value| value.trim().parse::<u64>().ok())
                .ok_or(ObjectStoreError::InvalidResponse),
            404 => Err(ObjectStoreError::NotFound),
            401 | 403 => Err(ObjectStoreError::AccessDenied),
            _ => Err(ObjectStoreError::InvalidResponse),
        }
    }

    /// `GET` one object, optionally with a byte `Range` request (`(start, end_inclusive)`).
    fn get_object(
        &self,
        key: &str,
        range: Option<(usize, usize)>,
    ) -> Result<Vec<u8>, ObjectStoreError> {
        let path = Self::object_path(&self.bucket, key);
        let range_header = range.map(|(start, end)| format!("bytes={start}-{end}"));
        let response = self.perform("GET", &path, range_header.as_deref())?;
        match response.status {
            200 | 206 => Ok(response.body),
            404 => Err(ObjectStoreError::NotFound),
            401 | 403 => Err(ObjectStoreError::AccessDenied),
            _ => Err(ObjectStoreError::InvalidResponse),
        }
    }
}

fn map_status(status: u16) -> Result<(), ObjectStoreError> {
    match status {
        200 | 206 => Ok(()),
        401 | 403 => Err(ObjectStoreError::AccessDenied),
        404 => Err(ObjectStoreError::NotFound),
        _ => Err(ObjectStoreError::InvalidResponse),
    }
}

/// Read and parse one complete HTTP/1.1 response: `Content-Length` framing, chunked transfer
/// decoding, or connection-close framing; `HEAD` responses carry no body.
fn read_response(
    stream: &mut TcpStream,
    head_only: bool,
) -> Result<S3HttpResponse, ObjectStoreError> {
    let mut raw = Vec::new();
    let mut chunk = [0_u8; 8_192];
    let header_end = loop {
        if let Some(position) = raw.windows(4).position(|window| window == b"\r\n\r\n") {
            break position + 4;
        }
        let read = stream
            .read(&mut chunk)
            .map_err(|_| ObjectStoreError::Transport)?;
        if read == 0 {
            return Err(ObjectStoreError::InvalidResponse);
        }
        raw.extend_from_slice(&chunk[..read]);
    };
    let header_text = String::from_utf8_lossy(&raw[..header_end]).into_owned();
    let mut lines = header_text.split("\r\n");
    let status_line = lines.next().ok_or(ObjectStoreError::InvalidResponse)?;
    let status = status_line
        .split_ascii_whitespace()
        .nth(1)
        .and_then(|code| code.parse::<u16>().ok())
        .ok_or(ObjectStoreError::InvalidResponse)?;
    let headers: Vec<(String, String)> = lines
        .filter(|line| !line.is_empty())
        .map(|line| {
            let (name, value) = line
                .split_once(':')
                .ok_or(ObjectStoreError::InvalidResponse)?;
            Ok((name.trim().to_ascii_lowercase(), value.trim().to_owned()))
        })
        .collect::<Result<_, _>>()?;
    let mut body = raw[header_end..].to_vec();
    if head_only {
        return Ok(S3HttpResponse {
            status,
            headers,
            body: Vec::new(),
        });
    }
    let header = |name: &str| {
        headers
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.clone())
    };
    if header("transfer-encoding")
        .is_some_and(|value| value.to_ascii_lowercase().contains("chunked"))
    {
        while !chunked_body_complete(&body) {
            let read = stream
                .read(&mut chunk)
                .map_err(|_| ObjectStoreError::Transport)?;
            if read == 0 {
                return Err(ObjectStoreError::InvalidResponse);
            }
            body.extend_from_slice(&chunk[..read]);
        }
        body = decode_chunked_body(&body)?;
    } else if let Some(length) = header("content-length") {
        let length = length
            .trim()
            .parse::<usize>()
            .map_err(|_| ObjectStoreError::InvalidResponse)?;
        while body.len() < length {
            let read = stream
                .read(&mut chunk)
                .map_err(|_| ObjectStoreError::Transport)?;
            if read == 0 {
                return Err(ObjectStoreError::InvalidResponse);
            }
            body.extend_from_slice(&chunk[..read]);
        }
        body.truncate(length);
    } else {
        loop {
            match stream.read(&mut chunk) {
                Ok(0) | Err(_) => break,
                Ok(read) => body.extend_from_slice(&chunk[..read]),
            }
        }
    }
    Ok(S3HttpResponse {
        status,
        headers,
        body,
    })
}

fn chunked_body_complete(body: &[u8]) -> bool {
    try_decode_chunked(body).is_ok()
}

fn decode_chunked_body(body: &[u8]) -> Result<Vec<u8>, ObjectStoreError> {
    try_decode_chunked(body).map_err(|()| ObjectStoreError::InvalidResponse)
}

fn try_decode_chunked(body: &[u8]) -> Result<Vec<u8>, ()> {
    let mut decoded = Vec::new();
    let mut cursor = 0_usize;
    loop {
        let line_end = body[cursor..]
            .windows(2)
            .position(|window| window == b"\r\n")
            .map(|position| cursor + position)
            .ok_or(())?;
        let size_text = std::str::from_utf8(&body[cursor..line_end]).map_err(|_| ())?;
        let size_text = size_text.split(';').next().unwrap_or_default().trim();
        let size = usize::from_str_radix(size_text, 16).map_err(|_| ())?;
        cursor = line_end + 2;
        if size == 0 {
            return Ok(decoded);
        }
        let end = cursor.checked_add(size).ok_or(())?;
        if body.len() < end + 2 {
            return Err(());
        }
        decoded.extend_from_slice(&body[cursor..end]);
        cursor = end + 2;
    }
}

// ---------------------------------------------------------------------------
// ListObjectsV2 response extraction (hand-rolled, frozen subset)
// ---------------------------------------------------------------------------

struct ListedObject {
    key: String,
    size: u64,
    last_modified_nanos: u128,
}

struct ListPage {
    objects: Vec<ListedObject>,
    truncated: bool,
    next_token: Option<String>,
}

/// Extract the frozen `ListObjectsV2` response subset: `Contents/Key`, `Contents/Size`,
/// `Contents/LastModified`, `IsTruncated`, and `NextContinuationToken`.
///
/// Tag scanning is unambiguous for this subset because object keys escape every `<` as an XML
/// entity, so a literal tag can never occur inside key text.
fn extract_list_page(body: &str) -> Result<ListPage, ()> {
    let mut objects = Vec::new();
    let mut remainder = String::with_capacity(body.len());
    let mut cursor = 0_usize;
    while let Some(start) = body[cursor..].find("<Contents>") {
        let start = cursor + start;
        let Some(end) = body[start..].find("</Contents>") else {
            return Err(());
        };
        let end = start + end;
        let inner = &body[start + "<Contents>".len()..end];
        let key = xml_unescape(extract_element(inner, "Key").ok_or(())?);
        let size = extract_element(inner, "Size")
            .ok_or(())?
            .trim()
            .parse::<u64>()
            .map_err(|_| ())?;
        let last_modified_nanos = extract_element(inner, "LastModified")
            .and_then(|value| parse_rfc3339_nanos(value.trim()))
            .unwrap_or(0);
        objects.push(ListedObject {
            key,
            size,
            last_modified_nanos,
        });
        remainder.push_str(&body[cursor..start]);
        cursor = end + "</Contents>".len();
    }
    remainder.push_str(&body[cursor..]);
    let truncated = extract_element(&remainder, "IsTruncated")
        .is_some_and(|value| value.trim().eq_ignore_ascii_case("true"));
    let next_token = extract_element(&remainder, "NextContinuationToken")
        .map(|value| xml_unescape(value.trim()));
    if truncated && next_token.is_none() {
        return Err(());
    }
    Ok(ListPage {
        objects,
        truncated,
        next_token,
    })
}

fn extract_element<'a>(haystack: &'a str, tag: &str) -> Option<&'a str> {
    let open = format!("<{tag}>");
    let close = format!("</{tag}>");
    let start = haystack.find(&open)? + open.len();
    let end = haystack[start..].find(&close)? + start;
    Some(&haystack[start..end])
}

/// Unescape the minimal frozen entity set (`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`).
/// Unrecognized sequences are preserved verbatim.
fn xml_unescape(value: &str) -> String {
    if !value.contains('&') {
        return value.to_owned();
    }
    let mut out = String::with_capacity(value.len());
    let mut rest = value;
    while let Some(position) = rest.find('&') {
        out.push_str(&rest[..position]);
        let Some(end) = rest[position..].find(';').map(|offset| position + offset) else {
            out.push('&');
            rest = &rest[position + 1..];
            continue;
        };
        match &rest[position + 1..end] {
            "amp" => out.push('&'),
            "lt" => out.push('<'),
            "gt" => out.push('>'),
            "quot" => out.push('"'),
            "apos" => out.push('\''),
            _ => out.push_str(&rest[position..=end]),
        }
        rest = &rest[end + 1..];
    }
    out.push_str(rest);
    out
}

fn parse_rfc3339_nanos(value: &str) -> Option<u128> {
    let instant = DateTime::parse_from_rfc3339(value).ok()?;
    let elapsed = instant
        .with_timezone(&Utc)
        .signed_duration_since(DateTime::from_timestamp(0, 0)?);
    let nanos = elapsed.num_nanoseconds()?;
    u128::try_from(nanos).ok()
}

// ---------------------------------------------------------------------------
// Listing → candidate objects → index (mirrors the directory store lifecycle)
// ---------------------------------------------------------------------------

struct CandidateObject {
    relative_path: String,
    key: String,
    byte_count: u64,
    last_modified_nanos: u128,
}

/// Filter one listing to supported-extension candidate artifacts, mirroring
/// `data_backend::scan_source_files`: unsupported extensions are never candidates, paths are
/// bounded, and the result is sorted by store-relative path.
fn candidate_objects(
    prefix: &str,
    objects: &[ListedObject],
) -> Result<Vec<CandidateObject>, DataStoreOpenError> {
    let mut candidates = Vec::new();
    for object in objects {
        let Some(relative_path) = object.key.strip_prefix(prefix) else {
            continue;
        };
        if relative_path.is_empty() {
            continue;
        }
        if !supported_key_extension(relative_path) {
            continue;
        }
        if relative_path.len() > MAXIMUM_RELATIVE_KEY_BYTES {
            return Err(DataStoreOpenError::new(
                "an Agent Data artifact key exceeds the supported bound",
            ));
        }
        candidates.push(CandidateObject {
            relative_path: relative_path.to_owned(),
            key: object.key.clone(),
            byte_count: object.size,
            last_modified_nanos: object.last_modified_nanos,
        });
    }
    if candidates.len() > MAXIMUM_SOURCE_FILES {
        return Err(DataStoreOpenError::new(
            "the object store contains too many candidate objects",
        ));
    }
    candidates.sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
    Ok(candidates)
}

fn supported_key_extension(relative_path: &str) -> bool {
    Path::new(relative_path)
        .extension()
        .and_then(|value| value.to_str())
        .is_some_and(|value| {
            matches!(
                value.to_ascii_lowercase().as_str(),
                "json" | "jsonl" | "ndjson"
            )
        })
}

/// Fingerprint the candidate listing, mirroring the directory store's source fingerprint
/// shape (relative path, byte count, modification marker) under a store-specific label.
fn candidates_fingerprint(candidates: &[CandidateObject]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(b"healthmd.agent-data.object-store-fingerprint.v1\n");
    for candidate in candidates {
        hasher.update(candidate.relative_path.len().to_be_bytes());
        hasher.update(candidate.relative_path.as_bytes());
        hasher.update(candidate.byte_count.to_be_bytes());
        hasher.update(candidate.last_modified_nanos.to_be_bytes());
    }
    data_backend::hex_digest(hasher.finalize())
}

/// Fetch and parse one candidate object. Network, integrity, and parsing failures make the
/// candidate invalid (counted, never queryable), exactly like an unreadable local file in the
/// directory store.
fn index_candidate(
    client: &S3Client,
    candidate: &CandidateObject,
) -> Result<Option<(ArtifactEntry, Vec<RecordEntry>)>, ()> {
    if candidate.byte_count > MAXIMUM_OBJECT_BYTES {
        return Err(());
    }
    let bytes = client.get_object(&candidate.key, None).map_err(|_| ())?;
    if u64::try_from(bytes.len()).unwrap_or(u64::MAX) != candidate.byte_count {
        return Err(());
    }
    parse_artifact_bytes(&candidate.relative_path, candidate.byte_count, &bytes)
}

/// Build the stable index over the candidate listing, re-listing at the end to prove the store
/// did not change during indexing (mirroring `data_backend::build_stable_index`).
fn build_object_index(
    client: &S3Client,
    candidates: &[CandidateObject],
    expected_fingerprint: &str,
) -> Result<ArtifactIndex, DataStoreOpenError> {
    let mut artifacts = Vec::new();
    let mut records = Vec::new();
    let mut seen_artifacts = BTreeSet::new();
    let mut ignored_file_count = 0_usize;
    let mut invalid_artifact_count = 0_usize;

    for candidate in candidates {
        match index_candidate(client, candidate) {
            Ok(Some((mut artifact, mut artifact_records))) => {
                if !seen_artifacts.insert(artifact.artifact_id.clone()) {
                    ignored_file_count += 1;
                    continue;
                }
                artifact.record_count = artifact_records.len();
                artifacts.push(artifact);
                records.append(&mut artifact_records);
            }
            Ok(None) => ignored_file_count += 1,
            Err(()) => invalid_artifact_count += 1,
        }
    }
    artifacts.sort_by(|left, right| left.artifact_id.cmp(&right.artifact_id));
    records.sort_by(record_order);

    let current = client.list_objects().map_err(object_open_error)?;
    let candidates = candidate_objects(&client.prefix, &current)?;
    if candidates_fingerprint(&candidates) != expected_fingerprint {
        return Err(DataStoreOpenError::new(
            "the object store changed during indexing",
        ));
    }
    finalize_index(
        expected_fingerprint.to_owned(),
        artifacts,
        records,
        ignored_file_count,
        invalid_artifact_count,
    )
}

fn object_open_error(error: ObjectStoreError) -> DataStoreOpenError {
    match error {
        ObjectStoreError::TlsUnavailable => DataStoreOpenError::new(
            "the https object-store transport is not available in this build; use a loopback http endpoint for local testing",
        ),
        ObjectStoreError::Transport => {
            DataStoreOpenError::new("the object store endpoint could not be reached")
        }
        ObjectStoreError::AccessDenied => {
            DataStoreOpenError::new("the object store rejected the request")
        }
        ObjectStoreError::NotFound => {
            DataStoreOpenError::new("the object store object was not found")
        }
        ObjectStoreError::InvalidResponse => {
            DataStoreOpenError::new("the object store response was invalid")
        }
        ObjectStoreError::TooManyObjects => {
            DataStoreOpenError::new("the object store contains too many candidate objects")
        }
    }
}

fn object_backend_error(_error: ObjectStoreError) -> BackendError {
    backend_failure("healthmd_agent_index_failed")
}

fn open_to_backend_failure(_error: DataStoreOpenError) -> BackendError {
    backend_failure("healthmd_agent_index_failed")
}

// ---------------------------------------------------------------------------
// The store
// ---------------------------------------------------------------------------

struct ObjectStoreShared {
    index: std::sync::RwLock<Arc<ArtifactIndex>>,
    refresh: std::sync::Mutex<()>,
    verified: std::sync::Mutex<HashMap<String, Arc<Vec<u8>>>>,
}

/// Serves the Agent Data contract from a read-only S3-compatible object store prefix.
///
/// Only list, head, and get requests are ever issued; no upload, delete, or write path
/// exists. Grant semantics, the five-tool surface, and every response contract are identical
/// to the directory and database stores; receipts report the backing class `object_store`.
pub struct ObjectStoreArtifactStore {
    client: S3Client,
    grant: Arc<AgentDataGrant>,
    cursor_key: [u8; 32],
    index_path: PathBuf,
    shared: Arc<ObjectStoreShared>,
}

impl ObjectStoreArtifactStore {
    /// Open a read-only object store prefix and build its external index.
    ///
    /// # Errors
    ///
    /// Returns a stable health-free error when the URL policy, bucket, prefix, credentials,
    /// grant, index path, listing, or artifact validation fails. No credential material is
    /// ever included in an error.
    #[allow(clippy::needless_pass_by_value)]
    pub fn open(options: DataServeOptions) -> Result<Self, DataStoreOpenError> {
        let DataServeOptions::ObjectStore {
            url,
            bucket,
            prefix,
            grant,
            index,
        } = &options
        else {
            return Err(DataStoreOpenError::new(
                "the object store requires --object-store-url backing options",
            ));
        };
        let endpoint = parse_endpoint_url(url)?;
        let bucket = validated_bucket_name(bucket)?;
        let prefix = normalized_prefix(prefix.as_deref())?;
        let credentials = ObjectStoreCredentials::from_environment()?;

        // The local grant gates everything; the store is just bytes. Unlike the directory
        // store there is no containment rule against the remote backing, and a grant-shaped
        // object inside the bucket is ordinary unrecognized content — never loaded as a grant.
        let grant_path = data_backend::validated_regular_file(grant, MAXIMUM_GRANT_BYTES)?;
        let grant_bytes = fs::read(&grant_path)
            .map_err(|_| DataStoreOpenError::new("the Agent Data grant could not be read"))?;
        let grant_value = serde_json::from_slice(&grant_bytes)
            .map_err(|_| DataStoreOpenError::new("the Agent Data grant is not valid JSON"))?;
        let grant = AgentDataGrant::from_value(grant_value)
            .map_err(|_| DataStoreOpenError::new("the Agent Data grant is invalid"))?;

        let client = S3Client {
            endpoint,
            bucket: bucket.clone(),
            prefix: prefix.clone(),
            credentials,
        };
        let root_binding = object_store_binding(&client);
        let index_path = match index {
            Some(path) => validated_object_index_path(path)?,
            None => default_index_path(&root_binding)?,
        };
        let listing = client.list_objects().map_err(object_open_error)?;
        let candidates = candidate_objects(&prefix, &listing)?;
        let fingerprint = candidates_fingerprint(&candidates);
        let index = build_object_index(&client, &candidates, &fingerprint)?;
        persist_index(&index_path, &index)?;

        let mut cursor_key = [0_u8; 32];
        getrandom::fill(&mut cursor_key)
            .map_err(|_| DataStoreOpenError::new("secure cursor state could not be initialized"))?;

        Ok(Self {
            client,
            grant: Arc::new(grant),
            cursor_key,
            index_path,
            shared: Arc::new(ObjectStoreShared {
                index: std::sync::RwLock::new(Arc::new(index)),
                refresh: std::sync::Mutex::new(()),
                verified: std::sync::Mutex::new(HashMap::new()),
            }),
        })
    }
}

fn validated_bucket_name(bucket: &str) -> Result<String, DataStoreOpenError> {
    if bucket.is_empty()
        || bucket.len() > 255
        || bucket
            .chars()
            .any(|character| matches!(character, '/' | '?' | '#' | ' ') || character.is_control())
    {
        return Err(DataStoreOpenError::new(
            "the object store bucket name is invalid",
        ));
    }
    Ok(bucket.to_owned())
}

/// Normalize the optional prefix: leading `/` is stripped, a non-empty prefix gains a
/// trailing `/`, and an effectively empty prefix selects the whole bucket.
fn normalized_prefix(prefix: Option<&str>) -> Result<String, DataStoreOpenError> {
    let Some(prefix) = prefix else {
        return Ok(String::new());
    };
    let trimmed = prefix.trim_start_matches('/');
    if trimmed.is_empty() {
        return Ok(String::new());
    }
    if trimmed.len() > MAXIMUM_RELATIVE_KEY_BYTES
        || trimmed
            .chars()
            .any(|character| matches!(character, '?' | '#') || character.is_control())
    {
        return Err(DataStoreOpenError::new(
            "the object store prefix is invalid",
        ));
    }
    if trimmed.ends_with('/') {
        Ok(trimmed.to_owned())
    } else {
        Ok(format!("{trimmed}/"))
    }
}

fn validated_object_index_path(path: &Path) -> Result<PathBuf, DataStoreOpenError> {
    if !path.is_absolute() {
        return Err(DataStoreOpenError::new(
            "the Agent Data index path must be absolute",
        ));
    }
    if fs::symlink_metadata(path)
        .is_ok_and(|metadata| metadata.file_type().is_symlink() || !metadata.is_file())
    {
        return Err(DataStoreOpenError::new(
            "the Agent Data index path must not be a symlink",
        ));
    }
    let parent = path.parent().ok_or_else(|| {
        DataStoreOpenError::new("the Agent Data index path has no parent directory")
    })?;
    prepare_private_directory(parent)?;
    let parent = parent
        .canonicalize()
        .map_err(|_| DataStoreOpenError::new("the Agent Data index directory is inaccessible"))?;
    let resolved = parent
        .join(path.file_name().ok_or_else(|| {
            DataStoreOpenError::new("the Agent Data index path has no file name")
        })?);
    Ok(resolved)
}

fn object_store_binding(client: &S3Client) -> String {
    let mut hasher = Sha256::new();
    hasher.update(b"healthmd.agent-data.object-store-binding.v1\n");
    hasher.update(client.endpoint.host_header.as_bytes());
    hasher.update(b"\n");
    hasher.update(client.bucket.as_bytes());
    hasher.update(b"\n");
    hasher.update(client.prefix.as_bytes());
    data_backend::hex_digest(hasher.finalize())
}

/// Reload the in-memory index when the object listing changed (mirrors the directory store's
/// per-query re-scan, double-checked under the refresh mutex).
fn current_index(
    shared: &Arc<ObjectStoreShared>,
    client: &S3Client,
    index_path: &Path,
) -> Result<Arc<ArtifactIndex>, BackendError> {
    refresh_if_needed(shared, client, index_path)?;
    let index = shared
        .index
        .read()
        .map_err(|_| backend_failure("healthmd_agent_index_failed"))?;
    Ok(Arc::clone(&index))
}

fn refresh_if_needed(
    shared: &Arc<ObjectStoreShared>,
    client: &S3Client,
    index_path: &Path,
) -> Result<(), BackendError> {
    let listing = client.list_objects().map_err(object_backend_error)?;
    let candidates =
        candidate_objects(&client.prefix, &listing).map_err(open_to_backend_failure)?;
    let fingerprint = candidates_fingerprint(&candidates);
    {
        let index = shared
            .index
            .read()
            .map_err(|_| backend_failure("healthmd_agent_index_failed"))?;
        if index.source_fingerprint == fingerprint {
            return Ok(());
        }
    }
    let _refresh_guard = shared
        .refresh
        .lock()
        .map_err(|_| backend_failure("healthmd_agent_index_failed"))?;
    {
        let index = shared
            .index
            .read()
            .map_err(|_| backend_failure("healthmd_agent_index_failed"))?;
        if index.source_fingerprint == fingerprint {
            return Ok(());
        }
    }
    let rebuilt =
        build_object_index(client, &candidates, &fingerprint).map_err(open_to_backend_failure)?;
    persist_index(index_path, &rebuilt).map_err(open_to_backend_failure)?;
    shared
        .verified
        .lock()
        .map_err(|_| backend_failure("healthmd_agent_index_failed"))?
        .clear();
    *shared
        .index
        .write()
        .map_err(|_| backend_failure("healthmd_agent_index_failed"))? = Arc::new(rebuilt);
    Ok(())
}

/// Reads verified artifact bytes from the object store.
///
/// Every returned byte window is verified against the indexed SHA-256; verified whole objects
/// are cached (bounded) so chunked reads of one artifact fetch its bytes once per store
/// instance. Remote mutation between queries invalidates cursors through the per-query
/// re-list fingerprint exactly like the directory store.
pub(super) struct ObjectByteSource {
    client: S3Client,
    shared: Arc<ObjectStoreShared>,
}

impl ObjectByteSource {
    fn new(client: S3Client, shared: Arc<ObjectStoreShared>) -> Self {
        Self { client, shared }
    }

    fn verified_bytes(&self, artifact: &ArtifactEntry) -> Result<Arc<Vec<u8>>, BackendError> {
        if let Ok(cache) = self.shared.verified.lock() {
            if let Some(cached) = cache.get(&artifact.artifact_id) {
                return Ok(Arc::clone(cached));
            }
        }
        let key = self.client.object_key(&artifact.relative_path);
        // Fast-fail when the object's size already drifted from the index.
        match self.client.head_object(&key) {
            Ok(length) if length == artifact.byte_count => {}
            _ => return Err(backend_failure("healthmd_agent_source_changed")),
        }
        let bytes = self
            .client
            .get_object(&key, None)
            .map_err(|_| backend_failure("healthmd_agent_source_changed"))?;
        if u64::try_from(bytes.len()).unwrap_or(u64::MAX) != artifact.byte_count
            || sha256_hex(&bytes) != artifact.artifact_id
        {
            return Err(backend_failure("healthmd_agent_source_changed"));
        }
        let bytes = Arc::new(bytes);
        if let Ok(mut cache) = self.shared.verified.lock() {
            if cache.len() >= MAXIMUM_VERIFIED_CACHE_ARTIFACTS {
                cache.clear();
            }
            cache.insert(artifact.artifact_id.clone(), Arc::clone(&bytes));
        }
        Ok(bytes)
    }
}

impl ArtifactByteSource for ObjectByteSource {
    fn full_bytes(&self, artifact: &ArtifactEntry) -> Result<Arc<Vec<u8>>, BackendError> {
        self.verified_bytes(artifact)
    }

    fn verified_chunk(
        &self,
        artifact: &ArtifactEntry,
        offset: usize,
        maximum_bytes: usize,
    ) -> Result<(Vec<u8>, usize), BackendError> {
        let bytes = self.verified_bytes(artifact)?;
        let total_byte_count = usize::try_from(artifact.byte_count)
            .map_err(|_| backend_failure("healthmd_agent_source_changed"))?;
        if offset > total_byte_count {
            return Err(data_backend::invalid_cursor());
        }
        let end = offset.saturating_add(maximum_bytes).min(total_byte_count);
        Ok((bytes[offset..end].to_vec(), total_byte_count))
    }

    fn verified_ndjson_line(
        &self,
        artifact: &ArtifactEntry,
        target_line: usize,
    ) -> Result<Vec<u8>, BackendError> {
        let bytes = self.verified_bytes(artifact)?;
        let mut selected = None;
        let mut line_number = 0_usize;
        for line in bytes.split_inclusive(|byte| *byte == b'\n') {
            line_number += 1;
            if line.len() > MAXIMUM_NDJSON_LINE_BYTES {
                return Err(backend_failure("healthmd_agent_source_changed"));
            }
            if line_number == target_line {
                let mut value = line.to_vec();
                if value.last() == Some(&b'\n') {
                    value.pop();
                    if value.last() == Some(&b'\r') {
                        value.pop();
                    }
                }
                selected = Some(value);
            }
        }
        selected.ok_or_else(|| backend_failure("healthmd_agent_source_changed"))
    }
}

#[async_trait]
impl ArtifactStore for ObjectStoreArtifactStore {
    fn capabilities(&self) -> BackendCapabilities {
        BackendCapabilities {
            source_kind: "artifact_store".to_owned(),
            transport: "s3_object_store".to_owned(),
            supports_queries: true,
            supports_local_file_exports: false,
            requires_foreground_source: false,
            instructions: "Use the fixed Agent Data tools to read only records permitted by the configured grant. The object store is served read-only; only list, head, and get requests are ever issued.".to_owned(),
        }
    }

    async fn readiness(&self, _context: &CallContext) -> Result<Value, BackendError> {
        let shared = Arc::clone(&self.shared);
        let client = self.client.clone();
        let index_path = self.index_path.clone();
        let index =
            tokio::task::spawn_blocking(move || current_index(&shared, &client, &index_path))
                .await
                .map_err(|_| backend_failure("healthmd_agent_index_failed"))??;
        Ok(json!({
            "schema": "healthmd.agent_data_readiness",
            "schema_version": 1,
            "ready": true,
            "source_kind": "object_store",
            "artifact_count": index.artifacts.len(),
            "record_count": index.records.len(),
            "index_revision": index.index_revision,
            "requires_foreground_source": false
        }))
    }

    async fn doctor(&self, _context: &CallContext) -> Result<Value, BackendError> {
        let shared = Arc::clone(&self.shared);
        let client = self.client.clone();
        let index_path = self.index_path.clone();
        let index =
            tokio::task::spawn_blocking(move || current_index(&shared, &client, &index_path))
                .await
                .map_err(|_| backend_failure("healthmd_agent_index_failed"))??;
        Ok(json!({
            "schema": "healthmd.agent_data_diagnostics",
            "schema_version": 1,
            "ready": true,
            "source_kind": "object_store",
            "artifact_count": index.artifacts.len(),
            "record_count": index.records.len(),
            "ignored_file_count": index.ignored_file_count,
            "invalid_artifact_count": index.invalid_artifact_count,
            "index_revision": index.index_revision,
            "source_modified": false
        }))
    }

    async fn query_page(
        &self,
        context: &CallContext,
        request: AgentDataQueryRequest,
    ) -> Result<Value, BackendError> {
        if context.cancellation.is_cancelled() {
            return Err(BackendError::new(
                "healthmd_request_cancelled",
                "The Agent Data request was cancelled.",
            ));
        }
        let grant = Arc::clone(&self.grant);
        let cursor_key = self.cursor_key;
        let shared = Arc::clone(&self.shared);
        let client = self.client.clone();
        let index_path = self.index_path.clone();
        let result = tokio::task::spawn_blocking(move || {
            let index = current_index(&shared, &client, &index_path)?;
            let source = ObjectByteSource::new(client, shared);
            execute_query(
                &source,
                "object_store",
                &index,
                &grant,
                &cursor_key,
                &request,
            )
        })
        .await
        .map_err(|_| backend_failure("healthmd_agent_query_failed"))??;
        if context.cancellation.is_cancelled() {
            return Err(BackendError::new(
                "healthmd_request_cancelled",
                "The Agent Data request was cancelled.",
            ));
        }
        Ok(result)
    }
}

impl fmt::Debug for ObjectStoreArtifactStore {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ObjectStoreArtifactStore")
            .finish_non_exhaustive()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const EMPTY_PAYLOAD_SHA256: &str =
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

    #[test]
    fn hmac_sha256_matches_rfc_4231_vectors() {
        let vectors: [(&str, Vec<u8>, Vec<u8>, &str); 7] = [
            (
                "test case 1",
                vec![0x0b; 20],
                b"Hi There".to_vec(),
                "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
            ),
            (
                "test case 2",
                b"Jefe".to_vec(),
                b"what do ya want for nothing?".to_vec(),
                "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
            ),
            (
                "test case 3",
                vec![0xaa; 20],
                vec![0xdd; 50],
                "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe",
            ),
            (
                "test case 4",
                (1_u8..=25).collect(),
                vec![0xcd; 50],
                "82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b",
            ),
            (
                "test case 5",
                vec![0x0c; 20],
                b"Test With Truncation".to_vec(),
                "a3b6167473100ee06e0c796c2955552bfa6f7c0a6a8aef8b93f860aab0cd20c5",
            ),
            (
                "test case 6",
                vec![0xaa; 131],
                b"Test Using Larger Than Block-Size Key - Hash Key First".to_vec(),
                "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54",
            ),
            (
                "test case 7",
                vec![0xaa; 131],
                b"This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm.".to_vec(),
                "9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2",
            ),
        ];
        for (name, key, data, expected) in vectors {
            assert_eq!(
                data_backend::hex_digest(hmac_sha256(&key, &data)),
                expected,
                "{name}"
            );
        }
    }

    /// The frozen AWS `SigV4` known-answer example: GET object with `Range: bytes=0-9` from the
    /// AWS Signature Version 4 documentation (canonical-request hash and signature as printed
    /// there). The store always signs with `UNSIGNED-PAYLOAD`; this vector exercises the same
    /// pipeline with the documentation's empty-body payload hash.
    #[test]
    fn sigv4_matches_the_frozen_aws_get_object_known_answer() {
        let signed_headers = request_signed_headers(
            "examplebucket.s3.amazonaws.com",
            EMPTY_PAYLOAD_SHA256,
            "20130524T000000Z",
            Some("bytes=0-9"),
        );
        assert_eq!(
            signed_header_list(&signed_headers),
            "host;range;x-amz-content-sha256;x-amz-date"
        );
        let canonical = canonical_request(
            "GET",
            "/test.txt",
            "",
            &signed_headers,
            EMPTY_PAYLOAD_SHA256,
        );
        assert_eq!(
            canonical,
            "GET\n/test.txt\n\nhost:examplebucket.s3.amazonaws.com\nrange:bytes=0-9\n\
             x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n\
             x-amz-date:20130524T000000Z\n\nhost;range;x-amz-content-sha256;x-amz-date\n\
             e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert_eq!(
            sha256_hex(canonical.as_bytes()),
            "7344ae5b7ee6c3e7e6b0fe0640412a37625d1fbfff95c48bbb2dc43964946972"
        );
        let (header_list, scope, signature) = sigv4_signature(
            "GET",
            "/test.txt",
            "",
            &signed_headers,
            "20130524T000000Z",
            EMPTY_PAYLOAD_SHA256,
            "us-east-1",
            "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        );
        assert_eq!(header_list, "host;range;x-amz-content-sha256;x-amz-date");
        assert_eq!(scope, "20130524/us-east-1/s3/aws4_request");
        assert_eq!(
            signature,
            "f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41"
        );
    }

    #[test]
    fn signed_request_text_carries_the_range_and_authorization_headers() {
        let request = signed_request_text(
            "GET",
            "/healthmd-exports/day%20one.json",
            "127.0.0.1:9876",
            "20130524T000000Z",
            Some("bytes=0-9"),
            "AKIDEXAMPLE",
            "secret",
            UNSIGNED_PAYLOAD,
            "auto",
        );
        let lines: Vec<&str> = request.split("\r\n").collect();
        assert_eq!(lines[0], "GET /healthmd-exports/day%20one.json HTTP/1.1");
        assert_eq!(lines[1], "Host: 127.0.0.1:9876");
        assert_eq!(lines[2], "Range: bytes=0-9");
        assert_eq!(lines[3], "x-amz-content-sha256: UNSIGNED-PAYLOAD");
        assert_eq!(lines[4], "x-amz-date: 20130524T000000Z");
        assert!(lines[5].starts_with("Authorization: AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20130524/auto/s3/aws4_request, SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, Signature="));
        assert_eq!(lines[6], "Connection: close");
        assert_eq!(lines[7], "");
        assert!(request.ends_with("\r\n\r\n"));
    }

    #[test]
    fn url_policy_requires_https_off_loopback_and_allows_loopback_http() {
        for raw in [
            "https://accountid.r2.cloudflarestorage.com",
            "https://s3.us-east-1.amazonaws.com:8443",
            "http://127.0.0.1:9876",
            "http://localhost",
            "http://[::1]:9876",
        ] {
            assert!(parse_endpoint_url(raw).is_ok(), "{raw} must be accepted");
        }
        for raw in [
            "http://accountid.r2.cloudflarestorage.com",
            "http://example.com",
            "ftp://127.0.0.1:9876",
            "accountid.r2.cloudflarestorage.com",
            "https://user:secret@accountid.r2.cloudflarestorage.com",
            "https://accountid.r2.cloudflarestorage.com/prefix",
            "https://accountid.r2.cloudflarestorage.com?query=1",
            "https://accountid.r2.cloudflarestorage.com#fragment",
            "https://",
            "https://host:notaport",
        ] {
            assert!(parse_endpoint_url(raw).is_err(), "{raw} must be rejected");
        }
        let endpoint = parse_endpoint_url("https://example.com").expect("default port");
        assert_eq!(endpoint.connect_port, 443);
        let endpoint = parse_endpoint_url("http://[::1]:9876").expect("ipv6 loopback");
        assert_eq!(endpoint.host_header, "[::1]:9876");
        assert_eq!(endpoint.connect_host, "::1");
        assert_eq!(endpoint.connect_port, 9876);
    }

    #[test]
    fn prefix_and_bucket_validation_normalize_and_reject() {
        assert_eq!(normalized_prefix(None).expect("none"), "");
        assert_eq!(normalized_prefix(Some("")).expect("empty"), "");
        assert_eq!(
            normalized_prefix(Some("exports/")).expect("kept"),
            "exports/"
        );
        assert_eq!(
            normalized_prefix(Some("/exports")).expect("gained slash"),
            "exports/"
        );
        assert!(normalized_prefix(Some("exports?x")).is_err());
        assert!(normalized_prefix(Some(&"x".repeat(4_097))).is_err());

        assert_eq!(
            validated_bucket_name("healthmd-exports").expect("valid bucket"),
            "healthmd-exports"
        );
        for bucket in ["", "a/b", "a?b", "a b", &"a".repeat(256)] {
            assert!(validated_bucket_name(bucket).is_err(), "{bucket:?} invalid");
        }
    }

    #[test]
    fn canonical_query_sorts_and_percent_encodes() {
        let query = canonical_query(&[
            ("prefix".to_owned(), "exports/2026 a&b".to_owned()),
            ("list-type".to_owned(), "2".to_owned()),
            ("continuation-token".to_owned(), "abc+/=".to_owned()),
        ]);
        assert_eq!(
            query,
            "continuation-token=abc%2B%2F%3D&list-type=2&prefix=exports%2F2026%20a%26b"
        );
    }

    #[test]
    fn object_paths_are_percent_encoded_once() {
        assert_eq!(
            S3Client::object_path("healthmd-exports", "day.json"),
            "/healthmd-exports/day.json"
        );
        assert_eq!(
            S3Client::object_path("healthmd-exports", "2026 exports/day one.json"),
            "/healthmd-exports/2026%20exports/day%20one.json"
        );
        assert_eq!(
            S3Client::object_path("healthmd-exports", "plus+tilde~.json"),
            "/healthmd-exports/plus%2Btilde~.json"
        );
        assert_eq!(
            S3Client::object_path("healthmd-exports", "résumé.json"),
            "/healthmd-exports/r%C3%A9sum%C3%A9.json"
        );
    }

    #[test]
    fn list_page_extraction_covers_the_frozen_subset() {
        let page = r#"<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <Name>healthmd-exports</Name>
  <Prefix>exports/</Prefix>
  <KeyCount>2</KeyCount>
  <MaxKeys>1</MaxKeys>
  <IsTruncated>true</IsTruncated>
  <NextContinuationToken>1ueGcxLPRx1Tr/XYExHnhbYLgveDs2J/wm36Hy4vbOwM=</NextContinuationToken>
  <Contents>
    <Key>exports/day &amp; night.json</Key>
    <LastModified>2026-01-02T03:04:05.000Z</LastModified>
    <ETag>&quot;abc123&quot;</ETag>
    <Size>42</Size>
    <StorageClass>STANDARD</StorageClass>
  </Contents>
</ListBucketResult>"#;
        let extracted = extract_list_page(page).expect("page extracts");
        assert_eq!(extracted.objects.len(), 1);
        assert_eq!(extracted.objects[0].key, "exports/day & night.json");
        assert_eq!(extracted.objects[0].size, 42);
        assert_eq!(
            extracted.objects[0].last_modified_nanos,
            1_767_323_045_000_000_000
        );
        assert!(extracted.truncated);
        assert_eq!(
            extracted.next_token.as_deref(),
            Some("1ueGcxLPRx1Tr/XYExHnhbYLgveDs2J/wm36Hy4vbOwM=")
        );

        let complete = r"<ListBucketResult><IsTruncated>false</IsTruncated>
        <Contents><Key>k.json</Key><Size>7</Size></Contents></ListBucketResult>";
        let extracted = extract_list_page(complete).expect("complete page");
        assert!(!extracted.truncated);
        assert_eq!(extracted.next_token, None);

        // Truncated without a continuation token is an invalid page.
        assert!(
            extract_list_page(
                "<ListBucketResult><IsTruncated>true</IsTruncated></ListBucketResult>"
            )
            .is_err()
        );
        // An unparseable size is an invalid page.
        assert!(extract_list_page("<Contents><Key>k</Key><Size>NaN</Size></Contents>").is_err());
    }

    #[test]
    fn xml_unescape_handles_the_frozen_entity_set_verbatim_unknowns() {
        assert_eq!(xml_unescape("a&amp;b"), "a&b");
        assert_eq!(xml_unescape("&lt;&gt;&quot;&apos;"), "<>\"'");
        assert_eq!(xml_unescape("plain"), "plain");
        assert_eq!(xml_unescape("a&unknown;b"), "a&unknown;b");
        assert_eq!(xml_unescape("a&"), "a&");
    }

    #[test]
    fn candidate_objects_mirror_the_directory_scan_rules() {
        let objects = [
            ListedObject {
                key: "exports/notes.txt".to_owned(),
                size: 3,
                last_modified_nanos: 1,
            },
            ListedObject {
                key: "exports/day.json".to_owned(),
                size: 10,
                last_modified_nanos: 2,
            },
            ListedObject {
                key: "exports/sub/night.ndjson".to_owned(),
                size: 20,
                last_modified_nanos: 3,
            },
            ListedObject {
                key: "other/day.json".to_owned(),
                size: 30,
                last_modified_nanos: 4,
            },
        ];
        let candidates = candidate_objects("exports/", &objects).expect("candidates");
        let paths: Vec<&str> = candidates
            .iter()
            .map(|candidate| candidate.relative_path.as_str())
            .collect();
        assert_eq!(paths, ["day.json", "sub/night.ndjson"]);
        assert_eq!(candidates[0].key, "exports/day.json");
    }
}
