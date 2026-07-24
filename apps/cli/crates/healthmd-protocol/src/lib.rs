#![forbid(unsafe_code)]

//! Language-neutral models and deterministic transformations for the Health.md
//! direct-iPhone protocol.
//!
//! This crate deliberately performs no networking, filesystem access, credential
//! storage, or logging. Health payload bytes are opaque to the transport layer.

pub mod crypto;
pub mod encoding;
pub mod models;
pub mod time;
pub mod transfer;
pub mod wire;

/// Direct protocol version implemented by the deployed Swift client and iPhone app.
pub const CURRENT_PROTOCOL_VERSION: u16 = 1;
/// Default TCP listener port used by the direct CLI backend.
pub const DEFAULT_MANUAL_IP_PORT: u16 = 17_647;
/// Maximum pre-authentication packet accepted by direct peers.
pub const MAXIMUM_PACKET_BYTES: usize = 2 * 1_024 * 1_024;
/// Maximum plaintext transfer frame body.
pub const TRANSFER_FRAME_BYTES: usize = 512 * 1_024;
/// Durable jobs expire after exactly seven days.
pub const JOB_LIFETIME_SECONDS: i64 = 7 * 24 * 60 * 60;
