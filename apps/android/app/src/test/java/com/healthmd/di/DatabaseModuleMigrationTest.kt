package com.healthmd.di

import androidx.sqlite.db.SupportSQLiteDatabase
import com.google.common.truth.Truth.assertThat
import io.mockk.mockk
import io.mockk.verify
import org.junit.Test

class DatabaseModuleMigrationTest {
    @Test
    fun `history migration 6 to 7 adds nullable Drive recovery identity without rewriting rows`() {
        val database = mockk<SupportSQLiteDatabase>(relaxed = true)

        DatabaseModule.MIGRATION_6_7.migrate(database)

        assertThat(DatabaseModule.MIGRATION_6_7.startVersion).isEqualTo(6)
        assertThat(DatabaseModule.MIGRATION_6_7.endVersion).isEqualTo(7)
        verify(exactly = 1) {
            database.execSQL("ALTER TABLE export_history ADD COLUMN driveOperationId TEXT")
        }
    }
}
