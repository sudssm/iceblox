package com.iceblox.app.persistence

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "offline_queue")
data class OfflineQueueEntry(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    @ColumnInfo(name = "plate_hash") val plateHash: String,
    @ColumnInfo(name = "timestamp") val timestamp: Long,
    @ColumnInfo(name = "latitude") val latitude: Double?,
    @ColumnInfo(name = "longitude") val longitude: Double?,
    @ColumnInfo(name = "session_id", defaultValue = "") val sessionId: String,
    @ColumnInfo(name = "confidence", defaultValue = "0") val confidence: Float = 0f,
    @ColumnInfo(name = "is_primary", defaultValue = "0") val isPrimary: Boolean = false
)
