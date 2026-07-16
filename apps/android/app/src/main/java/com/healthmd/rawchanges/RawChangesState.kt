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

internal interface RawChangesStateStore {
    fun load(scopeHash: String): RawChangesChainState?
    fun identity(scopeHash: String, nativeRecordId: String): RawNativeIdentity?
    fun pending(scopeHash: String): PendingArchive?
    fun beginPending(pending: PendingArchive, initialToken: SecretChangesToken)
    fun prepared(scopeHash: String, artifactPath: String, logicalHash: String, artifactHash: String)
    fun markPromoted(scopeHash: String)
    fun markSidecarDurable(scopeHash: String, sidecarPath: String)
    fun commit(pending: PendingArchive, scopeJson: String, nextToken: SecretChangesToken, mutations: Sequence<IdentityMutation>)
    fun discardPending(scopeHash: String)
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

/** SQLite is opened directly under noBackupFilesDir; token and identity mutations share one commit. */
internal class SQLiteRawChangesStateStore(
    context: Context,
    private val cipher: InstallationBoundTokenCipher = InstallationBoundTokenCipher(),
) : RawChangesStateStore, Closeable {
    private val root = File(context.noBackupFilesDir, "raw-changes").apply { mkdirs() }
    private val db = SQLiteDatabase.openOrCreateDatabase(File(root, "state.db"), null).apply {
        execSQL("PRAGMA journal_mode=WAL")
        execSQL("PRAGMA synchronous=FULL")
        execSQL("CREATE TABLE IF NOT EXISTS chain_state(scope_hash TEXT PRIMARY KEY, scope_json TEXT NOT NULL, chain_id TEXT NOT NULL, sequence INTEGER NOT NULL, previous_hash TEXT, token BLOB NOT NULL, token_sec INTEGER NOT NULL, token_nano INTEGER NOT NULL, before_base INTEGER NOT NULL)")
        execSQL("CREATE TABLE IF NOT EXISTS identities(scope_hash TEXT NOT NULL, record_id TEXT NOT NULL, type_key TEXT NOT NULL, wire_type TEXT NOT NULL, origin TEXT NOT NULL, record_hash TEXT NOT NULL, PRIMARY KEY(scope_hash, record_id))")
        execSQL("CREATE INDEX IF NOT EXISTS identities_scope_id ON identities(scope_hash, record_id)")
        execSQL("CREATE TABLE IF NOT EXISTS pending(scope_hash TEXT PRIMARY KEY, archive_id TEXT NOT NULL, chain_id TEXT NOT NULL, sequence INTEGER NOT NULL, previous_hash TEXT, created_sec INTEGER NOT NULL, created_nano INTEGER NOT NULL, work_db TEXT NOT NULL, artifact_path TEXT, logical_hash TEXT, artifact_hash TEXT, sidecar_path TEXT, initial_token BLOB NOT NULL, phase TEXT NOT NULL, token_sec INTEGER NOT NULL, token_nano INTEGER NOT NULL, before_base INTEGER NOT NULL)")
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
        "SELECT archive_id,chain_id,sequence,previous_hash,created_sec,created_nano,work_db,artifact_path,logical_hash,artifact_hash,sidecar_path,phase,token_sec,token_nano,before_base FROM pending WHERE scope_hash=?",
        arrayOf(scopeHash),
    ).use { cursor ->
        if (!cursor.moveToFirst()) null else PendingArchive(
            scopeHash, cursor.getString(0), cursor.getString(1), cursor.getLong(2), cursor.getString(3),
            cursor.getLong(4), cursor.getInt(5), cursor.getString(6), cursor.getString(7), cursor.getString(8),
            cursor.getString(9), cursor.getString(10), PendingPhase.valueOf(cursor.getString(11)),
            cursor.getLong(12), cursor.getInt(13), cursor.getInt(14) != 0,
        )
    }

    override fun beginPending(pending: PendingArchive, initialToken: SecretChangesToken) {
        db.execSQL(
            "INSERT OR REPLACE INTO pending(scope_hash,archive_id,chain_id,sequence,previous_hash,created_sec,created_nano,work_db,initial_token,phase,token_sec,token_nano,before_base) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",
            arrayOf(pending.scopeHash, pending.archiveId, pending.chainId, pending.sequence, pending.previousLogicalHash,
                pending.createdEpochSecond, pending.createdNano, pending.workDatabasePath, cipher.encrypt(initialToken), PendingPhase.READING.name,
                pending.tokenGeneratedAtEpochSecond, pending.tokenGeneratedAtNano, if (pending.tokenGeneratedBeforeBase) 1 else 0),
        )
    }

    override fun prepared(scopeHash: String, artifactPath: String, logicalHash: String, artifactHash: String) {
        // The next token remains memory-only until the final chain/index transaction.
        db.execSQL("UPDATE pending SET artifact_path=?,logical_hash=?,artifact_hash=?,phase=? WHERE scope_hash=?",
            arrayOf(artifactPath, logicalHash, artifactHash, PendingPhase.PREPARED.name, scopeHash))
    }

    override fun markPromoted(scopeHash: String) {
        db.execSQL("UPDATE pending SET phase=? WHERE scope_hash=?", arrayOf(PendingPhase.PROMOTED.name, scopeHash))
    }

    override fun markSidecarDurable(scopeHash: String, sidecarPath: String) {
        db.execSQL("UPDATE pending SET sidecar_path=?,phase=? WHERE scope_hash=?", arrayOf(sidecarPath, PendingPhase.SIDECAR_DURABLE.name, scopeHash))
    }

    override fun commit(
        pending: PendingArchive,
        scopeJson: String,
        nextToken: SecretChangesToken,
        mutations: Sequence<IdentityMutation>,
    ) {
        db.beginTransaction()
        try {
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
            db.execSQL(
                "INSERT OR REPLACE INTO chain_state(scope_hash,scope_json,chain_id,sequence,previous_hash,token,token_sec,token_nano,before_base) VALUES(?,?,?,?,?,?,?,?,?)",
                arrayOf(pending.scopeHash, scopeJson, pending.chainId, pending.sequence, pending.logicalHash, cipher.encrypt(nextToken),
                    pending.tokenGeneratedAtEpochSecond, pending.tokenGeneratedAtNano, if (pending.tokenGeneratedBeforeBase) 1 else 0),
            )
            db.execSQL("DELETE FROM pending WHERE scope_hash=?", arrayOf(pending.scopeHash))
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    override fun discardPending(scopeHash: String) {
        db.execSQL("DELETE FROM pending WHERE scope_hash=?", arrayOf(scopeHash))
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
        execSQL("PRAGMA journal_mode=WAL")
        execSQL("PRAGMA synchronous=FULL")
        execSQL("CREATE TABLE IF NOT EXISTS current(record_id TEXT PRIMARY KEY,type_key TEXT NOT NULL,wire_type TEXT NOT NULL,origin TEXT NOT NULL,record_hash TEXT NOT NULL)")
        execSQL("CREATE TABLE IF NOT EXISTS mutations(ordinal INTEGER PRIMARY KEY AUTOINCREMENT,record_id TEXT NOT NULL,op TEXT NOT NULL,type_key TEXT,wire_type TEXT,origin TEXT,record_hash TEXT)")
    }

    override fun record(record: com.healthmd.rawexport.RawRecord) = upsert(record)

    override fun lookup(nativeRecordId: String): RawNativeIdentity? = db.rawQuery(
        "SELECT type_key,wire_type,origin,record_hash FROM current WHERE record_id=?", arrayOf(nativeRecordId),
    ).use { cursor ->
        if (cursor.moveToFirst()) RawNativeIdentity(nativeRecordId, cursor.getString(0), cursor.getString(1), cursor.getString(2), cursor.getString(3))
        else committedLookup(scopeHash, nativeRecordId)
    }

    override fun upsert(record: com.healthmd.rawexport.RawRecord) {
        val metadata = requireNotNull(record.metadata) { "Health Connect changed records require native metadata." }
        require(metadata.id.isNotBlank()) { "Health Connect changed record ID is empty." }
        val identity = RawNativeIdentity(metadata.id, record.wireType, record.wireType, metadata.dataOriginPackageName, record.hash)
        db.execSQL("INSERT OR REPLACE INTO current(record_id,type_key,wire_type,origin,record_hash) VALUES(?,?,?,?,?)",
            arrayOf(identity.nativeRecordId, identity.typeKey, identity.wireType, identity.dataOriginPackageName, identity.lastKnownRecordHash))
        db.execSQL("INSERT INTO mutations(record_id,op,type_key,wire_type,origin,record_hash) VALUES(?,'U',?,?,?,?)",
            arrayOf(identity.nativeRecordId, identity.typeKey, identity.wireType, identity.dataOriginPackageName, identity.lastKnownRecordHash))
    }

    override fun delete(nativeRecordId: String): RawNativeIdentity? {
        val known = lookup(nativeRecordId)
        db.execSQL("DELETE FROM current WHERE record_id=?", arrayOf(nativeRecordId))
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
