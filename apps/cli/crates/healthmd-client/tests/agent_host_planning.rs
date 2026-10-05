//! Hermetic public-seam tests. No native credentials, real source, or output writer.
#![cfg(unix)] // Positive private-store tests cannot qualify the unavailable Windows backend.
use std::sync::Arc;

use async_trait::async_trait;
use healthmd_client as client_crate;
use healthmd_client::agent_host::{
    HostAuthorityStore, LocalEnrollment, LocalHostConsent, ProtectedHostKey,
};
use healthmd_client::agent_planning::HostPlanner;
use healthmd_protocol::v4::*;
use std::sync::atomic::{AtomicUsize, Ordering};
#[path = "support/agent.rs"]
mod support;
use healthmd_client::ClientError;
use healthmd_protocol::v4::ControlUuid;
use secrecy::SecretString;
use support::*;

struct DelayedConsent {
    clock: Arc<AdvancingClock>,
    calls: AtomicUsize,
}
#[async_trait]
impl LocalHostConsent for DelayedConsent {
    async fn enroll(&self, _: &LocalEnrollment) -> Result<(), ClientError> {
        Err(ClientError::AgentAuthorityUnavailable)
    }
    async fn decide(&self, _: &ExportPlan) -> Result<(), ClientError> {
        tokio::task::yield_now().await;
        self.clock.advance_to(300);
        self.calls.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }
}

fn issuer_bytes(temporary: &tempfile::TempDir) -> Vec<u8> {
    std::fs::read(temporary.path().join("agent-host-v1/issuer.json")).unwrap()
}
fn approval_request(plan: &ExportPlan) -> ApprovalRequest {
    ApprovalRequest {
        schema: ApprovalRequestSchema::HealthmdAgentApprovalRequest,
        schema_version: 1,
        request_id: id(11),
        plan_id: plan.plan_id.clone(),
        binding: approval_binding(plan),
    }
}

#[tokio::test]
async fn delayed_native_consent_expiry_never_publishes_a_host_decision() {
    let temporary = tempfile::TempDir::new().unwrap();
    let peer = peer(PeerPlatform::Apple);
    let (store, _) = enroll(temporary.path(), &peer, &now()).await;
    let clock = Arc::new(AdvancingClock::new());
    let planner = HostPlanner::new(store.clone());
    let plan = planner
        .plan(
            &mut NativeFake::new(peer.clone(), now()),
            input(&peer),
            clock.as_ref(),
        )
        .await
        .unwrap();
    let before = issuer_bytes(&temporary);
    let consent = DelayedConsent {
        clock: clock.clone(),
        calls: AtomicUsize::new(0),
    };
    let result = store
        .record_local_decision(2, &plan.plan_id, clock.as_ref(), &consent)
        .await;
    let revision = store.revision().await.unwrap();
    assert_eq!(consent.calls.load(Ordering::SeqCst), 1);
    eprintln!(
        "delayed consent executed; host revision after decision={revision}; rejected={}",
        result.is_err()
    );
    assert!(matches!(
        result,
        Err(ClientError::Agent(Error::PlanExpired))
    ));
    assert_eq!(revision, 2);
    assert_eq!(issuer_bytes(&temporary), before);
    assert!(
        planner
            .preflight_approval(&approval_request(&plan), &now())
            .await
            .is_err()
    );
}

#[tokio::test]
async fn delayed_protected_key_expiry_never_publishes_a_plan() {
    let temporary = tempfile::TempDir::new().unwrap();
    let peer = peer(PeerPlatform::Android);
    let clock = Arc::new(AdvancingClock::new());
    let key = Arc::new(DelayedProtectedKey::new(clock.clone()));
    let (store, output) = enroll_with_key(
        temporary.path(),
        &peer,
        delegation(&peer, AuthorityReferenceIssuer::AuthorizedHost, &now()),
        key.clone(),
    )
    .await;
    let before = issuer_bytes(&temporary);
    let mut source = KeyDelaySource {
        native: NativeFake::new(peer.clone(), now()),
        key: key.clone(),
        on_plan: true,
        on_approval: false,
        seconds: 300,
        loads: 2,
    };
    let result = HostPlanner::new(store.clone())
        .plan(&mut source, input(&peer), clock.as_ref())
        .await;
    let revision = store.revision().await.unwrap();
    assert_eq!(key.delays.load(Ordering::SeqCst), 1);
    eprintln!(
        "delayed publication key executed; host revision after plan={revision}; rejected={}",
        result.is_err()
    );
    assert!(matches!(
        result,
        Err(ClientError::Agent(Error::PlanExpired))
    ));
    assert_eq!(
        revision, 1,
        "final rejection is not prepublication rejection"
    );
    assert_eq!(issuer_bytes(&temporary), before);
    assert_eq!(std::fs::read_dir(output).unwrap().count(), 0);
}

#[tokio::test]
async fn delayed_protected_key_expiry_never_publishes_an_approval() {
    let temporary = tempfile::TempDir::new().unwrap();
    let peer = peer(PeerPlatform::Apple);
    let clock = Arc::new(AdvancingClock::new());
    let key = Arc::new(DelayedProtectedKey::new(clock.clone()));
    let (store, _) = enroll_with_key(
        temporary.path(),
        &peer,
        delegation(&peer, AuthorityReferenceIssuer::AuthorizedHost, &now()),
        key.clone(),
    )
    .await;
    let planner = HostPlanner::new(store.clone());
    let mut source = KeyDelaySource {
        native: NativeFake::new(peer.clone(), now()),
        key: key.clone(),
        on_plan: false,
        on_approval: false,
        seconds: 300,
        loads: 2,
    };
    let plan = planner
        .plan(&mut source, input(&peer), clock.as_ref())
        .await
        .unwrap();
    store
        .record_local_decision(2, &plan.plan_id, clock.as_ref(), &ExplicitFakeLocalConsent)
        .await
        .unwrap();
    source.native.store_exact_native_decision();
    source.on_approval = true;
    let before = issuer_bytes(&temporary);
    let result = planner
        .relay_approval(&mut source, approval_request(&plan), clock.as_ref())
        .await;
    let revision = store.revision().await.unwrap();
    assert_eq!(key.delays.load(Ordering::SeqCst), 1);
    eprintln!(
        "delayed publication key executed; host revision after approval={revision}; rejected={}",
        result.is_err()
    );
    assert!(matches!(
        result,
        Err(ClientError::Agent(Error::PlanExpired))
    ));
    assert_eq!(
        revision, 3,
        "final rejection is not prepublication rejection"
    );
    assert_eq!(issuer_bytes(&temporary), before);
}

struct HostMutatingConsent {
    store: HostAuthorityStore,
    output: Option<std::path::PathBuf>,
    calls: AtomicUsize,
}
#[async_trait]
impl LocalHostConsent for HostMutatingConsent {
    async fn enroll(&self, _: &LocalEnrollment) -> Result<(), ClientError> {
        Err(ClientError::AgentAuthorityUnavailable)
    }
    async fn decide(&self, _: &ExportPlan) -> Result<(), ClientError> {
        tokio::task::yield_now().await;
        if let Some(output) = &self.output {
            std::fs::rename(output, output.with_file_name("original-root")).unwrap();
            std::fs::create_dir(output).unwrap();
        } else {
            self.store.revoke_local(2, &id(5)).await?;
        }
        self.calls.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }
}

#[tokio::test]
async fn native_consent_delay_rechecks_revocation_cas_and_exact_root_before_decision() {
    for replace_root in [false, true] {
        let temporary = tempfile::TempDir::new().unwrap();
        let peer = peer(PeerPlatform::Android);
        let (store, output) = enroll(temporary.path(), &peer, &now()).await;
        let planner = HostPlanner::new(store.clone());
        let clock = FixedClock(now());
        let plan = planner
            .plan(
                &mut NativeFake::new(peer.clone(), now()),
                input(&peer),
                &clock,
            )
            .await
            .unwrap();
        let consent = HostMutatingConsent {
            store: store.clone(),
            output: replace_root.then_some(output),
            calls: AtomicUsize::new(0),
        };
        let result = store
            .record_local_decision(2, &plan.plan_id, &clock, &consent)
            .await;
        assert_eq!(consent.calls.load(Ordering::SeqCst), 1);
        if replace_root {
            assert!(matches!(
                result,
                Err(ClientError::Agent(Error::BindingChanged))
            ));
            assert_eq!(store.revision().await.unwrap(), 2);
        } else {
            assert!(matches!(
                result,
                Err(ClientError::Agent(Error::RevisionConflict))
            ));
            assert_eq!(store.revision().await.unwrap(), 3);
            assert!(
                store
                    .authority_references(&peer, &now())
                    .await
                    .unwrap()
                    .is_empty()
            );
        }
        let signed: serde_json::Value = serde_json::from_slice(&issuer_bytes(&temporary)).unwrap();
        assert!(signed["state"]["plans"][0].get("decision").is_none());
        assert!(
            planner
                .preflight_approval(&approval_request(&plan), &now())
                .await
                .is_err()
        );
    }
}

/// Advance only once a fully serialized private temporary exists, after the real staging write.
/// This is an exercised publication boundary, not unused time mocks or a final-only rejection.
struct StagedExpiryClock {
    private: std::path::PathBuf,
    time: Arc<AdvancingClock>,
    target_revision: u64,
    observed: AtomicUsize,
}
impl healthmd_client::agent_planning::PlanningClock for StagedExpiryClock {
    fn now(&self) -> UtcTimestamp {
        for entry in std::fs::read_dir(&self.private).unwrap() {
            let entry = entry.unwrap();
            if !entry.file_name().to_string_lossy().starts_with(".issuer-") {
                continue;
            }
            let bytes = std::fs::read(entry.path()).unwrap();
            let staged: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
            if staged["state"]["revision"] == self.target_revision {
                self.observed.fetch_add(1, Ordering::SeqCst);
                self.time.advance_to(300);
            }
        }
        healthmd_client::agent_planning::PlanningClock::now(self.time.as_ref())
    }
}

#[tokio::test]
async fn serialized_staged_plan_decision_and_approval_expiry_reject_before_publication() {
    for target_revision in [2, 3, 4] {
        let temporary = tempfile::TempDir::new().unwrap();
        let peer = peer(PeerPlatform::Apple);
        let (store, _) = enroll(temporary.path(), &peer, &now()).await;
        let clock = StagedExpiryClock {
            private: temporary.path().join("agent-host-v1"),
            time: Arc::new(AdvancingClock::new()),
            target_revision,
            observed: AtomicUsize::new(0),
        };
        let planner = HostPlanner::new(store.clone());
        let mut source = NativeFake::new(peer.clone(), now());
        let before = issuer_bytes(&temporary);
        let issuance = planner.plan(&mut source, input(&peer), &clock).await;
        if target_revision == 2 {
            assert!(matches!(
                issuance,
                Err(ClientError::Agent(Error::PlanExpired))
            ));
            assert_eq!(issuer_bytes(&temporary), before);
        } else {
            let plan = issuance.unwrap();
            let before = issuer_bytes(&temporary);
            let decided = store
                .record_local_decision(2, &plan.plan_id, &clock, &ExplicitFakeLocalConsent)
                .await;
            if target_revision == 3 {
                assert!(matches!(
                    decided,
                    Err(ClientError::Agent(Error::PlanExpired))
                ));
                assert_eq!(issuer_bytes(&temporary), before);
            } else {
                decided.unwrap();
                source.store_exact_native_decision();
                let before = issuer_bytes(&temporary);
                let approved = planner
                    .relay_approval(&mut source, approval_request(&plan), &clock)
                    .await;
                assert!(matches!(
                    approved,
                    Err(ClientError::Agent(Error::PlanExpired))
                ));
                assert_eq!(issuer_bytes(&temporary), before);
            }
        }
        assert!(clock.observed.load(Ordering::SeqCst) > 0);
        assert_eq!(store.revision().await.unwrap(), target_revision - 1);
        assert_eq!(
            std::fs::read_dir(clock.private).unwrap().count(),
            2,
            "only published state/lock remain"
        );
        eprintln!(
            "staged expiry callback executed; attempted revision={target_revision}; unpublished"
        );
    }
}

struct KeyArmingConsent {
    key: Arc<DelayedProtectedKey>,
    loads: usize,
}
#[async_trait]
impl LocalHostConsent for KeyArmingConsent {
    async fn enroll(&self, _: &LocalEnrollment) -> Result<(), ClientError> {
        Err(ClientError::AgentAuthorityUnavailable)
    }
    async fn decide(&self, _: &ExportPlan) -> Result<(), ClientError> {
        tokio::task::yield_now().await;
        self.key.arm(self.loads, 300);
        Ok(())
    }
}

#[tokio::test]
async fn delayed_decision_publication_key_and_postpublication_return_are_distinct() {
    for loads in [1, 2] {
        let temporary = tempfile::TempDir::new().unwrap();
        let peer = peer(PeerPlatform::Apple);
        let clock = Arc::new(AdvancingClock::new());
        let key = Arc::new(DelayedProtectedKey::new(clock.clone()));
        let (store, _) = enroll_with_key(
            temporary.path(),
            &peer,
            delegation(&peer, AuthorityReferenceIssuer::AuthorizedHost, &now()),
            key.clone(),
        )
        .await;
        let planner = HostPlanner::new(store.clone());
        let mut source = NativeFake::new(peer.clone(), now());
        let plan = planner
            .plan(&mut source, input(&peer), clock.as_ref())
            .await
            .unwrap();
        let before = issuer_bytes(&temporary);
        let result = store
            .record_local_decision(
                2,
                &plan.plan_id,
                clock.as_ref(),
                &KeyArmingConsent {
                    key: key.clone(),
                    loads,
                },
            )
            .await;
        assert!(matches!(
            result,
            Err(ClientError::Agent(Error::PlanExpired))
        ));
        assert_eq!(key.delays.load(Ordering::SeqCst), 1);
        assert_eq!(
            store.revision().await.unwrap(),
            if loads == 1 { 2 } else { 3 }
        );
        assert_eq!(issuer_bytes(&temporary) == before, loads == 1);
        source.store_exact_native_decision();
        assert!(
            planner
                .relay_approval(&mut source, approval_request(&plan), clock.as_ref())
                .await
                .is_err()
        );
        eprintln!(
            "decision key expiry; postpublication={}; no approval authority",
            loads == 2
        );
    }
}

#[tokio::test]
async fn final_key_delay_rejects_postpublished_plan_or_approval_and_stale_cached_return() {
    for approval_phase in [false, true] {
        let temporary = tempfile::TempDir::new().unwrap();
        let peer = peer(PeerPlatform::Android);
        let clock = Arc::new(AdvancingClock::new());
        let key = Arc::new(DelayedProtectedKey::new(clock.clone()));
        let (store, _) = enroll_with_key(
            temporary.path(),
            &peer,
            delegation(&peer, AuthorityReferenceIssuer::AuthorizedHost, &now()),
            key.clone(),
        )
        .await;
        let planner = HostPlanner::new(store.clone());
        // The first two publication-phase reads stay live; the FINAL return key crosses expiry.
        let mut source = KeyDelaySource {
            native: NativeFake::new(peer.clone(), now()),
            key: key.clone(),
            on_plan: false,
            on_approval: false,
            seconds: 300,
            loads: 2,
        };
        let result = if approval_phase {
            let plan = planner
                .plan(&mut source, input(&peer), clock.as_ref())
                .await
                .unwrap();
            store
                .record_local_decision(2, &plan.plan_id, clock.as_ref(), &ExplicitFakeLocalConsent)
                .await
                .unwrap();
            source.native.store_exact_native_decision();
            source.on_approval = true;
            source.loads = 3;
            planner
                .relay_approval(&mut source, approval_request(&plan), clock.as_ref())
                .await
                .map(|_| ())
        } else {
            source.on_plan = true;
            source.loads = 3;
            planner
                .plan(&mut source, input(&peer), clock.as_ref())
                .await
                .map(|_| ())
        };
        assert!(matches!(
            result,
            Err(ClientError::Agent(Error::PlanExpired))
        ));
        assert_eq!(key.delays.load(Ordering::SeqCst), 1);
        assert_eq!(
            store.revision().await.unwrap(),
            if approval_phase { 4 } else { 2 }
        );
        let plan = source.native.issued.as_ref().unwrap().clone();
        let before = issuer_bytes(&temporary);
        source.native.store_exact_native_decision();
        assert!(
            planner
                .relay_approval(&mut source, approval_request(&plan), clock.as_ref())
                .await
                .is_err()
        );
        assert_eq!(issuer_bytes(&temporary), before);
        assert_eq!(plan.expires_at, later(&now(), 300), "expiry never renewed");
        eprintln!(
            "final key expiry; approval_phase={approval_phase}; explicitly postpublication; stale relay rejected"
        );
    }
}

#[tokio::test]
async fn delayed_key_parent_expiry_is_checked_against_latest_host_grant() {
    let temporary = tempfile::TempDir::new().unwrap();
    let peer = peer(PeerPlatform::Apple);
    let clock = Arc::new(AdvancingClock::new());
    let key = Arc::new(DelayedProtectedKey::new(clock.clone()));
    let (store, _) = enroll_with_key(
        temporary.path(),
        &peer,
        delegation(&peer, AuthorityReferenceIssuer::AuthorizedHost, &now()),
        key.clone(),
    )
    .await;
    let before = issuer_bytes(&temporary);
    let mut source = KeyDelaySource {
        native: NativeFake::new(peer.clone(), now()),
        key: key.clone(),
        on_plan: true,
        on_approval: false,
        seconds: 1800,
        loads: 2,
    };
    assert!(matches!(
        HostPlanner::new(store.clone())
            .plan(&mut source, input(&peer), clock.as_ref())
            .await,
        Err(ClientError::Agent(Error::ApprovalRequired))
    ));
    assert_eq!(key.delays.load(Ordering::SeqCst), 1);
    assert_eq!(store.revision().await.unwrap(), 1);
    assert_eq!(issuer_bytes(&temporary), before);
    assert!(
        store
            .authority_references(&peer, &later(&now(), 1800))
            .await
            .unwrap()
            .is_empty()
    );
}

struct CachedReturnExpirySource {
    native: NativeFake,
    clock: Arc<AdvancingClock>,
    after_discovery: std::sync::atomic::AtomicBool,
    fired: AtomicUsize,
}
#[async_trait]
impl healthmd_client::agent_planning::PlanningSource for CachedReturnExpirySource {
    async fn require_current(&self) -> Result<(), ClientError> {
        if self.after_discovery.swap(false, Ordering::SeqCst) {
            tokio::task::yield_now().await;
            self.clock.advance_to(300);
            self.fired.fetch_add(1, Ordering::SeqCst);
        }
        Ok(())
    }
    fn peer(&self) -> &Peer {
        &self.native.peer
    }
    async fn discover(&mut self) -> Result<Discovery, ClientError> {
        self.after_discovery.store(true, Ordering::SeqCst);
        healthmd_client::agent_planning::PlanningSource::discover(&mut self.native).await
    }
    async fn plan(&mut self, _: PlanRequest) -> Result<ExportPlan, ClientError> {
        panic!("cached approval cannot issue a new plan")
    }
    async fn relay_approval(&mut self, _: ApprovalRequest) -> Result<Approval, ClientError> {
        panic!("cached approval cannot issue/renew another decision")
    }
}

#[tokio::test]
async fn cached_approval_final_authentication_delay_rejects_without_renewal_or_writes() {
    let temporary = tempfile::TempDir::new().unwrap();
    let peer = peer(PeerPlatform::Android);
    let (store, _) = enroll(temporary.path(), &peer, &now()).await;
    let clock = Arc::new(AdvancingClock::new());
    let planner = HostPlanner::new(store.clone());
    let mut native = NativeFake::new(peer.clone(), now());
    let plan = planner
        .plan(&mut native, input(&peer), clock.as_ref())
        .await
        .unwrap();
    store
        .record_local_decision(2, &plan.plan_id, clock.as_ref(), &ExplicitFakeLocalConsent)
        .await
        .unwrap();
    native.store_exact_native_decision();
    let approval = planner
        .relay_approval(&mut native, approval_request(&plan), clock.as_ref())
        .await
        .unwrap();
    let before = issuer_bytes(&temporary);
    let mut source = CachedReturnExpirySource {
        native,
        clock: clock.clone(),
        after_discovery: std::sync::atomic::AtomicBool::new(false),
        fired: AtomicUsize::new(0),
    };
    assert!(matches!(
        planner
            .relay_approval(&mut source, approval_request(&plan), clock.as_ref())
            .await,
        Err(ClientError::Agent(Error::PlanExpired))
    ));
    assert_eq!(source.fired.load(Ordering::SeqCst), 1);
    assert_eq!(issuer_bytes(&temporary), before);
    assert_eq!(store.revision().await.unwrap(), 4);
    assert_eq!(approval.binding.expires_at, later(&now(), 300));
    eprintln!(
        "cached approval final authentication callback crossed expiry; stored expiry unchanged; no writes"
    );
}

struct MissingKey;
#[async_trait]
impl ProtectedHostKey for MissingKey {
    async fn load_existing(&self, _: &ControlUuid) -> Result<SecretString, ClientError> {
        Err(ClientError::AgentAuthorityUnavailable)
    }
}

#[tokio::test]
async fn planning_cannot_initialize_missing_issuer_state() {
    let temporary = tempfile::TempDir::new().unwrap();
    let root = temporary.path().join("absent-issuer");
    let host = ControlUuid("00000000-0000-4000-8000-000000000002".into());
    let result = HostAuthorityStore::open_existing(root.clone(), host, Arc::new(MissingKey)).await;
    assert!(matches!(
        result,
        Err(ClientError::AgentAuthorityUnavailable)
    ));
    assert!(!root.exists());
    assert_eq!(std::fs::read_dir(temporary.path()).unwrap().count(), 0);
}

#[tokio::test]
async fn issuer_store_and_source_plan_roundtrip_both_platforms_with_exact_paths_and_origins() {
    for platform in [PeerPlatform::Apple, PeerPlatform::Android] {
        let temporary = tempfile::TempDir::new().unwrap();
        let peer = peer(platform);
        let (store, output) = enroll(temporary.path(), &peer, &now()).await;
        let mut source = NativeFake::new(peer.clone(), now());
        let plan = HostPlanner::new(store.clone())
            .plan(&mut source, input(&peer), &FixedClock(now()))
            .await
            .unwrap();
        assert_eq!(
            plan.predicted_paths
                .iter()
                .map(|p| p.0.as_str())
                .collect::<Vec<_>>(),
            ["2026/2026-01-01.json", "2026/2026-01-02.json"]
        );
        assert_eq!(plan.origins.len(), 40);
        assert!(
            plan.origins
                .iter()
                .any(|o| o.pointer == "/effective_settings/formats"
                    && o.origin == OriginOrigin::Request
                    && o.revision == 0)
        );
        assert!(
            plan.origins
                .iter()
                .any(|o| o.pointer == "/capture_scope/native_archive/type"
                    && o.origin == OriginOrigin::Request)
        );
        assert_eq!(plan.resolved_metric_ids, [SemanticId("steps".into())]);
        assert_eq!(
            plan.authority_references.host,
            store.authority_references(&peer, &now()).await.unwrap()[0]
        );
        assert_eq!(plan.authority_references.native.authority_id, id(4));
        assert_eq!(plan.intent.destination.binding_id, id(3));
        assert!(
            !serde_json::to_string(&plan)
                .unwrap()
                .contains(output.to_str().unwrap())
        );
        assert_eq!(std::fs::read_dir(output).unwrap().count(), 0);
        assert_eq!(store.revision().await.unwrap(), 2);
        assert!(
            !source
                .discovery(id(10))
                .features
                .contains(&DiscoveryFeaturesItem::BoundExecution)
        );
    }
}

#[tokio::test]
async fn logical_history_stays_unresolved_and_execution_has_no_fallback() {
    let temporary = tempfile::TempDir::new().unwrap();
    let peer = peer(PeerPlatform::Apple);
    let (store, output) = enroll(temporary.path(), &peer, &now()).await;
    let planner = HostPlanner::new(store);
    let mut source = NativeFake::new(peer.clone(), now());
    let mut request = input(&peer);
    request.dates = Dates::AllAvailable {};
    let plan = planner
        .plan(&mut source, request, &FixedClock(now()))
        .await
        .unwrap();
    assert!(matches!(plan.resolved_dates, Dates::AllAvailable {}));
    assert!(plan.predicted_paths.is_empty());
    assert_eq!(
        plan.path_prediction,
        ExportPlanPathPrediction::TemplateOnlyAllAvailable
    );
    assert_eq!(
        plan.limitations,
        [SemanticId("history_bounds_unresolved".into())]
    );
    let approval = Approval {
        schema: ApprovalSchema::HealthmdAgentApproval,
        schema_version: 1,
        approval_id: id(12),
        approved_at: now(),
        authority_id: id(4),
        binding: approval_binding(&plan),
        rights: vec![ApprovalRightsItem::ExportExecute],
    };
    let execute = ExecuteRequest {
        schema: ExecuteRequestSchema::HealthmdAgentExecuteRequest,
        schema_version: 1,
        approval,
        plan,
        job_id: id(20),
        idempotency_key: id(21),
        request_id: id(22),
    };
    assert!(matches!(
        planner.execute(&execute),
        Err(ClientError::Agent(Error::UnsupportedCapability))
    ));
    assert_eq!(std::fs::read_dir(output).unwrap().count(), 0);
}

#[tokio::test]
async fn approval_requires_separate_exact_host_and_native_decisions_and_survives_restart() {
    let temporary = tempfile::TempDir::new().unwrap();
    let peer = peer(PeerPlatform::Android);
    let (store, _) = enroll(temporary.path(), &peer, &now()).await;
    let planner = HostPlanner::new(store.clone());
    let mut source = NativeFake::new(peer.clone(), now());
    let plan = planner
        .plan(&mut source, input(&peer), &FixedClock(now()))
        .await
        .unwrap();
    let request = ApprovalRequest {
        schema: ApprovalRequestSchema::HealthmdAgentApprovalRequest,
        schema_version: 1,
        request_id: id(11),
        plan_id: plan.plan_id.clone(),
        binding: approval_binding(&plan),
    };
    assert!(matches!(
        planner.preflight_approval(&request, &now()).await,
        Err(ClientError::Agent(Error::ApprovalRequired))
    ));
    assert!(matches!(
        planner
            .relay_approval(&mut source, request.clone(), &FixedClock(now()))
            .await,
        Err(ClientError::Agent(Error::ApprovalRequired))
    ));
    store
        .record_local_decision(
            2,
            &plan.plan_id,
            &FixedClock(now()),
            &ExplicitFakeLocalConsent,
        )
        .await
        .unwrap();
    assert!(matches!(
        planner
            .relay_approval(&mut source, request.clone(), &FixedClock(now()))
            .await,
        Err(ClientError::Agent(Error::ApprovalRequired))
    ));
    source.store_exact_native_decision();
    let approval = planner
        .relay_approval(&mut source, request.clone(), &FixedClock(now()))
        .await
        .unwrap();
    assert_eq!(approval.binding, request.binding);
    let restarted = HostAuthorityStore::open_existing(
        std::fs::canonicalize(temporary.path())
            .unwrap()
            .join("agent-host-v1"),
        peer.host_installation_id.clone(),
        Arc::new(FakeProtectedKey),
    )
    .await
    .unwrap();
    let restarted = HostPlanner::new(restarted);
    assert_eq!(
        restarted
            .relay_approval(&mut source, request.clone(), &FixedClock(now()))
            .await
            .unwrap(),
        approval
    );
    let mut unknown = request.clone();
    unknown.plan_id = id(99);
    assert!(matches!(
        restarted.preflight_approval(&unknown, &now()).await,
        Err(ClientError::Agent(Error::ApprovalRequired))
    ));
    let mut changed = request;
    changed.binding.destination.revision += 1;
    assert!(matches!(
        restarted.preflight_approval(&changed, &now()).await,
        Err(ClientError::Agent(Error::BindingChanged))
    ));
}

#[tokio::test]
async fn wrong_peer_issuer_ref_metrics_or_destination_never_enroll_or_widen() {
    let temporary = tempfile::TempDir::new().unwrap();
    let peer = peer(PeerPlatform::Apple);
    let (store, output) = enroll(temporary.path(), &peer, &now()).await;
    let planner = HostPlanner::new(store.clone());
    let host_ref = store.authority_references(&peer, &now()).await.unwrap()[0].clone();
    let mut wrong_peer = peer.clone();
    wrong_peer.source_installation_id = id(99);
    assert!(
        planner
            .preflight(&wrong_peer, &input(&peer), &now())
            .await
            .is_err()
    );
    for change in [0, 1, 2, 3, 4, 5] {
        let mut input = input(&peer);
        match change {
            0 => input.destination_binding_id = id(99),
            1 => {
                let mut forged = host_ref.clone();
                forged.grant_sha256 = Digest("0".repeat(64));
                input.host_authority_reference = Some(forged);
            }
            2 => {
                let mut forged = host_ref.clone();
                forged.issuer = AuthorityReferenceIssuer::NativeSource;
                input.host_authority_reference = Some(forged);
            }
            3 => input.metric_ids = vec![SemanticId("android.hrv_rmssd".into())],
            4 => input.metric_ids = vec![SemanticId("heart_rate_avg".into())],
            _ => {
                let mut forged = host_ref.clone();
                forged.grant_revision += 1;
                input.host_authority_reference = Some(forged);
            }
        }
        assert!(planner.preflight(&peer, &input, &now()).await.is_err());
    }
    assert_eq!(store.revision().await.unwrap(), 1);
    assert_eq!(
        store.authority_references(&peer, &now()).await.unwrap(),
        [host_ref]
    );
    assert_eq!(std::fs::read_dir(output).unwrap().count(), 0);
}

#[tokio::test]
async fn valid_rehashes_do_not_authorize_substituted_native_plans_or_refs() {
    let mutations: [fn(&mut ExportPlan); 6] = [
        |p| p.authority_references.native.grant_sha256 = Digest("0".repeat(64)),
        |p| p.intent.peer.source_installation_id = id(99),
        |p| p.intent.destination.revision += 1,
        |p| p.capability_sha256 = Digest("0".repeat(64)),
        |p| p.origins[0].revision = 1,
        |p| p.predicted_paths = vec![RelativePath("other.json".into())],
    ];
    for mutate in mutations {
        let temporary = tempfile::TempDir::new().unwrap();
        let peer = peer(PeerPlatform::Apple);
        let (store, _) = enroll(temporary.path(), &peer, &now()).await;
        let mut source = NativeFake::new(peer.clone(), now());
        source.plan_mutation = Some(mutate);
        assert!(
            HostPlanner::new(store.clone())
                .plan(&mut source, input(&peer), &FixedClock(now()))
                .await
                .is_err()
        );
        assert_eq!(store.revision().await.unwrap(), 1);
    }
}

#[tokio::test]
async fn missing_native_consent_and_expired_scope_fail_without_private_plan_writes() {
    let temporary = tempfile::TempDir::new().unwrap();
    let peer = peer(PeerPlatform::Apple);
    let (store, _) = enroll(temporary.path(), &peer, &now()).await;
    let planner = HostPlanner::new(store.clone());
    let mut source = NativeFake::new(peer.clone(), now());
    source.stored_native = None;
    assert!(matches!(
        planner
            .plan(&mut source, input(&peer), &FixedClock(now()))
            .await,
        Err(ClientError::Agent(Error::ApprovalRequired))
    ));
    assert!(
        planner
            .preflight(&peer, &input(&peer), &later(&now(), 1800))
            .await
            .is_err()
    );
    assert_eq!(store.revision().await.unwrap(), 1);
}

#[tokio::test]
async fn separate_decisions_use_cas_and_revocations_are_retained_after_restart() {
    let temporary = tempfile::TempDir::new().unwrap();
    let peer = peer(PeerPlatform::Apple);
    let (store, _) = enroll(temporary.path(), &peer, &now()).await;
    let plan = HostPlanner::new(store.clone())
        .plan(
            &mut NativeFake::new(peer.clone(), now()),
            input(&peer),
            &FixedClock(now()),
        )
        .await
        .unwrap();
    let clock = FixedClock(now());
    let (first, second) = tokio::join!(
        store.record_local_decision(2, &plan.plan_id, &clock, &ExplicitFakeLocalConsent),
        store.record_local_decision(2, &plan.plan_id, &clock, &ExplicitFakeLocalConsent)
    );
    assert_eq!(usize::from(first.is_ok()) + usize::from(second.is_ok()), 1);
    store.revoke_local(3, &id(5)).await.unwrap();
    let path = std::fs::canonicalize(temporary.path())
        .unwrap()
        .join("agent-host-v1");
    let restarted = HostAuthorityStore::open_existing(
        path,
        peer.host_installation_id.clone(),
        Arc::new(FakeProtectedKey),
    )
    .await
    .unwrap();
    assert!(
        restarted
            .authority_references(&peer, &now())
            .await
            .unwrap()
            .is_empty()
    );
    assert!(
        HostPlanner::new(restarted)
            .preflight(&peer, &input(&peer), &now())
            .await
            .is_err()
    );
}

#[tokio::test]
async fn private_corruption_duplicate_keys_invalid_utf8_and_missing_secret_fail_closed() {
    for corrupted in [
        b"\xff".as_slice(),
        b"{\"state\":{},\"state\":{},\"mac\":\"x\"}",
        b"{}",
    ] {
        let temporary = tempfile::TempDir::new().unwrap();
        let peer = peer(PeerPlatform::Apple);
        let (store, _) = enroll(temporary.path(), &peer, &now()).await;
        let path = std::fs::canonicalize(temporary.path())
            .unwrap()
            .join("agent-host-v1");
        std::fs::write(path.join("issuer.json"), corrupted).unwrap();
        assert!(store.revision().await.is_err());
        assert!(
            HostAuthorityStore::open_existing(
                path.clone(),
                peer.host_installation_id.clone(),
                Arc::new(FakeProtectedKey)
            )
            .await
            .is_err()
        );
        assert_eq!(std::fs::read(path.join("issuer.json")).unwrap(), corrupted);
    }
    let temporary = tempfile::TempDir::new().unwrap();
    let peer = peer(PeerPlatform::Apple);
    let (_, _) = enroll(temporary.path(), &peer, &now()).await;
    let path = std::fs::canonicalize(temporary.path())
        .unwrap()
        .join("agent-host-v1");
    let before = std::fs::read(path.join("issuer.json")).unwrap();
    assert!(
        HostAuthorityStore::open_existing(
            path.clone(),
            peer.host_installation_id,
            Arc::new(MissingKey)
        )
        .await
        .is_err()
    );
    assert_eq!(std::fs::read(path.join("issuer.json")).unwrap(), before);
}

#[tokio::test]
async fn expiry_crossed_at_final_authentication_fence_prevents_plan_publication() {
    use healthmd_client::agent_planning::{PlanningClock, PlanningSource};
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    struct ExpiryClock(AtomicBool);
    impl PlanningClock for ExpiryClock {
        fn now(&self) -> UtcTimestamp {
            if self.0.load(Ordering::SeqCst) {
                later(&now(), 600)
            } else {
                now()
            }
        }
    }
    struct Source<'a> {
        native: NativeFake,
        clock: &'a ExpiryClock,
        fences: AtomicUsize,
    }
    #[async_trait]
    impl PlanningSource for Source<'_> {
        async fn require_current(&self) -> Result<(), ClientError> {
            if self.fences.fetch_add(1, Ordering::SeqCst) == 1 {
                self.clock.0.store(true, Ordering::SeqCst);
            }
            Ok(())
        }
        fn peer(&self) -> &Peer {
            &self.native.peer
        }
        async fn discover(&mut self) -> Result<Discovery, ClientError> {
            PlanningSource::discover(&mut self.native).await
        }
        async fn plan(&mut self, request: PlanRequest) -> Result<ExportPlan, ClientError> {
            self.native.plan(request).await
        }
        async fn relay_approval(
            &mut self,
            request: ApprovalRequest,
        ) -> Result<Approval, ClientError> {
            self.native.relay_approval(request).await
        }
    }
    let temporary = tempfile::TempDir::new().unwrap();
    let peer = peer(PeerPlatform::Apple);
    let (store, output) = enroll(temporary.path(), &peer, &now()).await;
    let clock = ExpiryClock(AtomicBool::new(false));
    let mut source = Source {
        native: NativeFake::new(peer.clone(), now()),
        clock: &clock,
        fences: AtomicUsize::new(0),
    };
    assert!(matches!(
        HostPlanner::new(store.clone())
            .plan(&mut source, input(&peer), &clock)
            .await,
        Err(ClientError::Agent(Error::PlanExpired))
    ));
    assert_eq!(store.revision().await.unwrap(), 1);
    assert_eq!(std::fs::read_dir(output).unwrap().count(), 0);
}

#[tokio::test]
async fn hmac_integrity_does_not_claim_historical_snapshot_rollback_protection() {
    let temporary = tempfile::TempDir::new().unwrap();
    let peer = peer(PeerPlatform::Apple);
    let (store, _) = enroll(temporary.path(), &peer, &now()).await;
    let record = std::fs::canonicalize(temporary.path())
        .unwrap()
        .join("agent-host-v1/issuer.json");
    let historical = std::fs::read(&record).unwrap();
    store.revoke_local(1, &id(5)).await.unwrap();
    assert_eq!(store.revision().await.unwrap(), 2);
    // Same authorized owner restores a valid old HMAC snapshot with the same fake key.
    // No OS-backed monotonic generation/anti-rollback mechanism is implemented here.
    std::fs::write(record, historical).unwrap();
    assert_eq!(store.revision().await.unwrap(), 1);
}

#[tokio::test]
async fn optional_private_decision_null_cannot_bypass_exact_record_grammar() {
    let temporary = tempfile::TempDir::new().unwrap();
    let peer = peer(PeerPlatform::Apple);
    let (store, _) = enroll(temporary.path(), &peer, &now()).await;
    HostPlanner::new(store.clone())
        .plan(
            &mut NativeFake::new(peer.clone(), now()),
            input(&peer),
            &FixedClock(now()),
        )
        .await
        .unwrap();
    let path = std::fs::canonicalize(temporary.path())
        .unwrap()
        .join("agent-host-v1/issuer.json");
    let mut signed: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
    signed["state"]["plans"][0]["decision"] = serde_json::Value::Null;
    std::fs::write(path, serde_json::to_vec(&signed).unwrap()).unwrap();
    assert!(store.revision().await.is_err());
}

#[cfg(unix)]
#[tokio::test]
async fn root_replacement_symlinks_private_permissions_and_hardlinks_fail_closed() {
    use std::os::unix::fs::{PermissionsExt as _, symlink};
    let temporary = tempfile::TempDir::new().unwrap();
    let peer = peer(PeerPlatform::Apple);
    let (store, output) = enroll(temporary.path(), &peer, &now()).await;
    let planner = HostPlanner::new(store.clone());
    std::fs::rename(&output, output.with_file_name("original")).unwrap();
    std::fs::create_dir(&output).unwrap();
    assert!(matches!(
        planner.preflight(&peer, &input(&peer), &now()).await,
        Err(ClientError::Agent(Error::BindingChanged))
    ));
    std::fs::remove_dir(&output).unwrap();
    symlink(output.with_file_name("original"), &output).unwrap();
    assert!(
        planner
            .preflight(&peer, &input(&peer), &now())
            .await
            .is_err()
    );
    let path = std::fs::canonicalize(temporary.path())
        .unwrap()
        .join("agent-host-v1");
    std::fs::set_permissions(
        path.join("issuer.json"),
        std::fs::Permissions::from_mode(0o644),
    )
    .unwrap();
    assert!(store.revision().await.is_err());
    std::fs::set_permissions(
        path.join("issuer.json"),
        std::fs::Permissions::from_mode(0o600),
    )
    .unwrap();
    std::fs::hard_link(path.join("issuer.json"), path.join("alias")).unwrap();
    assert!(store.revision().await.is_err());
}
