#![forbid(unsafe_code)]

//! Language-neutral models and deterministic transformations for Health.md
//! direct-source protocols.
//!
//! This crate deliberately performs no networking, filesystem access, credential
//! storage, or logging. Health payload bytes are opaque to the transport layer.

pub mod crypto;
pub mod encoding;
pub mod foundation;
pub mod models;
pub mod time;
pub mod transfer;
pub mod v2;
pub mod wire;

/// Deployed Apple direct-pairing protocol version.
pub const CURRENT_PROTOCOL_VERSION: u16 = 1;
/// Android direct-pairing protocol version selecting the reviewed v2 code transcripts.
pub const ANDROID_PAIRING_PROTOCOL_VERSION: u16 = 2;
/// Deployed iOS export application protocol version.
pub const IOS_APPLICATION_PROTOCOL_VERSION: i32 = 1;
/// Capability-gated iOS direct-query application protocol version.
pub const IOS_QUERY_APPLICATION_PROTOCOL_VERSION: i32 = 3;
/// Android application protocol version.
pub const ANDROID_APPLICATION_PROTOCOL_VERSION: i32 = 2;
/// Default TCP listener port used by the direct CLI backend.
pub const DEFAULT_MANUAL_IP_PORT: u16 = 17_647;
/// Maximum pre-authentication packet accepted by direct peers.
pub const MAXIMUM_PACKET_BYTES: usize = 2 * 1_024 * 1_024;
/// Maximum plaintext transfer frame body.
pub const TRANSFER_FRAME_BYTES: usize = 512 * 1_024;
/// Durable jobs expire after exactly seven days.
pub const JOB_LIFETIME_SECONDS: i64 = 7 * 24 * 60 * 60;
