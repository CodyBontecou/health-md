package com.healthmd.di

import androidx.sqlite.db.SupportSQLiteDatabase
import com.google.common.truth.Truth.assertThat
import io.mockk.mockk
import io.mockk.verify
import org.junit.Test

class DatabaseModuleMigrationTest {
    @Test
    fun `history migration 5 to 6 adds nullable Drive recovery identity without rewriting rows`() {
        val database = mockk<SupportSQLiteDatabase>(relaxed = true)

        DatabaseModule.MIGRATION_5_6.migrate(database)

        assertThat(DatabaseModule.MIGRATION_5_6.startVersion).isEqualTo(5)
        assertThat(DatabaseModule.MIGRATION_5_6.endVersion).isEqualTo(6)
        verify(exactly = 1) {
            database.execSQL("ALTER TABLE export_history ADD COLUMN driveOperationId TEXT")
        }
    }
}
