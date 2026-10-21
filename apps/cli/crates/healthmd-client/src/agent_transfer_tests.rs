//! Both deployed base envelopes over real encrypted synthetic peer channels.
use super::*;
use healthmd_protocol::{
    encoding::SwiftUuid,
    models as a, v2,
    wire::{DirectMessage, Unlabeled},
};
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum TransferCase {
    Exact,
    Large,
    BadDigest,
    PartitionTamper,
    PartitionFifo,
    CheckpointDelete,
    FinalPrefixDelete,
    FinalOutputEdit,
    BadSession,
    BadManifest,
    BadChain,
    BadOffset,
    BadChunk,
    BadComplete,
    BadFinalize,
    Disconnect,
    Quota,
}
pub(super) fn payload(case: TransferCase) -> Vec<u8> {
    if case == TransferCase::Large {
        let mut bytes = b"{\"synthetic\":\"".to_vec();
        bytes.resize(700_000, b'x');
        bytes.extend_from_slice(b"\"}");
        bytes
    } else {
        b"{\"synthetic\":true}".to_vec()
    }
}
pub(super) fn binding(
    request: &ExecuteRequest,
    platform: PeerPlatform,
    case: TransferCase,
) -> crate::agent_host::output::NativeBinding {
    let mut binding = synthetic_binding(request, platform);
    let data = payload(case);
    for item in &mut binding.manifest.artifacts {
        let Artifact::Branch1(item) = item else {
            unreachable!()
        };
        item.byte_count = data.len() as u64;
        item.sha256 = Digest(healthmd_protocol::transfer::sha256_hex(&data));
    }
    binding
}
async fn send(
    channel: &mut SecureChannel,
    platform: PeerPlatform,
    apple: DirectMessage,
    android: v2::Message,
) {
    if platform == PeerPlatform::Ios {
        channel.send(&apple).await.unwrap();
    } else {
        channel.send_v2(&v2::Envelope::new(android)).await.unwrap();
    }
}
async fn expect(
    channel: &mut SecureChannel,
    platform: PeerPlatform,
    apple: DirectMessage,
    android: v2::Message,
) {
    if platform == PeerPlatform::Ios {
        assert_eq!(
            channel.receive().await.unwrap(),
            crate::secure_channel::SecurePayload::Message(Box::new(apple))
        );
    } else {
        assert_eq!(
            channel.receive_v2().await.unwrap(),
            v2::Envelope::new(android)
        );
    }
}
fn apple_session(value: &v2::TransferSession) -> a::TransferSession {
    a::TransferSession {
        protocol_version: 1,
        session_id: SwiftUuid(value.session_id),
        job_id: SwiftUuid(value.job_id),
        request_fingerprint: a::RequestFingerprint {
            version: 1,
            sha256: value.request_fingerprint.clone(),
        },
        peer_binding: a::PeerBinding {
            source_installation_id: SwiftUuid(value.peer_binding.source_installation_id),
            destination_installation_id: SwiftUuid(value.peer_binding.destination_installation_id),
        },
        partition_target_bytes: i64::try_from(value.partition_target_bytes).unwrap(),
        created_at: value.created_at,
    }
}
// One real encrypted peer transcript retains the full source/acknowledgement order.
#[allow(clippy::too_many_lines)]
pub(super) async fn send_transfer(
    channel: &mut SecureChannel,
    request: &ExecuteRequest,
    platform: PeerPlatform,
    case: TransferCase,
) {
    let binding = binding(request, platform, case);
    let payload = payload(case);
    let mut session = v2::TransferSession {
        session_id: Uuid::parse_str(&id(30).0).unwrap(),
        job_id: Uuid::parse_str(&request.job_id.0).unwrap(),
        request_fingerprint: binding.manifest.request_sha256.0.clone(),
        peer_binding: v2::PeerBinding {
            source_installation_id: Uuid::parse_str(
                &request.plan.intent.peer.source_installation_id.0,
            )
            .unwrap(),
            destination_installation_id: Uuid::parse_str(
                &request.plan.intent.peer.host_installation_id.0,
            )
            .unwrap(),
        },
        partition_target_bytes: 50_331_648,
        created_at: chrono::DateTime::from_timestamp(
            binding.accepted.expires_at.seconds().unwrap() - 604_800,
            0,
        )
        .unwrap(),
    };
    if case == TransferCase::BadSession {
        session.request_fingerprint = "1".repeat(64);
    }
    send(
        channel,
        platform,
        DirectMessage::TransferSession(Unlabeled::from(apple_session(&session))),
        v2::Message::TransferSession(session.clone()),
    )
    .await;
    if matches!(case, TransferCase::BadSession | TransferCase::Quota) {
        return;
    }
    for item in &binding.manifest.artifacts {
        let Artifact::Branch1(item) = item else {
            unreachable!()
        };
        let file_id = Uuid::parse_str(&item.artifact_id.0).unwrap();
        let path = if case == TransferCase::BadManifest {
            "foreign.json".into()
        } else {
            item.relative_path.0.clone()
        };
        send(
            channel,
            platform,
            DirectMessage::FileManifest(Unlabeled::from(a::FileManifest {
                job_id: SwiftUuid(session.job_id),
                file_id: SwiftUuid(file_id),
                relative_path: path.clone(),
                byte_count: i64::try_from(item.byte_count).unwrap(),
                sha256: item.sha256.0.clone(),
                write_mode: a::FileWriteMode::Overwrite,
            })),
            v2::Message::ArtifactManifest(v2::ArtifactManifest {
                job_id: session.job_id,
                artifact_id: file_id,
                kind: v2::ArtifactKind::GeneratedFile,
                schema: v2::ArtifactSchema {
                    id: "healthmd.generated-files".into(),
                    major: 1,
                },
                media_type: "application/json".into(),
                byte_count: item.byte_count,
                sha256: item.sha256.0.clone(),
                relative_path: Some(path),
                write_mode: Some(v2::FileWriteMode::Overwrite),
                logical_checksum_sha256: None,
                snapshot_status: None,
                provider_id: None,
            }),
        )
        .await;
        if case == TransferCase::BadManifest {
            return;
        }
    }
    let mut previous = None;
    let mut index = 0_u64;
    for item in &binding.manifest.artifacts {
        let Artifact::Branch1(item) = item else {
            unreachable!()
        };
        let part_bytes = if case == TransferCase::Large {
            payload.len()
        } else {
            9
        };
        for (segment, content) in payload.chunks(part_bytes).enumerate() {
            let digest = healthmd_protocol::transfer::sha256_hex(content);
            let mut partition = v2::TransferPartition {
                index,
                transfer_id: Uuid::parse_str(&id(31 + index).0).unwrap(),
                artifact_id: Uuid::parse_str(&item.artifact_id.0).unwrap(),
                artifact_offset: (segment * part_bytes) as u64,
                byte_count: content.len() as u64,
                chunk_count: (content.len() as u64)
                    .div_ceil(healthmd_protocol::TRANSFER_FRAME_BYTES as u64),
                sha256: digest.clone(),
                previous_sha256: previous.clone(),
            };
            if case == TransferCase::BadChain {
                partition.previous_sha256 = Some("1".repeat(64));
            }
            if case == TransferCase::BadOffset {
                partition.artifact_offset = 1;
            }
            let apple_partition = a::TransferPartition {
                index: i64::try_from(index).unwrap(),
                transfer_id: SwiftUuid(partition.transfer_id),
                source_dates: vec![item.artifact_id.0.clone()],
                byte_count: i64::try_from(content.len()).unwrap(),
                chunk_count: i64::try_from(partition.chunk_count).unwrap(),
                sha256: digest.clone(),
                previous_sha256: partition.previous_sha256.clone(),
                item_segment: Some(a::TransferItemSegment {
                    item_id: item.artifact_id.0.clone(),
                    offset: i64::try_from(partition.artifact_offset).unwrap(),
                    item_byte_count: i64::try_from(item.byte_count).unwrap(),
                    is_final_segment: (segment + 1) * part_bytes >= payload.len(),
                }),
            };
            send(
                channel,
                platform,
                DirectMessage::TransferOpen(Unlabeled::from(a::TransferOpen {
                    session: apple_session(&session),
                    partition: apple_partition,
                })),
                v2::Message::TransferOpen(v2::TransferOpen {
                    session: session.clone(),
                    partition: partition.clone(),
                }),
            )
            .await;
            if matches!(
                case,
                TransferCase::BadChain | TransferCase::BadOffset | TransferCase::Disconnect
            ) {
                return;
            }
            expect(
                channel,
                platform,
                DirectMessage::TransferDisposition(Unlabeled::from(a::TransferDisposition {
                    session_id: SwiftUuid(session.session_id),
                    job_id: SwiftUuid(session.job_id),
                    partition_index: i64::try_from(index).unwrap(),
                    partition_sha256: digest.clone(),
                    disposition: a::TransferDispositionKind::Needed,
                    message: None,
                })),
                v2::Message::TransferDisposition(v2::TransferDisposition {
                    session_id: session.session_id,
                    job_id: session.job_id,
                    partition_index: index,
                    partition_sha256: digest.clone(),
                    disposition: v2::TransferDispositionKind::Needed,
                    message: None,
                }),
            )
            .await;
            let mut sent = content.to_vec();
            if case == TransferCase::BadDigest {
                sent[0] ^= 1;
            }
            for (chunk_index, body) in sent
                .chunks(healthmd_protocol::TRANSFER_FRAME_BYTES)
                .enumerate()
            {
                let sequence = u32::try_from(chunk_index + 1).unwrap();
                let chunk_digest = healthmd_protocol::transfer::sha256_hex(body);
                let chunk = a::TransferChunk {
                    transfer_id: SwiftUuid(partition.transfer_id),
                    sequence: if case == TransferCase::BadChunk {
                        2
                    } else {
                        i64::from(sequence)
                    },
                    data: body.to_vec(),
                    sha256: chunk_digest.clone(),
                };
                channel
                    .send_binary_transfer_frame(
                        &healthmd_protocol::transfer::encode_binary_chunk(&chunk).unwrap(),
                    )
                    .await
                    .unwrap();
                if case == TransferCase::BadChunk {
                    return;
                }
                expect(
                    channel,
                    platform,
                    DirectMessage::TransferChunkAcknowledgement(Unlabeled::from(
                        a::TransferChunkAcknowledgement {
                            transfer_id: SwiftUuid(partition.transfer_id),
                            sequence: i64::from(sequence),
                            accepted: true,
                            sha256: chunk_digest.clone(),
                            message: None,
                        },
                    )),
                    v2::Message::TransferChunkAcknowledgement(v2::TransferChunkAcknowledgement {
                        transfer_id: partition.transfer_id,
                        sequence,
                        accepted: true,
                        sha256: chunk_digest,
                        message: None,
                    }),
                )
                .await;
            }
            let complete = v2::TransferPartitionComplete {
                session_id: session.session_id,
                job_id: session.job_id,
                partition_index: index,
                transfer_id: partition.transfer_id,
                partition_sha256: if case == TransferCase::BadComplete {
                    "1".repeat(64)
                } else {
                    digest.clone()
                },
            };
            send(
                channel,
                platform,
                DirectMessage::TransferPartitionComplete(Unlabeled::from(
                    a::TransferPartitionComplete {
                        session_id: SwiftUuid(complete.session_id),
                        job_id: SwiftUuid(complete.job_id),
                        partition_index: i64::try_from(index).unwrap(),
                        transfer_id: SwiftUuid(complete.transfer_id),
                        partition_sha256: complete.partition_sha256.clone(),
                    },
                )),
                v2::Message::TransferPartitionComplete(complete.clone()),
            )
            .await;
            if matches!(
                case,
                TransferCase::BadComplete
                    | TransferCase::PartitionTamper
                    | TransferCase::PartitionFifo
                    | TransferCase::BadDigest
                    | TransferCase::CheckpointDelete
            ) {
                return;
            }
            expect(
                channel,
                platform,
                DirectMessage::TransferPartitionAcknowledgement(Unlabeled::from(
                    a::TransferPartitionAcknowledgement {
                        session_id: SwiftUuid(session.session_id),
                        job_id: SwiftUuid(session.job_id),
                        partition_index: i64::try_from(index).unwrap(),
                        transfer_id: SwiftUuid(partition.transfer_id),
                        partition_sha256: digest.clone(),
                        accepted: true,
                        message: None,
                    },
                )),
                v2::Message::TransferPartitionAcknowledgement(
                    v2::TransferPartitionAcknowledgement {
                        session_id: session.session_id,
                        job_id: session.job_id,
                        partition_index: index,
                        transfer_id: partition.transfer_id,
                        partition_sha256: digest.clone(),
                        accepted: true,
                        message: None,
                    },
                ),
            )
            .await;
            previous = Some(digest);
            index += 1;
        }
    }
    let finalize = v2::TransferFinalize {
        session_id: session.session_id,
        job_id: session.job_id,
        request_fingerprint: session.request_fingerprint.clone(),
        total_partitions: index,
        total_bytes: if case == TransferCase::BadFinalize {
            35
        } else {
            payload.len() as u64 * 2
        },
        final_partition_sha256: previous.clone(),
    };
    send(
        channel,
        platform,
        DirectMessage::TransferFinalize(Unlabeled::from(a::TransferFinalize {
            session_id: SwiftUuid(session.session_id),
            job_id: SwiftUuid(session.job_id),
            request_fingerprint: a::RequestFingerprint {
                version: 1,
                sha256: session.request_fingerprint,
            },
            total_partitions: i64::try_from(index).unwrap(),
            total_bytes: i64::try_from(finalize.total_bytes).unwrap(),
            final_partition_sha256: previous.clone(),
            outcome: None,
        })),
        v2::Message::TransferFinalize(finalize),
    )
    .await;
    if matches!(
        case,
        TransferCase::BadFinalize | TransferCase::FinalPrefixDelete | TransferCase::FinalOutputEdit
    ) {
        return;
    }
    expect(
        channel,
        platform,
        DirectMessage::TransferFinalAcknowledgement(Unlabeled::from(
            a::TransferFinalAcknowledgement {
                session_id: SwiftUuid(session.session_id),
                job_id: SwiftUuid(session.job_id),
                accepted: true,
                total_partitions: i64::try_from(index).unwrap(),
                total_bytes: i64::try_from(payload.len() * 2).unwrap(),
                final_partition_sha256: previous.clone(),
                response_byte_count: None,
                response_sha256: None,
                message: None,
            },
        )),
        v2::Message::TransferFinalAcknowledgement(v2::TransferFinalAcknowledgement {
            session_id: session.session_id,
            job_id: session.job_id,
            accepted: true,
            total_partitions: index,
            total_bytes: payload.len() as u64 * 2,
            final_partition_sha256: previous,
            response_byte_count: None,
            response_sha256: None,
            message: None,
        }),
    )
    .await;
}
#[tokio::test]
async fn authenticated_transfer_receives_segments_and_commits_original_outputs() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        Box::pin(check_output_case(
            platform,
            OutputCase::Transfer(TransferCase::Exact),
        ))
        .await;
        Box::pin(check_output_case(
            platform,
            OutputCase::Transfer(TransferCase::Large),
        ))
        .await;
    }
}
#[tokio::test]
async fn authenticated_transfer_rejects_changed_base_metadata_frames_and_totals() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [
            TransferCase::PartitionTamper,
            TransferCase::PartitionFifo,
            TransferCase::BadDigest,
            TransferCase::CheckpointDelete,
            TransferCase::FinalPrefixDelete,
            TransferCase::FinalOutputEdit,
            TransferCase::BadSession,
            TransferCase::BadManifest,
            TransferCase::BadChain,
            TransferCase::BadOffset,
            TransferCase::BadChunk,
            TransferCase::BadComplete,
            TransferCase::BadFinalize,
            TransferCase::Disconnect,
            TransferCase::Quota,
        ] {
            Box::pin(check_output_case(platform, OutputCase::Transfer(case))).await;
        }
    }
}

pub(super) async fn no_response(channel: &mut SecureChannel, platform: PeerPlatform) {
    let received = tokio::time::timeout(Duration::from_millis(100), async {
        if platform == PeerPlatform::Ios {
            channel.receive().await.map(|_| ())
        } else {
            channel.receive_v2().await.map(|_| ())
        }
    })
    .await;
    assert!(
        !matches!(received, Ok(Ok(()))),
        "rejected transfer must not emit a base acknowledgement"
    );
}
