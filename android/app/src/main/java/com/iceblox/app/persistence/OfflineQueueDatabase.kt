package com.iceblox.app.persistence

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(entities = [OfflineQueueEntry::class], version = 3, exportSchema = false)
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

        fun getInstance(context: Context): OfflineQueueDatabase = INSTANCE ?: synchronized(this) {
            INSTANCE ?: Room.databaseBuilder(
                context.applicationContext,
                OfflineQueueDatabase::class.java,
                "offline_queue.db"
            )
                .addMigrations(MIGRATION_1_2, MIGRATION_2_3)
                .build()
                .also { INSTANCE = it }
        }
    }
}
