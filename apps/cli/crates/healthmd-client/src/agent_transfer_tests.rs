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
    Confirmed,
    MarkdownConfirmed,
    BadConfirmationJob,
    BadSourceReceipt,
    MissingSourceReceipt,
    OutputEditDuringConfirmation,
    OutputJournalDeleteDuringConfirmation,
    OutputJournalCorruptDuringConfirmation,
    OutputJournalRollbackDuringConfirmation,
    CompletionDeleteAtReturn,
    CompletionCorruptAtReturn,
    Large,
    BadDigest,
    BadAggregate,
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
impl TransferCase {
    pub(super) fn confirms(self) -> bool {
        matches!(
            self,
            Self::Confirmed
                | Self::MarkdownConfirmed
                | Self::BadConfirmationJob
                | Self::BadSourceReceipt
                | Self::MissingSourceReceipt
                | Self::OutputEditDuringConfirmation
                | Self::OutputJournalDeleteDuringConfirmation
                | Self::OutputJournalCorruptDuringConfirmation
                | Self::OutputJournalRollbackDuringConfirmation
                | Self::CompletionDeleteAtReturn
                | Self::CompletionCorruptAtReturn
        )
    }
}
pub(super) fn payload(case: TransferCase) -> Vec<u8> {
    if case == TransferCase::MarkdownConfirmed {
        b"Fresh preamble\n\n## Steps\n\n- 42 synthetic steps in the recovered day\n".to_vec()
    } else if case == TransferCase::Large {
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
        item.sha256 = if case == TransferCase::BadAggregate {
            Digest("f".repeat(64))
        } else {
            Digest(healthmd_protocol::transfer::sha256_hex(&data))
        };
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
    send_transfer_from(channel, request, platform, case, 0).await;
}

// Ordinary fixture binding remains independently constructed for existing cases.
pub(super) async fn send_transfer_from(
    channel: &mut SecureChannel,
    request: &ExecuteRequest,
    platform: PeerPlatform,
    case: TransferCase,
    prefix: u64,
) {
    send_transfer_with_original(
        channel,
        request,
        platform,
        case,
        prefix,
        binding(request, platform, case),
        None,
    )
    .await;
}

// The resume transcript repeats original metadata and sends only partitions beyond the prefix.
#[allow(clippy::too_many_lines)]
pub(super) async fn send_transfer_with_original(
    channel: &mut SecureChannel,
    request: &ExecuteRequest,
    platform: PeerPlatform,
    case: TransferCase,
    prefix: u64,
    binding: crate::agent_host::output::NativeBinding,
    expected_receipts: Option<&[CommitReceipt]>,
) {
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
                write_mode: serde_json::from_value(serde_json::to_value(&item.write_mode).unwrap())
                    .unwrap(),
            })),
            v2::Message::ArtifactManifest(v2::ArtifactManifest {
                job_id: session.job_id,
                artifact_id: file_id,
                kind: v2::ArtifactKind::GeneratedFile,
                schema: v2::ArtifactSchema {
                    id: "healthmd.generated-files".into(),
                    major: 1,
                },
                media_type: serde_json::to_value(&item.media_type)
                    .unwrap()
                    .as_str()
                    .unwrap()
                    .to_owned(),
                byte_count: item.byte_count,
                sha256: item.sha256.0.clone(),
                relative_path: Some(path),
                write_mode: Some(
                    serde_json::from_value(serde_json::to_value(&item.write_mode).unwrap())
                        .unwrap(),
                ),
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
    let mut frontier = TransferFrontier::new(
        &request.job_id,
        &binding.manifest.request_sha256,
        &document_digest(&binding.manifest).unwrap(),
        &ControlUuid(session.session_id.to_string()),
    )
    .unwrap();
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
            if index < prefix {
                frontier = frontier
                    .appending(&TransferFrontierPartition {
                        partition_index: i64::try_from(index).unwrap(),
                        transfer_id: ControlUuid(partition.transfer_id.to_string()),
                        artifact_id: item.artifact_id.clone(),
                        artifact_offset: i64::try_from(partition.artifact_offset).unwrap(),
                        byte_count: i64::try_from(partition.byte_count).unwrap(),
                        chunk_count: i64::try_from(partition.chunk_count).unwrap(),
                        sha256: Digest(partition.sha256.clone()),
                    })
                    .unwrap();
                previous = Some(digest);
                index += 1;
                continue;
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
            frontier = frontier
                .appending(&TransferFrontierPartition {
                    partition_index: i64::try_from(index).unwrap(),
                    transfer_id: ControlUuid(partition.transfer_id.to_string()),
                    artifact_id: item.artifact_id.clone(),
                    artifact_offset: i64::try_from(partition.artifact_offset).unwrap(),
                    byte_count: i64::try_from(partition.byte_count).unwrap(),
                    chunk_count: i64::try_from(partition.chunk_count).unwrap(),
                    sha256: Digest(partition.sha256.clone()),
                })
                .unwrap();
            previous = Some(digest);
            index += 1;
        }
        if case == TransferCase::BadAggregate {
            no_response(channel, platform).await;
            return;
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
    if case.confirms() {
        if matches!(
            case,
            TransferCase::OutputEditDuringConfirmation
                | TransferCase::OutputJournalDeleteDuringConfirmation
                | TransferCase::OutputJournalCorruptDuringConfirmation
                | TransferCase::OutputJournalRollbackDuringConfirmation
        ) {
            return;
        }
        for (receipt_index, item) in binding.manifest.artifacts.iter().enumerate() {
            let Message::CommitReceipt(receipt) = channel
                .receive_v4(
                    v4::negotiate(
                        &request.plan.intent.peer.platform,
                        &[1, 2, 3, 4],
                        &[1, 2, 3, 4],
                        true,
                    )
                    .unwrap(),
                )
                .await
                .unwrap()
                .message
            else {
                panic!("expected exact host commit");
            };
            let Artifact::Branch1(item) = item else {
                unreachable!()
            };
            validate_commit_receipt(&receipt, None).unwrap();
            assert_eq!(receipt.artifact_id, item.artifact_id);
            assert_eq!(receipt.request_sha256, binding.manifest.request_sha256);
            assert_eq!(receipt.input_sha256, item.sha256);
            if let Some(expected) = expected_receipts {
                assert_eq!(*receipt, expected[receipt_index]);
            } else {
                assert_eq!(receipt.after_sha256, item.sha256);
            }
            assert_eq!(
                receipt.manifest_sha256,
                document_digest(&binding.manifest).unwrap()
            );
            assert_eq!(receipt.destination, request.plan.intent.destination);
        }
        let confirmed = if case == TransferCase::BadConfirmationJob {
            Uuid::parse_str(&id(48).0).unwrap()
        } else {
            session.job_id
        };
        send(
            channel,
            platform,
            DirectMessage::CompletionConfirmed(a::JobIdPayload {
                job_id: SwiftUuid(confirmed),
            }),
            v2::Message::CompletionConfirmed(v2::JobPayload { job_id: confirmed }),
        )
        .await;
        if matches!(
            case,
            TransferCase::BadConfirmationJob | TransferCase::MissingSourceReceipt
        ) {
            return;
        }
        let receipt = ExecutionReceipt {
            schema: ExecutionReceiptSchema::HealthmdAgentExecutionReceipt,
            schema_version: 1,
            job_id: request.job_id.clone(),
            binding: approval_binding(&request.plan),
            request_sha256: binding.manifest.request_sha256.clone(),
            manifest_sha256: document_digest(&binding.manifest).unwrap(),
            frontier_sha256: if case == TransferCase::BadSourceReceipt {
                Digest("1".repeat(64))
            } else {
                frontier.sha256().clone()
            },
            artifact_count: binding.manifest.artifacts.len() as u64,
            committed_partition_count: index,
            source_acknowledged: true,
            status: ExecutionReceiptStatus::Complete,
            expires_at: binding.accepted.expires_at.clone(),
        };
        let negotiation = v4::negotiate(
            &request.plan.intent.peer.platform,
            &[1, 2, 3, 4],
            &[1, 2, 3, 4],
            true,
        )
        .unwrap();
        channel
            .send_v4(
                &Envelope::new(Message::ExecutionReceipt(Box::new(receipt))),
                negotiation,
            )
            .await
            .unwrap();
    }
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

#[tokio::test]
async fn authenticated_transfer_requires_exact_native_confirmation_before_terminal_receipt() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [
            TransferCase::Confirmed,
            TransferCase::BadConfirmationJob,
            TransferCase::BadSourceReceipt,
            TransferCase::MissingSourceReceipt,
            TransferCase::OutputEditDuringConfirmation,
            TransferCase::OutputJournalDeleteDuringConfirmation,
            TransferCase::OutputJournalCorruptDuringConfirmation,
            TransferCase::OutputJournalRollbackDuringConfirmation,
            TransferCase::CompletionDeleteAtReturn,
            TransferCase::CompletionCorruptAtReturn,
        ] {
            Box::pin(check_output_case(platform, OutputCase::Transfer(case))).await;
        }
    }
}
