package com.iceblox.app.persistence

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(entities = [OfflineQueueEntry::class], version = 5, exportSchema = false)
abstract class OfflineQueueDatabase : RoomDatabase() {
    abstract fun queueDao(): OfflineQueueDao

    companion object {
        @Volatile
        private var INSTANCE: OfflineQueueDatabase? = null

        private val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    "ALTER TABLE offline_queue ADD COLUMN session_id TEXT NOT NULL DEFAULT ''"
                )
            }
        }

        private val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    "ALTER TABLE offline_queue ADD COLUMN substitutions INTEGER NOT NULL DEFAULT 0"
                )
            }
        }

        private val MIGRATION_3_4 = object : Migration(3, 4) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    "ALTER TABLE offline_queue ADD COLUMN confidence REAL NOT NULL DEFAULT 0"
                )
                database.execSQL(
                    "ALTER TABLE offline_queue ADD COLUMN is_primary INTEGER NOT NULL DEFAULT 0"
                )
            }
        }

        private val MIGRATION_4_5 = object : Migration(4, 5) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    "ALTER TABLE offline_queue DROP COLUMN substitutions"
                )
            }
        }

        fun getInstance(context: Context): OfflineQueueDatabase = INSTANCE ?: synchronized(this) {
            INSTANCE ?: Room.databaseBuilder(
                context.applicationContext,
                OfflineQueueDatabase::class.java,
                "offline_queue.db"
            )
                .addMigrations(MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4, MIGRATION_4_5)
                .build()
                .also { INSTANCE = it }
        }
    }
}
