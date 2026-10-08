/** Stage1 private contract only. All literals independently source-derived before candidate code. */
import type * as Effect from "effect/Effect";
import type * as Scope from "effect/Scope";
declare const outcomeBrand: unique symbol;
declare const modeBrand: unique symbol;
declare const valueBrand: unique symbol;
declare const bytesBrand: unique symbol;
declare const validatedBrand: unique symbol;
declare const decisionBrand: unique symbol;
declare const completionBrand: unique symbol;
declare const leaseBrand: unique symbol;
export interface OwnedCommonOutcome { readonly [outcomeBrand]: true }
export interface OwnedMode { readonly [modeBrand]: true }
export interface OwnedValue { readonly [valueBrand]: true }
export interface OwnedBytes { readonly [bytesBrand]: true }
export interface OwnedValidatedRaw { readonly [validatedBrand]: true }
export interface OwnedDecision { readonly [decisionBrand]: true }
export interface OwnedCompletion { readonly [completionBrand]: true }
export interface OwnedOutputLease { readonly [leaseBrand]: true }
export type FixedFailure = { readonly code: "private_cli_input" | "private_cli_owned" | "private_cli_codec" | "private_cli_authority" | "private_cli_cleanup" | "private_cli_busy" | "private_cli_publish" | "private_cli_capability" | "owned_handoff_closed" };
export type ModeMetadata = { readonly mode: "json" | "human"; readonly conflictingFlags: boolean; readonly plainHuman: true; readonly columns: 100 };
export type OutcomeKind = "structured_success" | "local_discovery" | "parse_failure" | "operational_failure" | "raw_artifact" | "plain_text";
export type ArtifactFamily = "raw_json_stdout" | "jsonl_stdout_and_receipt_stderr" | "artifact_destination" | "jsonl_destination_and_receipt";
export type OutcomeMetadata = { readonly kind: OutcomeKind; readonly command: "status" | "query" | "direct"; readonly value: OwnedValue | null; readonly artifactFamily: ArtifactFamily | null; readonly fixedPolicy: "none" | "unknown_argument" | "argument_conflict" | "runtime_unavailable" | "wake_window_expired" | "output_write_failed" };
export type SourceValue = null | boolean | string | { readonly kind: "signed_integer" | "unsigned_integer"; readonly decimal: string } | { readonly kind: "binary64"; readonly bits: string } | readonly SourceValue[] | { readonly kind: "object"; readonly entries: readonly (readonly [string, SourceValue])[] };
export interface CommonOutcomeIssuer {
  /** Issuance only inside captured trusted producer callback, primitive bounds first.
   * Same callback/context/factory owns values and outcomes. Provider cause/message is never an input. */
  value(primitiveSourceValueWire: unknown): OwnedValue | null;
  outcome(primitiveClosedMetadataWire: unknown, value: unknown): OwnedCommonOutcome | null;
}
export interface CommonOutcomePort {
  /** Closed inert synthetic stimulus, never an evaluator/parser/grant or caller-authenticating JSON. */
  receive(primitiveHandoffWire: string, issuer: CommonOutcomeIssuer): Effect.Effect<OwnedCommonOutcome, FixedFailure>;
}
export type AuthorityPhase = "after_common" | "before_raw_validation" | "after_raw_validation" | "before_render" | "before_materialization" | "after_render" | "before_decision" | "before_allocation" | "after_allocation" | "before_publication" | "after_publication" | "assert_current";
export interface InertOutcomeView { inspect(outcome: unknown): OutcomeMetadata | null }
export interface AuthorizedOutcomeView extends InertOutcomeView {
  /** Membership-first inert mode metadata only; unknown/foreign modes return null before properties. */
  mode(mode: unknown): ModeMetadata | null;
  /** LAZY EACH execution: exact request + OWN value membership and exact returned outcome.metadata.value identity before properties/check;
   * captured original current check before materialization, original Scope/context/callback
   * rechecked after await, including exact returned outcome/value identity, then return primitive wire without an intervening yield.
   * Unbound same-callback own values return null before current or materialization. */
  sourceValueWire(outcome: unknown, value: unknown): Effect.Effect<string | null, FixedFailure>;
}
export interface CurrentAuthority {
  /** Host binds original catalog/classification/caller/source/purpose/destination/latest independent
   * suppression frontier. Producer/input metadata, command, TTY and source IDs do not authenticate. */
  check(outcome: OwnedCommonOutcome, phase: AuthorityPhase, view: InertOutcomeView): Effect.Effect<void, FixedFailure>;
}
export interface ByteIssuer { encodedUTF8(primitiveText: unknown, outcome: unknown): OwnedBytes | null }
export interface CanonicalRenderer {
  /** Trusted pure rendering adapter with Effect-valued reads, not a second common evaluator.
   * JSON pretty/human complete algorithms and admitted exact-number adapter remain future owners.
   * Fakes use source-value input witnesses/generic restricted transforms, NEVER case IDs/expected bytes. */
  render(outcome: OwnedCommonOutcome, mode: OwnedMode, issuer: ByteIssuer, view: AuthorizedOutcomeView): Effect.Effect<OwnedBytes, FixedFailure>;
}
export interface RawIssuer { validated(primitiveUTF8Text: unknown, value: unknown, outcome: unknown): OwnedValidatedRaw | null }
export interface RawArtifactValidator {
  /** Callback-issued same-outcome validation witness, never a caller boolean/filename/profile claim. */
  validate(outcome: OwnedCommonOutcome, issuer: RawIssuer, view: AuthorizedOutcomeView): Effect.Effect<OwnedValidatedRaw, FixedFailure>;
}
export type DecisionMetadata = { readonly mode: "json" | "human" | "raw" | "text"; readonly exit: 0 | 1 | 2; readonly outputKind: "structured" | "raw_artifact" | "plain_text"; readonly artifactFamily: ArtifactFamily | null; readonly stderr: "empty" | "owned_receipt"; readonly publication: "not_started" };
export interface InertDecisionView { inspect(decision: unknown): DecisionMetadata | null }
export interface AuthorizedBytesView extends InertDecisionView {
  /** LAZY EACH execution; exact request + OWN byte token membership first. Captured current
   * before_publication then original Scope/poison/context/membership/sink-callback recheck.
   * Foreign Proxy request with OWN bytes returns null with zero checks/traps.
   * Callback expires immediately on actual sink Effect exit, before postcurrent/release ACK. */
  utf8(decision: unknown, bytes: unknown): Effect.Effect<string | null, FixedFailure>;
}
export interface CapturedOutputLifetime {
  /** Original constructor-captured Scope/poison sentinel; not a current-authority permit. */
  isLive(): boolean;
  /** Reusable lazy terminal notification completed by original Scope finalizer.
   * It never consults a caller Scope or replacement Layer and never awaits resource ACK. */
  readonly closed: Effect.Effect<void>;
}
export interface OutputWriter {
  /** Owns prepare, partial cleanup, finite commit/registration and release ACK. */
  withLease<A>(
    decision: OwnedDecision,
    view: InertDecisionView,
    lifetime: CapturedOutputLifetime,
    use: (lease: OwnedOutputLease) => Effect.Effect<A, FixedFailure>
  ): Effect.Effect<A, FixedFailure>;
  publish(decision: OwnedDecision, bytes: OwnedBytes, lease: OwnedOutputLease, view: AuthorizedBytesView): Effect.Effect<void, FixedFailure>;
}
export interface TrustedCapabilities {
  /** Captured host object, not caller wire; still not actual source/OS admission. */
  readonly rawFamilies: readonly ArtifactFamily[];
  readonly plainText: boolean;
}
export interface TrustedServices { readonly common: CommonOutcomePort; readonly current: CurrentAuthority; readonly renderer: CanonicalRenderer; readonly raw: RawArtifactValidator; readonly writer: OutputWriter; readonly capabilities: TrustedCapabilities }
export interface CliEnvelope {
  selectMode(primitiveFlagWire: unknown): Effect.Effect<OwnedMode, FixedFailure>;
  receive(primitiveHandoffWire: unknown): Effect.Effect<OwnedCommonOutcome, FixedFailure>;
  render(outcome: unknown, mode: unknown): Effect.Effect<OwnedDecision, FixedFailure>;
  inspect(decision: unknown): DecisionMetadata | null;
  publish(decision: unknown): Effect.Effect<OwnedCompletion, FixedFailure>;
  exit(completion: unknown): Effect.Effect<0 | 1 | 2, FixedFailure>;
  assertCurrent(decision: unknown): Effect.Effect<void, FixedFailure>;
}
export interface CliEnvelopeFactory { create(trusted: TrustedServices): Effect.Effect<CliEnvelope, FixedFailure, Scope.Scope> }
/** Closed procedure, frozen before business implementation:
 * Register original Scope sentinel BEFORE any trusted callback. Capture methods/services once.
 * WeakMaps/WeakSets own factory/context/value/mode/bytes/validated/decision/completion/lease;
 * every unknown input membership precedes properties, even revoked/throwing Proxies.
 * selectMode uses closed bounded private flags {force_json,force_human,tty}; booleans only.
 * OutputMode source JSON precedence preserved; bothflags require owned parse_failure/conflict
 * before rendering, not resolve() inventing an error. Caller flags never grant authority.
 * receive preflights bounded primitive wire then actual common callback owns issuer; issuer expires
 * by INNER ensuring immediately on callback Effect exit BEFORE after_common current callback.
 * Own callback output checked BEFORE properties. Every callback is followed by original liveness;
 * each ordinary callback/current/finished allocation/decision/publication/assert has fresh captured
 * current authority. Source policy absent/denied remains unavailable; no supplied grants honored.
 * render: before_render -> renderer effect -> after_render -> before_decision; read wire lazily
 * adds before_materialization EACH execution. Renderer view/issuer inner expiry before after_render.
 * raw: before_raw_validation -> validator (one lazy before_materialization read) -> after_raw_validation
 * -> before_decision; own validated token bypasses renderer; original rawUTF8 EXACT, no LF added.
 * Artifact identity and sidechannel remain distinct. Private raw_json_stdout witness only; denied
 * other families private_capability is NOT a new public unsupported claim; exact future tasks below.
 * Structured exit0, discovery0, parse2, operational1; JSON pretty source adds exactly ONE LF.
 * Plain text/help bypass source mode; full Clap/help/version/human/color requires its own adapter.
 * render never acquires native/source/output resource. publish: before_allocation ->
 * OutputWriter.withLease scoped bracket -> after_allocation inside use -> actual writer callback
 * (EACH byte read adds before_publication) -> after_publication -> bracket release ACK -> assert_current.
 * Completed/partial allocation, captured original-close signal and owned phase interruption protocol
 * are specified in the exact approved allocation contract below; no unknown acquisition return.
 * Writer view inner ensuring expires when actual writer callback exits before postcurrent/release.
 * One busy publication remains held until acknowledged bracket terminal, or cleanup poison.
 * No output/state rollback asserted after bytes observed; cancellation/failed write may have published
 * a prefix or whole result. Private failure stays fixed and ambiguous, never authenticates delivery.
 * Pure codec/renderer input witnesses contain inert source values, no caseID/expected response table.
 * All budgets below PRIVATE unmeasured, not public CLI restrictions/2MiB transport bounds.
 */

/** Approved allocation amendment source: 8f8cb53f27a58b9f1eb0d7a99ffff4f11702894d8025fa191a4aaec24267d077.
 * Exact approved scoped allocation ownership:
 * The bracket owns an issuer/WeakMap context for its exact decision, captured original lifetime and single use callback. Its own lease exists only for the registered allocation and cannot be accepted by another invocation, factory or closed context. A TypeScript brand alone does not validate the lease.
 * Envelope retains its own decision, bytes, completion ownership, one-busy gate, captured authority, Scope sentinel and per-sink callback sentinel. It never authenticates arbitrary lease properties or a returned unknown object.
 * use is entered at most once and only for the exact internally registered lease. Its effect is suspended, not eagerly invoked. Scope closure or cancellation before entry prohibits use. The output sink's own inner ensuring expires AuthorizedBytesView immediately when the actual publish callback exits, before after_publication or bracket release.
 * The factory registers its original Scope finalizer before any trusted port. That finalizer atomically expires the captured sentinel and completes a factory-owned Deferred terminal signal, then returns without joining operations or awaiting resource ACK. The readonly closed Effect is a reusable await of this same owned terminal signal, not an injected Scope lookup or grant. withLease owns its watcher, phase Fiber, and cleanup; it cannot accept caller replacement lifetimes. Scope.close acknowledgement means signal publication/Scope finalizers finished, not that an independently supervised output operation released resources.
 * Exact approved scoped allocation internal protocol:
 * The port is a trusted scoped resource adapter, not a raw acquire function. It must document and implement its own preparation-to-commit boundary. A fake test adapter must execute this protocol rather than promise that an opaque return is safe.
 * Before preparation, observe captured original lifetime and pending interruption. Preparation waits are interruptible. Preparation owns no committed output allocation; any temporary preparation handles remain owned entirely inside the bracket and have exception-safe cancellation/failed-preparation cleanup. Such cleanup is separate from completed-allocation release counters. No unreturned partial handle may escape.
 * The completed-allocation transition is finite and synchronous: inside a short interruption mask, recheck original lifetime, create the completed allocation and immediately install the bracket-local exactly-once finalizer before exposing the lease, invoking any reentrant trusted callback or restoring interruption. Creation plus registration must have no await/yield/Deferred gap. If a synchronous creator fails after obtaining a handle, it cleans that handle in the same owned protocol; it cannot discard an unregistered handle.
 * After registration, restore interruption and check pending interruption and original lifetime before invoking use. No effectful/unbounded preparation or delayed allocation wait is inside the short commit/registration mask. The port may have a cancellable registered-stage wait; interruption there runs the already installed finalizer instead of losing a late result.
 * Once use starts, the envelope first checks original lifetime then captured current after_allocation; denial/closure skips sink publication. The use body keeps the existing writer callback inner ensuring and EACH lazy byte-read current checks. Allocation is not a permit to publish.
 * On success, failure, interruption or original-lifetime closure, the bracket performs the registered completed-allocation release exactly once and awaits its asynchronous ACK before it completes. The release attempt is protected from the publish Fiber's interruption; it may await a port-specific bounded native cleanup protocol. A port-specific cleanup deadline must return fixed cleanup failure and poison rather than declare success or permit reuse; eventual physical cleanup alone is not a timely ACK.
 * No general unbounded ACK or native cancellation qualification follows from synthetic Deferred tests. The public real stdout/resource owner must specify concrete finite deadlines and cancellation/partial-write behavior. The current private fake deliberately holds ACK on a test-controlled Deferred until the action driver resumes it, so it measures ordering and exact once, not a real cleanup deadline.
 * If cleanup fails, withLease yields private_cli_cleanup with precedence over apparent use success and signals poison through its fixed result; envelope poisons before releasing its busy gate and refuses later operations. On interruption with successful ACK it preserves interruption. On normal use success and successful ACK it returns A, after which envelope assert_current is still required.
 * One busy publication remains held until acknowledged bracket completion. Completed allocations observed before failure may already have caused bytes to be seen; no rollback or atomic delivery claim.
 * Exact approved captured original-close protocol:
 * The bracket starts its single close watcher and phase ownership before any suspended preparation. Setup is finite under a short mask, checks the sentinel before and after installing the watcher, and the terminal Deferred is replayable, so closing before subscription cannot be missed. It never treats a fresh local Scope as original liveness.
 * Close notification latches originalClosed and requests interruption ONLY of the bracket-owned interruptible preparation/registered-wait/use Fiber. It does not interrupt a creator between synchronous commit and installed finalizer, and does not race or drop the protected partial/completed cleanup ACK phase.
 * Preparation suspension is interruptible and resource-free for the private fake. Closure wakes it without resuming its Deferred. If a future real prepare has temporary resources, its owned preparation cancellation must finish its separately acknowledged cleanup before termination; this is not a completed-allocation release count or a current native qualification.
 * If closure races the finite commit boundary, the sentinel recheck before commit either forbids commit, or a completed allocation is registered before interruption is restored. The latter receives exactly one release. Closed notification cannot discard a returned handle or start a duplicate release.
 * If closure occurs while use waits, interrupt the owned use Fiber, let its actual callback inner ensuring expire issuer/views, then run the already registered finalizer and await ACK. No sink/read is restarted or callback resumed because it completed normally after closure.
 * The outer bracket supervises phase interruption and ACK while preserving its original owned external interruption status. It awaits the phase Fiber to terminate and cleanup to acknowledge; cancellation of the watcher is idempotent and its own termination is joined before bracket completion. No detached watcher or Fiber survives completion.
 * When a callback itself invokes Scope.close(originalScope), the original finalizer only expires/signals and returns. The signal may interrupt the bracket-owned callback Fiber, but does not wait for that callback or its own cleanup. The separate operation bracket awaits cleanup ACK. This split avoids a close callback joining itself. Scope.close alone never attests resource release.
 * During protected completed release ACK, original closure only latches closure and invalidates liveness; it does not cancel/restart release or permit busy to clear. If release fails, poison before further operations; if it acknowledges, perform terminal disposition only afterward.
 * Terminal precedence: failed preparation/completed cleanup -> fixed private_cli_cleanup and poison; otherwise pending actual external publication-Fiber interruption -> preserve interruption; otherwise originalClosed -> fixed owned_handoff_closed; otherwise use failure or success. Closure-induced phase interruption is owned closure, not falsely presented as external cancellation. An external interruption observed before terminal disposition wins over closure, even if it arrives while waiting for protected ACK. Once bracket returns a terminal result, later events do not rewrite it.
 * Fresh current checks and membership/context/actual-callback liveness retain their exact order independently. No additional authority callback is run just to deliver close notification or release cleanup. Busy remains held until ACK or poisoned cleanup failure; no completion/exit before this disposition.
 * Exact reviewed original scene realizations:
 * interrupt-pending-uncompleted-output-allocation: The fake bracket suspends in interruptible preparation with no committed allocation and no partial handle. The driver interrupts its Fiber. No commit/use occurs; counters allocation0/release_attempt0/ACK0 remain exact.
 * late-completed-output-allocation-on-cancel: The fake bracket performs finite synchronous commit+registration first (allocation1), signals its registered-stage Deferred, then waits interruptibly before use. The driver interrupts there; interruption immediately starts the already installed exactly-once finalizer. That finalizer protects the completed allocation while awaiting the test-controlled release ACK Deferred. The driver releases the allocation/ACK gate, the bracket observes ACK1 and preserves interruption. The original phrase uninterruptible completed allocation held on Deferred refers to the protected registered allocation during finalization, not an uncompleted acquisition wait. No completed handle is unregistered and preparation never becomes uninterruptible.
 * Scope-close-inside-completed-output-allocation: The fake bracket registers the committed allocation before an owned registered-stage action closes the captured original Scope. The action runs outside the finite commit mask. The original lifetime check then fails before use and bracket release attempts1/ACK1. The close action must not synchronously wait for a parent finalizer that depends on the closing callback's own return; the bracket is operation-local and the original Scope sentinel is authoritative.
 * deny-after-output-allocation: Registered lease enters use; envelope current after_allocation denies. No writer callback; bracket releases1/ACK1. Authority7 unchanged.
 * releaseACK-pending-blocks-exit: use finishes, sink callback is already expired, after_publication completes; bracket release starts1 and waits on fake ACK Deferred. No completion/exit/assert_current until ACK resumes. The final authority10 and ACK1 remain exact.
 * release-defect-poisons-factory: Fake bracket finalizer fails with fixed cleanup failure rather than ACK. Envelope poisons before future use, authority9/release_attempt1/ACK0 unchanged.
 * Scope-close-inside-releaseACK: Cleanup closes original Scope but is allowed to acknowledge already-owned release. Bracket returns after ACK; original lifetime blocks completion before assert_current. No noncleanup callback after closure.
 * owned-output-busy-until-releaseACK: First bracket retains busy while registered use/ACK is pending. Second publication refuses before current/allocation. First Fiber cleanup awaits one ACK; busy can clear only afterward, or remain poisoned on cleanup failure.
 * delayed and Deferred lazy read / escaped sink callback scenes: Only envelope's actual publish callback receives its AuthorizedBytesView. Every lazy execution checks captured current and originalScope/member/context/sink live after await. Inner callback ensuring expires view before bracket postcallback current or release. Bracket lifetime does not extend callback authority.
 * Source-only private contract; real native deadlines/partial cleanup/public cancellation parity unqualified.
 */

/** Observation field contract: stderr_utf8 is the empty private synthetic transcript for
 * every scene: this interface has no stderr stream, observer, or write operation.
 * It is independent of returned-decision availability and does not attest a real
 * process stderr stream or public JSONL receipt side channel. stdout_field_meaning
 * remains the separate owned-returned-byte/absence contract retained in each scene.
 */
export const resultEnvelopeFixture = {
  "task_id": "CLI-RESULT-ENVELOPE",
  "assigned_source": "5952cb86ad1d212efdebfabe3523a4f42aff1454",
  "status": "Stage1_frozen_source_only_pending_independent_review_before_code",
  "proof_class": "portable_synthetic_private_UTF8_orchestration_only",
  "case_count": 84,
  "minimum_packet_case_count": 6,
  "packet_minima": [
    {
      "case_id": "cli-envelope-auto-terminal",
      "input": {
        "force_json": false,
        "force_human": false,
        "tty": true
      },
      "expected": {
        "mode": "human",
        "structured_only": false
      },
      "status": "literal proposal before implementation; complete typed interface/full exact bytes require independent Stage1 freeze"
    },
    {
      "case_id": "cli-envelope-auto-pipe",
      "input": {
        "force_json": false,
        "force_human": false,
        "tty": false
      },
      "expected": {
        "mode": "json",
        "stdout_diagnostic": false
      },
      "status": "literal proposal before implementation; complete typed interface/full exact bytes require independent Stage1 freeze"
    },
    {
      "case_id": "cli-envelope-operation-failure",
      "input": {
        "outcome": "operational_failure",
        "code": "runtime_unavailable",
        "provider_message": "SYNTHETIC_SECRET"
      },
      "expected": {
        "schema": "healthmd.cli_error",
        "schema_version": 1,
        "exit": 1,
        "request_sent": false,
        "provider_echo": false
      },
      "status": "literal proposal before implementation; complete typed interface/full exact bytes require independent Stage1 freeze"
    },
    {
      "case_id": "cli-envelope-parse-failure",
      "input": {
        "outcome": "parse_failure",
        "raw_arguments": [
          "SYNTHETIC_SECRET"
        ]
      },
      "expected": {
        "schema": "healthmd.cli_error",
        "schema_version": 1,
        "error": "invalid_request",
        "exit": 2,
        "raw_echo": false
      },
      "status": "literal proposal before implementation; complete typed interface/full exact bytes require independent Stage1 freeze"
    },
    {
      "case_id": "cli-envelope-raw-bypass",
      "input": {
        "outcome": "owned_validated_artifact",
        "artifact_utf8": "{}\n",
        "mode": "json"
      },
      "expected": {
        "stdout_utf8": "{}\n",
        "structured_wrapper": false,
        "exit": 0
      },
      "status": "literal proposal before implementation; complete typed interface/full exact bytes require independent Stage1 freeze"
    },
    {
      "case_id": "cli-envelope-wake-code-alias",
      "input": {
        "internal_code": "direct_wake_window_expired",
        "wake_window_seconds": 30
      },
      "expected": {
        "public_code": "direct_source_unavailable",
        "wake_window_seconds": 30,
        "exit": 1
      },
      "status": "literal proposal before implementation; complete typed interface/full exact bytes require independent Stage1 freeze"
    }
  ],
  "source_value_input_witnesses": [
    {
      "name": "ready",
      "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
      "source": "output.rs render_document + render_field Boolean/inline_value"
    },
    {
      "name": "runtime_unavailable",
      "value_wire": "{\"entries\":[[\"command\",\"healthmd status\"],[\"error\",\"runtime_unavailable\"],[\"help_command\",\"healthmd status --help\"],[\"message\",\"The local asynchronous runtime could not start; no command was executed.\"],[\"next_actions\",[{\"entries\":[[\"command\",\"healthmd --version\"],[\"description\",\"Verify that the installed executable can start without running a live command.\"]],\"kind\":\"object\"},{\"entries\":[[\"action\",\"Release local process/thread resources or reinstall the exact supported Health.md CLI build before retrying.\"]],\"kind\":\"object\"}]],[\"request_sent\",false],[\"schema\",\"healthmd.cli_error\"],[\"schema_version\",{\"decimal\":\"1\",\"kind\":\"unsigned_integer\"}],[\"status\",\"failure\"]],\"kind\":\"object\"}",
      "source": "main.rs runtime failure; guidance.rs command_error/recovery_actions"
    },
    {
      "name": "unknown_argument",
      "value_wire": "{\"entries\":[[\"accepted_arguments\",[\"--job <JOB_UUID>\"]],[\"command\",\"healthmd status\"],[\"error\",\"invalid_request\"],[\"error_kind\",\"unknown_argument\"],[\"help_command\",\"healthmd status --help\"],[\"message\",\"One argument is not recognized for this command. Review the accepted arguments below.\"],[\"next_actions\",[{\"entries\":[[\"command\",\"healthmd status --help\"],[\"description\",\"Review the accepted syntax, constraints, and examples, then retry with only documented arguments.\"]],\"kind\":\"object\"}]],[\"request_sent\",false],[\"schema\",\"healthmd.cli_error\"],[\"schema_version\",{\"decimal\":\"1\",\"kind\":\"unsigned_integer\"}],[\"status\",\"failure\"]],\"kind\":\"object\"}",
      "source": "guidance.rs parser_error/accepted_arguments/status/parser_message"
    },
    {
      "name": "argument_conflict",
      "value_wire": "{\"entries\":[[\"accepted_arguments\",[\"--job <JOB_UUID>\"]],[\"command\",\"healthmd status\"],[\"error\",\"invalid_request\"],[\"error_kind\",\"argument_conflict\"],[\"help_command\",\"healthmd status --help\"],[\"message\",\"Two supplied arguments cannot be used together. Choose one documented request shape.\"],[\"next_actions\",[{\"entries\":[[\"command\",\"healthmd status --help\"],[\"description\",\"Review the accepted syntax, constraints, and examples, then retry with only documented arguments.\"]],\"kind\":\"object\"}]],[\"request_sent\",false],[\"schema\",\"healthmd.cli_error\"],[\"schema_version\",{\"decimal\":\"1\",\"kind\":\"unsigned_integer\"}],[\"status\",\"failure\"]],\"kind\":\"object\"}",
      "source": "main.rs requested_output_mode +guidance.rs parser_error"
    },
    {
      "name": "wake_window_expired",
      "value_wire": "{\"entries\":[[\"command\",\"healthmd status\"],[\"error\",\"direct_source_unavailable\"],[\"help_command\",\"healthmd status --help\"],[\"message\",\"The direct mobile source is unavailable.\"],[\"next_actions\",[{\"entries\":[[\"action\",\"Keep Health.md open in the foreground on the paired mobile source.\"]],\"kind\":\"object\"},{\"entries\":[[\"command\",\"healthmd status\"],[\"description\",\"Check pairing, transport, protected-data, and source readiness.\"]],\"kind\":\"object\"},{\"entries\":[[\"command\",\"healthmd direct devices\"],[\"description\",\"Inspect local pairing and select a device explicitly when needed.\"]],\"kind\":\"object\"}]],[\"schema\",\"healthmd.cli_error\"],[\"schema_version\",{\"decimal\":\"1\",\"kind\":\"unsigned_integer\"}],[\"status\",\"failure\"],[\"wake_window_seconds\",{\"decimal\":\"30\",\"kind\":\"unsigned_integer\"}]],\"kind\":\"object\"}",
      "source": "main.rs direct_error; guidance.rs public_code/additivewindow/recovery"
    },
    {
      "name": "direct_catalog",
      "value_wire": "{\"entries\":[[\"available_commands\",[{\"entries\":[[\"command\",\"healthmd direct pair\"],[\"description\",\"Pair this CLI installation with an open iOS or Android app.\"]],\"kind\":\"object\"},{\"entries\":[[\"command\",\"healthmd direct devices\"],[\"description\",\"List local trusted devices without network access.\"]],\"kind\":\"object\"},{\"entries\":[[\"command\",\"healthmd direct unpair\"],[\"description\",\"Inspect the required device ID before removing one pairing.\"]],\"kind\":\"object\"},{\"entries\":[[\"command\",\"healthmd direct reset-trust\"],[\"description\",\"Review the destructive all-trust reset and its required confirmation.\"]],\"kind\":\"object\"}]],[\"command\",\"healthmd direct\"],[\"description\",\"Pair and manage direct mobile trust.\"],[\"message\",\"Choose one of the available commands below; no operation was started.\"],[\"next_actions\",[{\"entries\":[[\"command\",\"healthmd direct --help\"],[\"description\",\"Read the complete command help.\"]],\"kind\":\"object\"}]],[\"request_sent\",false],[\"schema\",\"healthmd.cli_guidance\"],[\"schema_version\",{\"decimal\":\"1\",\"kind\":\"unsigned_integer\"}],[\"status\",\"guidance\"]],\"kind\":\"object\"}",
      "source": "guidance.rs group(direct)"
    },
    {
      "name": "raw_json",
      "value_wire": "\"{\\\"synthetic\\\":true}\\n\"",
      "source": "main.rs CommandOutput::Artifact exact validated stdout; synthetic JSON only"
    },
    {
      "name": "raw_json_without_LF",
      "value_wire": "\"{\\\"synthetic\\\":true}\"",
      "source": "main.rs Artifact io::copy/flush; synthetic validated JSON without trailingLF"
    },
    {
      "name": "output_write_failed",
      "value_wire": "{\"entries\":[[\"command\",\"healthmd status\"],[\"error\",\"output_write_failed\"],[\"help_command\",\"healthmd status --help\"],[\"message\",\"The command result could not be written to stdout or the requested output destination.\"],[\"next_actions\",[{\"entries\":[[\"action\",\"Verify that stdout or the requested output destination is writable and has sufficient free space.\"]],\"kind\":\"object\"},{\"entries\":[[\"command\",\"healthmd status --help\"],[\"description\",\"Review accepted arguments and examples.\"]],\"kind\":\"object\"}]],[\"schema\",\"healthmd.cli_error\"],[\"schema_version\",{\"decimal\":\"1\",\"kind\":\"unsigned_integer\"}],[\"status\",\"failure\"]],\"kind\":\"object\"}",
      "source": "main.rs write_failure/guidance recovery"
    },
    {
      "name": "success_error_shaped",
      "value_wire": "{\"entries\":[[\"error\",\"runtime_unavailable\"],[\"message\",\"synthetic result data\"]],\"kind\":\"object\"}",
      "source": "CommandSuccess Json(Value) shape never changes success.exit_code"
    }
  ],
  "private_bounds": {
    "handoff_utf8_bytes": 65536,
    "mode_wire_utf8_bytes": 1024,
    "value_wire_utf8_bytes": 65536,
    "encoded_UTF8_bytes": 65536,
    "JSON_depth": 32,
    "JSON_nodes": 4096,
    "decoded_string_utf8_bytes": 16384,
    "numeric_scalar_tokens": "Canonical signed/unsigned integer strings bounded exact ranges; finitebinary64 bits16hex closed; no numeric sourceJSON Number conversion",
    "flags": "Exactly force_json/force_human/tty booleans; duplicate decodedkeys/unknownfields/loneUTF16/nonfiniteprivategrammar rejected; public Rust grammar untouched"
  },
  "normal_counter_order": [
    "after_common",
    "before_render",
    "before_materialization (renderer own read)",
    "after_render",
    "before_decision",
    "before_allocation",
    "after_allocation",
    "before_publication (sink own read)",
    "after_publication",
    "assert_current AFTER releaseACK"
  ],
  "raw_counter_order": [
    "after_common",
    "before_raw_validation",
    "before_materialization (validator own read)",
    "after_raw_validation",
    "before_decision",
    "before_allocation",
    "after_allocation",
    "before_publication (sink own read)",
    "after_publication",
    "assert_current AFTER releaseACK"
  ],
  "source_order_policies": [
    "JSON wins flags selection even both flags; trusted parser produces ArgumentConflict/parseexit2 separately.",
    "JSON structured pretty BTreeMap keyorder andoneLF; plain human100columns NO_COLOR witness only.",
    "Artifact validatedraw bypass exactbytes noLF; JSONL stdout/data +stderrreceipt/destination identities retained, not silently unsupported public sourcefamilies.",
    "Common structured success can contain error-shaped fields without becoming operational_failure; private error tag owns fixed guidance class.",
    "Localdiscoveryexit0/parseexit2/operationalexit1; raw/output exit success0; output publication mayambiguous after observations."
  ],
  "no_output_expected_or_case_ID_in_future_ports": true,
  "no_health_payload": true,
  "cases": [
    {
      "case_id": "cli-envelope-auto-terminal",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":true}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "human",
        "stdout_utf8": "Health.md result\n================\n\nReady: Yes\n",
        "stderr_utf8": "",
        "exit": 0,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "Health.md result\n================\n\nReady: Yes\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "output.rs22-28/309-333/heading/inline_value/finish; plain human host fixture"
    },
    {
      "case_id": "cli-envelope-auto-pipe",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "json",
        "stdout_utf8": "{\n  \"ready\": true\n}\n",
        "stderr_utf8": "",
        "exit": 0,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "{\n  \"ready\": true\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "output.rs22-28;main.rs2166-2181 BTreeMap pretty JSON +oneLF"
    },
    {
      "case_id": "cli-envelope-operation-failure",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"runtime_unavailable\",\"kind\":\"operational_failure\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"command\\\",\\\"healthmd status\\\"],[\\\"error\\\",\\\"runtime_unavailable\\\"],[\\\"help_command\\\",\\\"healthmd status --help\\\"],[\\\"message\\\",\\\"The local asynchronous runtime could not start; no command was executed.\\\"],[\\\"next_actions\\\",[{\\\"entries\\\":[[\\\"command\\\",\\\"healthmd --version\\\"],[\\\"description\\\",\\\"Verify that the installed executable can start without running a live command.\\\"]],\\\"kind\\\":\\\"object\\\"},{\\\"entries\\\":[[\\\"action\\\",\\\"Release local process/thread resources or reinstall the exact supported Health.md CLI build before retrying.\\\"]],\\\"kind\\\":\\\"object\\\"}]],[\\\"request_sent\\\",false],[\\\"schema\\\",\\\"healthmd.cli_error\\\"],[\\\"schema_version\\\",{\\\"decimal\\\":\\\"1\\\",\\\"kind\\\":\\\"unsigned_integer\\\"}],[\\\"status\\\",\\\"failure\\\"]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"command\",\"healthmd status\"],[\"error\",\"runtime_unavailable\"],[\"help_command\",\"healthmd status --help\"],[\"message\",\"The local asynchronous runtime could not start; no command was executed.\"],[\"next_actions\",[{\"entries\":[[\"command\",\"healthmd --version\"],[\"description\",\"Verify that the installed executable can start without running a live command.\"]],\"kind\":\"object\"},{\"entries\":[[\"action\",\"Release local process/thread resources or reinstall the exact supported Health.md CLI build before retrying.\"]],\"kind\":\"object\"}]],[\"request_sent\",false],[\"schema\",\"healthmd.cli_error\"],[\"schema_version\",{\"decimal\":\"1\",\"kind\":\"unsigned_integer\"}],[\"status\",\"failure\"]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"runtime_unavailable\",\"kind\":\"operational_failure\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        },
        "untrusted_provider_message": "SYNTHETIC_SECRET"
      },
      "expected": {
        "kind": "completion",
        "mode": "json",
        "stdout_utf8": "{\n  \"command\": \"healthmd status\",\n  \"error\": \"runtime_unavailable\",\n  \"help_command\": \"healthmd status --help\",\n  \"message\": \"The local asynchronous runtime could not start; no command was executed.\",\n  \"next_actions\": [\n    {\n      \"command\": \"healthmd --version\",\n      \"description\": \"Verify that the installed executable can start without running a live command.\"\n    },\n    {\n      \"action\": \"Release local process/thread resources or reinstall the exact supported Health.md CLI build before retrying.\"\n    }\n  ],\n  \"request_sent\": false,\n  \"schema\": \"healthmd.cli_error\",\n  \"schema_version\": 1,\n  \"status\": \"failure\"\n}\n",
        "stderr_utf8": "",
        "exit": 1,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "{\n  \"command\": \"healthmd status\",\n  \"error\": \"runtime_unavailable\",\n  \"help_command\": \"healthmd status --help\",\n  \"message\": \"The local asynchronous runtime could not start; no command was executed.\",\n  \"next_actions\": [\n    {\n      \"command\": \"healthmd --version\",\n      \"description\": \"Verify that the installed executable can start without running a live command.\"\n    },\n    {\n      \"action\": \"Release local process/thread resources or reinstall the exact supported Health.md CLI build before retrying.\"\n    }\n  ],\n  \"request_sent\": false,\n  \"schema\": \"healthmd.cli_error\",\n  \"schema_version\": 1,\n  \"status\": \"failure\"\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "main.rs650-657;guidance.rs502-548/682-687; fixed runtime message, never provider"
    },
    {
      "case_id": "cli-envelope-parse-failure",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"unknown_argument\",\"kind\":\"parse_failure\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"accepted_arguments\\\",[\\\"--job <JOB_UUID>\\\"]],[\\\"command\\\",\\\"healthmd status\\\"],[\\\"error\\\",\\\"invalid_request\\\"],[\\\"error_kind\\\",\\\"unknown_argument\\\"],[\\\"help_command\\\",\\\"healthmd status --help\\\"],[\\\"message\\\",\\\"One argument is not recognized for this command. Review the accepted arguments below.\\\"],[\\\"next_actions\\\",[{\\\"entries\\\":[[\\\"command\\\",\\\"healthmd status --help\\\"],[\\\"description\\\",\\\"Review the accepted syntax, constraints, and examples, then retry with only documented arguments.\\\"]],\\\"kind\\\":\\\"object\\\"}]],[\\\"request_sent\\\",false],[\\\"schema\\\",\\\"healthmd.cli_error\\\"],[\\\"schema_version\\\",{\\\"decimal\\\":\\\"1\\\",\\\"kind\\\":\\\"unsigned_integer\\\"}],[\\\"status\\\",\\\"failure\\\"]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"accepted_arguments\",[\"--job <JOB_UUID>\"]],[\"command\",\"healthmd status\"],[\"error\",\"invalid_request\"],[\"error_kind\",\"unknown_argument\"],[\"help_command\",\"healthmd status --help\"],[\"message\",\"One argument is not recognized for this command. Review the accepted arguments below.\"],[\"next_actions\",[{\"entries\":[[\"command\",\"healthmd status --help\"],[\"description\",\"Review the accepted syntax, constraints, and examples, then retry with only documented arguments.\"]],\"kind\":\"object\"}]],[\"request_sent\",false],[\"schema\",\"healthmd.cli_error\"],[\"schema_version\",{\"decimal\":\"1\",\"kind\":\"unsigned_integer\"}],[\"status\",\"failure\"]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"unknown_argument\",\"kind\":\"parse_failure\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        },
        "source_argv": [
          "healthmd",
          "status",
          "--SYNTHETIC_SECRET"
        ]
      },
      "expected": {
        "kind": "completion",
        "mode": "json",
        "stdout_utf8": "{\n  \"accepted_arguments\": [\n    \"--job <JOB_UUID>\"\n  ],\n  \"command\": \"healthmd status\",\n  \"error\": \"invalid_request\",\n  \"error_kind\": \"unknown_argument\",\n  \"help_command\": \"healthmd status --help\",\n  \"message\": \"One argument is not recognized for this command. Review the accepted arguments below.\",\n  \"next_actions\": [\n    {\n      \"command\": \"healthmd status --help\",\n      \"description\": \"Review the accepted syntax, constraints, and examples, then retry with only documented arguments.\"\n    }\n  ],\n  \"request_sent\": false,\n  \"schema\": \"healthmd.cli_error\",\n  \"schema_version\": 1,\n  \"status\": \"failure\"\n}\n",
        "stderr_utf8": "",
        "exit": 2,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "{\n  \"accepted_arguments\": [\n    \"--job <JOB_UUID>\"\n  ],\n  \"command\": \"healthmd status\",\n  \"error\": \"invalid_request\",\n  \"error_kind\": \"unknown_argument\",\n  \"help_command\": \"healthmd status --help\",\n  \"message\": \"One argument is not recognized for this command. Review the accepted arguments below.\",\n  \"next_actions\": [\n    {\n      \"command\": \"healthmd status --help\",\n      \"description\": \"Review the accepted syntax, constraints, and examples, then retry with only documented arguments.\"\n    }\n  ],\n  \"request_sent\": false,\n  \"schema\": \"healthmd.cli_error\",\n  \"schema_version\": 1,\n  \"status\": \"failure\"\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "main.rs617-620;guidance.rs551-592/acceptedarguments/parser_message"
    },
    {
      "case_id": "cli-envelope-raw-bypass",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":\"raw_json_stdout\",\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"raw_artifact\"},\"value_wire\":\"\\\"{\\\\\\\"synthetic\\\\\\\":true}\\\\n\\\"\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "\"{\\\"synthetic\\\":true}\\n\"",
          "descriptor_wire": "{\"artifactFamily\":\"raw_json_stdout\",\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"raw_artifact\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "raw",
        "stdout_utf8": "{\"synthetic\":true}\n",
        "stderr_utf8": "",
        "exit": 0,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 0,
        "raw_validator_calls": 1,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "{\"synthetic\":true}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "main.rs2184-2222 exact validated Artifact bytes, no pretty/human/LF addition"
    },
    {
      "case_id": "cli-envelope-wake-code-alias",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"wake_window_expired\",\"kind\":\"operational_failure\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"command\\\",\\\"healthmd status\\\"],[\\\"error\\\",\\\"direct_source_unavailable\\\"],[\\\"help_command\\\",\\\"healthmd status --help\\\"],[\\\"message\\\",\\\"The direct mobile source is unavailable.\\\"],[\\\"next_actions\\\",[{\\\"entries\\\":[[\\\"action\\\",\\\"Keep Health.md open in the foreground on the paired mobile source.\\\"]],\\\"kind\\\":\\\"object\\\"},{\\\"entries\\\":[[\\\"command\\\",\\\"healthmd status\\\"],[\\\"description\\\",\\\"Check pairing, transport, protected-data, and source readiness.\\\"]],\\\"kind\\\":\\\"object\\\"},{\\\"entries\\\":[[\\\"command\\\",\\\"healthmd direct devices\\\"],[\\\"description\\\",\\\"Inspect local pairing and select a device explicitly when needed.\\\"]],\\\"kind\\\":\\\"object\\\"}]],[\\\"schema\\\",\\\"healthmd.cli_error\\\"],[\\\"schema_version\\\",{\\\"decimal\\\":\\\"1\\\",\\\"kind\\\":\\\"unsigned_integer\\\"}],[\\\"status\\\",\\\"failure\\\"],[\\\"wake_window_seconds\\\",{\\\"decimal\\\":\\\"30\\\",\\\"kind\\\":\\\"unsigned_integer\\\"}]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"command\",\"healthmd status\"],[\"error\",\"direct_source_unavailable\"],[\"help_command\",\"healthmd status --help\"],[\"message\",\"The direct mobile source is unavailable.\"],[\"next_actions\",[{\"entries\":[[\"action\",\"Keep Health.md open in the foreground on the paired mobile source.\"]],\"kind\":\"object\"},{\"entries\":[[\"command\",\"healthmd status\"],[\"description\",\"Check pairing, transport, protected-data, and source readiness.\"]],\"kind\":\"object\"},{\"entries\":[[\"command\",\"healthmd direct devices\"],[\"description\",\"Inspect local pairing and select a device explicitly when needed.\"]],\"kind\":\"object\"}]],[\"schema\",\"healthmd.cli_error\"],[\"schema_version\",{\"decimal\":\"1\",\"kind\":\"unsigned_integer\"}],[\"status\",\"failure\"],[\"wake_window_seconds\",{\"decimal\":\"30\",\"kind\":\"unsigned_integer\"}]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"wake_window_expired\",\"kind\":\"operational_failure\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        },
        "internal_code": "direct_wake_window_expired",
        "wake_window_seconds": 30
      },
      "expected": {
        "kind": "completion",
        "mode": "json",
        "stdout_utf8": "{\n  \"command\": \"healthmd status\",\n  \"error\": \"direct_source_unavailable\",\n  \"help_command\": \"healthmd status --help\",\n  \"message\": \"The direct mobile source is unavailable.\",\n  \"next_actions\": [\n    {\n      \"action\": \"Keep Health.md open in the foreground on the paired mobile source.\"\n    },\n    {\n      \"command\": \"healthmd status\",\n      \"description\": \"Check pairing, transport, protected-data, and source readiness.\"\n    },\n    {\n      \"command\": \"healthmd direct devices\",\n      \"description\": \"Inspect local pairing and select a device explicitly when needed.\"\n    }\n  ],\n  \"schema\": \"healthmd.cli_error\",\n  \"schema_version\": 1,\n  \"status\": \"failure\",\n  \"wake_window_seconds\": 30\n}\n",
        "stderr_utf8": "",
        "exit": 1,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "{\n  \"command\": \"healthmd status\",\n  \"error\": \"direct_source_unavailable\",\n  \"help_command\": \"healthmd status --help\",\n  \"message\": \"The direct mobile source is unavailable.\",\n  \"next_actions\": [\n    {\n      \"action\": \"Keep Health.md open in the foreground on the paired mobile source.\"\n    },\n    {\n      \"command\": \"healthmd status\",\n      \"description\": \"Check pairing, transport, protected-data, and source readiness.\"\n    },\n    {\n      \"command\": \"healthmd direct devices\",\n      \"description\": \"Inspect local pairing and select a device explicitly when needed.\"\n    }\n  ],\n  \"schema\": \"healthmd.cli_error\",\n  \"schema_version\": 1,\n  \"status\": \"failure\",\n  \"wake_window_seconds\": 30\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "guidance.rs502-522/655-662;main.rsdirect_error fixed unavailable message"
    },
    {
      "case_id": "forced-json-terminal",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":true,\"tty\":true}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "json",
        "stdout_utf8": "{\n  \"ready\": true\n}\n",
        "stderr_utf8": "",
        "exit": 0,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "{\n  \"ready\": true\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "output.rsresolve/main.rs flags/source plain renderer witness"
    },
    {
      "case_id": "forced-human-pipe",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":true,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "human",
        "stdout_utf8": "Health.md result\n================\n\nReady: Yes\n",
        "stderr_utf8": "",
        "exit": 0,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "Health.md result\n================\n\nReady: Yes\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "output.rsresolve/main.rs flags/source plain renderer witness"
    },
    {
      "case_id": "forced-json-pipe",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":true,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "json",
        "stdout_utf8": "{\n  \"ready\": true\n}\n",
        "stderr_utf8": "",
        "exit": 0,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "{\n  \"ready\": true\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "output.rsresolve/main.rs flags/source plain renderer witness"
    },
    {
      "case_id": "json-human-conflict-pipe",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":true,\"force_json\":true,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"argument_conflict\",\"kind\":\"parse_failure\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"accepted_arguments\\\",[\\\"--job <JOB_UUID>\\\"]],[\\\"command\\\",\\\"healthmd status\\\"],[\\\"error\\\",\\\"invalid_request\\\"],[\\\"error_kind\\\",\\\"argument_conflict\\\"],[\\\"help_command\\\",\\\"healthmd status --help\\\"],[\\\"message\\\",\\\"Two supplied arguments cannot be used together. Choose one documented request shape.\\\"],[\\\"next_actions\\\",[{\\\"entries\\\":[[\\\"command\\\",\\\"healthmd status --help\\\"],[\\\"description\\\",\\\"Review the accepted syntax, constraints, and examples, then retry with only documented arguments.\\\"]],\\\"kind\\\":\\\"object\\\"}]],[\\\"request_sent\\\",false],[\\\"schema\\\",\\\"healthmd.cli_error\\\"],[\\\"schema_version\\\",{\\\"decimal\\\":\\\"1\\\",\\\"kind\\\":\\\"unsigned_integer\\\"}],[\\\"status\\\",\\\"failure\\\"]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"accepted_arguments\",[\"--job <JOB_UUID>\"]],[\"command\",\"healthmd status\"],[\"error\",\"invalid_request\"],[\"error_kind\",\"argument_conflict\"],[\"help_command\",\"healthmd status --help\"],[\"message\",\"Two supplied arguments cannot be used together. Choose one documented request shape.\"],[\"next_actions\",[{\"entries\":[[\"command\",\"healthmd status --help\"],[\"description\",\"Review the accepted syntax, constraints, and examples, then retry with only documented arguments.\"]],\"kind\":\"object\"}]],[\"request_sent\",false],[\"schema\",\"healthmd.cli_error\"],[\"schema_version\",{\"decimal\":\"1\",\"kind\":\"unsigned_integer\"}],[\"status\",\"failure\"]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"argument_conflict\",\"kind\":\"parse_failure\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "json",
        "stdout_utf8": "{\n  \"accepted_arguments\": [\n    \"--job <JOB_UUID>\"\n  ],\n  \"command\": \"healthmd status\",\n  \"error\": \"invalid_request\",\n  \"error_kind\": \"argument_conflict\",\n  \"help_command\": \"healthmd status --help\",\n  \"message\": \"Two supplied arguments cannot be used together. Choose one documented request shape.\",\n  \"next_actions\": [\n    {\n      \"command\": \"healthmd status --help\",\n      \"description\": \"Review the accepted syntax, constraints, and examples, then retry with only documented arguments.\"\n    }\n  ],\n  \"request_sent\": false,\n  \"schema\": \"healthmd.cli_error\",\n  \"schema_version\": 1,\n  \"status\": \"failure\"\n}\n",
        "stderr_utf8": "",
        "exit": 2,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "{\n  \"accepted_arguments\": [\n    \"--job <JOB_UUID>\"\n  ],\n  \"command\": \"healthmd status\",\n  \"error\": \"invalid_request\",\n  \"error_kind\": \"argument_conflict\",\n  \"help_command\": \"healthmd status --help\",\n  \"message\": \"Two supplied arguments cannot be used together. Choose one documented request shape.\",\n  \"next_actions\": [\n    {\n      \"command\": \"healthmd status --help\",\n      \"description\": \"Review the accepted syntax, constraints, and examples, then retry with only documented arguments.\"\n    }\n  ],\n  \"request_sent\": false,\n  \"schema\": \"healthmd.cli_error\",\n  \"schema_version\": 1,\n  \"status\": \"failure\"\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Clap flags conflict parsed after requested_output_mode JSON precedence; parser fixed ArgumentConflict"
    },
    {
      "case_id": "json-human-conflict-terminal",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":true,\"force_json\":true,\"tty\":true}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"argument_conflict\",\"kind\":\"parse_failure\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"accepted_arguments\\\",[\\\"--job <JOB_UUID>\\\"]],[\\\"command\\\",\\\"healthmd status\\\"],[\\\"error\\\",\\\"invalid_request\\\"],[\\\"error_kind\\\",\\\"argument_conflict\\\"],[\\\"help_command\\\",\\\"healthmd status --help\\\"],[\\\"message\\\",\\\"Two supplied arguments cannot be used together. Choose one documented request shape.\\\"],[\\\"next_actions\\\",[{\\\"entries\\\":[[\\\"command\\\",\\\"healthmd status --help\\\"],[\\\"description\\\",\\\"Review the accepted syntax, constraints, and examples, then retry with only documented arguments.\\\"]],\\\"kind\\\":\\\"object\\\"}]],[\\\"request_sent\\\",false],[\\\"schema\\\",\\\"healthmd.cli_error\\\"],[\\\"schema_version\\\",{\\\"decimal\\\":\\\"1\\\",\\\"kind\\\":\\\"unsigned_integer\\\"}],[\\\"status\\\",\\\"failure\\\"]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"accepted_arguments\",[\"--job <JOB_UUID>\"]],[\"command\",\"healthmd status\"],[\"error\",\"invalid_request\"],[\"error_kind\",\"argument_conflict\"],[\"help_command\",\"healthmd status --help\"],[\"message\",\"Two supplied arguments cannot be used together. Choose one documented request shape.\"],[\"next_actions\",[{\"entries\":[[\"command\",\"healthmd status --help\"],[\"description\",\"Review the accepted syntax, constraints, and examples, then retry with only documented arguments.\"]],\"kind\":\"object\"}]],[\"request_sent\",false],[\"schema\",\"healthmd.cli_error\"],[\"schema_version\",{\"decimal\":\"1\",\"kind\":\"unsigned_integer\"}],[\"status\",\"failure\"]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"argument_conflict\",\"kind\":\"parse_failure\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "json",
        "stdout_utf8": "{\n  \"accepted_arguments\": [\n    \"--job <JOB_UUID>\"\n  ],\n  \"command\": \"healthmd status\",\n  \"error\": \"invalid_request\",\n  \"error_kind\": \"argument_conflict\",\n  \"help_command\": \"healthmd status --help\",\n  \"message\": \"Two supplied arguments cannot be used together. Choose one documented request shape.\",\n  \"next_actions\": [\n    {\n      \"command\": \"healthmd status --help\",\n      \"description\": \"Review the accepted syntax, constraints, and examples, then retry with only documented arguments.\"\n    }\n  ],\n  \"request_sent\": false,\n  \"schema\": \"healthmd.cli_error\",\n  \"schema_version\": 1,\n  \"status\": \"failure\"\n}\n",
        "stderr_utf8": "",
        "exit": 2,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "{\n  \"accepted_arguments\": [\n    \"--job <JOB_UUID>\"\n  ],\n  \"command\": \"healthmd status\",\n  \"error\": \"invalid_request\",\n  \"error_kind\": \"argument_conflict\",\n  \"help_command\": \"healthmd status --help\",\n  \"message\": \"Two supplied arguments cannot be used together. Choose one documented request shape.\",\n  \"next_actions\": [\n    {\n      \"command\": \"healthmd status --help\",\n      \"description\": \"Review the accepted syntax, constraints, and examples, then retry with only documented arguments.\"\n    }\n  ],\n  \"request_sent\": false,\n  \"schema\": \"healthmd.cli_error\",\n  \"schema_version\": 1,\n  \"status\": \"failure\"\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Clap flags conflict parsed after requested_output_mode JSON precedence; parser fixed ArgumentConflict"
    },
    {
      "case_id": "local-discovery-exit-zero",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"direct\",\"fixedPolicy\":\"none\",\"kind\":\"local_discovery\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"available_commands\\\",[{\\\"entries\\\":[[\\\"command\\\",\\\"healthmd direct pair\\\"],[\\\"description\\\",\\\"Pair this CLI installation with an open iOS or Android app.\\\"]],\\\"kind\\\":\\\"object\\\"},{\\\"entries\\\":[[\\\"command\\\",\\\"healthmd direct devices\\\"],[\\\"description\\\",\\\"List local trusted devices without network access.\\\"]],\\\"kind\\\":\\\"object\\\"},{\\\"entries\\\":[[\\\"command\\\",\\\"healthmd direct unpair\\\"],[\\\"description\\\",\\\"Inspect the required device ID before removing one pairing.\\\"]],\\\"kind\\\":\\\"object\\\"},{\\\"entries\\\":[[\\\"command\\\",\\\"healthmd direct reset-trust\\\"],[\\\"description\\\",\\\"Review the destructive all-trust reset and its required confirmation.\\\"]],\\\"kind\\\":\\\"object\\\"}]],[\\\"command\\\",\\\"healthmd direct\\\"],[\\\"description\\\",\\\"Pair and manage direct mobile trust.\\\"],[\\\"message\\\",\\\"Choose one of the available commands below; no operation was started.\\\"],[\\\"next_actions\\\",[{\\\"entries\\\":[[\\\"command\\\",\\\"healthmd direct --help\\\"],[\\\"description\\\",\\\"Read the complete command help.\\\"]],\\\"kind\\\":\\\"object\\\"}]],[\\\"request_sent\\\",false],[\\\"schema\\\",\\\"healthmd.cli_guidance\\\"],[\\\"schema_version\\\",{\\\"decimal\\\":\\\"1\\\",\\\"kind\\\":\\\"unsigned_integer\\\"}],[\\\"status\\\",\\\"guidance\\\"]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"available_commands\",[{\"entries\":[[\"command\",\"healthmd direct pair\"],[\"description\",\"Pair this CLI installation with an open iOS or Android app.\"]],\"kind\":\"object\"},{\"entries\":[[\"command\",\"healthmd direct devices\"],[\"description\",\"List local trusted devices without network access.\"]],\"kind\":\"object\"},{\"entries\":[[\"command\",\"healthmd direct unpair\"],[\"description\",\"Inspect the required device ID before removing one pairing.\"]],\"kind\":\"object\"},{\"entries\":[[\"command\",\"healthmd direct reset-trust\"],[\"description\",\"Review the destructive all-trust reset and its required confirmation.\"]],\"kind\":\"object\"}]],[\"command\",\"healthmd direct\"],[\"description\",\"Pair and manage direct mobile trust.\"],[\"message\",\"Choose one of the available commands below; no operation was started.\"],[\"next_actions\",[{\"entries\":[[\"command\",\"healthmd direct --help\"],[\"description\",\"Read the complete command help.\"]],\"kind\":\"object\"}]],[\"request_sent\",false],[\"schema\",\"healthmd.cli_guidance\"],[\"schema_version\",{\"decimal\":\"1\",\"kind\":\"unsigned_integer\"}],[\"status\",\"guidance\"]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"direct\",\"fixedPolicy\":\"none\",\"kind\":\"local_discovery\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "json",
        "stdout_utf8": "{\n  \"available_commands\": [\n    {\n      \"command\": \"healthmd direct pair\",\n      \"description\": \"Pair this CLI installation with an open iOS or Android app.\"\n    },\n    {\n      \"command\": \"healthmd direct devices\",\n      \"description\": \"List local trusted devices without network access.\"\n    },\n    {\n      \"command\": \"healthmd direct unpair\",\n      \"description\": \"Inspect the required device ID before removing one pairing.\"\n    },\n    {\n      \"command\": \"healthmd direct reset-trust\",\n      \"description\": \"Review the destructive all-trust reset and its required confirmation.\"\n    }\n  ],\n  \"command\": \"healthmd direct\",\n  \"description\": \"Pair and manage direct mobile trust.\",\n  \"message\": \"Choose one of the available commands below; no operation was started.\",\n  \"next_actions\": [\n    {\n      \"command\": \"healthmd direct --help\",\n      \"description\": \"Read the complete command help.\"\n    }\n  ],\n  \"request_sent\": false,\n  \"schema\": \"healthmd.cli_guidance\",\n  \"schema_version\": 1,\n  \"status\": \"guidance\"\n}\n",
        "stderr_utf8": "",
        "exit": 0,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "{\n  \"available_commands\": [\n    {\n      \"command\": \"healthmd direct pair\",\n      \"description\": \"Pair this CLI installation with an open iOS or Android app.\"\n    },\n    {\n      \"command\": \"healthmd direct devices\",\n      \"description\": \"List local trusted devices without network access.\"\n    },\n    {\n      \"command\": \"healthmd direct unpair\",\n      \"description\": \"Inspect the required device ID before removing one pairing.\"\n    },\n    {\n      \"command\": \"healthmd direct reset-trust\",\n      \"description\": \"Review the destructive all-trust reset and its required confirmation.\"\n    }\n  ],\n  \"command\": \"healthmd direct\",\n  \"description\": \"Pair and manage direct mobile trust.\",\n  \"message\": \"Choose one of the available commands below; no operation was started.\",\n  \"next_actions\": [\n    {\n      \"command\": \"healthmd direct --help\",\n      \"description\": \"Read the complete command help.\"\n    }\n  ],\n  \"request_sent\": false,\n  \"schema\": \"healthmd.cli_guidance\",\n  \"schema_version\": 1,\n  \"status\": \"guidance\"\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "main.rs625-629;guidance.rsgroup(direct);no source/network"
    },
    {
      "case_id": "raw-human-mode-still-exact",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":true,\"force_json\":false,\"tty\":true}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":\"raw_json_stdout\",\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"raw_artifact\"},\"value_wire\":\"\\\"{\\\\\\\"synthetic\\\\\\\":true}\\\\n\\\"\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "\"{\\\"synthetic\\\":true}\\n\"",
          "descriptor_wire": "{\"artifactFamily\":\"raw_json_stdout\",\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"raw_artifact\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "raw",
        "stdout_utf8": "{\"synthetic\":true}\n",
        "stderr_utf8": "",
        "exit": 0,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 0,
        "raw_validator_calls": 1,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "{\"synthetic\":true}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Artifact branch bypasses mode entirely after validation"
    },
    {
      "case_id": "raw-no-terminal-LF-fabrication",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":\"raw_json_stdout\",\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"raw_artifact\"},\"value_wire\":\"\\\"{\\\\\\\"synthetic\\\\\\\":true}\\\"\"}",
        "actions": [
          {
            "common": "replace raw primitive value with exact {\"synthetic\":true} no LF"
          }
        ],
        "port_inputs": {
          "value_wire": "\"{\\\"synthetic\\\":true}\"",
          "descriptor_wire": "{\"artifactFamily\":\"raw_json_stdout\",\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"raw_artifact\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "raw",
        "stdout_utf8": "{\"synthetic\":true}",
        "stderr_utf8": "",
        "exit": 0,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 0,
        "raw_validator_calls": 1,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "{\"synthetic\":true}"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Raw Artifact io::copy/flush adds no LF; private input amended below"
    },
    {
      "case_id": "common-throwing-proxy",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "receive_only",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        },
        "input_override": {
          "kind": "throwing_Proxy_all_traps"
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_input",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "New private closed primitive UTF8/depth/node grammar; no public parser restriction"
    },
    {
      "case_id": "common-revoked-proxy",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "receive_only",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        },
        "input_override": {
          "kind": "revoked_Proxy"
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_input",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "New private closed primitive UTF8/depth/node grammar; no public parser restriction"
    },
    {
      "case_id": "common-coercible-object",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "receive_only",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        },
        "input_override": {
          "kind": "coercion_object_all_hooks"
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_input",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "New private closed primitive UTF8/depth/node grammar; no public parser restriction"
    },
    {
      "case_id": "common-malformed-json",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "receive_only",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        },
        "input_override": {
          "kind": "primitive",
          "value": "{"
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_input",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "New private closed primitive UTF8/depth/node grammar; no public parser restriction"
    },
    {
      "case_id": "common-escaped-duplicate-key",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "receive_only",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        },
        "input_override": {
          "kind": "primitive",
          "value": "{\"kind\":0,\"\\u006bind\":1}"
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_input",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "New private closed primitive UTF8/depth/node grammar; no public parser restriction"
    },
    {
      "case_id": "common-noncanonical-integer",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "receive_only",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        },
        "input_override": {
          "kind": "primitive",
          "value": "{\"kind\":\"structured_success\",\"revision\":1.0000000000000001}"
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_input",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "New private closed primitive UTF8/depth/node grammar; no public parser restriction"
    },
    {
      "case_id": "common-UTF16-lone-high",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "receive_only",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        },
        "input_override": {
          "kind": "UTF16_units",
          "units": [
            55296
          ]
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_input",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "New private closed primitive UTF8/depth/node grammar; no public parser restriction"
    },
    {
      "case_id": "common-UTF16-lone-low",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "receive_only",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        },
        "input_override": {
          "kind": "UTF16_units",
          "units": [
            56320
          ]
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_input",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "New private closed primitive UTF8/depth/node grammar; no public parser restriction"
    },
    {
      "case_id": "common-UTF8-overbudget",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "receive_only",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        },
        "input_override": {
          "kind": "repeat_ASCII",
          "character": "x",
          "count": 65537
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_input",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "New private closed primitive UTF8/depth/node grammar; no public parser restriction"
    },
    {
      "case_id": "common-depth-overbudget",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "receive_only",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        },
        "input_override": {
          "kind": "nested_array",
          "levels": 33,
          "leaf": "null"
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_input",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "New private closed primitive UTF8/depth/node grammar; no public parser restriction"
    },
    {
      "case_id": "common-node-overbudget",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "receive_only",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        },
        "input_override": {
          "kind": "flat_array",
          "elements": 4097,
          "leaf": "null"
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_input",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "New private closed primitive UTF8/depth/node grammar; no public parser restriction"
    },
    {
      "case_id": "mode-Proxy",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "select_mode_only",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        },
        "mode_override": {
          "kind": "throwing_Proxy_all_traps"
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_input",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Private mode wire canonical closed booleans/max1024; membership/primitive-first zero traps"
    },
    {
      "case_id": "mode-revoked-Proxy",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "select_mode_only",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        },
        "mode_override": {
          "kind": "revoked_Proxy"
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_input",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Private mode wire canonical closed booleans/max1024; membership/primitive-first zero traps"
    },
    {
      "case_id": "mode-nonboolean",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "select_mode_only",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        },
        "mode_override": {
          "kind": "primitive",
          "value": "{\"force_json\":1,\"force_human\":false,\"tty\":false}"
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_input",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Private mode wire canonical closed booleans/max1024; membership/primitive-first zero traps"
    },
    {
      "case_id": "mode-unknown-field",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "select_mode_only",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        },
        "mode_override": {
          "kind": "primitive",
          "value": "{\"force_json\":false,\"force_human\":false,\"tty\":false,\"grant\":true}"
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_input",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Private mode wire canonical closed booleans/max1024; membership/primitive-first zero traps"
    },
    {
      "case_id": "mode-duplicate-decoded-key",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "select_mode_only",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        },
        "mode_override": {
          "kind": "primitive",
          "value": "{\"force_json\":false,\"force_human\":false,\"tty\":false,\"\\u0074ty\":true}"
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_input",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Private mode wire canonical closed booleans/max1024; membership/primitive-first zero traps"
    },
    {
      "case_id": "mode-overbudget",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "select_mode_only",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        },
        "mode_override": {
          "kind": "repeat_ASCII",
          "character": "x",
          "count": 1025
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_input",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Private mode wire canonical closed booleans/max1024; membership/primitive-first zero traps"
    },
    {
      "case_id": "foreign-outcome-Proxy",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_foreign",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "override": "outcome_Proxy"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_owned",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Factory/context membership before properties; actual authentic other-factory tokens seeded outside counter window"
    },
    {
      "case_id": "foreign-outcome-revoked-Proxy",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_foreign",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "override": "outcome_revoked_Proxy"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_owned",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Factory/context membership before properties; actual authentic other-factory tokens seeded outside counter window"
    },
    {
      "case_id": "foreign-authentic-outcome-other-factory",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_foreign",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "override": "other_factory_outcome"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_owned",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Factory/context membership before properties; actual authentic other-factory tokens seeded outside counter window"
    },
    {
      "case_id": "foreign-mode-Proxy",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_foreign",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "override": "mode_Proxy"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_owned",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Factory/context membership before properties; actual authentic other-factory tokens seeded outside counter window"
    },
    {
      "case_id": "foreign-authentic-mode-other-factory",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_foreign",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "override": "other_factory_mode"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_owned",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Factory/context membership before properties; actual authentic other-factory tokens seeded outside counter window"
    },
    {
      "case_id": "private-unadmitted-jsonl_stdout_and_receipt_stderr",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":\"jsonl_stdout_and_receipt_stderr\",\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"raw_artifact\"},\"value_wire\":\"\\\"{\\\\\\\"synthetic\\\\\\\":true}\\\\n\\\"\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "\"{\\\"synthetic\\\":true}\\n\"",
          "descriptor_wire": "{\"artifactFamily\":\"jsonl_stdout_and_receipt_stderr\",\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"raw_artifact\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_capability",
        "common_calls": 1,
        "authority_calls": 1,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "source_family_identity_retained": "jsonl_stdout_and_receipt_stderr",
        "public_unsupported_claim": false,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Source CommandOutput identity/sidechannel preserved; fake host lacks resource family; separate tasks required, not public unsupported"
    },
    {
      "case_id": "private-unadmitted-artifact_destination",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":\"artifact_destination\",\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"raw_artifact\"},\"value_wire\":\"\\\"{\\\\\\\"synthetic\\\\\\\":true}\\\\n\\\"\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "\"{\\\"synthetic\\\":true}\\n\"",
          "descriptor_wire": "{\"artifactFamily\":\"artifact_destination\",\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"raw_artifact\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_capability",
        "common_calls": 1,
        "authority_calls": 1,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "source_family_identity_retained": "artifact_destination",
        "public_unsupported_claim": false,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Source CommandOutput identity/sidechannel preserved; fake host lacks resource family; separate tasks required, not public unsupported"
    },
    {
      "case_id": "private-unadmitted-jsonl_destination_and_receipt",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":\"jsonl_destination_and_receipt\",\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"raw_artifact\"},\"value_wire\":\"\\\"{\\\\\\\"synthetic\\\\\\\":true}\\\\n\\\"\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "\"{\\\"synthetic\\\":true}\\n\"",
          "descriptor_wire": "{\"artifactFamily\":\"jsonl_destination_and_receipt\",\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"raw_artifact\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_capability",
        "common_calls": 1,
        "authority_calls": 1,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "source_family_identity_retained": "jsonl_destination_and_receipt",
        "public_unsupported_claim": false,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Source CommandOutput identity/sidechannel preserved; fake host lacks resource family; separate tasks required, not public unsupported"
    },
    {
      "case_id": "Scope-closed-before-common",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "controller": "Scope.close original before receive"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "owned_handoff_closed",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "Scope-close-inside-common",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "common": "Scope.close original then return normal own outcome"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "owned_handoff_closed",
        "common_calls": 1,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "Scope-close-inside-after-common-current",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "current": "Scope.close at after_common; return normally"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "owned_handoff_closed",
        "common_calls": 1,
        "authority_calls": 1,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "deny-before-render",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "current": "deny latest frontier at before_render"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_authority",
        "common_calls": 1,
        "authority_calls": 2,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "Scope-close-inside-renderer-before-read",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "renderer": "Scope.close original before sourceValueWire; return normally"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "owned_handoff_closed",
        "common_calls": 1,
        "authority_calls": 2,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "Scope-close-during-Deferred-value-read-current",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "renderer": "yield own lazy read waiting in Deferred current; controller closes original Scope then resumes normal permit"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "owned_handoff_closed",
        "common_calls": 1,
        "authority_calls": 3,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "revoke-between-same-renderer-read-effect-executions",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "renderer": "execute same own read once; revoke trusted frontier without Scope.close; execute same read again"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_authority",
        "common_calls": 1,
        "authority_calls": 4,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 1,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "renderer-defect-fixed",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "renderer": "die with SYNTHETIC_SECRET before read"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_codec",
        "common_calls": 1,
        "authority_calls": 2,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "common-defect-fixed",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "common": "die with SYNTHETIC_SECRET"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_codec",
        "common_calls": 1,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "foreign-renderer-byte-result",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "renderer": "return other-factory authentic OwnedBytes after own read"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_codec",
        "common_calls": 1,
        "authority_calls": 3,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 1,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "byte-issuer-overbudget",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "renderer": "issue repeat ASCII x 65537 at encodedUTF8; do not reflect error payload"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_codec",
        "common_calls": 1,
        "authority_calls": 3,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 1,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "deny-before-output-allocation",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "current": "deny at before_allocation"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_authority",
        "common_calls": 1,
        "authority_calls": 6,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 1,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "Scope-close-before-output-allocation",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "current": "Scope.close at before_allocation; return normal"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "owned_handoff_closed",
        "common_calls": 1,
        "authority_calls": 6,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 1,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "late-completed-output-allocation-on-cancel",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "allocation": "uninterruptible completed allocation held on Deferred; interrupt owned publish Fiber; release allocation then await exactACK"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "interruption",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 6,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 0,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "interrupt-pending-uncompleted-output-allocation",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "allocation": "interruptible pending Deferred with no completed resource; interrupt Fiber"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "interruption",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 6,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 1,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "Scope-close-inside-completed-output-allocation",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "allocation": "complete resource, close originalScope before return; actual acquireRelease must register ACK"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "owned_handoff_closed",
        "common_calls": 1,
        "authority_calls": 6,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 0,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "deny-after-output-allocation",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "current": "deny latest frontier at after_allocation"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_authority",
        "common_calls": 1,
        "authority_calls": 7,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 0,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "delayed-byte-read-revoke-Scope-live",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "sink": "construct own lazy read; signal entered Deferred; await proceed; controller revokes grant not Scope then read"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_authority",
        "common_calls": 1,
        "authority_calls": 8,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "Scope-close-during-Deferred-byte-read-current",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "sink": "await own read current Deferred; controller Scope.close original then resume normal current"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "owned_handoff_closed",
        "common_calls": 1,
        "authority_calls": 8,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "sink-defect-after-observed-output",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "sink": "read own bytes once; then die with SYNTHETIC_SECRET"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_publish",
        "common_calls": 1,
        "authority_calls": 8,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": true,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "{\n  \"ready\": true\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "revoke-between-two-same-byte-effect-reads",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "sink": "read once, retain observedbytes; revoke frontier; execute SAME lazy read again"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_authority",
        "common_calls": 1,
        "authority_calls": 9,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": true,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "{\n  \"ready\": true\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "Scope-close-inside-sink-after-read",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "sink": "read once, close originalScope, return normally"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "owned_handoff_closed",
        "common_calls": 1,
        "authority_calls": 8,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": true,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "{\n  \"ready\": true\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "releaseACK-pending-blocks-exit",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "release": "Deferred pending ACK; assert child poll absent; resume ACK and complete"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "json",
        "stdout_utf8": "{\n  \"ready\": true\n}\n",
        "stderr_utf8": "",
        "exit": 0,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "{\n  \"ready\": true\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "release-defect-poisons-factory",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "release": "fail with private provider sentinel instead of ACK; subsequent publish refused cleanup before callbacks"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_cleanup",
        "common_calls": 1,
        "authority_calls": 9,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 0,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": true,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "{\n  \"ready\": true\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "Scope-close-inside-releaseACK",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "release": "Scope.close original then ACK exactly once"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "owned_handoff_closed",
        "common_calls": 1,
        "authority_calls": 9,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": true,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "{\n  \"ready\": true\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "deny-after-ACK-before-exit",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "current": "deny at assert_current after release ACK"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_authority",
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": true,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "{\n  \"ready\": true\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "foreign-Proxy-request-OWN-value",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "renderer": "evaluate foreign membership variant then normal own read"
          },
          {
            "variant": {
              "request": "throwing_Proxy_all_traps",
              "payload": "own_value"
            }
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "json",
        "stdout_utf8": "{\n  \"ready\": true\n}\n",
        "stderr_utf8": "",
        "exit": 0,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "variant_results": [
          null
        ],
        "variant_authority_calls": 0,
        "variant_materializations": 0,
        "byte_text_observations": [
          "{\n  \"ready\": true\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Exact original request vs own authentic payload membership first; no alternative foreign payload substitution"
    },
    {
      "case_id": "foreign-Proxy-request-OWN-bytes",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "sink": "evaluate foreign membership variant then normal own read"
          },
          {
            "variant": {
              "request": "throwing_Proxy_all_traps",
              "payload": "own_bytes"
            }
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "json",
        "stdout_utf8": "{\n  \"ready\": true\n}\n",
        "stderr_utf8": "",
        "exit": 0,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "variant_results": [
          null
        ],
        "variant_authority_calls": 0,
        "variant_materializations": 0,
        "byte_text_observations": [
          "{\n  \"ready\": true\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Exact original request vs own authentic payload membership first; no alternative foreign payload substitution"
    },
    {
      "case_id": "foreign-revoked-Proxy-value",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "renderer": "evaluate foreign membership variant then normal own read"
          },
          {
            "variant": {
              "request": "own_request",
              "payload": "revoked_value"
            }
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "json",
        "stdout_utf8": "{\n  \"ready\": true\n}\n",
        "stderr_utf8": "",
        "exit": 0,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "variant_results": [
          null
        ],
        "variant_authority_calls": 0,
        "variant_materializations": 0,
        "byte_text_observations": [
          "{\n  \"ready\": true\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Exact original request vs own authentic payload membership first; no alternative foreign payload substitution"
    },
    {
      "case_id": "foreign-revoked-Proxy-bytes",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "sink": "evaluate foreign membership variant then normal own read"
          },
          {
            "variant": {
              "request": "own_request",
              "payload": "revoked_bytes"
            }
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "json",
        "stdout_utf8": "{\n  \"ready\": true\n}\n",
        "stderr_utf8": "",
        "exit": 0,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "variant_results": [
          null
        ],
        "variant_authority_calls": 0,
        "variant_materializations": 0,
        "byte_text_observations": [
          "{\n  \"ready\": true\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Exact original request vs own authentic payload membership first; no alternative foreign payload substitution"
    },
    {
      "case_id": "escaped-common-issuer-dead-at-after-common",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "common": "save own view/issuer/lazy read; reenter from named postcallback current or release callback after actual callback Effect exits"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "json",
        "stdout_utf8": "{\n  \"ready\": true\n}\n",
        "stderr_utf8": "",
        "exit": 0,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "escaped_results": [
          null
        ],
        "escaped_authority_calls": 0,
        "escaped_materializations": 0,
        "revival": false,
        "byte_text_observations": [
          "{\n  \"ready\": true\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Inner actual callback Effect.ensuring expires BEFORE outer current/release; original Scope remains live/permitted"
    },
    {
      "case_id": "escaped-renderer-view-and-issuer-dead-at-after-render",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "renderer": "save own view/issuer/lazy read; reenter from named postcallback current or release callback after actual callback Effect exits"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "json",
        "stdout_utf8": "{\n  \"ready\": true\n}\n",
        "stderr_utf8": "",
        "exit": 0,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "escaped_results": [
          null
        ],
        "escaped_authority_calls": 0,
        "escaped_materializations": 0,
        "revival": false,
        "byte_text_observations": [
          "{\n  \"ready\": true\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Inner actual callback Effect.ensuring expires BEFORE outer current/release; original Scope remains live/permitted"
    },
    {
      "case_id": "escaped-sink-view-dead-at-after-publication",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "sink": "save own view/issuer/lazy read; reenter from named postcallback current or release callback after actual callback Effect exits"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "json",
        "stdout_utf8": "{\n  \"ready\": true\n}\n",
        "stderr_utf8": "",
        "exit": 0,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "escaped_results": [
          null
        ],
        "escaped_authority_calls": 0,
        "escaped_materializations": 0,
        "revival": false,
        "byte_text_observations": [
          "{\n  \"ready\": true\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Inner actual callback Effect.ensuring expires BEFORE outer current/release; original Scope remains live/permitted"
    },
    {
      "case_id": "escaped-sink-view-dead-before-releaseACK",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "release": "save own view/issuer/lazy read; reenter from named postcallback current or release callback after actual callback Effect exits"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "json",
        "stdout_utf8": "{\n  \"ready\": true\n}\n",
        "stderr_utf8": "",
        "exit": 0,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "escaped_results": [
          null
        ],
        "escaped_authority_calls": 0,
        "escaped_materializations": 0,
        "revival": false,
        "byte_text_observations": [
          "{\n  \"ready\": true\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Inner actual callback Effect.ensuring expires BEFORE outer current/release; original Scope remains live/permitted"
    },
    {
      "case_id": "escaped-read-cannot-reprovide-original-lifetime",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "renderer": "save unexecuted own lazy read; normal own read once then return"
          },
          {
            "controller": "after publish mutate original trusted current.check object to replacement; provide fresh Scope; execute saved effect before/after originalScope.close"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "json",
        "stdout_utf8": "{\n  \"ready\": true\n}\n",
        "stderr_utf8": "",
        "exit": 0,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "late_results": [
          null,
          null
        ],
        "late_authority_calls": 0,
        "replacement_authority_calls": 0,
        "revival": false,
        "byte_text_observations": [
          "{\n  \"ready\": true\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Captured original service + originalScope, exact real object mutation; freshScope neverrevives"
    },
    {
      "case_id": "foreign-raw-validation-witness",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":\"raw_json_stdout\",\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"raw_artifact\"},\"value_wire\":\"\\\"{\\\\\\\"synthetic\\\\\\\":true}\\\\n\\\"\"}",
        "actions": [
          {
            "raw_validator": "return foreign authentic validation token from another factory"
          }
        ],
        "port_inputs": {
          "value_wire": "\"{\\\"synthetic\\\":true}\\n\"",
          "descriptor_wire": "{\"artifactFamily\":\"raw_json_stdout\",\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"raw_artifact\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_codec",
        "common_calls": 1,
        "authority_calls": 3,
        "renderer_calls": 0,
        "raw_validator_calls": 1,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 1,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Membership/context/actual callback issuer before raw bypass"
    },
    {
      "case_id": "Scope-close-inside-raw-validator",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":\"raw_json_stdout\",\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"raw_artifact\"},\"value_wire\":\"\\\"{\\\\\\\"synthetic\\\\\\\":true}\\\\n\\\"\"}",
        "actions": [
          {
            "raw_validator": "Scope.close before read; return normally"
          }
        ],
        "port_inputs": {
          "value_wire": "\"{\\\"synthetic\\\":true}\\n\"",
          "descriptor_wire": "{\"artifactFamily\":\"raw_json_stdout\",\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"raw_artifact\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "owned_handoff_closed",
        "common_calls": 1,
        "authority_calls": 2,
        "renderer_calls": 0,
        "raw_validator_calls": 1,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "OriginalScope wins after raw callback, no renderer/bypass/output"
    },
    {
      "case_id": "output_write_failed-fixed-owned-kind",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"output_write_failed\",\"kind\":\"operational_failure\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"command\\\",\\\"healthmd status\\\"],[\\\"error\\\",\\\"output_write_failed\\\"],[\\\"help_command\\\",\\\"healthmd status --help\\\"],[\\\"message\\\",\\\"The command result could not be written to stdout or the requested output destination.\\\"],[\\\"next_actions\\\",[{\\\"entries\\\":[[\\\"action\\\",\\\"Verify that stdout or the requested output destination is writable and has sufficient free space.\\\"]],\\\"kind\\\":\\\"object\\\"},{\\\"entries\\\":[[\\\"command\\\",\\\"healthmd status --help\\\"],[\\\"description\\\",\\\"Review accepted arguments and examples.\\\"]],\\\"kind\\\":\\\"object\\\"}]],[\\\"schema\\\",\\\"healthmd.cli_error\\\"],[\\\"schema_version\\\",{\\\"decimal\\\":\\\"1\\\",\\\"kind\\\":\\\"unsigned_integer\\\"}],[\\\"status\\\",\\\"failure\\\"]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"command\",\"healthmd status\"],[\"error\",\"output_write_failed\"],[\"help_command\",\"healthmd status --help\"],[\"message\",\"The command result could not be written to stdout or the requested output destination.\"],[\"next_actions\",[{\"entries\":[[\"action\",\"Verify that stdout or the requested output destination is writable and has sufficient free space.\"]],\"kind\":\"object\"},{\"entries\":[[\"command\",\"healthmd status --help\"],[\"description\",\"Review accepted arguments and examples.\"]],\"kind\":\"object\"}]],[\"schema\",\"healthmd.cli_error\"],[\"schema_version\",{\"decimal\":\"1\",\"kind\":\"unsigned_integer\"}],[\"status\",\"failure\"]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"output_write_failed\",\"kind\":\"operational_failure\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "json",
        "stdout_utf8": "{\n  \"command\": \"healthmd status\",\n  \"error\": \"output_write_failed\",\n  \"help_command\": \"healthmd status --help\",\n  \"message\": \"The command result could not be written to stdout or the requested output destination.\",\n  \"next_actions\": [\n    {\n      \"action\": \"Verify that stdout or the requested output destination is writable and has sufficient free space.\"\n    },\n    {\n      \"command\": \"healthmd status --help\",\n      \"description\": \"Review accepted arguments and examples.\"\n    }\n  ],\n  \"schema\": \"healthmd.cli_error\",\n  \"schema_version\": 1,\n  \"status\": \"failure\"\n}\n",
        "stderr_utf8": "",
        "exit": 1,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "{\n  \"command\": \"healthmd status\",\n  \"error\": \"output_write_failed\",\n  \"help_command\": \"healthmd status --help\",\n  \"message\": \"The command result could not be written to stdout or the requested output destination.\",\n  \"next_actions\": [\n    {\n      \"action\": \"Verify that stdout or the requested output destination is writable and has sufficient free space.\"\n    },\n    {\n      \"command\": \"healthmd status --help\",\n      \"description\": \"Review accepted arguments and examples.\"\n    }\n  ],\n  \"schema\": \"healthmd.cli_error\",\n  \"schema_version\": 1,\n  \"status\": \"failure\"\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "main.rs write_failure/guidance recovery"
    },
    {
      "case_id": "success_error_shaped-fixed-owned-kind",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"error\\\",\\\"runtime_unavailable\\\"],[\\\"message\\\",\\\"synthetic result data\\\"]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"error\",\"runtime_unavailable\"],[\"message\",\"synthetic result data\"]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "json",
        "stdout_utf8": "{\n  \"error\": \"runtime_unavailable\",\n  \"message\": \"synthetic result data\"\n}\n",
        "stderr_utf8": "",
        "exit": 0,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "{\n  \"error\": \"runtime_unavailable\",\n  \"message\": \"synthetic result data\"\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "CommandSuccess Json(Value) shape never changes success.exit_code"
    },
    {
      "case_id": "byte-issuer-invalid-Unicode",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "renderer": "issue UTF16 lone high surrogate as bytes after own value read"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_codec",
        "common_calls": 1,
        "authority_calls": 3,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 1,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Private UTF8-only bounded byte issuance; no replacement or source serializer equivalence claim"
    },
    {
      "case_id": "owned-output-busy-until-releaseACK",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "second_publish_while_first_pending",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "setup": "same factory render normal decision; first publish acquiredresource and writerpendingDeferred; reset counters for secondpublish"
          },
          {
            "second": "publish same authentic decision while first pending => busy BEFOREcurrent/allocation"
          },
          {
            "cleanup": "interrupt first ownedFiber and await exactreleaseACK; busy cleared onlyafterACK"
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_busy",
        "common_calls": 0,
        "authority_calls": 0,
        "renderer_calls": 0,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "background_release_ACKs": 1,
        "busy_until_ACK": true,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "New private one-output ownership/resource budget; no public multi-process lock claim"
    },
    {
      "case_id": "raw-validation-Proxy-shape-never-authority",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":\"raw_json_stdout\",\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"raw_artifact\"},\"value_wire\":\"\\\"{\\\\\\\"synthetic\\\\\\\":true}\\\\n\\\"\"}",
        "actions": [
          {
            "raw_validator": "return plain validated-looking throwingProxy instead of own callback-issued token"
          }
        ],
        "port_inputs": {
          "value_wire": "\"{\\\"synthetic\\\":true}\\n\"",
          "descriptor_wire": "{\"artifactFamily\":\"raw_json_stdout\",\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"raw_artifact\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "private_cli_codec",
        "common_calls": 1,
        "authority_calls": 2,
        "renderer_calls": 0,
        "raw_validator_calls": 1,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 0,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee"
      },
      "source_basis": "Unknown raw witness membership before fields; host input boolean/profile/path not authority"
    },
    {
      "case_id": "external-originalScope-close-during-prepare",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "external_original_close_then_await_owned_bracket_without_resuming_phase",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "setup": "Use original factory Scope; render authentic JSON ready decision. Publish in owned Fiber with fake resource-free preparation and synchronous commit/register."
          },
          {
            "phase": "Signal preparation entered then suspend interruptibly before commit on never-resumed preparation Deferred."
          },
          {
            "close": "From a separate driver Fiber, close ORIGINAL factory Scope; original finalizer expires sentinel and completes close Deferred without joining publication."
          },
          {
            "preparation_cleanup": "Resource-free fake acknowledges cancellation internally; no completed release callback exists. No resumed preparation Deferred."
          },
          {
            "observe": "Do not resume preparation/registered-wait Deferred. Await owned bracket cancellation and exact cleanup disposition; no after_allocation current or use/sink callbacks allowed."
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "owned_handoff_closed",
        "common_calls": 1,
        "authority_calls": 6,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 0,
        "sink_calls": 0,
        "release_attempts": 0,
        "release_ACKs": 0,
        "value_materializations": 1,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee",
        "external_close_notification_completed": true,
        "phase_Deferred_resumed": false,
        "use_calls": 0,
        "after_allocation_authority_calls": 0,
        "original_close_claims_resource_ACK": false,
        "completed_release_ACK_before_bracket_terminal": false,
        "preparation_cancellation_acknowledged": true,
        "watcher_outstanding_after_terminal": 0,
        "owned_phase_Fibers_outstanding_after_terminal": 0
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "external-originalScope-close-during-registered-wait",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "external_original_close_then_await_owned_bracket_without_resuming_phase",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "setup": "Use original factory Scope; render authentic JSON ready decision. Publish in owned Fiber with fake resource-free preparation and synchronous commit/register."
          },
          {
            "phase": "Complete synchronous allocation and local finalizer registration; signal registered phase entered then suspend interruptibly before use on never-resumed registered-wait Deferred."
          },
          {
            "close": "From a separate driver Fiber, close ORIGINAL factory Scope; original finalizer expires sentinel and completes close Deferred without joining publication."
          },
          {
            "ACK_order": "Hold completed release ACK on separate cleanup Deferred. Scope.close driver completion must be observed while ACK remains pending; publication Fiber must still be incomplete and busy held. Resume ONLY cleanup ACK Deferred, never registered wait."
          },
          {
            "observe": "Do not resume preparation/registered-wait Deferred. Await owned bracket cancellation and exact cleanup disposition; no after_allocation current or use/sink callbacks allowed."
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}"
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "private_failure",
        "mode": null,
        "stdout_utf8": null,
        "stderr_utf8": "",
        "exit": null,
        "private_failure": "owned_handoff_closed",
        "common_calls": 1,
        "authority_calls": 6,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 0,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee",
        "external_close_notification_completed": true,
        "phase_Deferred_resumed": false,
        "use_calls": 0,
        "after_allocation_authority_calls": 0,
        "original_close_claims_resource_ACK": false,
        "completed_release_ACK_before_bracket_terminal": true,
        "preparation_cancellation_acknowledged": false,
        "watcher_outstanding_after_terminal": 0,
        "owned_phase_Fibers_outstanding_after_terminal": 0,
        "Scope_close_completed_while_release_ACK_pending": true,
        "publish_terminal_before_ACK": false,
        "busy_held_while_ACK_pending": true
      },
      "source_basis": "Independent source-only private originalScope/current/Effect acquireRelease/captured callback contract; synthetic only"
    },
    {
      "case_id": "same-common-callback-unbound-own-value-is-not-readable-for-returned-outcome",
      "derivation": "Before-code independent static source-flow witness, not executed. Ownership must bind the value to the exact authorized outcome rather than merely a callback that can issue multiple values. RawIssuer already applies this exact-value distinction.",
      "stimulus": {
        "counter_window": "target operation after any independent factory/setup; cleanup permitted after closure",
        "procedure": "render_then_publish",
        "mode_wire": "{\"force_human\":false,\"force_json\":false,\"tty\":false}",
        "common_input_wire": "{\"descriptor\":{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"},\"value_wire\":\"{\\\"entries\\\":[[\\\"ready\\\",true]],\\\"kind\\\":\\\"object\\\"}\"}",
        "actions": [
          {
            "common": "Issue existing value A and outcome A; also issue distinct own value B through the SAME still-active issuer; retain B; return only A."
          },
          {
            "renderer": "During renderer callback for A, execute sourceValueWire(A,B), record result/check/materialization deltas, then execute sourceValueWire(A,A.metadata.value) and render normally."
          }
        ],
        "port_inputs": {
          "value_wire": "{\"entries\":[[\"ready\",true]],\"kind\":\"object\"}",
          "descriptor_wire": "{\"artifactFamily\":null,\"command\":\"status\",\"fixedPolicy\":\"none\",\"kind\":\"structured_success\"}",
          "common_extra_value_wire": "\"SECOND_SYNTHETIC_VALUE\""
        },
        "host": {
          "rawFamilies": [
            "raw_json_stdout"
          ],
          "plainText": false,
          "human_plain": true,
          "columns": 100,
          "real_source_IO": false
        }
      },
      "expected": {
        "kind": "completion",
        "mode": "json",
        "stdout_utf8": "{\n  \"ready\": true\n}\n",
        "stderr_utf8": "",
        "exit": 0,
        "private_failure": null,
        "common_calls": 1,
        "authority_calls": 10,
        "renderer_calls": 1,
        "raw_validator_calls": 0,
        "allocation_calls": 1,
        "sink_calls": 1,
        "release_attempts": 1,
        "release_ACKs": 1,
        "value_materializations": 1,
        "byte_observations": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "property_traps": 0,
        "provider_echo": false,
        "publication_ambiguous": false,
        "new_noncleanup_callbacks_after_close": 0,
        "byte_text_observations": [
          "{\n  \"ready\": true\n}\n"
        ],
        "stdout_field_meaning": "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee",
        "same_callback_other_value_result": null,
        "same_callback_other_value_authority_calls": 0,
        "same_callback_other_value_materializations": 0
      }
    }
  ],
  "remaining_qualification": [
    {
      "id": "SPLIT-CODECS/CLI-CANONICAL-JSON-ADAPTER",
      "owner": "core_cli codec coordinator",
      "trigger": "Before actual sourceJSON/numeric/TOML/canonical public result byte parity",
      "proof": "Exact number source reuse/export admission/fullserde features/perconsumer and full JSON grammar; private witnesses are not full renderer."
    },
    {
      "id": "CLI-COMPLETE-HUMAN-COLOR-RENDERER",
      "owner": "core_cli source-rendering coordinator",
      "trigger": "Before full human/color/wrapping/dynamic COLUMNS/NO_COLOR/TERM public behavior",
      "proof": "Entire output.rs schema/report families/ANSI/source environmental color and widths independently sourced bytes."
    },
    {
      "id": "CLI-FULL-PARSER-AND-COMMON-RESULTS",
      "owner": "core_cli parser and common operation coordinator",
      "trigger": "Before public CLI launcher/common complete14+HTTP/21full13readonly result integration",
      "proof": "Full Clap/help/version/discovery/error/default/schema/receipt dispatch andcontext; no fake fixed table authenticates actual common output."
    },
    {
      "id": "CLI-RAW-ARTIFACT-JSONL-DESTINATION",
      "owner": "core_cli O05/C09 output capability coordinator",
      "trigger": "Before raw full binary streams/JSONL stderrreceipt/destinationcopy/atomic destination admission",
      "proof": "All sourceArtifact andJsonlArtifact identities exactbytes/sidechannel/validation/capabilities/durableack and ambiguous possiblecommit; no privatecapabilityunavailable promoted as public unsupported."
    },
    {
      "id": "CLI-REAL-STDOUT-LIFETIME",
      "owner": "core_cli stdio transport owner",
      "trigger": "Before actual stdout/stderr/pipe/remote/OS distribution execution",
      "proof": "Boundedbyte framing/partialwrites/flush/EOF/brokenpipe/realresourceACK/process/principal/currentgrant/frontier andatomicdelivery limits."
    },
    {
      "id": "CLI-OTHER-COMMAND-FAMILIES",
      "owner": "core_cli complete-common-result coordinator",
      "trigger": "Before more than private status/query/direct outcomes, arbitrary CommandSuccess exit_code u8 or source report/receipt families",
      "proof": "Preserve complete14+HTTP/21full13readonly registries/defaults/report/extractpartial/raw/plainhelp/setup/state identities; current private exit0/1/2 subset does not remove others."
    }
  ],
  "current_integration_authority": {
    "core_inputs": 43,
    "core_outputs": 26,
    "guard_negatives": 84,
    "historical_CLI_tests": 341,
    "numeric_prospective_raw_inputs": 46,
    "numeric_not_adopted_into_current_core_cohort": true,
    "no_generated_current_outputs_read": true
  }
} as const;
