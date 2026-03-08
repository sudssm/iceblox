package com.iceblox.app.persistence

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(entities = [OfflineQueueEntry::class], version = 1, exportSchema = false)
abstract class OfflineQueueDatabase : RoomDatabase() {
    abstract fun queueDao(): OfflineQueueDao

    companion object {
        @Volatile
        private var INSTANCE: OfflineQueueDatabase? = null

        fun getInstance(context: Context): OfflineQueueDatabase = INSTANCE ?: synchronized(this) {
            INSTANCE ?: Room.databaseBuilder(
                context.applicationContext,
                OfflineQueueDatabase::class.java,
                "offline_queue.db"
            ).build().also { INSTANCE = it }
        }
    }
}
