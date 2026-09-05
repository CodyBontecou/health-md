//! Self-hosted reference gateway for Agent Data ingestion protocol v1.
//!
//! `healthmd data ingest-serve` fronts the SAME `SQLite` ingestion machinery
//! as `healthmd data ingest` with a minimal std-only HTTP/1.1 listener on
//! loopback. One `POST /v1/ingest` request carries one `\n`-terminated
//! `healthmd.agent_data_ingest` v1 manifest line followed immediately by the
//! exact artifact bytes (`Content-Type: application/x-healthmd-agent-data-ingest`,
//! exact `Content-Length`, `Connection: close` per request — no keep-alive and
//! no chunked transfer encoding in v1). Every validated outcome answers
//! `HTTP 200` with the same `healthmd.agent_ingest_response` v1 receipt the
//! local command prints; rejections are protocol outcomes, never HTTP error
//! statuses. Transport-level failures (oversize, wrong method, unknown path,
//! wrong media type, malformed request) answer health-free, path-free
//! code+message JSON errors, and a connection that closes before the full
//! declared body arrives is simply closed from the server side with NO
//! receipt — the phone-side retryable class.
//!
//! The listener policy mirrors `serve_data_http`'s unauthenticated posture
//! exactly (same flag names, same defaults, same validation): loopback-only
//! bind, loopback `Host` values accepted by default with non-loopback hosts
//! rejected until allowlisted, and any browser `Origin` rejected until
//! explicitly allowlisted — all validated before the database is opened or
//! created. The reference serves plain HTTP on loopback; a hosted deployment
//! terminates TLS in a co-resident reverse proxy in front of this listener
//! and never exposes it directly.
//!
//! Concurrency model: a std thread-per-connection accept loop (documented
//! choice). Each connection carries exactly one `Connection: close` request,
//! and each request opens its own `SQLite` connection, so no connection state
//! is shared beyond the immutable listener policy and database path. This is
//! deliberately minimal for the reference; the hosted gateway is a separate
//! later cycle.

use serde_json::{Value, json};
use std::{
    fmt,
    io::{BufRead, BufReader, Read as _, Write as _},
    net::{IpAddr, SocketAddr, TcpListener, TcpStream},
    path::{Path, PathBuf},
    sync::Arc,
    time::Duration,
};

use super::DataStoreOpenError;
use super::data_sqlite;
use super::ingest::{
    INGEST_MANIFEST_LINE_BOUND_BYTES, Rejection, ingest_gateway_upload, rejected_receipt,
};

/// Body bound: the 64 MiB artifact bound plus 64 KiB of manifest framing.
const MAXIMUM_REQUEST_BYTES: u64 = 67_108_864 + 65_536;
/// Bound for one request-line or header line.
const MAXIMUM_HEADER_LINE_BYTES: usize = 8_192;
/// Bound for the header block of one request.
const MAXIMUM_HEADER_COUNT: usize = 100;
/// The single frozen request path of the ingestion surface.
const INGEST_REQUEST_PATH: &str = "/v1/ingest";
/// Required media type of the framed ingestion request body.
const INGEST_MEDIA_TYPE: &str = "application/x-healthmd-agent-data-ingest";
/// Per-connection socket timeout so a stalled peer cannot hold a thread.
const CONNECTION_TIMEOUT: Duration = Duration::from_secs(30);

/// Listener and store configuration of `healthmd data ingest-serve`.
#[derive(Clone, Debug)]
pub struct IngestServeOptions {
    /// Absolute path of the `SQLite` Agent Data database to create or extend.
    pub database: PathBuf,
    /// Loopback listener address.
    pub bind: SocketAddr,
    /// Accepted `Host` header values; loopback hosts when empty.
    pub allowed_hosts: Vec<String>,
    /// Accepted browser `Origin` values; every `Origin` is rejected when empty.
    pub allowed_origins: Vec<String>,
}

/// Startup failures of the ingestion gateway; every message is health-free
/// and path-free.
#[derive(Debug)]
pub enum IngestServeError {
    /// The database path is not absolute.
    RelativeDatabasePath,
    /// The requested bind is not a loopback address.
    NonLoopbackBind,
    /// An allowlisted Host or Origin is not loopback.
    UnauthenticatedRemotePolicy,
    /// The store could not be opened or migrated.
    Store(DataStoreOpenError),
    /// The listener could not bind or serve.
    Listener,
    /// The server task could not be driven to completion.
    Join,
}

impl fmt::Display for IngestServeError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::RelativeDatabasePath => {
                formatter.write_str("the Agent Data database path must be absolute")
            }
            Self::NonLoopbackBind => formatter.write_str(
                "the ingestion gateway must bind to loopback; terminate TLS in a co-resident reverse proxy",
            ),
            Self::UnauthenticatedRemotePolicy => formatter.write_str(
                "the unauthenticated ingestion gateway accepts only loopback Host and Origin values",
            ),
            Self::Store(error) => error.fmt(formatter),
            Self::Listener => {
                formatter.write_str("the ingestion gateway listener could not bind the requested address")
            }
            Self::Join => formatter.write_str("the ingestion gateway could not be started"),
        }
    }
}

impl std::error::Error for IngestServeError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Store(error) => Some(error),
            _ => None,
        }
    }
}

/// Serve the ingestion gateway: validate the listener policy, open and
/// migrate the store, then accept loopback connections until the process is
/// stopped.
///
/// Ordering mirrors the data HTTP surface: the listener policy validates
/// BEFORE the database is opened or created, and the store opens and migrates
/// BEFORE the listener binds, so every CLI-level failure exits non-zero
/// without ever accepting a request.
///
/// # Errors
///
/// Returns an [`IngestServeError`] when the policy, store, or listener is
/// unusable; never for per-request outcomes, which are receipts or transport
/// errors on the connection itself.
pub async fn serve_ingest_gateway(options: IngestServeOptions) -> Result<(), IngestServeError> {
    validate_policy(&options)?;
    open_and_migrate_store(&options.database)?;
    let listener = TcpListener::bind(options.bind).map_err(|_| IngestServeError::Listener)?;
    let state = Arc::new(GatewayState {
        database: options.database.clone(),
        allowed_hosts: effective_allowed_hosts(&options),
        allowed_origins: options.allowed_origins.clone(),
    });
    let server = move || -> Result<(), IngestServeError> {
        for stream in listener.incoming() {
            match stream {
                Ok(stream) => {
                    let state = Arc::clone(&state);
                    std::thread::spawn(move || handle_connection(stream, &state));
                }
                // Transient accept failures — a peer resetting before the accept
                // completes, or a signal-interrupted accept — must not take the
                // gateway down; skip them and keep serving. Only a listener that
                // is genuinely unusable stops the server.
                Err(error)
                    if error.kind() == std::io::ErrorKind::ConnectionAborted
                        || error.kind() == std::io::ErrorKind::Interrupted =>
                {
                    // Nothing to do: fall through to the next `incoming()` item.
                }
                Err(_) => return Err(IngestServeError::Listener),
            }
        }
        Ok(())
    };
    tokio::task::spawn_blocking(server)
        .await
        .map_err(|_| IngestServeError::Join)?
}

struct GatewayState {
    database: PathBuf,
    allowed_hosts: Vec<String>,
    allowed_origins: Vec<String>,
}

/// Open (or create) and migrate the store once at startup.
fn open_and_migrate_store(database: &Path) -> Result<(), IngestServeError> {
    let mut connection = data_sqlite::open_read_write(database).map_err(IngestServeError::Store)?;
    data_sqlite::migrate(&mut connection).map_err(IngestServeError::Store)?;
    Ok(())
}

/// Validate the listener policy before anything is opened or bound.
fn validate_policy(options: &IngestServeOptions) -> Result<(), IngestServeError> {
    if !options.database.is_absolute() {
        return Err(IngestServeError::RelativeDatabasePath);
    }
    if !options.bind.ip().is_loopback() {
        return Err(IngestServeError::NonLoopbackBind);
    }
    let hosts_are_loopback = effective_allowed_hosts(options)
        .iter()
        .all(|value| authority_host(value).is_some_and(|host| host_is_loopback(&host)));
    let origins_are_loopback = options
        .allowed_origins
        .iter()
        .all(|value| origin_host(value).is_some_and(host_is_loopback));
    if hosts_are_loopback && origins_are_loopback {
        Ok(())
    } else {
        Err(IngestServeError::UnauthenticatedRemotePolicy)
    }
}

/// The effective `Host` allowlist: the explicit list when provided, otherwise
/// the loopback defaults plus the bind address (mirroring the data HTTP
/// surface's defaults exactly).
pub fn effective_allowed_hosts(options: &IngestServeOptions) -> Vec<String> {
    if !options.allowed_hosts.is_empty() {
        return options.allowed_hosts.clone();
    }
    let mut hosts = vec![
        "localhost".to_owned(),
        "127.0.0.1".to_owned(),
        "[::1]".to_owned(),
    ];
    let bind_host = options.bind.ip().to_string();
    if !hosts.contains(&bind_host) {
        hosts.push(bind_host);
    }
    hosts
}

fn host_is_loopback(host: &str) -> bool {
    host.eq_ignore_ascii_case("localhost")
        || host
            .parse::<IpAddr>()
            .is_ok_and(|address| address.is_loopback())
}

/// Host part of an `authority` (`host` or `host:port`, IPv6 in brackets).
fn authority_host(value: &str) -> Option<String> {
    let trimmed = value.trim();
    let host = if let Some(rest) = trimmed.strip_prefix('[') {
        let end = rest.find(']')?;
        &rest[..end]
    } else if let Some((head, tail)) = trimmed.rsplit_once(':') {
        if tail.chars().all(|character| character.is_ascii_digit()) && !tail.is_empty() {
            head
        } else {
            trimmed
        }
    } else {
        trimmed
    };
    (!host.is_empty()).then(|| host.to_owned())
}

/// Explicit port of an `authority`, when present.
fn authority_port(value: &str) -> Option<u16> {
    let trimmed = value.trim();
    if let Some(rest) = trimmed.strip_prefix('[') {
        let end = rest.find(']')?;
        return rest[end + 1..].strip_prefix(':')?.parse().ok();
    }
    let (_, tail) = trimmed.rsplit_once(':')?;
    tail.parse().ok()
}

/// Host part of an `Origin` value (`scheme://host[:port][/...]`).
fn origin_host(origin: &str) -> Option<&str> {
    let rest = origin
        .strip_prefix("https://")
        .or_else(|| origin.strip_prefix("http://"))
        .unwrap_or(origin);
    let end = rest.find(['/', ':', '?']).unwrap_or(rest.len());
    let host = &rest[..end];
    (!host.is_empty()).then_some(host)
}

/// One parsed HTTP/1.1 request head.
struct RequestHead {
    method: String,
    path: String,
    headers: Vec<(String, String)>,
}

impl RequestHead {
    fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.as_str())
    }
}

/// The unauthenticated Host/Origin gate, mirroring the data HTTP surface's
/// middleware: the `Host` must match an allowlisted authority (host
/// case-insensitive, port when the entry declares one) and an `Origin`, when
/// present, must exactly match one allowlisted value.
fn request_host_and_origin_allowed(
    request: &RequestHead,
    allowed_hosts: &[String],
    allowed_origins: &[String],
) -> bool {
    let Some(host_header) = request.header("host") else {
        return false;
    };
    let Some(host) = authority_host(host_header) else {
        return false;
    };
    let port = authority_port(host_header);
    let host_allowed = allowed_hosts.iter().any(|allowed| {
        let Some(allowed_host) = authority_host(allowed) else {
            return false;
        };
        allowed_host.eq_ignore_ascii_case(&host)
            && authority_port(allowed).is_none_or(|allowed_port| port == Some(allowed_port))
    });
    if !host_allowed {
        return false;
    }
    match request.header("origin") {
        None => true,
        Some(origin) => allowed_origins.iter().any(|allowed| origin == allowed),
    }
}

/// Read one `\n`-terminated line bounded by `maximum` bytes.
///
/// Returns `Ok(None)` on a clean end-of-stream before any bytes, and an error
/// when the line exceeds the bound or the stream fails mid-line.
fn read_line_bounded(reader: &mut impl BufRead, maximum: usize) -> std::io::Result<Option<String>> {
    let mut line = Vec::new();
    loop {
        let available = reader.fill_buf()?;
        if available.is_empty() {
            return if line.is_empty() {
                Ok(None)
            } else {
                Ok(Some(String::from_utf8_lossy(&line).into_owned()))
            };
        }
        let newline = available.iter().position(|byte| *byte == b'\n');
        let consumed = newline.map_or(available.len(), |index| index + 1);
        if line
            .len()
            .saturating_add(newline.unwrap_or(available.len()))
            > maximum
        {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "line exceeds the bound",
            ));
        }
        line.extend_from_slice(&available[..newline.unwrap_or(available.len())]);
        reader.consume(consumed);
        if newline.is_some() {
            return Ok(Some(
                String::from_utf8_lossy(&line)
                    .trim_end_matches('\r')
                    .to_owned(),
            ));
        }
    }
}

/// The read outcome of one request head: complete, closed by the peer before
/// a full head arrived, or malformed.
enum HeadRead {
    Head(RequestHead),
    Closed,
    Malformed,
}

/// Handle one connection: exactly one request, then close.
fn handle_connection(stream: TcpStream, state: &GatewayState) {
    if stream.set_read_timeout(Some(CONNECTION_TIMEOUT)).is_err() {
        return;
    }
    if stream.set_write_timeout(Some(CONNECTION_TIMEOUT)).is_err() {
        return;
    }
    let mut reader = BufReader::new(stream);
    let request = match read_request_head(&mut reader) {
        HeadRead::Head(request) => request,
        HeadRead::Closed => return,
        HeadRead::Malformed => {
            respond_transport_error(&mut reader, 400, "bad_request", MALFORMED_REQUEST);
            return;
        }
    };

    // Host/Origin gate first, mirroring the data HTTP middleware posture:
    // an unconfigured Host or browser Origin is refused before any request
    // logic runs and before the store is touched.
    if !request_host_and_origin_allowed(&request, &state.allowed_hosts, &state.allowed_origins) {
        respond(&mut reader, 403, "Forbidden", None, &[]);
        return;
    }
    let content_length = match route_transport_checks(&request) {
        Ok(content_length) => content_length,
        Err((status, code, message)) => {
            respond_transport_error(&mut reader, status, code, message);
            return;
        }
    };

    // Read the exact declared body. A connection that closes before the full
    // Content-Length body arrives is closed without any receipt (case 1, the
    // phone-side retryable class).
    let Some(body) = read_declared_body(&mut reader, content_length) else {
        return;
    };
    dispatch_framed_upload(&mut reader, &state.database, &body);
}

/// Parse the request line plus header block of one request.
fn read_request_head(reader: &mut BufReader<TcpStream>) -> HeadRead {
    // Request line.
    let Some(request_line) = read_line_bounded(reader, MAXIMUM_HEADER_LINE_BYTES)
        .ok()
        .flatten()
    else {
        return HeadRead::Closed;
    };
    let mut segments = request_line.split_ascii_whitespace();
    let parsed = if let (Some(method), Some(path), Some("HTTP/1.1"), None) = (
        segments.next(),
        segments.next(),
        segments.next(),
        segments.next(),
    ) {
        (method.to_owned(), path.to_owned())
    } else {
        return HeadRead::Malformed;
    };
    let (method, path) = parsed;

    // Header block.
    let mut headers = Vec::new();
    loop {
        let Some(line) = read_line_bounded(reader, MAXIMUM_HEADER_LINE_BYTES)
            .ok()
            .flatten()
        else {
            return HeadRead::Closed;
        };
        if line.is_empty() {
            break;
        }
        if headers.len() >= MAXIMUM_HEADER_COUNT {
            return HeadRead::Malformed;
        }
        match line.split_once(':') {
            Some((name, value)) if !name.is_empty() => {
                headers.push((name.trim().to_ascii_lowercase(), value.trim().to_owned()));
            }
            _ => return HeadRead::Malformed,
        }
    }
    HeadRead::Head(RequestHead {
        method,
        path,
        headers,
    })
}

/// Apply the transport-level routing checks (path, method, framing headers,
/// body bound, media type) and return the validated `Content-Length`.
///
/// # Errors
///
/// Returns the health-free transport error (status, code, message) of the
/// first violated check.
fn route_transport_checks(request: &RequestHead) -> Result<u64, (u16, &'static str, &'static str)> {
    if request.path != INGEST_REQUEST_PATH {
        return Err((404, "not_found", UNKNOWN_PATH));
    }
    if request.method != "POST" {
        return Err((405, "method_not_allowed", WRONG_METHOD));
    }
    if request.header("transfer-encoding").is_some() {
        return Err((400, "chunked_encoding_unsupported", CHUNKED_NOT_SUPPORTED));
    }
    let content_lengths: Vec<&str> = request
        .headers
        .iter()
        .filter(|(name, _)| name == "content-length")
        .map(|(_, value)| value.as_str())
        .collect();
    let content_length = match content_lengths.as_slice() {
        [single] => single
            .parse::<u64>()
            .map_err(|_| (400, "bad_request", MALFORMED_REQUEST))?,
        _ => return Err((400, "bad_request", MALFORMED_REQUEST)),
    };
    if content_length > MAXIMUM_REQUEST_BYTES {
        return Err((413, "payload_too_large", BODY_TOO_LARGE));
    }
    let media_type = request
        .header("content-type")
        .map(|value| {
            value
                .split(';')
                .next()
                .unwrap_or_default()
                .trim()
                .to_ascii_lowercase()
        })
        .unwrap_or_default();
    if media_type != INGEST_MEDIA_TYPE {
        return Err((415, "unsupported_media_type", WRONG_MEDIA_TYPE));
    }
    Ok(content_length)
}

/// Read exactly the declared number of body bytes; `None` closes the
/// connection silently (case 1).
fn read_declared_body(reader: &mut BufReader<TcpStream>, content_length: u64) -> Option<Vec<u8>> {
    let length = usize::try_from(content_length).ok()?;
    let mut body = vec![0_u8; length];
    reader.read_exact(&mut body).ok()?;
    Some(body)
}

/// Split the framed body and dispatch the shared ingestion path, answering
/// HTTP 200 with the resulting receipt.
fn dispatch_framed_upload(reader: &mut BufReader<TcpStream>, database: &Path, body: &[u8]) {
    // Framing: one `\n`-terminated manifest line followed immediately by the
    // artifact bytes. A missing or oversized manifest line is an
    // unidentifiable manifest (protocol outcome, mirroring the local
    // oversized-manifest mapping).
    let bound = INGEST_MANIFEST_LINE_BOUND_BYTES.min(body.len());
    let Some(newline) = body[..bound].iter().position(|byte| *byte == b'\n') else {
        let receipt = rejected_receipt(Rejection::ManifestIncomplete, None);
        respond_receipt(reader, &receipt);
        return;
    };
    let manifest_line = &body[..newline];
    let artifact_bytes = &body[newline + 1..];
    let receipt = ingest_gateway_upload(database, manifest_line, artifact_bytes);
    respond_receipt(reader, &receipt);
}

const MALFORMED_REQUEST: &str =
    "the ingestion request could not be parsed; v1 accepts HTTP/1.1 requests only";
const UNKNOWN_PATH: &str = "the ingestion gateway serves only POST /v1/ingest";
const WRONG_METHOD: &str = "the ingestion gateway accepts only POST requests";
const CHUNKED_NOT_SUPPORTED: &str =
    "chunked transfer encoding is not supported in v1; send an exact Content-Length body";
const BODY_TOO_LARGE: &str = "the ingestion request exceeds the 64 MiB artifact body bound";
const WRONG_MEDIA_TYPE: &str =
    "the ingestion gateway requires the application/x-healthmd-agent-data-ingest media type";

fn respond_transport_error(
    reader: &mut BufReader<TcpStream>,
    status: u16,
    code: &str,
    message: &str,
) {
    let body =
        serde_json::to_vec(&json!({"code": code, "message": message})).unwrap_or_else(|_| {
            b"{\"code\":\"bad_request\",\"message\":\"the ingestion request could not be parsed\"}"
                .to_vec()
        });
    respond(
        reader,
        status,
        reason(status),
        Some("application/json"),
        &body,
    );
}

fn respond_receipt(reader: &mut BufReader<TcpStream>, receipt: &Value) {
    let body = serde_json::to_vec(receipt).unwrap_or_default();
    respond(reader, 200, "OK", Some("application/json"), &body);
}

fn reason(status: u16) -> &'static str {
    match status {
        400 => "Bad Request",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        413 => "Payload Too Large",
        415 => "Unsupported Media Type",
        _ => "Error",
    }
}

/// Write one complete `Connection: close` response.
///
/// After writing, the listener half-closes its write side and drains any
/// unread request bytes until the peer closes or the socket timeout fires,
/// so closing with an unread request body sends a clean FIN instead of a
/// reset that could overtake the response on the client.
fn respond(
    reader: &mut BufReader<TcpStream>,
    status: u16,
    reason: &str,
    content_type: Option<&str>,
    body: &[u8],
) {
    let stream = reader.get_mut();
    let mut response = format!(
        "HTTP/1.1 {status} {reason}\r\nContent-Length: {}\r\nConnection: close\r\n",
        body.len()
    );
    if let Some(content_type) = content_type {
        response.push_str("Content-Type: ");
        response.push_str(content_type);
        response.push_str("\r\n");
    }
    response.push_str("\r\n");
    let _ = stream.write_all(response.as_bytes());
    let _ = stream.write_all(body);
    let _ = stream.flush();
    let _ = stream.shutdown(std::net::Shutdown::Write);
    let mut sink = [0_u8; 4_096];
    loop {
        match stream.read(&mut sink) {
            Ok(0) | Err(_) => break,
            Ok(_) => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use std::net::SocketAddr;

    use super::*;

    fn options(bind: SocketAddr) -> IngestServeOptions {
        IngestServeOptions {
            database: "/nonexistent/agent-data.sqlite".into(),
            bind,
            allowed_hosts: Vec::new(),
            allowed_origins: Vec::new(),
        }
    }

    #[tokio::test]
    async fn policy_validates_before_the_store_opens() {
        // A non-loopback bind is refused before the (nonexistent) store opens.
        let mut non_loopback = options(SocketAddr::from(([0, 0, 0, 0], 8_791)));
        non_loopback.database = "/nonexistent/directory/store.sqlite".into();
        let error = serve_ingest_gateway(non_loopback)
            .await
            .expect_err("non-loopback binds must be refused");
        assert!(matches!(error, IngestServeError::NonLoopbackBind));

        // A relative database path is refused first.
        let mut relative = options(SocketAddr::from(([127, 0, 0, 1], 0)));
        relative.database = "relative.sqlite".into();
        let error = serve_ingest_gateway(relative)
            .await
            .expect_err("relative database paths must be refused");
        assert!(matches!(error, IngestServeError::RelativeDatabasePath));

        // A non-loopback allowlisted Host is refused for the unauthenticated
        // surface, and a non-loopback Origin likewise.
        let mut remote_host = options(SocketAddr::from(([127, 0, 0, 1], 0)));
        remote_host.allowed_hosts = vec!["gateway.example.com".to_owned()];
        assert!(matches!(
            validate_policy(&remote_host),
            Err(IngestServeError::UnauthenticatedRemotePolicy)
        ));
        let mut remote_origin = options(SocketAddr::from(([127, 0, 0, 1], 0)));
        remote_origin.allowed_origins = vec!["https://untrusted.example".to_owned()];
        assert!(matches!(
            validate_policy(&remote_origin),
            Err(IngestServeError::UnauthenticatedRemotePolicy)
        ));
    }

    #[test]
    fn effective_hosts_default_to_loopback_plus_bind() {
        let effective =
            effective_allowed_hosts(&options(SocketAddr::from(([127, 0, 0, 1], 8_791))));
        assert!(effective.contains(&"localhost".to_owned()));
        assert!(effective.contains(&"127.0.0.1".to_owned()));
        assert!(effective.contains(&"[::1]".to_owned()));
        let explicit = options(SocketAddr::from(([127, 0, 0, 1], 8_791)));
        let with_explicit = IngestServeOptions {
            allowed_hosts: vec!["127.0.0.1:8791".to_owned()],
            ..explicit
        };
        assert_eq!(
            effective_allowed_hosts(&with_explicit),
            vec!["127.0.0.1:8791".to_owned()]
        );
    }

    fn request(headers: &[(&str, &str)]) -> RequestHead {
        RequestHead {
            method: "POST".to_owned(),
            path: INGEST_REQUEST_PATH.to_owned(),
            headers: headers
                .iter()
                .map(|(name, value)| ((*name).to_owned(), (*value).to_owned()))
                .collect(),
        }
    }

    #[test]
    fn host_and_origin_gate_mirrors_the_data_http_surface() {
        let hosts = effective_allowed_hosts(&options(SocketAddr::from(([127, 0, 0, 1], 8_791))));
        let origins = vec!["http://127.0.0.1:8791".to_owned()];

        // Loopback hosts are accepted by default, with or without a port.
        assert!(request_host_and_origin_allowed(
            &request(&[("host", "127.0.0.1:8791")]),
            &hosts,
            &origins
        ));
        assert!(request_host_and_origin_allowed(
            &request(&[("host", "localhost")]),
            &hosts,
            &origins
        ));
        assert!(request_host_and_origin_allowed(
            &request(&[("host", "[::1]:8791")]),
            &hosts,
            &origins
        ));
        // A missing Host, an unconfigured Host, or a mismatched port on an
        // entry that declares one is rejected.
        assert!(!request_host_and_origin_allowed(
            &request(&[]),
            &hosts,
            &origins
        ));
        assert!(!request_host_and_origin_allowed(
            &request(&[("host", "untrusted.example")]),
            &hosts,
            &origins
        ));
        let pinned = vec!["127.0.0.1:8791".to_owned()];
        assert!(request_host_and_origin_allowed(
            &request(&[("host", "127.0.0.1:8791")]),
            &pinned,
            &[]
        ));
        assert!(!request_host_and_origin_allowed(
            &request(&[("host", "127.0.0.1:9999")]),
            &pinned,
            &[]
        ));
        // Any Origin is rejected until explicitly allowlisted; the exact
        // allowlisted value is accepted.
        assert!(!request_host_and_origin_allowed(
            &request(&[
                ("host", "127.0.0.1"),
                ("origin", "https://untrusted.example")
            ]),
            &hosts,
            &origins
        ));
        assert!(request_host_and_origin_allowed(
            &request(&[("host", "127.0.0.1"), ("origin", "http://127.0.0.1:8791")]),
            &hosts,
            &origins
        ));
    }

    #[test]
    fn authority_and_origin_helpers_parse_the_documented_shapes() {
        assert_eq!(authority_host("127.0.0.1").as_deref(), Some("127.0.0.1"));
        assert_eq!(
            authority_host("127.0.0.1:8791").as_deref(),
            Some("127.0.0.1")
        );
        assert_eq!(authority_host("[::1]:8791").as_deref(), Some("::1"));
        assert_eq!(authority_port("127.0.0.1:8791"), Some(8_791));
        assert_eq!(authority_port("127.0.0.1"), None);
        assert_eq!(authority_port("[::1]:8791"), Some(8_791));
        assert_eq!(
            origin_host("https://127.0.0.1:8791/path"),
            Some("127.0.0.1")
        );
        assert_eq!(origin_host("http://localhost"), Some("localhost"));
        assert_eq!(origin_host("not-a-url"), Some("not-a-url"));
        assert!(host_is_loopback("localhost"));
        assert!(host_is_loopback("127.0.0.1"));
        assert!(!host_is_loopback("example.com"));
    }
}
