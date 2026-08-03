use std::{collections::VecDeque, sync::Arc, time::Duration};

use chrono::{DateTime, Utc};
use healthmd_client::{
    ClientError,
    direct::{DirectClient, PairingResult},
};
use healthmd_operations::PairingStartResult;
use qrcode::{QrCode, types::Color};
use serde_json::{Value, json};
use tokio::{
    sync::{Mutex, oneshot, watch},
    task::AbortHandle,
};
use uuid::Uuid;

const MAXIMUM_RETAINED_PAIRING_SESSIONS: usize = 8;
const LISTENER_START_TIMEOUT: Duration = Duration::from_secs(5);
const QR_QUIET_ZONE_MODULES: usize = 4;
const QR_MODULE_SCALE: usize = 12;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LocalAddress {
    pub address: String,
    pub interface: String,
    pub tailscale: bool,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PairingCoordinatorError {
    InvalidTimeout,
    Busy,
    AlreadyPaired,
    ConfiguredDevicePinned,
    AddressUnavailable,
    SecureRandomUnavailable,
    ListenerUnavailable,
    QrUnavailable,
    TrustInvalid,
    IdentityInvalid,
    StorageUnavailable,
    SessionNotFound,
}

impl PairingCoordinatorError {
    pub const fn code(self) -> &'static str {
        match self {
            Self::InvalidTimeout => "healthmd_pairing_timeout_invalid",
            Self::Busy => "healthmd_pairing_busy",
            Self::AlreadyPaired => "healthmd_already_paired",
            Self::ConfiguredDevicePinned => "healthmd_pairing_device_pinned",
            Self::AddressUnavailable => "healthmd_pairing_address_unavailable",
            Self::SecureRandomUnavailable => "healthmd_pairing_random_unavailable",
            Self::ListenerUnavailable => "healthmd_pairing_listener_unavailable",
            Self::QrUnavailable => "healthmd_pairing_qr_unavailable",
            Self::TrustInvalid => "healthmd_pairing_trust_invalid",
            Self::IdentityInvalid => "healthmd_pairing_identity_invalid",
            Self::StorageUnavailable => "healthmd_pairing_storage_unavailable",
            Self::SessionNotFound => "healthmd_pairing_session_not_found",
        }
    }

    pub const fn message(self) -> &'static str {
        match self {
            Self::InvalidTimeout => "Pairing timeout must be between 30 and 600 seconds.",
            Self::Busy => "Another direct iPhone operation or pairing session is active.",
            Self::AlreadyPaired => {
                "A mobile source is already paired. Use healthmd_doctor instead of starting another onboarding session."
            }
            Self::ConfiguredDevicePinned => {
                "This MCP server is pinned to a device that is not locally paired. Remove the stale device selection before onboarding."
            }
            Self::AddressUnavailable => {
                "No eligible LAN or Tailscale IPv4 address is available for iPhone pairing."
            }
            Self::SecureRandomUnavailable => {
                "The operating system could not generate a secure one-time pairing code."
            }
            Self::ListenerUnavailable => {
                "The bounded local iPhone pairing listener could not be started."
            }
            Self::QrUnavailable => "The iPhone pairing QR code could not be generated.",
            Self::TrustInvalid => {
                "Saved direct trust is invalid. Explicitly reset local trust and forget the CLI in Health.md before pairing again."
            }
            Self::IdentityInvalid => {
                "The local Health.md CLI installation identity is invalid and must be repaired before pairing."
            }
            Self::StorageUnavailable => {
                "Native secure storage is unavailable for local iPhone pairing."
            }
            Self::SessionNotFound => "The local iPhone pairing session was not found.",
        }
    }
}

#[derive(Clone, Debug)]
enum PairingState {
    Starting,
    WaitingForScan,
    Paired {
        installation_id: Uuid,
        display_name: String,
    },
    TimedOut,
    Failed {
        code: &'static str,
        message: &'static str,
    },
}

impl PairingState {
    const fn is_active(&self) -> bool {
        matches!(self, Self::Starting | Self::WaitingForScan)
    }
}

struct PairingSession {
    id: Uuid,
    started_at: DateTime<Utc>,
    expires_at: DateTime<Utc>,
    bound_port: u16,
    state: watch::Receiver<PairingState>,
}

pub struct PairingCoordinator {
    client: Arc<DirectClient>,
    configured_device_id: Option<Uuid>,
    port: u16,
    operation_gate: Arc<Mutex<()>>,
    sessions: Mutex<VecDeque<PairingSession>>,
}

impl PairingCoordinator {
    pub fn new(
        client: Arc<DirectClient>,
        configured_device_id: Option<Uuid>,
        port: u16,
        operation_gate: Arc<Mutex<()>>,
    ) -> Self {
        Self {
            client,
            configured_device_id,
            port,
            operation_gate,
            sessions: Mutex::new(VecDeque::new()),
        }
    }

    /// Start one bounded local iPhone pairing listener and return its scan-ready QR image.
    ///
    /// # Errors
    ///
    /// Returns a stable health-free error when onboarding would create ambiguous trust, another
    /// direct operation is active, no eligible address exists, secure storage/randomness is
    /// unavailable, or the listener/QR cannot be created.
    #[allow(clippy::too_many_lines)]
    pub async fn start(
        &self,
        timeout_seconds: u64,
    ) -> Result<PairingStartResult, PairingCoordinatorError> {
        if !(healthmd_operations::limits::MINIMUM_PAIRING_TIMEOUT_SECONDS
            ..=healthmd_operations::limits::MAXIMUM_PAIRING_TIMEOUT_SECONDS)
            .contains(&timeout_seconds)
        {
            return Err(PairingCoordinatorError::InvalidTimeout);
        }
        let devices = self
            .client
            .paired_devices()
            .await
            .map_err(|error| pairing_preflight_error(&error))?;
        if self.configured_device_id.is_some_and(|configured| {
            !devices
                .iter()
                .any(|device| device.installation_id.0 == configured)
        }) {
            return Err(PairingCoordinatorError::ConfiguredDevicePinned);
        }
        if !devices.is_empty() {
            return Err(PairingCoordinatorError::AlreadyPaired);
        }
        let address = preferred_pairing_address(&local_ipv4_addresses())
            .ok_or(PairingCoordinatorError::AddressUnavailable)?;
        let ios_code = generate_numeric_code(6)?;
        // Direct protocol negotiation remains multi-platform. This secret Android code is never
        // exposed, and pair_ios rejects/forgets a non-iOS peer before returning.
        let android_code = generate_numeric_code(20)?;
        let operation_guard = Arc::clone(&self.operation_gate)
            .try_lock_owned()
            .map_err(|_| PairingCoordinatorError::Busy)?;

        let id = Uuid::new_v4();
        let started_at = Utc::now();
        let expires_at = started_at
            + chrono::Duration::seconds(i64::try_from(timeout_seconds).unwrap_or(i64::MAX));
        let (state_sender, state_receiver) = watch::channel(PairingState::Starting);
        let (port_sender, port_receiver) = oneshot::channel();

        {
            let mut sessions = self.sessions.lock().await;
            if sessions
                .iter()
                .any(|session| session.state.borrow().is_active())
            {
                return Err(PairingCoordinatorError::Busy);
            }
            while sessions.len() >= MAXIMUM_RETAINED_PAIRING_SESSIONS {
                sessions.pop_front();
            }
            sessions.push_back(PairingSession {
                id,
                started_at,
                expires_at,
                bound_port: 0,
                state: state_receiver.clone(),
            });
        }

        let client = Arc::clone(&self.client);
        let configured_port = self.port;
        let ios_code_for_listener = ios_code.clone();
        let terminal_sender = state_sender.clone();
        let task = tokio::spawn(async move {
            let _operation_guard = operation_guard;
            let result = client
                .pair_first_ios(
                    &ios_code_for_listener,
                    &android_code,
                    configured_port,
                    Duration::from_secs(timeout_seconds),
                    move |bound_port| {
                        let _ = port_sender.send(bound_port);
                    },
                )
                .await;
            let _ = terminal_sender.send(terminal_pairing_state(result));
        });
        let mut start_guard = PairingStartGuard::new(task.abort_handle(), state_sender.clone());
        drop(task);

        let bound_port = match tokio::time::timeout(LISTENER_START_TIMEOUT, port_receiver).await {
            Ok(Ok(port)) => port,
            Ok(Err(_)) => {
                start_guard.disarm();
                return Err(PairingCoordinatorError::ListenerUnavailable);
            }
            Err(_) => {
                start_guard.abort_with(PairingState::Failed {
                    code: "healthmd_pairing_listener_unavailable",
                    message: "The bounded local iPhone pairing listener could not be started.",
                });
                return Err(PairingCoordinatorError::ListenerUnavailable);
            }
        };

        {
            let mut sessions = self.sessions.lock().await;
            if let Some(session) = sessions.iter_mut().find(|session| session.id == id) {
                session.bound_port = bound_port;
            }
        }
        let _ = state_sender.send_if_modified(|state| {
            if matches!(state, PairingState::Starting) {
                *state = PairingState::WaitingForScan;
                true
            } else {
                false
            }
        });

        if !matches!(*state_receiver.borrow(), PairingState::WaitingForScan) {
            start_guard.disarm();
            return Err(PairingCoordinatorError::ListenerUnavailable);
        }

        let link = ios_pairing_link(&address.address, bound_port, &ios_code);
        let qr_png = match render_qr_png(&link) {
            Ok(png) => png,
            Err(error) => {
                start_guard.abort_with(PairingState::Failed {
                    code: error.code(),
                    message: error.message(),
                });
                return Err(error);
            }
        };
        start_guard.disarm();

        Ok(PairingStartResult {
            receipt: pairing_receipt(
                id,
                started_at,
                expires_at,
                bound_port,
                "waiting_for_scan",
                "Open foreground Health.md, go to Sync > Direct CLI Access, tap Scan Pairing QR, and scan this image; pairing starts automatically.",
            ),
            qr_png,
        })
    }

    /// Read the latest health-free receipt for one in-memory pairing session.
    ///
    /// # Errors
    ///
    /// Returns [`PairingCoordinatorError::SessionNotFound`] when the bounded session history no
    /// longer contains `id`.
    pub async fn status(&self, id: Uuid) -> Result<Value, PairingCoordinatorError> {
        let sessions = self.sessions.lock().await;
        let session = sessions
            .iter()
            .find(|session| session.id == id)
            .ok_or(PairingCoordinatorError::SessionNotFound)?;
        let state = session.state.borrow().clone();
        Ok(pairing_status_value(session, &state))
    }
}

struct PairingStartGuard {
    abort: AbortHandle,
    state: watch::Sender<PairingState>,
    armed: bool,
}

impl PairingStartGuard {
    fn new(abort: AbortHandle, state: watch::Sender<PairingState>) -> Self {
        Self {
            abort,
            state,
            armed: true,
        }
    }

    fn abort_with(&mut self, state: PairingState) {
        self.abort.abort();
        let _ = self.state.send(state);
        self.armed = false;
    }

    fn disarm(&mut self) {
        self.armed = false;
    }
}

impl Drop for PairingStartGuard {
    fn drop(&mut self) {
        if self.armed {
            self.abort.abort();
            let _ = self.state.send(PairingState::Failed {
                code: "healthmd_pairing_start_cancelled",
                message: "The local iPhone pairing listener stopped before its QR code was returned.",
            });
        }
    }
}

fn pairing_preflight_error(error: &ClientError) -> PairingCoordinatorError {
    match error {
        ClientError::InvalidTrustState => PairingCoordinatorError::TrustInvalid,
        ClientError::InvalidIdentity => PairingCoordinatorError::IdentityInvalid,
        ClientError::Storage(_) | ClientError::CredentialStore(_) => {
            PairingCoordinatorError::StorageUnavailable
        }
        _ => PairingCoordinatorError::StorageUnavailable,
    }
}

fn terminal_pairing_state(result: Result<PairingResult, ClientError>) -> PairingState {
    match result {
        Ok(result) => PairingState::Paired {
            installation_id: result.device.installation_id.0,
            display_name: result.device.display_name,
        },
        Err(ClientError::PairingConflict) => PairingState::Failed {
            code: PairingCoordinatorError::AlreadyPaired.code(),
            message: PairingCoordinatorError::AlreadyPaired.message(),
        },
        Err(ClientError::TimedOut) => PairingState::TimedOut,
        Err(ClientError::InvalidTrustState) => PairingState::Failed {
            code: PairingCoordinatorError::TrustInvalid.code(),
            message: PairingCoordinatorError::TrustInvalid.message(),
        },
        Err(ClientError::InvalidIdentity) => PairingState::Failed {
            code: PairingCoordinatorError::IdentityInvalid.code(),
            message: PairingCoordinatorError::IdentityInvalid.message(),
        },
        Err(ClientError::CredentialStore(_) | ClientError::Storage(_)) => PairingState::Failed {
            code: PairingCoordinatorError::StorageUnavailable.code(),
            message: PairingCoordinatorError::StorageUnavailable.message(),
        },
        Err(ClientError::CredentialMutationOutcomeUnknown) => PairingState::Failed {
            code: "healthmd_pairing_storage_outcome_unknown",
            message: "The native credential update may have completed. Check pairing status before retrying.",
        },
        Err(_) => PairingState::Failed {
            code: "healthmd_pairing_failed",
            message: "Local iPhone pairing failed. Keep Health.md foreground and scan a fresh QR with its in-app Direct CLI scanner.",
        },
    }
}

fn pairing_status_value(session: &PairingSession, state: &PairingState) -> Value {
    match state {
        PairingState::Starting => pairing_receipt(
            session.id,
            session.started_at,
            session.expires_at,
            session.bound_port,
            "starting_listener",
            "The bounded local iPhone pairing listener is starting.",
        ),
        PairingState::WaitingForScan => pairing_receipt(
            session.id,
            session.started_at,
            session.expires_at,
            session.bound_port,
            "waiting_for_scan",
            "In foreground Health.md, open Sync > Direct CLI Access, tap Scan Pairing QR, and scan the displayed image; pairing starts automatically.",
        ),
        PairingState::Paired {
            installation_id,
            display_name,
        } => {
            let mut value = pairing_receipt(
                session.id,
                session.started_at,
                session.expires_at,
                session.bound_port,
                "paired",
                "The iPhone is paired with this Health.md CLI installation.",
            );
            value["device"] = json!({
                "installation_id": installation_id.to_string().to_lowercase(),
                "name": display_name,
                "platform": "ios"
            });
            value
        }
        PairingState::TimedOut => {
            let mut value = pairing_receipt(
                session.id,
                session.started_at,
                session.expires_at,
                session.bound_port,
                "timed_out",
                "The pairing QR code expired. Start a new local pairing session.",
            );
            value["error"] = json!("healthmd_pairing_timed_out");
            value
        }
        PairingState::Failed { code, message } => {
            let mut value = pairing_receipt(
                session.id,
                session.started_at,
                session.expires_at,
                session.bound_port,
                "failed",
                message,
            );
            value["error"] = json!(code);
            value
        }
    }
}

fn pairing_receipt(
    id: Uuid,
    started_at: DateTime<Utc>,
    expires_at: DateTime<Utc>,
    bound_port: u16,
    status: &str,
    message: &str,
) -> Value {
    let id = id.to_string().to_lowercase();
    let mut value = json!({
        "schema": "healthmd.pairing_session",
        "schema_version": 1,
        "pairing_session_id": id.clone(),
        "status": status,
        "started_at": started_at,
        "expires_at": expires_at,
        "listener": {
            "transport": "manual-ip",
            "port": bound_port
        },
        "message": message
    });
    if matches!(status, "starting_listener" | "waiting_for_scan") {
        value["next_tool"] = json!({
            "name": "healthmd_pairing_status",
            "arguments": {"pairing_session_id": id}
        });
    }
    value
}

/// Generate an unbiased numeric one-time code from operating-system secure randomness.
///
/// # Errors
///
/// Returns [`PairingCoordinatorError::SecureRandomUnavailable`] when the operating system random
/// source fails.
pub fn generate_numeric_code(digit_count: usize) -> Result<String, PairingCoordinatorError> {
    let mut code = String::with_capacity(digit_count);
    while code.len() < digit_count {
        let bytes = healthmd_protocol::crypto::random_bytes::<32>()
            .map_err(|_| PairingCoordinatorError::SecureRandomUnavailable)?;
        for byte in bytes.into_iter().filter(|byte| *byte < 250) {
            code.push(char::from(b'0' + (byte % 10)));
            if code.len() == digit_count {
                break;
            }
        }
    }
    Ok(code)
}

pub fn ios_pairing_link(address: &str, port: u16, pairing_code: &str) -> String {
    format!("healthmd://direct-cli/pair?host={address}&port={port}&code={pairing_code}")
}

pub fn preferred_pairing_address(addresses: &[LocalAddress]) -> Option<LocalAddress> {
    preferred_pairing_address_with_default(addresses, default_route_ipv4().as_deref())
}

fn preferred_pairing_address_with_default(
    addresses: &[LocalAddress],
    default_address: Option<&str>,
) -> Option<LocalAddress> {
    default_address
        .and_then(|default| {
            addresses.iter().find(|address| {
                address.address == default
                    && !address.tailscale
                    && !is_likely_virtual_interface(&address.interface)
            })
        })
        .or_else(|| {
            addresses.iter().find(|address| {
                !address.tailscale && !is_likely_virtual_interface(&address.interface)
            })
        })
        .or_else(|| addresses.iter().find(|address| address.tailscale))
        .or_else(|| addresses.iter().find(|address| !address.tailscale))
        .or_else(|| addresses.first())
        .cloned()
}

fn default_route_ipv4() -> Option<String> {
    let socket = std::net::UdpSocket::bind(("0.0.0.0", 0)).ok()?;
    socket.connect(("1.1.1.1", 80)).ok()?;
    let std::net::IpAddr::V4(address) = socket.local_addr().ok()?.ip() else {
        return None;
    };
    (!address.is_loopback() && !address.is_unspecified()).then(|| address.to_string())
}

fn is_likely_virtual_interface(interface: &str) -> bool {
    let interface = interface.to_ascii_lowercase();
    [
        "docker",
        "br-",
        "bridge",
        "utun",
        "tun",
        "tap",
        "wg",
        "ppp",
        "ipsec",
        "vpn",
        "zt",
        "ham",
        "veth",
        "virbr",
        "vmnet",
        "vbox",
        "podman",
        "vethernet",
    ]
    .iter()
    .any(|prefix| interface.starts_with(prefix))
}

pub fn local_ipv4_addresses() -> Vec<LocalAddress> {
    let mut addresses: Vec<_> = if_addrs::get_if_addrs()
        .unwrap_or_default()
        .into_iter()
        .filter_map(|interface| {
            let std::net::IpAddr::V4(address) = interface.ip() else {
                return None;
            };
            if address.is_loopback()
                || address.is_unspecified()
                || address.is_multicast()
                || address.is_link_local()
            {
                return None;
            }
            let octets = address.octets();
            if !is_allowed_local_pairing_ipv4(octets) {
                return None;
            }
            Some(LocalAddress {
                address: address.to_string(),
                interface: interface.name,
                tailscale: is_tailscale_ipv4(octets),
            })
        })
        .collect();
    addresses.sort_by(|left, right| {
        right
            .tailscale
            .cmp(&left.tailscale)
            .then_with(|| left.interface.cmp(&right.interface))
            .then_with(|| left.address.cmp(&right.address))
    });
    addresses.dedup_by(|left, right| left.address == right.address);
    addresses
}

pub const fn is_tailscale_ipv4(octets: [u8; 4]) -> bool {
    octets[0] == 100 && octets[1] >= 64 && octets[1] <= 127
}

const fn is_allowed_local_pairing_ipv4(octets: [u8; 4]) -> bool {
    octets[0] == 10
        || (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31)
        || (octets[0] == 192 && octets[1] == 168)
        || is_tailscale_ipv4(octets)
}

fn render_qr_png(contents: &str) -> Result<Vec<u8>, PairingCoordinatorError> {
    let code =
        QrCode::new(contents.as_bytes()).map_err(|_| PairingCoordinatorError::QrUnavailable)?;
    let module_width = code.width();
    let raster_modules = module_width
        .checked_add(QR_QUIET_ZONE_MODULES * 2)
        .ok_or(PairingCoordinatorError::QrUnavailable)?;
    let raster_width = raster_modules
        .checked_mul(QR_MODULE_SCALE)
        .ok_or(PairingCoordinatorError::QrUnavailable)?;
    let pixel_count = raster_width
        .checked_mul(raster_width)
        .ok_or(PairingCoordinatorError::QrUnavailable)?;
    let mut pixels = vec![255_u8; pixel_count];

    for module_y in 0..module_width {
        for module_x in 0..module_width {
            if code[(module_x, module_y)] != Color::Dark {
                continue;
            }
            let start_x = (module_x + QR_QUIET_ZONE_MODULES) * QR_MODULE_SCALE;
            let start_y = (module_y + QR_QUIET_ZONE_MODULES) * QR_MODULE_SCALE;
            for y in start_y..start_y + QR_MODULE_SCALE {
                let row = y * raster_width;
                pixels[row + start_x..row + start_x + QR_MODULE_SCALE].fill(0);
            }
        }
    }

    let width = u32::try_from(raster_width).map_err(|_| PairingCoordinatorError::QrUnavailable)?;
    let mut png_bytes = Vec::new();
    {
        let mut encoder = png::Encoder::new(&mut png_bytes, width, width);
        encoder.set_color(png::ColorType::Grayscale);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder
            .write_header()
            .map_err(|_| PairingCoordinatorError::QrUnavailable)?;
        writer
            .write_image_data(&pixels)
            .map_err(|_| PairingCoordinatorError::QrUnavailable)?;
    }
    Ok(png_bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn numeric_codes_have_exact_ascii_digit_length() {
        for length in [6, 20] {
            let code = generate_numeric_code(length).unwrap();
            assert_eq!(code.len(), length);
            assert!(code.bytes().all(|byte| byte.is_ascii_digit()));
        }
    }

    #[test]
    fn qr_hosts_are_limited_to_private_lan_and_tailscale_ipv4() {
        for address in [
            [10, 0, 0, 1],
            [172, 16, 0, 1],
            [172, 31, 255, 254],
            [192, 168, 1, 42],
            [100, 64, 0, 1],
            [100, 127, 255, 254],
        ] {
            assert!(is_allowed_local_pairing_ipv4(address));
        }
        for address in [
            [127, 0, 0, 1],
            [8, 8, 8, 8],
            [172, 32, 0, 1],
            [100, 128, 0, 1],
        ] {
            assert!(!is_allowed_local_pairing_ipv4(address));
        }
    }

    #[test]
    fn pairing_link_is_exact_and_qr_is_a_decodable_square_png() {
        let link = ios_pairing_link("192.168.1.42", 17_647, "123456");
        assert_eq!(
            link,
            "healthmd://direct-cli/pair?host=192.168.1.42&port=17647&code=123456"
        );
        let bytes = render_qr_png(&link).unwrap();
        assert_eq!(&bytes[..8], b"\x89PNG\r\n\x1a\n");
        let decoder = png::Decoder::new(std::io::Cursor::new(bytes));
        let reader = decoder.read_info().unwrap();
        assert_eq!(reader.info().width, reader.info().height);
        assert!(reader.info().width >= 400);
    }

    #[test]
    fn preferred_address_uses_lan_before_tailscale() {
        let addresses = vec![
            LocalAddress {
                address: "100.70.1.2".into(),
                interface: "utun4".into(),
                tailscale: true,
            },
            LocalAddress {
                address: "192.168.1.42".into(),
                interface: "en0".into(),
                tailscale: false,
            },
        ];
        assert_eq!(
            preferred_pairing_address_with_default(&addresses, None)
                .unwrap()
                .address,
            "192.168.1.42"
        );
    }

    #[test]
    fn default_route_wins_and_virtual_bridges_do_not_hide_tailscale() {
        let addresses = vec![
            LocalAddress {
                address: "172.17.0.1".into(),
                interface: "docker0".into(),
                tailscale: false,
            },
            LocalAddress {
                address: "100.70.1.2".into(),
                interface: "utun4".into(),
                tailscale: true,
            },
            LocalAddress {
                address: "10.0.0.8".into(),
                interface: "en0".into(),
                tailscale: false,
            },
        ];
        assert_eq!(
            preferred_pairing_address_with_default(&addresses, Some("10.0.0.8"))
                .unwrap()
                .address,
            "10.0.0.8"
        );
        assert_eq!(
            preferred_pairing_address_with_default(&addresses, Some("100.70.1.2"))
                .unwrap()
                .address,
            "10.0.0.8"
        );
        assert_eq!(
            preferred_pairing_address_with_default(&addresses[..2], None)
                .unwrap()
                .address,
            "100.70.1.2"
        );
    }

    #[test]
    fn receipts_never_include_the_pairing_secret_or_uri() {
        let value = pairing_receipt(
            Uuid::nil(),
            Utc::now(),
            Utc::now(),
            17_647,
            "waiting_for_scan",
            "Scan the QR code.",
        );
        let encoded = value.to_string();
        assert!(!encoded.contains("123456"));
        assert!(!encoded.contains("healthmd://"));
        assert!(!encoded.contains("192.168."));
    }
}
