// Frozen independently source-derived proposals; NO codec implementation executed.
export const personalCodecInterfaceProposal = "Private candidate revision 1 only; no index/package/host exports. Proposed factory createPersonalRecordCodec(context: TrustedPersonalCodecContext) returns decode(input: unknown): Result<OwnedPersonalRecord, PersonalCodecFailure> and encode(input: unknown): Result<string, PersonalCodecFailure>. decode admits only primitive JSON strings; encode admits only owned deep-frozen records minted by the same factory and tracked by private WeakSet, refusing proxies/accessors/foreign clones before property access. No arbitrary caller objects are traversed. Trusted context is separate from JSON, injected by qualified host; synthetic tests do not authenticate it. context.authorize receives a deeply frozen inert closed descriptor with dataset/source-contract/device-install/original-record/purpose/payload-kind and exact source boundary metadata; caller claims in descriptor are not authority. The trusted host reconstructs/binds authoritative catalog/source identity, classification, detail grants and current suppression/deletion fences independently of caller app_class/lineage. The result provides current permitted/denied plus authority/frontier bindings and authoritative app classification/detail eligibility. Excluded or ungranted title raw token spans remain unmaterialized before that authority check; a descriptor never carries title/payload values. Factory trusts this callback; callback faults collapse to fixed scope_not_authorized. No grant/frontier/snapshot/OS permission is inferred from record fields. decode performs bounded syntax/shape preflight before any callback, rejects malformed/ungranted/oversized/excluded records with no parsed payload returned, and checks source catalog plus classification and current detail before payload materialization. encode rechecks current trusted context; suppression denied before serialization. Host authority does not implement store commit/page/native acquisition checks. Fixed failures contain only _tag PersonalCodecFailure and one closed code; no paths/IDs/raw errors/cause. New private JSON grammar: standard JSON tokens only, duplicate keys rejected even escaped-equivalent, scalar Unicode only, NUL/unpaired surrogate rejected, nesting <=32, nodes <=4096, exactly 65536 UTF-8 bytes accepted; raw bound before token work. Key order is ignored on decode; arrays retain order. Canonical encode recursively sorts map keys by Unicode scalar sequence, emits compact UTF-8 JSON, uses explicit primitive string escaping (JSON.stringify scalar strings qualified for this new grammar), revision/nanoseconds/offset raw numeric lexemes must be canonical integer tokens matching 0|-?[1-9][0-9]* before any Number conversion, with revision exactly 1, nanos 0..999999999 and max 9 digits, offsets -86400..86400 and max 6 characters; reject fractional tokens, decimal points, exponent notation and -0 even if numerically integral, as explicitly new PRIVATE grammar; no inherited keys or toJSON. All accepted tagged values preserved byte-for-byte in their string representation. Four closed payloads only, empty health extensions/observation_intervals, synthetic fixture identities/profile/basis only pending source admission. Required fields/selected union arms closed, unknown absent and known states field-specific. Health count exact signed/unsigned/binary64 finite; location canonical units and ranges; source sensor unavailable arms are accepted only fixed native_invalid codes; invalid source payload itself rejects (no source evidence adapter implemented). Aggregate exact bucket start<end duration>=0 and duration<=width under accepted synthetic single-device semantics; session observed start<=end and exact duration equality for synthetic_observation; nonadmitted native_source_arithmetic rejects unsupported_shape. Exact arithmetic uses bounded BigInt IEEE rational decoding and epoch offset 978307200, never Date/Number time conversion. Civil grammar valid years 0001..9999 (new candidate rule) with integer offsets +/-86400; legacy decodeCivilDate year9998 cap and legacy offset +/-64800 are not reused. No query membership/clip/identity mint/equality/store/frontier transaction/archive/profile/native collector implemented." as const;

export const acceptedContractCaseMap = [
  {
    "case_id": "combined-three-domains",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "combined-three-domains",
      "input": {
        "manifest_ref": "#/combined_manifest",
        "records": [
          "synthetic-health-1",
          "synthetic-location-1",
          "synthetic-usage-aggregate-1"
        ]
      },
      "expected": {
        "accept": true,
        "domains": [
          "health",
          "location",
          "device_usage"
        ],
        "record_count": 3,
        "completeness": "partial",
        "native_archive_complete": false
      },
      "evidence_refs": [
        "domain-lineage",
        "health-fixtures"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "health-scoped-same-dataset",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "health-scoped-same-dataset",
      "input": {
        "manifest_ref": "#/combined_manifest",
        "selection_override": {
          "domains": [
            "health"
          ]
        }
      },
      "expected": {
        "dataset_id": "synthetic-dataset-a",
        "record_ids": [
          "synthetic-health-1"
        ],
        "coverage_domains": [
          "health"
        ],
        "no_location_or_usage_detail": true
      },
      "evidence_refs": [
        "domain-lineage",
        "domain-grants"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "point-binary64-lossless",
    "authority": "accepted_draft",
    "classification": "codec",
    "raw_contract": {
      "case_id": "point-binary64-lossless",
      "input": {
        "record_ref": "#/records/1"
      },
      "expected": {
        "timestamp_bits": "3ff0000000000001",
        "epoch": "apple_reference_2001",
        "invented_nanoseconds": false,
        "latitude_bits": "3ff0000000000000",
        "altitude_state": "absent"
      },
      "evidence_refs": [
        "location-point"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "health-large-integer-lossless",
    "authority": "accepted_draft",
    "classification": "codec",
    "raw_contract": {
      "case_id": "health-large-integer-lossless",
      "input": {
        "record_ref": "#/records/0"
      },
      "expected": {
        "decimal": "9007199254740993",
        "number_coercion": false,
        "unit": "count"
      },
      "evidence_refs": [
        "health-precision"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "health-negativezero-preserve",
    "authority": "accepted_draft",
    "classification": "codec",
    "raw_contract": {
      "case_id": "health-negativezero-preserve",
      "input": {
        "value": {
          "representation": "binary64",
          "bits": "8000000000000000",
          "unit": "count"
        }
      },
      "expected": {
        "bits": "8000000000000000",
        "normalized_to_positive_zero": false
      },
      "evidence_refs": [
        "health-precision"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "mixed-epoch-selection-precision",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "mixed-epoch-selection-precision",
      "input": {
        "record_ref": "#/records/1",
        "selection_ref": "#/combined_manifest/selection"
      },
      "expected": {
        "inside_requested_interval": true,
        "point_bits_unchanged": "3ff0000000000001",
        "comparison": "exact_binary_rational_epoch_conversion_required",
        "round_timestamp_for_selection": false
      },
      "evidence_refs": [
        "location-point",
        "health-precision"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "timestamp-nanos-order",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "timestamp-nanos-order",
      "input": {
        "left": {
          "representation": "seconds_nanos",
          "epoch": "unix",
          "epoch_seconds": "9007199254740993",
          "nanoseconds": 1,
          "source_resolution": "nanosecond_representation_not_accuracy",
          "uncertainty": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "right": {
          "representation": "seconds_nanos",
          "epoch": "unix",
          "epoch_seconds": "9007199254740993",
          "nanoseconds": 2,
          "source_resolution": "nanosecond_representation_not_accuracy",
          "uncertainty": {
            "state": "unknown",
            "reason": "not_reported"
          }
        }
      },
      "expected": {
        "order": "left_before_right",
        "Date_or_Number_ordering": false
      },
      "evidence_refs": [
        "health-precision"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "native-calendar-not-inferred",
    "authority": "accepted_draft",
    "classification": "codec",
    "raw_contract": {
      "case_id": "native-calendar-not-inferred",
      "input": {
        "record_ref": "#/records/1"
      },
      "expected": {
        "owner_date": "unknown",
        "timezone": "unknown",
        "derive_from_current_host_zone": false
      },
      "evidence_refs": [
        "location-point",
        "mac-clock"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "aggregate-not-session",
    "authority": "accepted_draft",
    "classification": "codec",
    "raw_contract": {
      "case_id": "aggregate-not-session",
      "input": {
        "record_ref": "#/records/2"
      },
      "expected": {
        "kind": "usage_aggregate",
        "duration_seconds": 600,
        "bucket_seconds": 3600,
        "synthesized_session": false,
        "fill_whole_bucket": false
      },
      "evidence_refs": [
        "mobile-ios",
        "mobile-history"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "short-session-retained",
    "authority": "accepted_draft",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "short-session-retained",
      "input": {
        "record_ref": "#/records/3"
      },
      "expected": {
        "persist_future_observed": true,
        "duration_seconds": 1,
        "discard_below_two_seconds": false
      },
      "evidence_refs": [
        "mac-clock"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "historical-donor-short-tail-gap",
    "authority": "accepted_draft",
    "classification": "separate_native_or_consumer",
    "raw_contract": {
      "case_id": "historical-donor-short-tail-gap",
      "input": {
        "donor_gap": [
          "discarded_short",
          "crash_unflushed",
          "pre_collector"
        ]
      },
      "expected": {
        "reconstruct_exact_session": false,
        "coverage": "partial",
        "gap_retained": true
      },
      "evidence_refs": [
        "mac-clock",
        "mac-history"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "ios-exact-sessions-unestablished",
    "authority": "accepted_draft",
    "classification": "separate_native_or_consumer",
    "raw_contract": {
      "case_id": "ios-exact-sessions-unestablished",
      "input": {
        "source": "ios_historical_usage_aggregate",
        "requested_kind": "foreground_app_session"
      },
      "expected": {
        "fabricate": false,
        "outcome": "unavailable_for_this_source",
        "S06": "required_open",
        "aggregate_shipping_closes_S06": false
      },
      "evidence_refs": [
        "mobile-ios",
        "mobile-history"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "android-prototype-not-supported",
    "authority": "accepted_draft",
    "classification": "separate_native_or_consumer",
    "raw_contract": {
      "case_id": "android-prototype-not-supported",
      "input": {
        "source": "donor_android_event_prototype"
      },
      "expected": {
        "health_android_usage_state": "planned",
        "native_build_capture_coverage_proof": "pending",
        "claim_shared_support": false
      },
      "evidence_refs": [
        "mobile-android"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "unknown-empty-is-not-zero",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "unknown-empty-is-not-zero",
      "input": {
        "source_response": [],
        "coverage": "unknown"
      },
      "expected": {
        "known_usage_seconds": null,
        "coverage": "unknown"
      },
      "evidence_refs": [
        "mobile-history"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "unavailable-empty-is-not-zero",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "unavailable-empty-is-not-zero",
      "input": {
        "source_response": [],
        "coverage": "unavailable",
        "reason": "source_policy_unavailable"
      },
      "expected": {
        "known_usage_seconds": null,
        "coverage": "unavailable",
        "reason_preserved": true
      },
      "evidence_refs": [
        "mobile-ios"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "observed-zero-only-evidence",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "observed-zero-only-evidence",
      "input": {
        "source_value": {
          "representation": "unsigned_integer",
          "decimal": "0",
          "unit": "second"
        },
        "coverage": "complete",
        "completion_evidence": "synthetic_source_receipt",
        "scope": "synthetic_interval_only"
      },
      "expected": {
        "known_zero": true,
        "extend_to_other_period_device_detail": false
      },
      "evidence_refs": [
        "domain-lineage"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "no-fabricated-completeness",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "no-fabricated-completeness",
      "input": {
        "record_count": 0,
        "source_observedSources_flag": true,
        "source_receipt": null
      },
      "expected": {
        "complete": false,
        "coverage": "unknown"
      },
      "evidence_refs": [
        "mobile-history"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "hourly-daily-overlap",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "hourly-daily-overlap",
      "input": {
        "hourly_duration_seconds": "600",
        "daily_duration_seconds": "600",
        "same_source_device_scope": true,
        "same_overlap_group": "synthetic-hourly-daily-group"
      },
      "expected": {
        "sum_seconds": "600",
        "not_sum_seconds": "1200",
        "method": "explicit_reviewed_projection_precedence",
        "originals_retained": true
      },
      "evidence_refs": [
        "mobile-history",
        "domain-lineage"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "cross-device-overlap",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "cross-device-overlap",
      "input": {
        "source_a_total_seconds": "600",
        "source_b_total_seconds": "600",
        "identity_equivalence": "unknown"
      },
      "expected": {
        "automatic_person_total_seconds": null,
        "retain_separate_source_totals": true
      },
      "evidence_refs": [
        "mobile-ios",
        "domain-lineage"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "same-key-same-bytes-replay",
    "authority": "accepted_draft",
    "classification": "separate_repository",
    "raw_contract": {
      "case_id": "same-key-same-bytes-replay",
      "input": {
        "lineage_key": "synthetic-key-a",
        "original_bytes_digest": [
          "synthetic-digest-a",
          "synthetic-digest-a"
        ]
      },
      "expected": {
        "logical_records": 1,
        "idempotent": true,
        "source_lineage_retained": true
      },
      "evidence_refs": [
        "domain-transfer"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "same-key-different-bytes-conflict",
    "authority": "accepted_draft",
    "classification": "separate_repository",
    "raw_contract": {
      "case_id": "same-key-different-bytes-conflict",
      "input": {
        "lineage_key": "synthetic-key-a",
        "original_bytes_digest": [
          "synthetic-digest-a",
          "synthetic-digest-b"
        ]
      },
      "expected": {
        "accept": false,
        "safe_code": "record_identity_conflict",
        "silent_replace": false
      },
      "evidence_refs": [
        "domain-transfer"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "new-install-not-same-device-history",
    "authority": "accepted_draft",
    "classification": "separate_repository",
    "raw_contract": {
      "case_id": "new-install-not-same-device-history",
      "input": {
        "device_id": "synthetic-device-a",
        "installation_ids": [
          "synthetic-install-a",
          "synthetic-install-c"
        ]
      },
      "expected": {
        "preserve_two_installations": true,
        "automatic_dedup": false
      },
      "evidence_refs": [
        "domain-lineage"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "missing-donor-lineage",
    "authority": "accepted_draft",
    "classification": "separate_repository",
    "raw_contract": {
      "case_id": "missing-donor-lineage",
      "input": {
        "original_device": "missing",
        "source_record_id": "missing",
        "import_artifact_id": "synthetic-artifact-a",
        "partition": "synthetic-partition-a",
        "ordinal": "0"
      },
      "expected": {
        "original_identity": "unknown",
        "import_identity": "stable_artifact_partition_ordinal",
        "fabricated_device_or_session_link": false
      },
      "evidence_refs": [
        "location-point",
        "mobile-ios"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "correction-preserves-original",
    "authority": "accepted_draft",
    "classification": "separate_repository",
    "raw_contract": {
      "case_id": "correction-preserves-original",
      "input": {
        "original_record_id": "synthetic-location-1",
        "correction_id": "synthetic-correction-a",
        "correction_timestamp": "not_reported"
      },
      "expected": {
        "original_immutable": true,
        "correction_linked": true,
        "timestamp_invented": false,
        "undo": "append_reversal_preserving_original"
      },
      "evidence_refs": [
        "location-visit",
        "domain-transfer"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "visit-sentinel-not-observed",
    "authority": "accepted_draft",
    "classification": "separate_native_or_consumer",
    "raw_contract": {
      "case_id": "visit-sentinel-not-observed",
      "input": {
        "arrival": "distantPast",
        "departure": "distantFuture",
        "donor_default": "automatic"
      },
      "expected": {
        "sentinel_as_real_epoch": false,
        "certainty": "unknown",
        "default_proves_observation": false
      },
      "evidence_refs": [
        "location-visit"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "outing-not-recording",
    "authority": "accepted_draft",
    "classification": "separate_native_or_consumer",
    "raw_contract": {
      "case_id": "outing-not-recording",
      "input": {
        "source_kind": "inferred_outing",
        "summary_id": "synthetic-summary-a"
      },
      "expected": {
        "recording_session_uuid": null,
        "kind": "inferred_outing",
        "inference_revision_required": true
      },
      "evidence_refs": [
        "location-session"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "browser-app-duration-allowed",
    "authority": "accepted_draft",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "browser-app-duration-allowed",
      "input": {
        "record_ref": "#/records/2"
      },
      "expected": {
        "app_duration_allowed_under_own_grants": true,
        "window_title_or_domain_allowed": false,
        "missing_human_label_omits_app": false
      },
      "evidence_refs": [
        "mac-exclusions",
        "mobile-exclusions"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "browser-title-before-observation",
    "authority": "accepted_draft",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "browser-title-before-observation",
      "input": {
        "app_class": "browser",
        "requested_detail": "desktop_window_title",
        "title_grant": true
      },
      "expected": {
        "call_title_API": false,
        "persist_title": false,
        "queue_title": false,
        "export_or_log_title": false,
        "safe_code": "detail_excluded"
      },
      "evidence_refs": [
        "mac-exclusions",
        "mobile-exclusions"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "unknown-app-class-title-fails-closed",
    "authority": "accepted_draft",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "unknown-app-class-title-fails-closed",
      "input": {
        "app_class": "unknown",
        "requested_detail": "desktop_window_title"
      },
      "expected": {
        "call_title_API": false,
        "persist_title": false,
        "safe_code": "detail_unadmitted"
      },
      "evidence_refs": [
        "mac-exclusions"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "excluded-import-before-staging",
    "authority": "accepted_draft",
    "classification": "separate_native_or_consumer",
    "raw_contract": {
      "case_id": "excluded-import-before-staging",
      "input": {
        "incoming_fields": [
          "browser_url",
          "page_title",
          "typed_text",
          "mouse_coordinates"
        ],
        "migration_requested": true
      },
      "expected": {
        "observe_payload": false,
        "copy_to_staging_or_queue": false,
        "quarantine_payload_copy": false,
        "fixed_field_presence_report_only": true,
        "source_donor_unchanged": true
      },
      "evidence_refs": [
        "mac-exclusions",
        "mobile-exclusions",
        "domain-grants"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "capture-not-export-grant",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "capture-not-export-grant",
      "input": {
        "capture": "allowed",
        "display": "allowed",
        "query": "allowed",
        "export": "not_authorized",
        "destination": "synthetic-local-file"
      },
      "expected": {
        "export": false,
        "automatic_grant": false,
        "safe_code": "export_not_authorized"
      },
      "evidence_refs": [
        "domain-grants",
        "mobile-ios"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "report-view-not-record-export",
    "authority": "accepted_draft",
    "classification": "separate_native_or_consumer",
    "raw_contract": {
      "case_id": "report-view-not-record-export",
      "input": {
        "source": "standard_ios_report_sandbox",
        "display": "allowed",
        "export_request": true
      },
      "expected": {
        "export": false,
        "report_sandbox_escape": false,
        "capability": "display_only"
      },
      "evidence_refs": [
        "mobile-ios"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "future-uploads-not-auto-agent-grant",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "future-uploads-not-auto-agent-grant",
      "input": {
        "upload_enrollment": "allowed",
        "agent_current_snapshot": "allowed",
        "agent_future_uploads": "not_granted"
      },
      "expected": {
        "agent_new_upload_read": false,
        "grant_future_scope_inferred": false
      },
      "evidence_refs": [
        "domain-grants"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "title-query-not-agent-share",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "title-query-not-agent-share",
      "input": {
        "desktop_title_capture": "allowed",
        "desktop_title_local_query": "allowed",
        "agent_detail_grant": "absent"
      },
      "expected": {
        "agent_title": false,
        "upload_enrollment_implies_read": false
      },
      "evidence_refs": [
        "domain-grants"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "strict-scope-denied-no-leak",
    "authority": "accepted_draft",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "strict-scope-denied-no-leak",
      "input": {
        "selection_ref": "#/combined_manifest/selection",
        "denied_detail": "location_exact_point",
        "strictness": "strict"
      },
      "expected": {
        "publish_manifest_or_record": false,
        "partial_deliverable": false,
        "safe_code": "scope_not_authorized",
        "raw_record_id_or_coordinate_in_error": false
      },
      "evidence_refs": [
        "domain-grants"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "partial-scope-explicit",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "partial-scope-explicit",
      "input": {
        "selection_ref": "#/combined_manifest/selection",
        "denied_domain": "location",
        "strictness": "allow_partial"
      },
      "expected": {
        "deliverable_domains": [
          "health",
          "device_usage"
        ],
        "omitted_scope_status": "unavailable",
        "omitted_personal_payload": true,
        "manifest_complete": false
      },
      "evidence_refs": [
        "domain-grants",
        "domain-lineage"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "grant-revoked-during-page",
    "authority": "accepted_draft",
    "classification": "separate_repository",
    "raw_contract": {
      "case_id": "grant-revoked-during-page",
      "input": {
        "grant_revision_before": "synthetic-grant1",
        "grant_revision_now": "synthetic-revoked2"
      },
      "expected": {
        "continue_page": false,
        "publish_staged_results": false,
        "recheck_source_purpose_destination": true
      },
      "evidence_refs": [
        "domain-grants"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "selector-cursor-crosswire",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "selector-cursor-crosswire",
      "input": {
        "requested_dataset": "synthetic-dataset-a",
        "cursor_dataset": "synthetic-dataset-b"
      },
      "expected": {
        "accept": false,
        "safe_code": "scope_binding_mismatch",
        "binding_required": [
          "caller",
          "dataset",
          "revision",
          "source",
          "purpose",
          "selection",
          "snapshot",
          "grant_revision",
          "expiry"
        ]
      },
      "evidence_refs": [
        "domain-lineage"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "geographic-health-distance-distinct",
    "authority": "accepted_draft",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "geographic-health-distance-distinct",
      "input": {
        "location_path_distance": "synthetic_location_distance",
        "health_distance": "distance_walking_running"
      },
      "expected": {
        "alias_semantic_id": false,
        "sum_as_same_statistic": false
      },
      "evidence_refs": [
        "health-precision",
        "location-point"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "frozen-health-profiles",
    "authority": "accepted_draft",
    "classification": "separate_native_or_consumer",
    "raw_contract": {
      "case_id": "frozen-health-profiles",
      "input": {
        "requested_profiles": [
          "apple_health_data_v8",
          "android_frozen_v4",
          "android_analytical_v5"
        ]
      },
      "expected": {
        "bytes_or_grammar_changed": false,
        "personal_candidate_admitted": false
      },
      "evidence_refs": [
        "health-fixtures"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "summary-not-complete-transfer",
    "authority": "accepted_draft",
    "classification": "separate_native_or_consumer",
    "raw_contract": {
      "case_id": "summary-not-complete-transfer",
      "input": {
        "donor_artifacts": [
          "mac365daymirror",
          "mobile370snapshot",
          "location_formatted_export"
        ]
      },
      "expected": {
        "complete_native_archive": false,
        "required_full_retained_history": "all_available_permitted_native_state",
        "credentials_purchases_armed_schedules_adopted": false
      },
      "evidence_refs": [
        "domain-transfer",
        "mac-mirror",
        "location-transfer",
        "mobile-history"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "complete-history-no-dashboard-cap",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "complete-history-no-dashboard-cap",
      "input": {
        "available_history_days": "synthetic-more-than-370",
        "page_limit_records": 4096
      },
      "expected": {
        "iterate_all_available_authorized_pages": true,
        "global_history_cap_days": null,
        "invent_unavailable_history": false
      },
      "evidence_refs": [
        "mac-history",
        "mobile-history"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "nonfinite-or-overprecision",
    "authority": "accepted_draft",
    "classification": "codec",
    "raw_contract": {
      "case_id": "nonfinite-or-overprecision",
      "input": {
        "number_bits": "7ff0000000000000",
        "timestamp_nanos": 1000000000
      },
      "expected": {
        "accept": false,
        "safe_code": "invalid_exact_value",
        "coerce_or_round": false
      },
      "evidence_refs": [
        "health-precision"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "bounded-page-admission",
    "authority": "accepted_draft",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "bounded-page-admission",
      "input": {
        "candidate_record_raw_bytes": 65537,
        "candidate_page_record_count": 4097
      },
      "expected": {
        "accept": false,
        "safe_code": "candidate_limit_exceeded",
        "claim_production_budget": false
      },
      "evidence_refs": [
        "health-precision"
      ],
      "proof_class": "planning",
      "execution": "literal_expected_before_future_codec_not_executed"
    }
  },
  {
    "case_id": "resolution-coordinate-endpoints",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "resolution-coordinate-endpoints",
      "input": {
        "latitude": "4056800000000000",
        "longitude": "4066800000000000"
      },
      "expected": {
        "canonical_status": "valid",
        "latitude_degrees": 90,
        "longitude_degrees": 180,
        "wrap": false
      }
    }
  },
  {
    "case_id": "resolution-coordinate-outside",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "resolution-coordinate-outside",
      "input": {
        "latitude": "4056c00000000000"
      },
      "expected": {
        "canonical_status": "outside_canonical",
        "reason": "coordinate_out_of_range",
        "retain_eligible_original_evidence": true
      }
    }
  },
  {
    "case_id": "resolution-nonfinite-coordinate",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "resolution-nonfinite-coordinate",
      "input": {
        "latitude": "7ff8000000000000"
      },
      "expected": {
        "canonical_status": "outside_canonical",
        "canonical_value": null,
        "retain_eligible_original_evidence": true
      }
    }
  },
  {
    "case_id": "resolution-negative-speed-sentinel",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "resolution-negative-speed-sentinel",
      "input": {
        "speed_bits": "bff0000000000000"
      },
      "expected": {
        "state": "unavailable",
        "reason": "native_invalid_speed",
        "original_bits_retained": "bff0000000000000",
        "complete_archive_silent_drop": false
      }
    }
  },
  {
    "case_id": "resolution-negative-accuracy-sentinel",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "resolution-negative-accuracy-sentinel",
      "input": {
        "accuracy_bits": "bff0000000000000"
      },
      "expected": {
        "state": "unavailable",
        "reason": "native_invalid_accuracy",
        "coerce_zero": false
      }
    }
  },
  {
    "case_id": "resolution-negativezero-speed",
    "authority": "accepted_resolution",
    "classification": "codec",
    "raw_contract": {
      "case_id": "resolution-negativezero-speed",
      "input": {
        "speed_bits": "8000000000000000"
      },
      "expected": {
        "canonical_status": "valid",
        "bits": "8000000000000000"
      }
    }
  },
  {
    "case_id": "resolution-reversed-session",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "resolution-reversed-session",
      "input": {
        "start_seconds": "2",
        "end_seconds": "1",
        "duration_bits": "bff0000000000000"
      },
      "expected": {
        "canonical_status": "outside_canonical",
        "reason": "clock_inconsistent",
        "invent_session": false,
        "retain_original": true
      }
    }
  },
  {
    "case_id": "resolution-duration-disagreement",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "resolution-duration-disagreement",
      "input": {
        "start_seconds": "0",
        "end_seconds": "1",
        "duration_bits": "4000000000000000",
        "basis": "synthetic_observation"
      },
      "expected": {
        "canonical_status": "outside_canonical",
        "repair_duration": false
      }
    }
  },
  {
    "case_id": "resolution-zero-session",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "resolution-zero-session",
      "input": {
        "start_seconds": "1",
        "end_seconds": "1",
        "duration_bits": "0000000000000000"
      },
      "expected": {
        "canonical_status": "valid",
        "retain": true,
        "membership": "point"
      }
    }
  },
  {
    "case_id": "resolution-original-record-equality",
    "authority": "accepted_resolution",
    "classification": "separate_repository",
    "raw_contract": {
      "case_id": "resolution-original-record-equality",
      "input": {
        "same_key": true,
        "same_lossless_field_vector": true,
        "artifact_whitespace_changed": true,
        "transport_page_changed": true
      },
      "expected": {
        "logical_originals": 1,
        "retain_two_import_evidence_links": true
      }
    }
  },
  {
    "case_id": "resolution-lossy-equality-conflict",
    "authority": "accepted_resolution",
    "classification": "separate_repository",
    "raw_contract": {
      "case_id": "resolution-lossy-equality-conflict",
      "input": {
        "same_key": true,
        "canonical_values_equal": true,
        "original_accuracy_bits_differ": true
      },
      "expected": {
        "accept": false,
        "safe_code": "record_identity_conflict"
      }
    }
  },
  {
    "case_id": "resolution-repartition-key",
    "authority": "accepted_resolution",
    "classification": "separate_repository",
    "raw_contract": {
      "case_id": "resolution-repartition-key",
      "input": {
        "original_artifact_id": "synthetic-artifact",
        "original_partition": "root",
        "ordinal": "7",
        "transport_pages": [
          "page-a",
          "page-b"
        ]
      },
      "expected": {
        "import_keys": 1,
        "native_original_identity": "unknown",
        "page_in_identity": false
      }
    }
  },
  {
    "case_id": "resolution-missing-stable-import-order",
    "authority": "accepted_resolution",
    "classification": "separate_repository",
    "raw_contract": {
      "case_id": "resolution-missing-stable-import-order",
      "input": {
        "native_id": "unknown",
        "stable_artifact_enumeration": false
      },
      "expected": {
        "automatic_merge": false,
        "import_identity": "unknown"
      }
    }
  },
  {
    "case_id": "resolution-apple-unix-equality",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "resolution-apple-unix-equality",
      "input": {
        "apple_bits": "0000000000000000",
        "unix_seconds": "978307200",
        "unix_nanos": 0
      },
      "expected": {
        "order": "equal",
        "stored_epoch_unchanged": true
      }
    }
  },
  {
    "case_id": "resolution-dyadic-subnanosecond",
    "authority": "accepted_resolution",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "resolution-dyadic-subnanosecond",
      "input": {
        "unix_bits": "3ff0000000000001",
        "query_start_seconds": "1",
        "query_start_nanos": 0,
        "query_end_seconds": "1",
        "query_end_nanos": 1
      },
      "expected": {
        "membership": true,
        "round_to_one_second": false,
        "source_nanos_invented": false
      }
    }
  },
  {
    "case_id": "resolution-half-open-end",
    "authority": "accepted_resolution",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "resolution-half-open-end",
      "input": {
        "point_seconds": "1",
        "start_seconds": "0",
        "end_seconds": "1"
      },
      "expected": {
        "membership": false
      }
    }
  },
  {
    "case_id": "resolution-negative-floor-nanos",
    "authority": "accepted_resolution",
    "classification": "codec",
    "raw_contract": {
      "case_id": "resolution-negative-floor-nanos",
      "input": {
        "epoch_seconds": "-1",
        "nanoseconds": 999999999
      },
      "expected": {
        "exact_seconds": "-1/1000000000",
        "valid": true
      }
    }
  },
  {
    "case_id": "resolution-aggregate-partial-strict",
    "authority": "accepted_resolution",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "resolution-aggregate-partial-strict",
      "input": {
        "bucket": [
          "0",
          "3600"
        ],
        "query": [
          "1800",
          "3600"
        ],
        "duration_seconds": "600",
        "strictness": "strict"
      },
      "expected": {
        "deliverable": false,
        "safe_code": "aggregate_partial_overlap",
        "estimated_seconds": null
      }
    }
  },
  {
    "case_id": "resolution-aggregate-partial-allowed",
    "authority": "accepted_resolution",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "resolution-aggregate-partial-allowed",
      "input": {
        "bucket": [
          "0",
          "3600"
        ],
        "query": [
          "1800",
          "3600"
        ],
        "strictness": "allow_partial"
      },
      "expected": {
        "selected_aggregate_count": 0,
        "coverage": "partial",
        "complete": false
      }
    }
  },
  {
    "case_id": "resolution-aggregate-whole-context",
    "authority": "accepted_resolution",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "resolution-aggregate-whole-context",
      "input": {
        "bucket": [
          "0",
          "3600"
        ],
        "query": [
          "1800",
          "3600"
        ],
        "duration_seconds": "600",
        "projection": "whole_bucket_context",
        "whole_bucket_grant": true
      },
      "expected": {
        "duration_seconds": "600",
        "extends_beyond_selection": true,
        "requested_interval_total": null
      }
    }
  },
  {
    "case_id": "resolution-aggregate-context-denied",
    "authority": "accepted_resolution",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "resolution-aggregate-context-denied",
      "input": {
        "projection": "whole_bucket_context",
        "whole_bucket_grant": false
      },
      "expected": {
        "materialize": false,
        "safe_code": "scope_not_authorized"
      }
    }
  },
  {
    "case_id": "resolution-observed-session-clip",
    "authority": "accepted_resolution",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "resolution-observed-session-clip",
      "input": {
        "original": [
          "0",
          "10"
        ],
        "query": [
          "3",
          "7"
        ],
        "consistent_observation": true
      },
      "expected": {
        "original": [
          "0",
          "10"
        ],
        "derived_interval": [
          "3",
          "7"
        ],
        "derived_duration_seconds": "4",
        "derived_not_original": true
      }
    }
  },
  {
    "case_id": "resolution-tombstone-replay",
    "authority": "accepted_resolution",
    "classification": "separate_repository",
    "raw_contract": {
      "case_id": "resolution-tombstone-replay",
      "input": {
        "tombstone_revision": "2",
        "replay_original_revision": "1"
      },
      "expected": {
        "query_visible": false,
        "export_visible": false,
        "original_evidence_immutable": true
      }
    }
  },
  {
    "case_id": "resolution-correction-under-tombstone",
    "authority": "accepted_resolution",
    "classification": "separate_repository",
    "raw_contract": {
      "case_id": "resolution-correction-under-tombstone",
      "input": {
        "tombstone_current": true,
        "correction_new": true,
        "explicit_restore": false
      },
      "expected": {
        "current_projection_visible": false
      }
    }
  },
  {
    "case_id": "resolution-delete-backup-regrant",
    "authority": "accepted_resolution",
    "classification": "separate_repository",
    "raw_contract": {
      "case_id": "resolution-delete-backup-regrant",
      "input": {
        "deletion_fence_current": true,
        "old_backup": true,
        "new_capture_grant": true
      },
      "expected": {
        "resurrect": false,
        "publish": false
      }
    }
  },
  {
    "case_id": "resolution-frontier-changes-before-commit",
    "authority": "accepted_resolution",
    "classification": "separate_repository",
    "raw_contract": {
      "case_id": "resolution-frontier-changes-before-commit",
      "input": {
        "page_frontier": "1",
        "current_frontier": "2"
      },
      "expected": {
        "commit": false,
        "staged_visible": false,
        "safe_code": "scope_binding_mismatch"
      }
    }
  },
  {
    "case_id": "resolution-recipient-copy-limit",
    "authority": "accepted_resolution",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "resolution-recipient-copy-limit",
      "input": {
        "recipient_already_downloaded": true,
        "grant_now_revoked": true
      },
      "expected": {
        "new_reads": false,
        "recall_claim": false
      }
    }
  },
  {
    "case_id": "resolution-schema-boolean-version",
    "authority": "accepted_resolution",
    "classification": "codec",
    "raw_contract": {
      "case_id": "resolution-schema-boolean-version",
      "input": {
        "payload_revision": true
      },
      "expected": {
        "accept": false,
        "safe_code": "unsupported_shape"
      }
    }
  },
  {
    "case_id": "resolution-unknown-source-field",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "resolution-unknown-source-field",
      "input": {
        "new_source_field": true,
        "same_canonical_projection": true
      },
      "expected": {
        "silently_discard": false,
        "admit_unreviewed_schema": false
      }
    }
  },
  {
    "case_id": "resolution-archive-excluded-title",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "resolution-archive-excluded-title",
      "input": {
        "browser_title_present": true,
        "archive_grant": true
      },
      "expected": {
        "observe_or_stage_title": false,
        "complete_eligible_archive_includes_title": false
      }
    }
  },
  {
    "case_id": "resolution-reasonless-sensor-absent",
    "authority": "accepted_resolution",
    "classification": "codec",
    "raw_contract": {
      "case_id": "resolution-reasonless-sensor-absent",
      "input": {
        "altitude": {
          "state": "absent"
        },
        "speed": {
          "state": "absent"
        }
      },
      "expected": {
        "accept": true,
        "reason_required": false
      }
    }
  },
  {
    "case_id": "resolution-absent-sensor-wrong-value",
    "authority": "accepted_resolution",
    "classification": "codec",
    "raw_contract": {
      "case_id": "resolution-absent-sensor-wrong-value",
      "input": {
        "speed": {
          "state": "absent",
          "value": 0
        }
      },
      "expected": {
        "accept": false,
        "safe_code": "unsupported_shape"
      }
    }
  },
  {
    "case_id": "resolution-native-source-rounded-subtraction",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "resolution-native-source-rounded-subtraction",
      "input": {
        "start_bits": "3fb999999999999a",
        "end_bits": "3ff199999999999a",
        "duration_bits": "3ff0000000000000",
        "basis": "native_source_arithmetic"
      },
      "expected": {
        "exact_endpoint_difference": "36028797018963971/36028797018963968",
        "source_duration_bits_retained": "3ff0000000000000",
        "automatic_clock_inconsistent": false,
        "current_synthetic_admission": false,
        "future_source_semantic_qualification": "required"
      }
    }
  },
  {
    "case_id": "resolution-delete-restore-denied",
    "authority": "accepted_resolution",
    "classification": "separate_repository",
    "raw_contract": {
      "case_id": "resolution-delete-restore-denied",
      "input": {
        "deletion_fence_current": true,
        "explicit_restore_event": true,
        "restore_revision_above_delete": true,
        "new_grant": true
      },
      "expected": {
        "restore": false,
        "query_or_export": false,
        "safe_code": "restoration_fenced"
      }
    }
  },
  {
    "case_id": "resolution-authoritative-frontier-restore-denied",
    "authority": "accepted_resolution",
    "classification": "separate_repository",
    "raw_contract": {
      "case_id": "resolution-authoritative-frontier-restore-denied",
      "input": {
        "current_external_suppression_journal": true,
        "local_restore_event": true,
        "backup_or_renamed_record": true
      },
      "expected": {
        "restore": false,
        "publish": false,
        "safe_code": "restoration_fenced"
      }
    }
  },
  {
    "case_id": "resolution-local-tombstone-reversible-only",
    "authority": "accepted_resolution",
    "classification": "separate_repository",
    "raw_contract": {
      "case_id": "resolution-local-tombstone-reversible-only",
      "input": {
        "local_tombstone": true,
        "deletion_or_revocation_fence": false,
        "evidence_eligible": true,
        "reviewed_restore_intent_and_current_grants": true
      },
      "expected": {
        "candidate_local_reversal_permitted": true,
        "override_external_frontier": false,
        "durable_restoration_execution_qualified": false
      }
    }
  },
  {
    "case_id": "resolution-unrepresentable-clipped-duration",
    "authority": "accepted_resolution",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "resolution-unrepresentable-clipped-duration",
      "input": {
        "exact_duration": "36028797018963971/36028797018963968",
        "accepted_rational_or_ticks_derivation_schema": false
      },
      "expected": {
        "projection": false,
        "round_to_binary64": false,
        "safe_code": "exact_projection_unrepresentable"
      }
    }
  }
] as const;

export const personalRecordVectors = [
  {
    "case_id": "literal-record-0",
    "input_json": "{\"domain\":\"health\",\"payload_kind\":\"health_fact\",\"payload_revision\":1,\"record_id\":\"synthetic-health-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"semantic_id\":\"synthetic.health.exact_count\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"statistic\":\"observation\",\"value\":{\"representation\":\"unsigned_integer\",\"decimal\":\"9007199254740993\",\"unit\":\"count\"},\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"extensions\":[]}}",
    "expected_record": {
      "domain": "health",
      "payload_kind": "health_fact",
      "payload_revision": 1,
      "record_id": "synthetic-health-1",
      "lineage": {
        "dataset_id": "synthetic-dataset-a",
        "device": {
          "state": "known",
          "value": "synthetic-device-a"
        },
        "installation": {
          "state": "known",
          "value": "synthetic-install-a"
        },
        "source_id": "synthetic-source-a",
        "source_revision": "synthetic-source-contract1",
        "purpose": "synthetic_local_collection",
        "original_record": {
          "state": "known",
          "value": "synthetic-health-original"
        },
        "record_revision": "1",
        "acquisition": "synthetic_fixture",
        "source_observation": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "integrity_binding": "fixture_only_not_authentication"
      },
      "time": {
        "instant": {
          "representation": "seconds_nanos",
          "epoch": "unix",
          "epoch_seconds": "0",
          "nanoseconds": 1,
          "source_resolution": "nanosecond_representation_not_accuracy",
          "uncertainty": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "source_utc_offset_seconds": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "calendar": {
          "time_zone": {
            "state": "unknown",
            "reason": "not_reported"
          },
          "owner_date": {
            "state": "unknown",
            "reason": "not_reported"
          },
          "owner_rule": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "observed_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "captured_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "imported_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "uploaded_at": {
          "state": "unknown",
          "reason": "not_reported"
        }
      },
      "payload": {
        "semantic_id": "synthetic.health.exact_count",
        "native_semantic_id": {
          "state": "known",
          "value": "synthetic.health.exact_count"
        },
        "statistic": "observation",
        "value": {
          "representation": "unsigned_integer",
          "decimal": "9007199254740993",
          "unit": "count"
        },
        "native_profile": "synthetic_only_not_metric_registry_admission",
        "extensions": []
      }
    },
    "expected_encoded": "{\"domain\":\"health\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"extensions\":[],\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"semantic_id\":\"synthetic.health.exact_count\",\"statistic\":\"observation\",\"value\":{\"decimal\":\"9007199254740993\",\"representation\":\"unsigned_integer\",\"unit\":\"count\"}},\"payload_kind\":\"health_fact\",\"payload_revision\":1,\"record_id\":\"synthetic-health-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}"
  },
  {
    "case_id": "literal-record-1",
    "input_json": "{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}",
    "expected_record": {
      "domain": "location",
      "payload_kind": "location_point",
      "payload_revision": 1,
      "record_id": "synthetic-location-1",
      "lineage": {
        "dataset_id": "synthetic-dataset-a",
        "device": {
          "state": "known",
          "value": "synthetic-device-a"
        },
        "installation": {
          "state": "known",
          "value": "synthetic-install-a"
        },
        "source_id": "synthetic-source-a",
        "source_revision": "synthetic-source-contract1",
        "purpose": "synthetic_local_collection",
        "original_record": {
          "state": "known",
          "value": "synthetic-location-uuid"
        },
        "record_revision": "1",
        "acquisition": "synthetic_fixture",
        "source_observation": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "integrity_binding": "fixture_only_not_authentication"
      },
      "time": {
        "instant": {
          "representation": "binary64_epoch_seconds",
          "epoch": "apple_reference_2001",
          "bits": "3ff0000000000001",
          "source_resolution": "binary64_storage",
          "uncertainty": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "source_utc_offset_seconds": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "calendar": {
          "time_zone": {
            "state": "unknown",
            "reason": "not_reported"
          },
          "owner_date": {
            "state": "unknown",
            "reason": "not_reported"
          },
          "owner_rule": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "observed_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "captured_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "imported_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "uploaded_at": {
          "state": "unknown",
          "reason": "not_reported"
        }
      },
      "payload": {
        "latitude": {
          "representation": "binary64",
          "bits": "3ff0000000000000",
          "unit": "degree"
        },
        "longitude": {
          "representation": "binary64",
          "bits": "c000000000000000",
          "unit": "degree"
        },
        "horizontal_accuracy": {
          "representation": "binary64",
          "bits": "4000000000000000",
          "unit": "meter"
        },
        "altitude": {
          "state": "absent"
        },
        "speed": {
          "state": "absent"
        },
        "quality": {
          "source_is_outlier": false,
          "certainty": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "recording_session": {
          "state": "unknown",
          "reason": "not_reported"
        }
      }
    },
    "expected_encoded": "{\"domain\":\"location\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"altitude\":{\"state\":\"absent\"},\"horizontal_accuracy\":{\"bits\":\"4000000000000000\",\"representation\":\"binary64\",\"unit\":\"meter\"},\"latitude\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"longitude\":{\"bits\":\"c000000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"quality\":{\"certainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_is_outlier\":false},\"recording_session\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"speed\":{\"state\":\"absent\"}},\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3ff0000000000001\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}"
  },
  {
    "case_id": "literal-record-2",
    "input_json": "{\"domain\":\"device_usage\",\"payload_kind\":\"usage_aggregate\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-aggregate-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-b\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-b\"},\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-bucket-id\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"app\":{\"identity\":{\"state\":\"known\",\"value\":\"synthetic-browser-app\"},\"identity_kind\":\"synthetic_application_id\",\"app_class\":\"browser\",\"display_label\":{\"state\":\"unknown\",\"reason\":\"withheld\"}},\"bucket\":{\"start\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"end\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"3600\",\"nanoseconds\":0,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"boundaries\":\"half_open\",\"calendar\":{\"time_zone\":{\"state\":\"known\",\"value\":\"Etc/UTC\"},\"owner_date\":{\"state\":\"known\",\"value\":\"1970-01-01\"},\"owner_rule\":\"synthetic_source_bucket\"}},\"statistic\":\"source_total_duration\",\"duration\":{\"representation\":\"binary64\",\"bits\":\"4082c00000000000\",\"unit\":\"second\"},\"resolution\":\"hourly_bucket\",\"source_device_scope\":\"one_synthetic_device\",\"observed_session_count\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"original_source_precision\":{\"state\":\"known\",\"value\":\"binary64_seconds\"},\"overlap_group\":{\"state\":\"known\",\"value\":\"synthetic-hourly-daily-group\"},\"derived\":false}}",
    "expected_record": {
      "domain": "device_usage",
      "payload_kind": "usage_aggregate",
      "payload_revision": 1,
      "record_id": "synthetic-usage-aggregate-1",
      "lineage": {
        "dataset_id": "synthetic-dataset-a",
        "device": {
          "state": "known",
          "value": "synthetic-device-b"
        },
        "installation": {
          "state": "known",
          "value": "synthetic-install-b"
        },
        "source_id": "synthetic-source-b",
        "source_revision": "synthetic-source-contract1",
        "purpose": "synthetic_local_collection",
        "original_record": {
          "state": "known",
          "value": "synthetic-bucket-id"
        },
        "record_revision": "1",
        "acquisition": "synthetic_fixture",
        "source_observation": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "integrity_binding": "fixture_only_not_authentication"
      },
      "time": {
        "instant": {
          "representation": "seconds_nanos",
          "epoch": "unix",
          "epoch_seconds": "0",
          "nanoseconds": 0,
          "source_resolution": "nanosecond_representation_not_accuracy",
          "uncertainty": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "source_utc_offset_seconds": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "calendar": {
          "time_zone": {
            "state": "unknown",
            "reason": "not_reported"
          },
          "owner_date": {
            "state": "unknown",
            "reason": "not_reported"
          },
          "owner_rule": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "observed_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "captured_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "imported_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "uploaded_at": {
          "state": "unknown",
          "reason": "not_reported"
        }
      },
      "payload": {
        "app": {
          "identity": {
            "state": "known",
            "value": "synthetic-browser-app"
          },
          "identity_kind": "synthetic_application_id",
          "app_class": "browser",
          "display_label": {
            "state": "unknown",
            "reason": "withheld"
          }
        },
        "bucket": {
          "start": {
            "representation": "seconds_nanos",
            "epoch": "unix",
            "epoch_seconds": "0",
            "nanoseconds": 0,
            "source_resolution": "nanosecond_representation_not_accuracy",
            "uncertainty": {
              "state": "unknown",
              "reason": "not_reported"
            }
          },
          "end": {
            "representation": "seconds_nanos",
            "epoch": "unix",
            "epoch_seconds": "3600",
            "nanoseconds": 0,
            "source_resolution": "nanosecond_representation_not_accuracy",
            "uncertainty": {
              "state": "unknown",
              "reason": "not_reported"
            }
          },
          "boundaries": "half_open",
          "calendar": {
            "time_zone": {
              "state": "known",
              "value": "Etc/UTC"
            },
            "owner_date": {
              "state": "known",
              "value": "1970-01-01"
            },
            "owner_rule": "synthetic_source_bucket"
          }
        },
        "statistic": "source_total_duration",
        "duration": {
          "representation": "binary64",
          "bits": "4082c00000000000",
          "unit": "second"
        },
        "resolution": "hourly_bucket",
        "source_device_scope": "one_synthetic_device",
        "observed_session_count": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "original_source_precision": {
          "state": "known",
          "value": "binary64_seconds"
        },
        "overlap_group": {
          "state": "known",
          "value": "synthetic-hourly-daily-group"
        },
        "derived": false
      }
    },
    "expected_encoded": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-b\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-b\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-bucket-id\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-b\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"browser\",\"display_label\":{\"reason\":\"withheld\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-browser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"bucket\":{\"boundaries\":\"half_open\",\"calendar\":{\"owner_date\":{\"state\":\"known\",\"value\":\"1970-01-01\"},\"owner_rule\":\"synthetic_source_bucket\",\"time_zone\":{\"state\":\"known\",\"value\":\"Etc/UTC\"}},\"end\":{\"epoch\":\"unix\",\"epoch_seconds\":\"3600\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"start\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"derived\":false,\"duration\":{\"bits\":\"4082c00000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"observed_session_count\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"original_source_precision\":{\"state\":\"known\",\"value\":\"binary64_seconds\"},\"overlap_group\":{\"state\":\"known\",\"value\":\"synthetic-hourly-daily-group\"},\"resolution\":\"hourly_bucket\",\"source_device_scope\":\"one_synthetic_device\",\"statistic\":\"source_total_duration\"},\"payload_kind\":\"usage_aggregate\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-aggregate-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}"
  },
  {
    "case_id": "literal-record-3",
    "input_json": "{\"domain\":\"device_usage\",\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"app\":{\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\",\"app_class\":\"non_browser\",\"display_label\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"start\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"certainty\":\"observed\"},\"end\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":1,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"certainty\":\"observed\"},\"duration\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"observation_intervals\":[],\"title\":{\"state\":\"not_observed\",\"reason\":\"no_title_grant\"},\"device_state\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}",
    "expected_record": {
      "domain": "device_usage",
      "payload_kind": "foreground_app_session",
      "payload_revision": 1,
      "record_id": "synthetic-usage-session-1",
      "lineage": {
        "dataset_id": "synthetic-dataset-a",
        "device": {
          "state": "known",
          "value": "synthetic-device-a"
        },
        "installation": {
          "state": "known",
          "value": "synthetic-install-a"
        },
        "source_id": "synthetic-source-a",
        "source_revision": "synthetic-source-contract1",
        "purpose": "synthetic_local_collection",
        "original_record": {
          "state": "known",
          "value": "synthetic-session-original"
        },
        "record_revision": "1",
        "acquisition": "synthetic_fixture",
        "source_observation": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "integrity_binding": "fixture_only_not_authentication"
      },
      "time": {
        "instant": {
          "representation": "seconds_nanos",
          "epoch": "unix",
          "epoch_seconds": "0",
          "nanoseconds": 1,
          "source_resolution": "nanosecond_representation_not_accuracy",
          "uncertainty": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "source_utc_offset_seconds": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "calendar": {
          "time_zone": {
            "state": "unknown",
            "reason": "not_reported"
          },
          "owner_date": {
            "state": "unknown",
            "reason": "not_reported"
          },
          "owner_rule": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "observed_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "captured_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "imported_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "uploaded_at": {
          "state": "unknown",
          "reason": "not_reported"
        }
      },
      "payload": {
        "app": {
          "identity": {
            "state": "known",
            "value": "synthetic-nonbrowser-app"
          },
          "identity_kind": "synthetic_application_id",
          "app_class": "non_browser",
          "display_label": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "start": {
          "instant": {
            "representation": "seconds_nanos",
            "epoch": "unix",
            "epoch_seconds": "0",
            "nanoseconds": 1,
            "source_resolution": "nanosecond_representation_not_accuracy",
            "uncertainty": {
              "state": "unknown",
              "reason": "not_reported"
            }
          },
          "certainty": "observed"
        },
        "end": {
          "instant": {
            "representation": "seconds_nanos",
            "epoch": "unix",
            "epoch_seconds": "1",
            "nanoseconds": 1,
            "source_resolution": "nanosecond_representation_not_accuracy",
            "uncertainty": {
              "state": "unknown",
              "reason": "not_reported"
            }
          },
          "certainty": "observed"
        },
        "duration": {
          "representation": "binary64",
          "bits": "3ff0000000000000",
          "unit": "second"
        },
        "duration_basis": "synthetic_observation",
        "observation_intervals": [],
        "title": {
          "state": "not_observed",
          "reason": "no_title_grant"
        },
        "device_state": {
          "state": "unknown",
          "reason": "not_reported"
        }
      }
    },
    "expected_encoded": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":1,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}"
  }
] as const;

export const personalMutationVectors = [
  {
    "case_id": "boolean-revision",
    "base_record_index": 0,
    "replace_or_add": "/payload_revision",
    "literal_value": true,
    "expected_failure": "unsupported_shape"
  },
  {
    "case_id": "unknown-root-key",
    "base_record_index": 0,
    "replace_or_add": "/unknown",
    "literal_value": true,
    "expected_failure": "unsupported_shape"
  },
  {
    "case_id": "wrong-domain-kind",
    "base_record_index": 0,
    "replace_or_add": "/domain",
    "literal_value": "location",
    "expected_failure": "unsupported_shape"
  },
  {
    "case_id": "nonempty-health-extension",
    "base_record_index": 0,
    "replace_or_add": "/payload/extensions",
    "literal_value": [
      {}
    ],
    "expected_failure": "unsupported_shape"
  },
  {
    "case_id": "negative-zero-decimal",
    "base_record_index": 0,
    "replace_or_add": "/payload/value/decimal",
    "literal_value": "-0",
    "expected_failure": "invalid_exact_value"
  },
  {
    "case_id": "leading-zero-decimal",
    "base_record_index": 0,
    "replace_or_add": "/payload/value/decimal",
    "literal_value": "01",
    "expected_failure": "invalid_exact_value"
  },
  {
    "case_id": "overflow-unsigned",
    "base_record_index": 0,
    "replace_or_add": "/payload/value/decimal",
    "literal_value": "340282366920938463463374607431768211456",
    "expected_failure": "invalid_exact_value"
  },
  {
    "case_id": "bad-unit",
    "base_record_index": 0,
    "replace_or_add": "/payload/value/unit",
    "literal_value": "meter",
    "expected_failure": "unsupported_shape"
  },
  {
    "case_id": "nanos-overflow",
    "base_record_index": 0,
    "replace_or_add": "/time/instant/nanoseconds",
    "literal_value": 1000000000,
    "expected_failure": "invalid_exact_value"
  },
  {
    "case_id": "unknown-epoch",
    "base_record_index": 1,
    "replace_or_add": "/time/instant/epoch",
    "literal_value": "local",
    "expected_failure": "unsupported_shape"
  },
  {
    "case_id": "latitude-outside",
    "base_record_index": 1,
    "replace_or_add": "/payload/latitude/bits",
    "literal_value": "4056c00000000000",
    "expected_failure": "coordinate_out_of_range"
  },
  {
    "case_id": "coordinate-nan",
    "base_record_index": 1,
    "replace_or_add": "/payload/latitude/bits",
    "literal_value": "7ff8000000000000",
    "expected_failure": "invalid_exact_value"
  },
  {
    "case_id": "negative-accuracy",
    "base_record_index": 1,
    "replace_or_add": "/payload/horizontal_accuracy/bits",
    "literal_value": "bff0000000000000",
    "expected_failure": "native_invalid_accuracy"
  },
  {
    "case_id": "sensor-absent-value",
    "base_record_index": 1,
    "replace_or_add": "/payload/speed",
    "literal_value": {
      "state": "absent",
      "value": 0
    },
    "expected_failure": "unsupported_shape"
  },
  {
    "case_id": "sensor-negative-speed",
    "base_record_index": 1,
    "replace_or_add": "/payload/speed",
    "literal_value": {
      "state": "known",
      "value": {
        "representation": "binary64",
        "bits": "bff0000000000000",
        "unit": "meter_per_second"
      }
    },
    "expected_failure": "native_invalid_speed"
  },
  {
    "case_id": "aggregate-negative-duration",
    "base_record_index": 2,
    "replace_or_add": "/payload/duration/bits",
    "literal_value": "bff0000000000000",
    "expected_failure": "invalid_exact_value"
  },
  {
    "case_id": "bucket-empty",
    "base_record_index": 2,
    "replace_or_add": "/payload/bucket/end/epoch_seconds",
    "literal_value": "0",
    "expected_failure": "invalid_bucket"
  },
  {
    "case_id": "aggregate-overbucket",
    "base_record_index": 2,
    "replace_or_add": "/payload/duration/bits",
    "literal_value": "40ac220000000000",
    "expected_failure": "duration_outside_bucket"
  },
  {
    "case_id": "session-negative-duration",
    "base_record_index": 3,
    "replace_or_add": "/payload/duration/bits",
    "literal_value": "bff0000000000000",
    "expected_failure": "clock_inconsistent"
  },
  {
    "case_id": "session-duration-disagreement",
    "base_record_index": 3,
    "replace_or_add": "/payload/duration/bits",
    "literal_value": "4000000000000000",
    "expected_failure": "clock_inconsistent"
  },
  {
    "case_id": "native-basis-unadmitted",
    "base_record_index": 3,
    "replace_or_add": "/payload/duration_basis",
    "literal_value": "native_source_arithmetic",
    "expected_failure": "unsupported_shape"
  },
  {
    "case_id": "browser-title",
    "base_record_index": 3,
    "replace_or_add": "/payload/title",
    "literal_value": {"state":"known","value":"synthetic_title"},
    "additional_replacements": [{"path":"/payload/app/app_class","value":"browser"}],
    "expected_failure": "scope_not_authorized"
  },
  {
    "case_id": "unknown-title-app-class",
    "base_record_index": 3,
    "replace_or_add": "/payload/title",
    "literal_value": {"state":"known","value":"synthetic_title"},
    "additional_replacements": [{"path":"/payload/app/app_class","value":"unknown"}],
    "expected_failure": "scope_not_authorized"
  },
  {
    "case_id": "identity-empty",
    "base_record_index": 0,
    "replace_or_add": "/record_id",
    "literal_value": "",
    "expected_failure": "unsupported_shape"
  },
  {
    "case_id": "identity-nul",
    "base_record_index": 0,
    "replace_or_add": "/record_id",
    "literal_value": "synthetic\u0000id",
    "expected_failure": "unsupported_shape"
  },
  {
    "case_id": "unknown-tag-with-value",
    "base_record_index": 0,
    "replace_or_add": "/lineage/device",
    "literal_value": {
      "state": "unknown",
      "reason": "not_reported",
      "value": "synthetic-device"
    },
    "expected_failure": "unsupported_shape"
  },
  {
    "case_id": "calendar-invalid-day",
    "base_record_index": 0,
    "replace_or_add": "/time/calendar/owner_date",
    "literal_value": {
      "state": "known",
      "value": "2001-02-29"
    },
    "expected_failure": "invalid_exact_value"
  },
  {
    "case_id": "offset-outside",
    "base_record_index": 0,
    "replace_or_add": "/time/source_utc_offset_seconds",
    "literal_value": {
      "state": "known",
      "value": 86401
    },
    "expected_failure": "invalid_exact_value"
  },
  {
    "case_id": "source-unknown-field",
    "base_record_index": 0,
    "replace_or_add": "/lineage/new_source_field",
    "literal_value": "fixture",
    "expected_failure": "unsupported_shape"
  }
] as const;

export const personalMalformedJsonVectors = [
  {
    "case_id": "duplicate-json-key",
    "input_json": "{\"domain\":\"health\",\"domain\":\"health\"}",
    "expected_failure": "unsupported_shape"
  },
  {
    "case_id": "escaped-duplicate-json-key",
    "input_json": "{\"domain\":\"health\",\"\\u0064omain\":\"health\"}",
    "expected_failure": "unsupported_shape"
  },
  {
    "case_id": "json-nan-token",
    "input_json": "{\"payload_revision\":NaN}",
    "expected_failure": "unsupported_shape"
  },
  {
    "case_id": "unpaired-surrogate",
    "input_json": "{\"record_id\":\"\\ud800\"}",
    "expected_failure": "unsupported_shape"
  }
] as const;

export const personalAdditionalPositiveMutations = [
  { case_id: "aggregate-exact-bucket-width", base_record_index: 2, replace_or_add: "/payload/duration/bits", literal_value: "40ac200000000000", expected_accept: true, expected_preserved_bits: "40ac200000000000" }
] as const;

export const personalRawIntegerTokenNegatives = [
  {
    "case_id": "numeric-revision-rounded-fraction",
    "input_json": "{\"domain\":\"health\",\"payload_kind\":\"health_fact\",\"payload_revision\":1.0000000000000001,\"record_id\":\"synthetic-health-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"semantic_id\":\"synthetic.health.exact_count\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"statistic\":\"observation\",\"value\":{\"representation\":\"unsigned_integer\",\"decimal\":\"9007199254740993\",\"unit\":\"count\"},\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"extensions\":[]}}",
    "expected_failure": "unsupported_shape",
    "expected_authority_callback_count": 0
  },
  {
    "case_id": "numeric-revision-decimal-integer",
    "input_json": "{\"domain\":\"health\",\"payload_kind\":\"health_fact\",\"payload_revision\":1.0,\"record_id\":\"synthetic-health-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"semantic_id\":\"synthetic.health.exact_count\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"statistic\":\"observation\",\"value\":{\"representation\":\"unsigned_integer\",\"decimal\":\"9007199254740993\",\"unit\":\"count\"},\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"extensions\":[]}}",
    "expected_failure": "unsupported_shape",
    "expected_authority_callback_count": 0
  },
  {
    "case_id": "numeric-revision-exponent-integer",
    "input_json": "{\"domain\":\"health\",\"payload_kind\":\"health_fact\",\"payload_revision\":1e0,\"record_id\":\"synthetic-health-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"semantic_id\":\"synthetic.health.exact_count\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"statistic\":\"observation\",\"value\":{\"representation\":\"unsigned_integer\",\"decimal\":\"9007199254740993\",\"unit\":\"count\"},\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"extensions\":[]}}",
    "expected_failure": "unsupported_shape",
    "expected_authority_callback_count": 0
  },
  {
    "case_id": "numeric-revision-negativezero",
    "input_json": "{\"domain\":\"health\",\"payload_kind\":\"health_fact\",\"payload_revision\":-0,\"record_id\":\"synthetic-health-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"semantic_id\":\"synthetic.health.exact_count\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"statistic\":\"observation\",\"value\":{\"representation\":\"unsigned_integer\",\"decimal\":\"9007199254740993\",\"unit\":\"count\"},\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"extensions\":[]}}",
    "expected_failure": "unsupported_shape",
    "expected_authority_callback_count": 0
  },
  {
    "case_id": "numeric-nanos-underflow",
    "input_json": "{\"domain\":\"health\",\"payload_kind\":\"health_fact\",\"payload_revision\":1,\"record_id\":\"synthetic-health-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1e-9999,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"semantic_id\":\"synthetic.health.exact_count\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"statistic\":\"observation\",\"value\":{\"representation\":\"unsigned_integer\",\"decimal\":\"9007199254740993\",\"unit\":\"count\"},\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"extensions\":[]}}",
    "expected_failure": "invalid_exact_value",
    "expected_authority_callback_count": 0
  },
  {
    "case_id": "numeric-nanos-decimal-integer",
    "input_json": "{\"domain\":\"health\",\"payload_kind\":\"health_fact\",\"payload_revision\":1,\"record_id\":\"synthetic-health-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1.0,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"semantic_id\":\"synthetic.health.exact_count\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"statistic\":\"observation\",\"value\":{\"representation\":\"unsigned_integer\",\"decimal\":\"9007199254740993\",\"unit\":\"count\"},\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"extensions\":[]}}",
    "expected_failure": "invalid_exact_value",
    "expected_authority_callback_count": 0
  },
  {
    "case_id": "numeric-nanos-exponent-integer",
    "input_json": "{\"domain\":\"health\",\"payload_kind\":\"health_fact\",\"payload_revision\":1,\"record_id\":\"synthetic-health-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1e0,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"semantic_id\":\"synthetic.health.exact_count\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"statistic\":\"observation\",\"value\":{\"representation\":\"unsigned_integer\",\"decimal\":\"9007199254740993\",\"unit\":\"count\"},\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"extensions\":[]}}",
    "expected_failure": "invalid_exact_value",
    "expected_authority_callback_count": 0
  },
  {
    "case_id": "numeric-nanos-negativezero",
    "input_json": "{\"domain\":\"health\",\"payload_kind\":\"health_fact\",\"payload_revision\":1,\"record_id\":\"synthetic-health-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":-0,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"semantic_id\":\"synthetic.health.exact_count\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"statistic\":\"observation\",\"value\":{\"representation\":\"unsigned_integer\",\"decimal\":\"9007199254740993\",\"unit\":\"count\"},\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"extensions\":[]}}",
    "expected_failure": "invalid_exact_value",
    "expected_authority_callback_count": 0
  },
  {
    "case_id": "numeric-offset-huge-exponent",
    "input_json": "{\"domain\":\"health\",\"payload_kind\":\"health_fact\",\"payload_revision\":1,\"record_id\":\"synthetic-health-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"known\",\"value\":1e999999},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"semantic_id\":\"synthetic.health.exact_count\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"statistic\":\"observation\",\"value\":{\"representation\":\"unsigned_integer\",\"decimal\":\"9007199254740993\",\"unit\":\"count\"},\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"extensions\":[]}}",
    "expected_failure": "invalid_exact_value",
    "expected_authority_callback_count": 0
  },
  {
    "case_id": "numeric-offset-negativezero",
    "input_json": "{\"domain\":\"health\",\"payload_kind\":\"health_fact\",\"payload_revision\":1,\"record_id\":\"synthetic-health-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"known\",\"value\":-0},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"semantic_id\":\"synthetic.health.exact_count\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"statistic\":\"observation\",\"value\":{\"representation\":\"unsigned_integer\",\"decimal\":\"9007199254740993\",\"unit\":\"count\"},\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"extensions\":[]}}",
    "expected_failure": "invalid_exact_value",
    "expected_authority_callback_count": 0
  },
  {
    "case_id": "numeric-offset-rounded-fraction",
    "input_json": "{\"domain\":\"health\",\"payload_kind\":\"health_fact\",\"payload_revision\":1,\"record_id\":\"synthetic-health-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"known\",\"value\":1.0000000000000001},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"semantic_id\":\"synthetic.health.exact_count\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"statistic\":\"observation\",\"value\":{\"representation\":\"unsigned_integer\",\"decimal\":\"9007199254740993\",\"unit\":\"count\"},\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"extensions\":[]}}",
    "expected_failure": "invalid_exact_value",
    "expected_authority_callback_count": 0
  },
  {
    "case_id": "numeric-revision-notjson-nan",
    "input_json": "{\"domain\":\"health\",\"payload_kind\":\"health_fact\",\"payload_revision\":NaN,\"record_id\":\"synthetic-health-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"semantic_id\":\"synthetic.health.exact_count\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"statistic\":\"observation\",\"value\":{\"representation\":\"unsigned_integer\",\"decimal\":\"9007199254740993\",\"unit\":\"count\"},\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"extensions\":[]}}",
    "expected_failure": "unsupported_shape",
    "expected_authority_callback_count": 0
  }
] as const;
