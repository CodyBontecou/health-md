package com.healthmd.direct

import android.content.Context
import android.os.Looper
import android.os.Process
import android.system.Os
import com.healthmd.direct.protocol.*
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.Path
import java.nio.file.StandardCopyOption.ATOMIC_MOVE
import java.nio.file.StandardCopyOption.REPLACE_EXISTING
import java.nio.file.StandardOpenOption.*
import java.nio.file.attribute.GroupPrincipal
import java.nio.file.attribute.PosixFileAttributes
import java.nio.file.attribute.PosixFilePermission
import java.nio.file.attribute.PosixFilePermissions
import java.nio.file.attribute.UserPrincipal
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import javax.crypto.Mac
import javax.crypto.SecretKey
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** Load only. Provisioning a distinct protected HmacSHA256 key is a separate native UI operation.
 * No planner, lookup, dispatcher or store API can create a key or fall back to plaintext. */
internal fun interface AgentBridgeExportProtectedKeyProvider { fun loadExisting(): SecretKey? }

/** Non-wire native authentication session. Pairing proves identity, not export consent.
 * The future secure-channel adapter must recheck current native trust on EVERY call. */
internal abstract class AgentBridgeExportAuthenticatedPeer protected constructor() {
    abstract fun requireCurrent(): AgentBridgePeer
}

/** Non-serializable human/native authorization session, never a Boolean/UUID/JSON permission.
 * Revalidate an already reviewed exact decision without prompting or minting authority; a single
 * operation calls this repeatedly around delaying SDK/storage boundaries.
 * No implementation or consent UI is installed here. Tests supply an independently gated fake. */
internal abstract class AgentBridgeExportNativeAuthorization protected constructor() {
    abstract fun requireDecision(decision: AgentBridgeExportNativeDecision)
}
internal sealed interface AgentBridgeExportNativeDecision {
    data object InitializeStore : AgentBridgeExportNativeDecision
    data class Delegation(val canonicalSha256: String, val expectedGrantRevision: Int) : AgentBridgeExportNativeDecision
    data class Revoke(val peer: AgentBridgePeer, val authorityId: String, val expectedGrantRevision: Int) : AgentBridgeExportNativeDecision
    data class ExactApproval(val planId: String, val binding: AgentBridgeBinding) : AgentBridgeExportNativeDecision
}

/** Isolated bounded no-backup issuer ledger. No default paths/preferences/trust stores are accessed.
 * Unknown/missing state never regenerates. Revoked IDs and issued request identities are retained;
 * exhaustion rejects rather than evicting/renewing. Atomic snapshot + fsync under an existing lock,
 * strict bounded byte parser + canonical typed roundtrip + protected-key MAC on every access.
 * MAC is integrity ONLY: a privileged actor can roll back a valid historical signed snapshot.
 * Inode pins are in-memory/per-operation, NOT a persisted fresh-open identity or OS protection proof.
 * Accepted-pending jobs retain immutable pre-capture inputs only; no capture claim/transfer/resume state. */
internal class AgentBridgeExportAuthorityStore private constructor(
    private val parent: Path,
    private val owner: UserPrincipal,
    private val group: GroupPrincipal,
    private val parentIdentity: Any,
    private val parentPermissions: Set<PosixFilePermission>,
    private val parentMode: Int,
    private val nativeOwnership: Pair<Int, Int>?,
    private val nativeAnchor: AgentBridgeExportNativeDirectoryAnchor?,
    private val keys: AgentBridgeExportProtectedKeyProvider,
) {
    private val root = parent.resolve(DIRECTORY_NAME)
    private var observedRootIdentity: Any? = null // Same-instance fence only; no anti-rollback/fresh-open claim.
    private val json = Json { encodeDefaults = true; ignoreUnknownKeys = false; isLenient = false; coerceInputValues = false }

    fun initialize(native: AgentBridgeExportNativeAuthorization) = initializeNew(native, true) { key() }

    private fun initializeNew(native: AgentBridgeExportNativeAuthorization, keyBeforeReservation: Boolean,
        beforeReservation: () -> Unit = {}, prepareKey: () -> SecretKey) = safe {
        native.requireDecision(AgentBridgeExportNativeDecision.InitializeStore)
        AgentBridgeNativeAuthorityChanges.mutation {
            serialized {
                checkParent()
                demand(!Files.exists(root, NOFOLLOW_LINKS), AgentBridgeErrorCode.REVISION_CONFLICT)
                beforeReservation()
                val existingKey = if (keyBeforeReservation) prepareKey() else null
                Files.createDirectory(root, PosixFilePermissions.asFileAttribute(directoryPermissions))
                val identity = attributes(root, directory = true).fileKey()
                observedRootIdentity = identity
                val key = existingKey ?: prepareKey()
                // Credential SDK work may delay. Recheck original native parent and reserved inode
                // before publishing files; no missing-key repair of an existing ledger is possible.
                checkParent()
                demand(attributes(root, directory = true).fileKey() == identity)
                writeNew(root.resolve(LOCK_NAME), ByteArray(0))
                val initial = fileBytes(AgentBridgeExportLedger(1, 1, emptyList(), emptyList(), emptyList()), key)
                if (keyBeforeReservation) {
                    writeNew(root.resolve(LEDGER_NAME), initial)
                } else {
                    native.requireDecision(AgentBridgeExportNativeDecision.InitializeStore)
                    checkParent()
                    demand(attributes(root, true).fileKey() == identity)
                    // Stage/fsync before the final native decision. Revocation during either the
                    // credential SDK or staging must not publish a usable initialized issuer.
                    replace(initial) {
                        checkParent()
                        demand(attributes(root, true).fileKey() == identity)
                        native.requireDecision(AgentBridgeExportNativeDecision.InitializeStore)
                    }
                }
                forceDirectory()
                demand(attributes(root, true).fileKey() == identity)
                if (!keyBeforeReservation) {
                    native.requireDecision(AgentBridgeExportNativeDecision.InitializeStore)
                    checkParent()
                    demand(attributes(root, true).fileKey() == identity)
                }
            }
        }
    }

    /** Local-only CAS. The sanitized document is review material; a separate native session is required. */
    fun putDelegation(native: AgentBridgeExportNativeAuthorization, value: AgentBridgeExportDelegation,
        expectedGrantRevision: Int): AgentBridgeAuthorityReference = safe {
        val bytes = AgentBridgeCodec.encode(value)
        val frozen = AgentBridgeCodec.decode(bytes) as AgentBridgeExportDelegation
        demand(frozen.issuer == AgentBridgeIssuer.NATIVE_SOURCE && frozen.peer.platform == AgentBridgePlatform.ANDROID,
            AgentBridgeErrorCode.APPROVAL_REQUIRED)
        val decision = AgentBridgeExportNativeDecision.Delegation(AgentBridgeCodec.sha256(bytes), expectedGrantRevision)
        native.requireDecision(decision)
        AgentBridgeNativeAuthorityChanges.mutation {
            access(fence = { native.requireDecision(decision) }) { transaction ->
                val tx = transaction ?: fail(AgentBridgeErrorCode.APPROVAL_REQUIRED)
                val old = tx.state.grants.singleOrNull { it.delegation().authorityId == frozen.authorityId }
                if (old == null) {
                    demand(expectedGrantRevision == 0 && frozen.grantRevision == 1, AgentBridgeErrorCode.REVISION_CONFLICT)
                    demand(tx.state.grants.size < MAX_GRANTS, AgentBridgeErrorCode.BUSY)
                } else {
                    val previous = old.delegation()
                    demand(!old.revoked && previous.peer == frozen.peer, AgentBridgeErrorCode.APPROVAL_REQUIRED)
                    demand(previous.grantRevision == expectedGrantRevision && expectedGrantRevision < Int.MAX_VALUE &&
                        frozen.grantRevision == expectedGrantRevision + 1, AgentBridgeErrorCode.REVISION_CONFLICT)
                }
                tx.state = tx.state.copy(grants = tx.state.grants.filterNot { it === old } + AgentBridgeExportGrantRecord(bytes.decodeToString(), false))
                reference(frozen)
            }
        }
    }

    fun revoke(native: AgentBridgeExportNativeAuthorization, peer: AgentBridgePeer, authorityId: String, expectedGrantRevision: Int) = safe {
        val decision = AgentBridgeExportNativeDecision.Revoke(peer, authorityId, expectedGrantRevision)
        native.requireDecision(decision)
        AgentBridgeNativeAuthorityChanges.mutation {
            access(fence = { native.requireDecision(decision) }) { transaction ->
                val tx = transaction ?: fail(AgentBridgeErrorCode.APPROVAL_REQUIRED)
                val old = tx.state.grants.singleOrNull { it.delegation().authorityId == authorityId } ?: fail(AgentBridgeErrorCode.APPROVAL_REQUIRED)
                val grant = old.delegation()
                demand(grant.peer == peer, AgentBridgeErrorCode.APPROVAL_REQUIRED)
                demand(grant.grantRevision == expectedGrantRevision, AgentBridgeErrorCode.REVISION_CONFLICT)
                tx.state = tx.state.copy(grants = tx.state.grants.map { if (it === old) it.copy(revoked = true) else it })
            }
        }
    }

    /** Native lifecycle publication only. Reuses signed/fsynced issuer storage, never initializes
     * state, keys, grants or consent. Sampling must not reenter this issuer store.
     * Native observers can invalidate a transition that coalesced before sampling; equal facts
     * then advance the revision. Ordinary unchanged retries leave that flag false. */
    fun publishNativeCatalog(sourceInstallationId: String, invalidatingObservedChange: Boolean = false, sample: () -> AgentBridgeNativePlanningFacts): AgentBridgeNativeCatalogPublication {
        if (Looper.myLooper() == Looper.getMainLooper()) fail(AgentBridgeErrorCode.PERMISSION_REQUIRED)
        var selected: AgentBridgeNativeCatalogPublication? = null
        return access(fence = {
            val current = selected ?: fail(AgentBridgeErrorCode.BINDING_CHANGED)
            demand(current.factsSha256 == sample().fingerprint(sourceInstallationId))
        }) { transaction ->
            val tx = transaction ?: fail(AgentBridgeErrorCode.APPROVAL_REQUIRED)
            val digest = sample().fingerprint(sourceInstallationId)
            val current = tx.state.nativeCatalog
            if (current != null) {
                demand(current.sourceInstallationId == sourceInstallationId)
                if (current.factsSha256 == digest && !invalidatingObservedChange) { selected = current; return@access current }
                demand(current.revision < Int.MAX_VALUE, AgentBridgeErrorCode.BUSY)
            }
            val next = AgentBridgeNativeCatalogPublication((current?.revision ?: 0) + 1, sourceInstallationId, digest)
            next.validate()
            tx.state = tx.state.copy(version = if (tx.state.acceptedJobs == null) 2 else 3, nativeCatalog = next)
            selected = next
            next
        }
    }

    /** Only the production service uses this transaction seam; remote dispatch has no issuer APIs. */
    internal fun <T> access(fence: (AgentBridgeExportAuthorityTransaction?) -> Unit = {}, block: (AgentBridgeExportAuthorityTransaction?) -> T): T = safe {
        serialized {
            checkParent()
            if (!Files.exists(root, NOFOLLOW_LINKS)) {
                demand(observedRootIdentity == null) // Previously observed state lost: never silently regenerate.
                val result = block(null)
                fence(null)
                return@serialized result
            }
            val rootIdentity = attributes(root, true).fileKey()
            if (observedRootIdentity == null) observedRootIdentity = rootIdentity
            demand(observedRootIdentity == rootIdentity)
            checkInventory()
            val lockPath = root.resolve(LOCK_NAME)
            val lockIdentity = attributes(lockPath, false).fileKey()
            FileChannel.open(lockPath, WRITE, NOFOLLOW_LINKS).use { channel ->
                var lock = channel.tryLock()
                var attempts = 0
                while (lock == null && attempts++ < 100) { Thread.sleep(10); lock = channel.tryLock() }
                val held = lock ?: fail(AgentBridgeErrorCode.BUSY)
                held.use {
                    checkIdentity(rootIdentity, lockIdentity)
                    checkInventory()
                    val key = key()
                    val before = read(key)
                    val tx = AgentBridgeExportAuthorityTransaction(before)
                    val result = block(tx)
                    fence(tx)
                    checkIdentity(rootIdentity, lockIdentity)
                    if (tx.state != before) {
                        demand(before.revision < Long.MAX_VALUE, AgentBridgeErrorCode.BUSY)
                        val after = tx.state.copy(revision = before.revision + 1)
                        validate(after)
                        val bytes = fileBytes(after, key)
                        demand(bytes.size <= MAX_BYTES, AgentBridgeErrorCode.BUSY)
                        checkIdentity(rootIdentity, lockIdentity)
                        fence(tx) // Current trust/authority/time after bounded validation and MAC signing.
                        checkIdentity(rootIdentity, lockIdentity)
                        replace(bytes) {
                            checkIdentity(rootIdentity, lockIdentity)
                            fence(tx) // Actual publication, AFTER pending-file write/fsync and native callbacks.
                            checkIdentity(rootIdentity, lockIdentity)
                        }
                    }
                    checkIdentity(rootIdentity, lockIdentity)
                    fence(tx) // Late expiry/revocation suppresses return, NOT a postpublication rollback.
                    checkIdentity(rootIdentity, lockIdentity)
                    result
                }
            }
        }
    }

    private fun key(): SecretKey = try {
        val key = keys.loadExisting() ?: fail(AgentBridgeErrorCode.PERMISSION_REQUIRED)
        // Hardware-backed keys may not expose encoded bytes. Ask the provider, never serialize it.
        demand(key.algorithm == "HmacSHA256", AgentBridgeErrorCode.PERMISSION_REQUIRED)
        Mac.getInstance("HmacSHA256").init(key)
        key
    } catch (_: Exception) { fail(AgentBridgeErrorCode.PERMISSION_REQUIRED) }

    private fun fileBytes(state: AgentBridgeExportLedger, key: SecretKey): ByteArray {
        val stateBytes = canonical(json.encodeToString(state))
        return canonical(json.encodeToString(AgentBridgeExportLedgerFile(state, mac(key, stateBytes))))
    }
    private fun mac(key: SecretKey, bytes: ByteArray): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(key)
        mac.update("HealthMd.AgentBridge.AndroidExportAuthorityStore.v1\u0000".toByteArray())
        return mac.doFinal(bytes).joinToString("") { "%02x".format(it) }
    }
    private fun read(key: SecretKey): AgentBridgeExportLedger = try {
        readChecked(key)
    } catch (_: Exception) {
        // A malformed stored record is corrupt issuer state, not a remote request error.
        fail(AgentBridgeErrorCode.BINDING_CHANGED)
    }
    private fun readChecked(key: SecretKey): AgentBridgeExportLedger {
        val path = root.resolve(LEDGER_NAME)
        val identity = attributes(path, false).fileKey()
        val bytes = FileChannel.open(path, READ, NOFOLLOW_LINKS).use { channel ->
            val size = channel.size()
            demand(size in 1..MAX_BYTES.toLong())
            val buffer = ByteBuffer.allocate(size.toInt())
            while (buffer.hasRemaining()) demand(channel.read(buffer) > 0)
            demand(channel.size() == size)
            buffer.array()
        }
        demand(attributes(path, false).fileKey() == identity)
        // canonicalize invokes the actual strict UTF8/duplicate-decoded-key/depth/node/string parser.
        val canonical = AgentBridgeCodec.canonicalize(bytes)
        val file = json.decodeFromString<AgentBridgeExportLedgerFile>(canonical.decodeToString())
        demand(canonical.contentEquals(canonical(json.encodeToString(file)))) // Unknown/coerced/missing fields fail closed.
        demand(Regex("[0-9a-f]{64}").matches(file.mac))
        demand(MessageDigest.isEqual(file.mac.toByteArray(), mac(key, canonical(json.encodeToString(file.state))).toByteArray()))
        validate(file.state)
        return file.state
    }
    private fun validate(state: AgentBridgeExportLedger) {
        demand(state.version == (if (state.acceptedJobs != null) 3 else if (state.nativeCatalog == null) 1 else 2) && state.revision >= 1)
        state.nativeCatalog?.validate()
        demand(state.grants.size <= MAX_GRANTS && state.plans.size <= MAX_PLANS && state.decisions.size <= MAX_DECISIONS)
        val grants = state.grants.map { it.delegation() }
        demand(grants.map { it.authorityId }.distinct().size == grants.size)
        demand(grants.all { it.issuer == AgentBridgeIssuer.NATIVE_SOURCE && it.peer.platform == AgentBridgePlatform.ANDROID })
        val plans = state.plans.map { record ->
            val request = record.request()
            val plan = record.plan()
            demand(plan.intent == request.intent && plan.capabilitySha256 == request.capabilitySha256 &&
                plan.authorityReferences.host == request.hostAuthorityReference && plan.authorityReferences.native.authorityId == request.authorityId &&
                plan.authorityReferences.native.grantRevision == request.authorityRevision)
            val authority = AgentBridgeCodec.decode(record.nativeAuthorityCanonical.toByteArray()) as AgentBridgeAuthority
            demand(record.nativeAuthorityCanonical == AgentBridgeCodec.encode(authority).decodeToString())
            demand(authority.issuer == AgentBridgeIssuer.NATIVE_SOURCE && authority.authorityId == request.authorityId &&
                authority.peer == plan.intent.peer && authority.scopeSha256 == plan.scopeSha256 && authority.expiresAt == plan.expiresAt)
            val resolutionBytes = AgentBridgeCodec.canonicalize(record.resolutionCanonical.toByteArray())
            val resolution = json.decodeFromString<AgentBridgeRequestSettingsResolution>(resolutionBytes.decodeToString())
            demand(resolutionBytes.contentEquals(canonical(json.encodeToString(resolution))))
            demand(resolution.version == 1 && resolution.intentSha256 == AgentBridgeCodec.fingerprint(plan.intent) &&
                resolution.peer == plan.intent.peer && resolution.destination == plan.intent.destination && resolution.dates == plan.resolvedDates &&
                resolution.predictedRelativePaths == plan.predictedPaths && resolution.selection.map { it.semanticId } == plan.resolvedMetricIds)
            resolution.exporterSettings() // Validates private snapshot restoration without preferences/provider work.
            demand(Regex("[0-9a-f]{64}").matches(record.configurationSha256))
            plan
        }
        demand(plans.map { it.planId }.distinct().size == plans.size)
        demand(state.plans.map { it.request().intent.let { intent ->
            val peer = when (intent) { is AgentBridgeGeneratedIntent -> intent.peer; is AgentBridgeProjectionIntent -> intent.peer }
            peer to it.request().requestId
        } }.distinct().size == plans.size)
        val approvals = state.decisions.map { record ->
            val approval = record.approval()
            val plan = plans.singleOrNull { it.planId == record.planId } ?: fail(AgentBridgeErrorCode.BINDING_CHANGED)
            demand(approval.binding == AgentBridgeValidation.bindingFor(plan) && approval.authorityId == plan.authorityReferences.native.authorityId)
            demand(Instant.parse(approval.approvedAt) >= Instant.parse(plan.issuedAt) && Instant.parse(approval.approvedAt) < Instant.parse(plan.expiresAt))
            approval
        }
        demand(state.decisions.map { it.planId }.distinct().size == approvals.size && approvals.map { it.approvalId }.distinct().size == approvals.size)
        state.acceptedJobs?.let { jobs ->
            demand(jobs.isNotEmpty() && jobs.size <= 16)
            val identities = jobs.map { job ->
                job.validate()
                val request = job.request(); val plan = request.plan as AgentBridgeGeneratedPlan
                val stored = state.plans.singleOrNull { it.plan() == plan } ?: fail(AgentBridgeErrorCode.BINDING_CHANGED)
                demand(stored.resolutionCanonical == job.resolutionCanonical)
                demand(state.decisions.any { it.planId == plan.planId && it.approval() == request.approval })
                "${plan.intent.peer.sourceInstallationId}:${plan.intent.peer.hostInstallationId}:${request.jobId}"
            }
            demand(identities.distinct().size == identities.size)
        }
    }

    private fun replace(bytes: ByteArray, beforePublication: () -> Unit) {
        checkParent()
        val rootIdentity = attributes(root, true).fileKey()
        val temporary = root.resolve("pending-" + UUID.randomUUID())
        writeNew(temporary, bytes)
        val temporaryIdentity = attributes(temporary, false).fileKey()
        fun requireOriginalStage() {
            checkParent()
            demand(attributes(root, true).fileKey() == rootIdentity)
            demand(attributes(temporary, false).fileKey() == temporaryIdentity)
        }
        try {
            beforePublication()
            // The callback may delay or change native state. Recheck AFTER it, before any
            // rename/cleanup by absolute path; an earlier pin cannot authorize a replacement.
            requireOriginalStage()
        } catch (failure: Exception) {
            // Only clean the original staged file in the original still-reachable directory.
            // Otherwise retain the orphan and original denial; never touch a replacement root.
            // These sampled fences do not claim protection from an arbitrary same-UID writer.
            if (runCatching { requireOriginalStage() }.isSuccess) {
                runCatching { Files.delete(temporary); forceDirectory() }
                    .exceptionOrNull()?.let { failure.addSuppressed(it) }
            }
            throw failure
        }
        // Interrupted leftovers are still corruption, never silently deleted/reused on restart.
        Files.move(temporary, root.resolve(LEDGER_NAME), ATOMIC_MOVE, REPLACE_EXISTING)
        forceDirectory()
    }
    private fun writeNew(path: Path, bytes: ByteArray) {
        Files.createFile(path, PosixFilePermissions.asFileAttribute(filePermissions))
        FileChannel.open(path, WRITE, NOFOLLOW_LINKS).use { channel ->
            val buffer = ByteBuffer.wrap(bytes)
            while (buffer.hasRemaining()) channel.write(buffer)
            channel.force(true)
        }
        attributes(path, false)
    }
    private fun forceDirectory() { FileChannel.open(root, READ, NOFOLLOW_LINKS).use { it.force(true) } }
    private fun checkIdentity(rootIdentity: Any?, lockIdentity: Any?) {
        checkParent()
        demand(attributes(root, true).fileKey() == rootIdentity && attributes(root.resolve(LOCK_NAME), false).fileKey() == lockIdentity)
    }
    private fun checkInventory() {
        val names = Files.newDirectoryStream(root).use { stream -> stream.map { it.fileName.toString() }.toSet() }
        demand(names == setOf(LOCK_NAME, LEDGER_NAME))
        attributes(root.resolve(LOCK_NAME), false); attributes(root.resolve(LEDGER_NAME), false)
        demand(Files.size(root.resolve(LOCK_NAME)) == 0L)
    }
    private fun checkParent() {
        demand(parent.toRealPath() == parent)
        val attrs = attributes(parent, true)
        demand(attrs.fileKey() == parentIdentity)
        nativeAnchor?.let { anchor ->
            demand(anchor.path.toRealPath() == anchor.path && attributes(anchor.path, true).fileKey() == anchor.identity)
        }
    }
    private fun attributes(path: Path, directory: Boolean): PosixFileAttributes {
        val attrs = Files.readAttributes(path, PosixFileAttributes::class.java, NOFOLLOW_LINKS)
        demand(!attrs.isSymbolicLink && (if (directory) attrs.isDirectory else attrs.isRegularFile) &&
            attrs.owner() == owner && attrs.group() == group && attrs.fileKey() != null)
        val anchor = nativeAnchor?.takeIf { it.path == path }
        val permissions = when {
            path == parent -> parentPermissions
            anchor != null -> anchor.permissions
            directory -> directoryPermissions
            else -> filePermissions
        }
        val expectedMode = when {
            path == parent -> parentMode
            anchor != null -> anchor.mode
            directory -> 448 // 0700, including rejection of setgid/sticky bits.
            else -> 384 // 0600.
        }
        demand(attrs.permissions() == permissions && mode(path) == expectedMode)
        nativeOwnership?.let { (uid, gid) -> demand(unixId(path, "uid") == uid && unixId(path, "gid") == gid) }
        if (!directory) demand((Files.getAttribute(path, "unix:nlink", NOFOLLOW_LINKS) as Number).toLong() == 1L)
        return attrs
    }
    private fun canonical(text: String) = AgentBridgeCodec.canonicalize(text.toByteArray())

    companion object {
        const val DIRECTORY_NAME = "agent-bridge-export-authority-v1"
        internal const val LEDGER_NAME = "ledger.json"
        private const val LOCK_NAME = "issuer.lock"
        const val MAX_GRANTS = 32
        const val MAX_PLANS = 64
        const val MAX_DECISIONS = 64
        const val MAX_BYTES = 2097152
        private val processLock = ReentrantLock(true) // Bounded JVM admission + existing cross-process file lock.
        private fun <T> serialized(block: () -> T): T {
            demand(!processLock.isHeldByCurrentThread, AgentBridgeErrorCode.BUSY)
            demand(processLock.tryLock(1, TimeUnit.SECONDS), AgentBridgeErrorCode.BUSY)
            return try { block() } finally { processLock.unlock() }
        }
        private val directoryPermissions = PosixFilePermissions.fromString("rwx------")
        private val filePermissions = PosixFilePermissions.fromString("rw-------")

        /** Read EXISTING credential-protected dataDir/no_backup only. AOSP ContextImpl's
         * getNoBackupFilesDir/getFilesDir can mkdir/chmod mode0771, so neither getter is called here.
         * OS-native 0771 is accepted ONLY for this fixed Context-derived UID/GID-owned parent;
         * it never weakens the issuer leaf0700/files0600 or arbitrary test-root injection. */
        fun forNoBackup(context: Context, keys: AgentBridgeExportProtectedKeyProvider = AgentBridgeExportProtectedKey(context)): AgentBridgeExportAuthorityStore = safe {
            demand(!context.isDeviceProtectedStorage)
            val uid = Process.myUid()
            val gid = Os.getgid()
            val data = context.dataDir.toPath().toAbsolutePath().normalize()
            val dataAttrs = nativeDirectory(data, uid, gid)
            val path = data.resolve("no_backup")
            val attrs = nativeDirectory(path, uid, gid) // Missing is fail-closed; no mkdir/getter/key load.
            AgentBridgeExportAuthorityStore(path, attrs.owner(), attrs.group(), requireNotNull(attrs.fileKey()), attrs.permissions(),
                mode(path), uid to gid, AgentBridgeExportNativeDirectoryAnchor(data, requireNotNull(dataAttrs.fileKey()),
                    dataAttrs.permissions(), mode(data)), keys)
        }
        /** Human/native setup only, not remote dispatch or an existing-store repair path.
         * The fixed no-backup directory is reserved exclusively before any Keystore generation.
         * A lost/invalid key with an existing issuer directory rejects without credential writes. */
        fun initializeNative(context: Context, native: AgentBridgeExportNativeAuthorization): AgentBridgeExportAuthorityStore {
            val provisioner = AgentBridgeExportProtectedKeyProvisioner(context)
            // Explicit setup may create the FIXED missing SDK parent, never chmod/repair an
            // existing path through Context's creating getter. Load-only factories stay unchanged.
            demand(!context.isDeviceProtectedStorage)
            val data = context.dataDir.toPath().toAbsolutePath().normalize()
            val uid = Process.myUid()
            val gid = Os.getgid()
            val dataIdentity = nativeDirectory(data, uid, gid).fileKey()
            val parent = data.resolve("no_backup")
            if (!Files.exists(parent, NOFOLLOW_LINKS)) {
                native.requireDecision(AgentBridgeExportNativeDecision.InitializeStore)
                provisioner.requireAvailable()
                demand(nativeDirectory(data, uid, gid).fileKey() == dataIdentity)
                // Exclusive creation rejects races instead of adopting or repairing another path.
                Files.createDirectory(parent, PosixFilePermissions.asFileAttribute(directoryPermissions))
                FileChannel.open(data, READ, NOFOLLOW_LINKS).use { it.force(true) }
                demand(nativeDirectory(data, uid, gid).fileKey() == dataIdentity)
            }
            val store = forNoBackup(context, provisioner.reader)
            store.initializeNew(native, false, provisioner::requireAvailable) { provisioner.loadOrCreateForNewPrivateStore() }
            return store
        }

        private fun nativeDirectory(path: Path, uid: Int, gid: Int): PosixFileAttributes {
            demand(path.toRealPath() == path)
            val attrs = Files.readAttributes(path, PosixFileAttributes::class.java, NOFOLLOW_LINKS)
            demand(attrs.isDirectory && !attrs.isSymbolicLink && attrs.fileKey() != null &&
                unixId(path, "uid") == uid && unixId(path, "gid") == gid)
            // Group-write is safe only in the exact native0771 mode with this trusted process GID.
            // Other-write, other modes and special bits are rejected, never repaired.
            demand(mode(path) in setOf(448, 505)) // 0700, 0771.
            return attrs
        }
        private fun unixId(path: Path, field: String) = (Files.getAttribute(path, "unix:$field", NOFOLLOW_LINKS) as Number).toInt()
        private fun mode(path: Path) = (Files.getAttribute(path, "unix:mode", NOFOLLOW_LINKS) as Number).toInt() and 0xfff
        /** Explicit STRICT0700 injection for hermetic tests only, never caller paths on wire. */
        fun inPrivateDirectory(parent: Path, keys: AgentBridgeExportProtectedKeyProvider): AgentBridgeExportAuthorityStore = safe {
            val path = parent.toAbsolutePath().normalize()
            demand(path.toRealPath() == path)
            val attrs = Files.readAttributes(path, PosixFileAttributes::class.java, NOFOLLOW_LINKS)
            demand(attrs.isDirectory && !attrs.isSymbolicLink && attrs.permissions() == directoryPermissions && mode(path) == 448 && attrs.fileKey() != null)
            AgentBridgeExportAuthorityStore(path, attrs.owner(), attrs.group(), requireNotNull(attrs.fileKey()), directoryPermissions, 448, null, null, keys)
        }
        internal fun reference(grant: AgentBridgeExportDelegation) = AgentBridgeAuthorityReference(grant.authorityId, grant.grantRevision,
            AgentBridgeCodec.fingerprint(grant), grant.issuer)
        private fun demand(value: Boolean, code: AgentBridgeErrorCode = AgentBridgeErrorCode.BINDING_CHANGED) { if (!value) fail(code) }
        private fun fail(code: AgentBridgeErrorCode): Nothing = throw AgentBridgeException(code)
        private inline fun <T> safe(block: () -> T): T = try { block() } catch (e: AgentBridgeException) { throw e }
            catch (_: Exception) { fail(AgentBridgeErrorCode.BINDING_CHANGED) }
    }
}

private data class AgentBridgeExportNativeDirectoryAnchor(val path: Path, val identity: Any,
    val permissions: Set<PosixFilePermission>, val mode: Int)

@Serializable
internal data class AgentBridgeExportLedgerFile(val state: AgentBridgeExportLedger, val mac: String)
@OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
@Serializable
internal data class AgentBridgeExportLedger(val version: Int, val revision: Long, val grants: List<AgentBridgeExportGrantRecord>,
    val plans: List<AgentBridgeExportIssuedPlanRecord>, val decisions: List<AgentBridgeExportDecisionRecord>,
    @kotlinx.serialization.EncodeDefault(kotlinx.serialization.EncodeDefault.Mode.NEVER)
    val nativeCatalog: AgentBridgeNativeCatalogPublication? = null,
    @kotlinx.serialization.EncodeDefault(kotlinx.serialization.EncodeDefault.Mode.NEVER)
    val acceptedJobs: List<AgentBridgeExportAcceptedJob>? = null)
@Serializable
internal data class AgentBridgeExportGrantRecord(val delegationCanonical: String, val revoked: Boolean) {
    fun delegation(): AgentBridgeExportDelegation {
        val value = AgentBridgeCodec.decode(delegationCanonical.toByteArray()) as AgentBridgeExportDelegation
        require(delegationCanonical == AgentBridgeCodec.encode(value).decodeToString())
        return value
    }
}
@Serializable
internal data class AgentBridgeExportIssuedPlanRecord(val requestCanonical: String, val planCanonical: String,
    val resolutionCanonical: String, val nativeAuthorityCanonical: String, val configurationSha256: String) {
    fun request(): AgentBridgePlanRequest {
        val value = AgentBridgeCodec.decode(requestCanonical.toByteArray()) as AgentBridgePlanRequest
        require(requestCanonical == AgentBridgeCodec.encode(value).decodeToString())
        return value
    }
    fun plan(): AgentBridgeGeneratedPlan {
        val value = AgentBridgeCodec.decode(planCanonical.toByteArray()) as AgentBridgeGeneratedPlan
        require(planCanonical == AgentBridgeCodec.encode(value).decodeToString())
        return value
    }
}
@Serializable
internal data class AgentBridgeExportDecisionRecord(val planId: String, val approvalCanonical: String) {
    fun approval(): AgentBridgeApproval {
        val value = AgentBridgeCodec.decode(approvalCanonical.toByteArray()) as AgentBridgeApproval
        require(approvalCanonical == AgentBridgeCodec.encode(value).decodeToString())
        return value
    }
}

internal class AgentBridgeExportAuthorityTransaction(internal var state: AgentBridgeExportLedger) {
    fun references(peer: AgentBridgePeer, now: Instant): List<AgentBridgeAuthorityReference> = state.grants.filter { record ->
        val grant = record.delegation()
        !record.revoked && grant.peer == peer && Instant.parse(grant.expiresAt) > now && AgentBridgeExportDelegationRightsItem.DISCOVER in grant.rights
    }.map { AgentBridgeExportAuthorityStore.reference(it.delegation()) }.sortedBy { it.authorityId }

    fun grant(peer: AgentBridgePeer, id: String, revision: Int, now: Instant): AgentBridgeExportDelegation {
        val record = state.grants.singleOrNull { it.delegation().authorityId == id } ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
        val grant = record.delegation()
        if (record.revoked || grant.peer != peer) throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
        if (grant.grantRevision != revision) throw AgentBridgeException(AgentBridgeErrorCode.REVISION_CONFLICT)
        if (Instant.parse(grant.expiresAt) <= now) throw AgentBridgeException(AgentBridgeErrorCode.PLAN_EXPIRED)
        return grant
    }
    fun issuedFor(peer: AgentBridgePeer, requestId: String): AgentBridgeExportIssuedPlanRecord? = state.plans.singleOrNull {
        it.plan().intent.peer == peer && it.request().requestId == requestId
    }
    fun plan(peer: AgentBridgePeer, id: String): AgentBridgeExportIssuedPlanRecord = state.plans.singleOrNull {
        it.plan().intent.peer == peer && it.plan().planId == id
    } ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
    fun planForApproval(peer: AgentBridgePeer, approval: AgentBridgeApproval): AgentBridgeExportIssuedPlanRecord {
        val decision = state.decisions.singleOrNull { it.approval() == approval }
            ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
        return plan(peer, decision.planId)
    }
    fun issue(record: AgentBridgeExportIssuedPlanRecord) {
        if (state.plans.size >= AgentBridgeExportAuthorityStore.MAX_PLANS) throw AgentBridgeException(AgentBridgeErrorCode.BUSY)
        state = state.copy(plans = state.plans + record)
    }
    fun decision(planId: String): AgentBridgeApproval? = state.decisions.singleOrNull { it.planId == planId }?.approval()
    fun decide(planId: String, approval: AgentBridgeApproval) {
        if (state.decisions.size >= AgentBridgeExportAuthorityStore.MAX_DECISIONS) throw AgentBridgeException(AgentBridgeErrorCode.BUSY)
        state = state.copy(decisions = state.decisions + AgentBridgeExportDecisionRecord(planId, AgentBridgeCodec.encode(approval).decodeToString()))
    }
}

/** One exact native confirmation scoped to its synchronous operation. Not a serializable grant,
 * export/configuration authority, renewable policy Boolean, or remote permission endpoint. */
internal class AgentBridgeExportNativeConsent private constructor(
    private val expectedDecision: String,
    private val requireCurrentNativePolicy: () -> Unit,
    private val clockNanos: () -> Long,
) : AgentBridgeExportNativeAuthorization() {
    private val lock = Any()
    private var active = true
    private val startedAt = clockNanos()

    override fun requireDecision(decision: AgentBridgeExportNativeDecision) {
        try {
            demand(token(decision) == expectedDecision)
            demand(synchronized(lock) { active })
            demand((clockNanos() - startedAt) in 0L until TIMEOUT_NANOS)
            requireCurrentNativePolicy()
            demand(token(decision) == expectedDecision)
            demand(synchronized(lock) { active })
            demand((clockNanos() - startedAt) in 0L until TIMEOUT_NANOS)
        } catch (_: Exception) {
            invalidate()
            throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
        }
    }

    private fun invalidate() { synchronized(lock) { active = false } }
    private fun demand(value: Boolean) {
        if (!value) throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
    }

    companion object {
        // Scalars are immutable; hash a canonical exact approval to freeze any caller-owned lists.
        private fun token(value: AgentBridgeExportNativeDecision): String = when (value) {
            AgentBridgeExportNativeDecision.InitializeStore -> "setup"
            is AgentBridgeExportNativeDecision.Delegation -> "grant:${value.canonicalSha256}:${value.expectedGrantRevision}"
            is AgentBridgeExportNativeDecision.Revoke -> "revoke:${value.peer.platform}:${value.peer.sourceInstallationId}:${value.peer.hostInstallationId}:${value.authorityId}:${value.expectedGrantRevision}"
            is AgentBridgeExportNativeDecision.ExactApproval -> "approval:" + AgentBridgeCodec.sha256(AgentBridgeCodec.encode(
                AgentBridgeApprovalRequest(value.binding, value.planId, value.planId, "healthmd.agent_approval_request", 1)))
        }
        private const val TIMEOUT_NANOS = 30_000_000_000L
        fun <T> withNativeConfirmation(
            decision: AgentBridgeExportNativeDecision,
            requireCurrentNativePolicy: () -> Unit,
            clockNanos: () -> Long = { android.os.SystemClock.elapsedRealtimeNanos() },
            operation: (AgentBridgeExportNativeAuthorization) -> T,
        ): T {
            val consent = AgentBridgeExportNativeConsent(token(decision), requireCurrentNativePolicy, clockNanos)
            return try {
                consent.requireDecision(decision)
                val result = operation(consent)
                consent.requireDecision(decision)
                result
            } finally { consent.invalidate() }
        }
    }
}

/** Setup-only entry point retained for callers; it cannot create a grant/approval proof. */
internal object AgentBridgeExportNativeSetupConsent {
    fun <T> withNativeConfirmation(
        requireCurrentNativePolicy: () -> Unit,
        clockNanos: () -> Long = { android.os.SystemClock.elapsedRealtimeNanos() },
        operation: (AgentBridgeExportNativeAuthorization) -> T,
    ): T = AgentBridgeExportNativeConsent.withNativeConfirmation(
        AgentBridgeExportNativeDecision.InitializeStore, requireCurrentNativePolicy, clockNanos, operation)
}


@Serializable
internal data class AgentBridgeExportAcceptedJob(val version: Int, val requestCanonical: String,
    val requestSha256: String, val resolutionCanonical: String, val acceptedAt: String, val expiresAt: String) {
    fun request() = AgentBridgeCodec.decode(requestCanonical.toByteArray()) as AgentBridgeExecuteRequest
    fun validate() {
        val request = request(); val plan = request.plan as AgentBridgeGeneratedPlan
        require(version == 1 && requestCanonical.toByteArray().size <= 48 * 1024 && resolutionCanonical.toByteArray().size <= 48 * 1024)
        require(requestCanonical == AgentBridgeCodec.encode(request).decodeToString() && requestSha256 == AgentBridgeCodec.sha256(requestCanonical.toByteArray()))
        val accepted = Instant.parse(acceptedAt)
        require(Instant.parse(expiresAt) == accepted.plusSeconds(604800) && accepted >= Instant.parse(plan.issuedAt) && accepted < Instant.parse(plan.expiresAt))
        require(Instant.parse(request.approval.approvedAt) <= accepted)
        Json { encodeDefaults = true; ignoreUnknownKeys = false }.decodeFromString<AgentBridgeRequestSettingsResolution>(resolutionCanonical)
    }
}
internal data class AgentBridgeExportJobAcceptance(val job: AgentBridgeExportAcceptedJob, val newlyAccepted: Boolean)
