package com.healthmd.di

import android.content.Context
import androidx.room.Room
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.sqlite.db.SupportSQLiteOpenHelper
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.history.ExportHistoryDatabase
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ExportHistoryMigrationTest {
    @Test
    fun `room opens a complete version 5 database and preserves legacy history`() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val databaseName = "history-migration-${System.nanoTime()}.db"
        val legacyHelper = FrameworkSQLiteOpenHelperFactory().create(
            SupportSQLiteOpenHelper.Configuration.builder(context)
                .name(databaseName)
                .callback(
                    object : SupportSQLiteOpenHelper.Callback(5) {
                        override fun onCreate(db: SupportSQLiteDatabase) {
                            db.execSQL(
                                "CREATE TABLE export_history (" +
                                    "id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
                                    "timestamp INTEGER NOT NULL, " +
                                    "source TEXT NOT NULL, " +
                                    "dateRangeStart TEXT NOT NULL, " +
                                    "dateRangeEnd TEXT NOT NULL, " +
                                    "successCount INTEGER NOT NULL, " +
                                    "totalCount INTEGER NOT NULL, " +
                                    "failureReason TEXT, " +
                                    "failedDateDetailsJson TEXT, " +
                                    "targetType TEXT NOT NULL, " +
                                    "targetLabel TEXT, " +
                                    "fileCount INTEGER NOT NULL, " +
                                    "warningSummary TEXT, " +
                                    "exportMode TEXT NOT NULL, " +
                                    "reconciliationKey TEXT)",
                            )
                            db.execSQL(
                                "CREATE UNIQUE INDEX index_export_history_reconciliationKey " +
                                    "ON export_history(reconciliationKey)",
                            )
                            db.execSQL(
                                "INSERT INTO export_history (" +
                                    "timestamp, source, dateRangeStart, dateRangeEnd, " +
                                    "successCount, totalCount, targetType, targetLabel, " +
                                    "fileCount, exportMode, reconciliationKey" +
                                    ") VALUES (" +
                                    "1000, 'SCHEDULED', '2026-07-24', '2026-07-25', " +
                                    "2, 2, 'DEVICE_FOLDER', 'Research Exports', " +
                                    "2, 'COMPATIBILITY', 'legacy-profile-run')",
                            )
                        }

                        override fun onUpgrade(
                            db: SupportSQLiteDatabase,
                            oldVersion: Int,
                            newVersion: Int,
                        ) = Unit
                    },
                )
                .build(),
        )

        try {
            legacyHelper.writableDatabase
            legacyHelper.close()

            val room = Room.databaseBuilder(
                context,
                ExportHistoryDatabase::class.java,
                databaseName,
            )
                .allowMainThreadQueries()
                .addMigrations(DatabaseModule.MIGRATION_5_6)
                .build()
            try {
                val migrated = room.openHelper.writableDatabase
                migrated.query(
                    "SELECT source, targetLabel, profileName FROM export_history",
                ).use { cursor ->
                    assertThat(cursor.moveToFirst()).isTrue()
                    assertThat(cursor.getString(0)).isEqualTo("SCHEDULED")
                    assertThat(cursor.getString(1)).isEqualTo("Research Exports")
                    assertThat(cursor.isNull(2)).isTrue()
                }
            } finally {
                room.close()
            }
        } finally {
            legacyHelper.close()
            context.deleteDatabase(databaseName)
        }
    }
}
