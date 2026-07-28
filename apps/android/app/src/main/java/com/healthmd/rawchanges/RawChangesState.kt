package com.healthmd.rawchanges

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.Closeable
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal data class RawChangesChainState(
    val scopeHash: String,
    val scopeJson: String,
    val chainId: String,
    val sequence: Long,
    val previousLogicalHash: String?,
    val token: SecretChangesToken,
    val tokenGeneratedAtEpochSecond: Long,
    val tokenGeneratedAtNano: Int,
    val tokenGeneratedBeforeBase: Boolean,
)

internal enum class PendingPhase { READING, PREPARED, PROMOTED, SIDECAR_DURABLE }

internal data class PendingArchive(
    val scopeHash: String,
    val archiveId: String,
    val chainId: String,
    val sequence: Long,
    val previousLogicalHash: String?,
    /** Chain state observed before this pending row was inserted; all-null means no prior chain. */
    val expectedChainId: String?,
    val expectedSequence: Long?,
    val expectedLogicalHash: String?,
    val createdEpochSecond: Long,
    val createdNano: Int,
    val workDatabasePath: String,
    val artifactPath: String?,
    val logicalHash: String?,
    val artifactHash: String?,
    val sidecarPath: String?,
    val phase: PendingPhase,
    val tokenGeneratedAtEpochSecond: Long,
    val tokenGeneratedAtNano: Int,
    val tokenGeneratedBeforeBase: Boolean,
)

internal sealed interface IdentityMutation {
    val nativeRecordId: String
    data class Upsert(val identity: RawNativeIdentity) : IdentityMutation {
        override val nativeRecordId: String get() = identity.nativeRecordId
    }
    data class Delete(override val nativeRecordId: String) : IdentityMutation
}

internal class RawChangesStateConflictException : IllegalStateException(
    "Raw changes state is busy or changed; retry the scoped operation.",
)

internal interface RawChangesStateStore {
    fun load(scopeHash: String): RawChangesChainState?
    fun identity(scopeHash: String, nativeRecordId: String): RawNativeIdentity?
    fun pending(scopeHash: String): PendingArchive?
    fun allPending(): List<PendingArchive>
    fun beginPending(pending: PendingArchive, initialToken: SecretChangesToken)
    fun prepared(pending: PendingArchive, artifactPath: String, logicalHash: String, artifactHash: String)
    fun markPromoted(pending: PendingArchive)
    fun markSidecarDurable(pending: PendingArchive, sidecarPath: String)
    fun commit(
        pending: PendingArchive,
        scopeJson: String,
        nextToken: SecretChangesToken,
        nextTokenReceivedEpochSecond: Long,
        nextTokenReceivedNano: Int,
        mutations: Sequence<IdentityMutation>,
    )
    fun discardPending(pending: PendingArchive)
}

/** Installation-bound AES-GCM. Key material never leaves AndroidKeyStore. */
internal class InstallationBoundTokenCipher(private val alias: String = "healthmd.raw-changes.token.v1") {
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }

    fun encrypt(token: SecretChangesToken): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        return cipher.iv + cipher.doFinal(token.value.toByteArray(Charsets.UTF_8))
    }

    fun decrypt(value: ByteArray): SecretChangesToken {
        require(value.size > IV_BYTES) { "Encrypted changes state is invalid." }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, value.copyOfRange(0, IV_BYTES)))
        return SecretChangesToken(String(cipher.doFinal(value.copyOfRange(IV_BYTES, value.size)), Charsets.UTF_8))
    }

    companion object { private const val IV_BYTES = 12 }
}

private fun SQLiteDatabase.configureDurableJournal() {
    rawQuery("PRAGMA journal_mode=WAL", null).use { cursor ->
        check(cursor.moveToFirst() && cursor.getString(0).equals("wal", ignoreCase = true)) {
            "Unable to enable the raw changes WAL journal."
        }
    }
    execSQL("PRAGMA synchronous=FULL")
}

/** SQLite is opened directly under noBackupFilesDir; token and identity mutations share one commit. */
internal class SQLiteRawChangesStateStore(
    context: Context,
    private val cipher: InstallationBoundTokenCipher = InstallationBoundTokenCipher(),
) : RawChangesStateStore, Closeable {
    private val root = File(context.noBackupFilesDir, "raw-changes").apply { mkdirs() }
    private val db = SQLiteDatabase.openOrCreateDatabase(File(root, "state.db"), null).apply {
        configureDurableJournal()
        execSQL("CREATE TABLE IF NOT EXISTS chain_state(scope_hash TEXT PRIMARY KEY, scope_json TEXT NOT NULL, chain_id TEXT NOT NULL, sequence INTEGER NOT NULL, previous_hash TEXT, token BLOB NOT NULL, token_sec INTEGER NOT NULL, token_nano INTEGER NOT NULL, before_base INTEGER NOT NULL)")
        execSQL("CREATE TABLE IF NOT EXISTS identities(scope_hash TEXT NOT NULL, record_id TEXT NOT NULL, type_key TEXT NOT NULL, wire_type TEXT NOT NULL, origin TEXT NOT NULL, record_hash TEXT NOT NULL, PRIMARY KEY(scope_hash, record_id))")
        execSQL("CREATE INDEX IF NOT EXISTS identities_scope_id ON identities(scope_hash, record_id)")
        execSQL("CREATE TABLE IF NOT EXISTS pending(scope_hash TEXT PRIMARY KEY, archive_id TEXT NOT NULL, chain_id TEXT NOT NULL, sequence INTEGER NOT NULL, previous_hash TEXT, expected_chain_id TEXT, expected_sequence INTEGER, expected_hash TEXT, created_sec INTEGER NOT NULL, created_nano INTEGER NOT NULL, work_db TEXT NOT NULL, artifact_path TEXT, logical_hash TEXT, artifact_hash TEXT, sidecar_path TEXT, initial_token BLOB NOT NULL, phase TEXT NOT NULL, token_sec INTEGER NOT NULL, token_nano INTEGER NOT NULL, before_base INTEGER NOT NULL)")
        ensureColumn("pending", "expected_chain_id", "TEXT")
        ensureColumn("pending", "expected_sequence", "INTEGER")
        ensureColumn("pending", "expected_hash", "TEXT")
    }

    override fun load(scopeHash: String): RawChangesChainState? = db.rawQuery(
        "SELECT scope_json,chain_id,sequence,previous_hash,token,token_sec,token_nano,before_base FROM chain_state WHERE scope_hash=?",
        arrayOf(scopeHash),
    ).use { cursor ->
        if (!cursor.moveToFirst()) null else RawChangesChainState(
            scopeHash, cursor.getString(0), cursor.getString(1), cursor.getLong(2),
            cursor.getString(3), cipher.decrypt(cursor.getBlob(4)), cursor.getLong(5), cursor.getInt(6), cursor.getInt(7) != 0,
        )
    }

    override fun identity(scopeHash: String, nativeRecordId: String): RawNativeIdentity? = db.rawQuery(
        "SELECT type_key,wire_type,origin,record_hash FROM identities WHERE scope_hash=? AND record_id=?",
        arrayOf(scopeHash, nativeRecordId),
    ).use { cursor ->
        if (!cursor.moveToFirst()) null else RawNativeIdentity(nativeRecordId, cursor.getString(0), cursor.getString(1), cursor.getString(2), cursor.getString(3))
    }

    override fun pending(scopeHash: String): PendingArchive? = db.rawQuery(
        "SELECT archive_id,chain_id,sequence,previous_hash,expected_chain_id,expected_sequence,expected_hash,created_sec,created_nano,work_db,artifact_path,logical_hash,artifact_hash,sidecar_path,phase,token_sec,token_nano,before_base FROM pending WHERE scope_hash=?",
        arrayOf(scopeHash),
    ).use { cursor ->
        if (!cursor.moveToFirst()) null else cursor.pending(scopeHash)
    }

    override fun allPending(): List<PendingArchive> = db.rawQuery(
        "SELECT scope_hash,archive_id,chain_id,sequence,previous_hash,expected_chain_id,expected_sequence,expected_hash,created_sec,created_nano,work_db,artifact_path,logical_hash,artifact_hash,sidecar_path,phase,token_sec,token_nano,before_base FROM pending",
        null,
    ).use { cursor ->
        buildList { while (cursor.moveToNext()) add(cursor.pending(cursor.getString(0), 1)) }
    }

    override fun beginPending(pending: PendingArchive, initialToken: SecretChangesToken) {
        db.beginTransaction()
        try {
            verifyExpectedChain(pending)
            try {
                db.execSQL(
                    "INSERT INTO pending(scope_hash,archive_id,chain_id,sequence,previous_hash,expected_chain_id,expected_sequence,expected_hash,created_sec,created_nano,work_db,initial_token,phase,token_sec,token_nano,before_base) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    arrayOf(
                        pending.scopeHash, pending.archiveId, pending.chainId, pending.sequence, pending.previousLogicalHash,
                        pending.expectedChainId, pending.expectedSequence, pending.expectedLogicalHash,
                        pending.createdEpochSecond, pending.createdNano, pending.workDatabasePath, cipher.encrypt(initialToken), PendingPhase.READING.name,
                        pending.tokenGeneratedAtEpochSecond, pending.tokenGeneratedAtNano, if (pending.tokenGeneratedBeforeBase) 1 else 0,
                    ),
                )
            } catch (_: android.database.sqlite.SQLiteConstraintException) {
                throw RawChangesStateConflictException()
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    override fun prepared(pending: PendingArchive, artifactPath: String, logicalHash: String, artifactHash: String) {
        // The terminal token remains memory-only until the final chain/index transaction.
        casUpdate(
            "UPDATE pending SET artifact_path=?,logical_hash=?,artifact_hash=?,phase=? WHERE scope_hash=? AND archive_id=? AND chain_id=? AND sequence=? AND phase=?",
            (listOf<Any?>(artifactPath, logicalHash, artifactHash, PendingPhase.PREPARED.name) + identityArgs(pending).asList() + PendingPhase.READING.name).toTypedArray(),
        )
    }

    override fun markPromoted(pending: PendingArchive) {
        casUpdate(
            "UPDATE pending SET phase=? WHERE scope_hash=? AND archive_id=? AND chain_id=? AND sequence=? AND phase=?",
            (listOf<Any?>(PendingPhase.PROMOTED.name) + identityArgs(pending).asList() + PendingPhase.PREPARED.name).toTypedArray(),
        )
    }

    override fun markSidecarDurable(pending: PendingArchive, sidecarPath: String) {
        casUpdate(
            "UPDATE pending SET sidecar_path=?,phase=? WHERE scope_hash=? AND archive_id=? AND chain_id=? AND sequence=? AND phase=?",
            (listOf<Any?>(sidecarPath, PendingPhase.SIDECAR_DURABLE.name) + identityArgs(pending).asList() + PendingPhase.PROMOTED.name).toTypedArray(),
        )
    }

    override fun commit(
        pending: PendingArchive,
        scopeJson: String,
        nextToken: SecretChangesToken,
        nextTokenReceivedEpochSecond: Long,
        nextTokenReceivedNano: Int,
        mutations: Sequence<IdentityMutation>,
    ) {
        db.beginTransaction()
        try {
            verifyPending(pending, PendingPhase.SIDECAR_DURABLE)
            verifyExpectedChain(pending)
            // A sequence-1 commit replaces the scope's chain. Clear the prior chain's identities
            // in the same transaction before applying the base snapshot and catch-up journal.
            if (pending.sequence == 1L) {
                db.execSQL("DELETE FROM identities WHERE scope_hash=?", arrayOf(pending.scopeHash))
            }
            mutations.forEach { mutation ->
                when (mutation) {
                    is IdentityMutation.Upsert -> db.execSQL(
                        "INSERT OR REPLACE INTO identities(scope_hash,record_id,type_key,wire_type,origin,record_hash) VALUES(?,?,?,?,?,?)",
                        arrayOf(pending.scopeHash, mutation.identity.nativeRecordId, mutation.identity.typeKey, mutation.identity.wireType, mutation.identity.dataOriginPackageName, mutation.identity.lastKnownRecordHash),
                    )
                    is IdentityMutation.Delete -> db.execSQL(
                        "DELETE FROM identities WHERE scope_hash=? AND record_id=?", arrayOf(pending.scopeHash, mutation.nativeRecordId),
                    )
                }
            }
            val encrypted = cipher.encrypt(nextToken)
            db.execSQL(
                "UPDATE chain_state SET scope_json=?,chain_id=?,sequence=?,previous_hash=?,token=?,token_sec=?,token_nano=?,before_base=0 WHERE scope_hash=?",
                arrayOf(scopeJson, pending.chainId, pending.sequence, pending.logicalHash, encrypted,
                    nextTokenReceivedEpochSecond, nextTokenReceivedNano, pending.scopeHash),
            )
            if (changedRows() == 0) {
                db.execSQL(
                    "INSERT INTO chain_state(scope_hash,scope_json,chain_id,sequence,previous_hash,token,token_sec,token_nano,before_base) VALUES(?,?,?,?,?,?,?,?,0)",
                    arrayOf(pending.scopeHash, scopeJson, pending.chainId, pending.sequence, pending.logicalHash, encrypted,
                        nextTokenReceivedEpochSecond, nextTokenReceivedNano),
                )
            }
            casDelete(pending, PendingPhase.SIDECAR_DURABLE)
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    override fun discardPending(pending: PendingArchive) {
        db.execSQL(
            "DELETE FROM pending WHERE scope_hash=? AND archive_id=? AND chain_id=? AND sequence=?",
            identityArgs(pending),
        )
        if (changedRows() != 1) throw RawChangesStateConflictException()
    }

    private fun verifyExpectedChain(pending: PendingArchive) {
        val actual = load(pending.scopeHash)
        val matches = if (pending.expectedChainId == null && pending.expectedSequence == null && pending.expectedLogicalHash == null) {
            actual == null
        } else {
            actual != null && actual.chainId == pending.expectedChainId && actual.sequence == pending.expectedSequence &&
                actual.previousLogicalHash == pending.expectedLogicalHash
        }
        if (!matches) throw RawChangesStateConflictException()
    }

    private fun verifyPending(pending: PendingArchive, phase: PendingPhase) {
        db.rawQuery(
            "SELECT phase FROM pending WHERE scope_hash=? AND archive_id=? AND chain_id=? AND sequence=?",
            identityArgs(pending).map { it.toString() }.toTypedArray(),
        ).use { cursor ->
            if (!cursor.moveToFirst() || cursor.getString(0) != phase.name) throw RawChangesStateConflictException()
        }
    }

    private fun casUpdate(sql: String, args: Array<Any?>) {
        db.execSQL(sql, args)
        if (changedRows() != 1) throw RawChangesStateConflictException()
    }

    private fun casDelete(pending: PendingArchive, phase: PendingPhase) {
        db.execSQL(
            "DELETE FROM pending WHERE scope_hash=? AND archive_id=? AND chain_id=? AND sequence=? AND phase=?",
            (identityArgs(pending).asList() + phase.name).toTypedArray(),
        )
        if (changedRows() != 1) throw RawChangesStateConflictException()
    }

    private fun changedRows(): Int = db.rawQuery("SELECT changes()", null).use { cursor ->
        check(cursor.moveToFirst())
        cursor.getInt(0)
    }

    private fun identityArgs(pending: PendingArchive): Array<Any?> =
        arrayOf(pending.scopeHash, pending.archiveId, pending.chainId, pending.sequence)

    private fun android.database.Cursor.pending(scopeHash: String, offset: Int = 0): PendingArchive = PendingArchive(
        scopeHash = scopeHash,
        archiveId = getString(offset),
        chainId = getString(offset + 1),
        sequence = getLong(offset + 2),
        previousLogicalHash = getString(offset + 3),
        expectedChainId = getString(offset + 4),
        expectedSequence = if (isNull(offset + 5)) null else getLong(offset + 5),
        expectedLogicalHash = getString(offset + 6),
        createdEpochSecond = getLong(offset + 7),
        createdNano = getInt(offset + 8),
        workDatabasePath = getString(offset + 9),
        artifactPath = getString(offset + 10),
        logicalHash = getString(offset + 11),
        artifactHash = getString(offset + 12),
        sidecarPath = getString(offset + 13),
        phase = PendingPhase.valueOf(getString(offset + 14)),
        tokenGeneratedAtEpochSecond = getLong(offset + 15),
        tokenGeneratedAtNano = getInt(offset + 16),
        tokenGeneratedBeforeBase = getInt(offset + 17) != 0,
    )

    private fun SQLiteDatabase.ensureColumn(table: String, column: String, declaration: String) {
        val exists = rawQuery("PRAGMA table_info($table)", null).use { cursor ->
            val name = cursor.getColumnIndexOrThrow("name")
            var found = false
            while (cursor.moveToNext()) if (cursor.getString(name) == column) found = true
            found
        }
        if (!exists) execSQL("ALTER TABLE $table ADD COLUMN $column $declaration")
    }

    override fun close() = db.close()
}

internal interface RawChangesMutableIndex : RawBaseSnapshotIndex, Closeable {
    fun lookup(nativeRecordId: String): RawNativeIdentity?
    fun upsert(record: com.healthmd.rawexport.RawRecord)
    fun delete(nativeRecordId: String): RawNativeIdentity?
    fun mutations(): Sequence<IdentityMutation>
}

/** Per-run disk index: bounded lookup plus an ordered mutation journal; never loads the identity set. */
internal class RawChangesRunIndex(
    file: File,
    private val scopeHash: String,
    private val committedLookup: (String, String) -> RawNativeIdentity?,
) : RawChangesMutableIndex {
    private val db = SQLiteDatabase.openOrCreateDatabase(file, null).apply {
        configureDurableJournal()
        execSQL("CREATE TABLE IF NOT EXISTS current(record_id TEXT PRIMARY KEY,type_key TEXT NOT NULL,wire_type TEXT NOT NULL,origin TEXT NOT NULL,record_hash TEXT NOT NULL)")
        execSQL("CREATE TABLE IF NOT EXISTS deleted(record_id TEXT PRIMARY KEY,type_key TEXT,wire_type TEXT,origin TEXT,record_hash TEXT)")
        execSQL("CREATE TABLE IF NOT EXISTS mutations(ordinal INTEGER PRIMARY KEY AUTOINCREMENT,record_id TEXT NOT NULL,op TEXT NOT NULL,type_key TEXT,wire_type TEXT,origin TEXT,record_hash TEXT)")
    }

    override fun record(record: com.healthmd.rawexport.RawRecord) = upsert(record)

    override fun lookup(nativeRecordId: String): RawNativeIdentity? = db.rawQuery(
        "SELECT type_key,wire_type,origin,record_hash FROM current WHERE record_id=?", arrayOf(nativeRecordId),
    ).use { cursor ->
        if (cursor.moveToFirst()) {
            RawNativeIdentity(nativeRecordId, cursor.getString(0), cursor.getString(1), cursor.getString(2), cursor.getString(3))
        } else {
            db.rawQuery(
                "SELECT type_key,wire_type,origin,record_hash FROM deleted WHERE record_id=?",
                arrayOf(nativeRecordId),
            ).use { deleted ->
                if (!deleted.moveToFirst()) committedLookup(scopeHash, nativeRecordId)
                else if (deleted.isNull(0)) null
                else RawNativeIdentity(nativeRecordId, deleted.getString(0), deleted.getString(1), deleted.getString(2), deleted.getString(3))
            }
        }
    }

    override fun upsert(record: com.healthmd.rawexport.RawRecord) {
        val metadata = requireNotNull(record.metadata) { "Health Connect changed records require native metadata." }
        require(metadata.id.isNotBlank()) { "Health Connect changed record ID is empty." }
        val identity = RawNativeIdentity(metadata.id, record.wireType, record.wireType, metadata.dataOriginPackageName, record.hash)
        db.execSQL("INSERT OR REPLACE INTO current(record_id,type_key,wire_type,origin,record_hash) VALUES(?,?,?,?,?)",
            arrayOf(identity.nativeRecordId, identity.typeKey, identity.wireType, identity.dataOriginPackageName, identity.lastKnownRecordHash))
        db.execSQL("DELETE FROM deleted WHERE record_id=?", arrayOf(identity.nativeRecordId))
        db.execSQL("INSERT INTO mutations(record_id,op,type_key,wire_type,origin,record_hash) VALUES(?,'U',?,?,?,?)",
            arrayOf(identity.nativeRecordId, identity.typeKey, identity.wireType, identity.dataOriginPackageName, identity.lastKnownRecordHash))
    }

    override fun delete(nativeRecordId: String): RawNativeIdentity? {
        val known = lookup(nativeRecordId)
        db.execSQL("DELETE FROM current WHERE record_id=?", arrayOf(nativeRecordId))
        db.execSQL(
            "INSERT OR REPLACE INTO deleted(record_id,type_key,wire_type,origin,record_hash) VALUES(?,?,?,?,?)",
            arrayOf(nativeRecordId, known?.typeKey, known?.wireType, known?.dataOriginPackageName, known?.lastKnownRecordHash),
        )
        db.execSQL("INSERT INTO mutations(record_id,op) VALUES(?,'D')", arrayOf(nativeRecordId))
        return known
    }

    override fun mutations(): Sequence<IdentityMutation> = sequence {
        db.rawQuery("SELECT record_id,op,type_key,wire_type,origin,record_hash FROM mutations ORDER BY ordinal", null).use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getString(1) == "D") yield(IdentityMutation.Delete(cursor.getString(0)))
                else yield(IdentityMutation.Upsert(RawNativeIdentity(cursor.getString(0), cursor.getString(2), cursor.getString(3), cursor.getString(4), cursor.getString(5))))
            }
        }
    }

    override fun close() = db.close()
}
