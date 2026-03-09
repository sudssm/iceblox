package com.iceblox.app.persistence

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query

@Dao
interface OfflineQueueDao {
    @Insert
    suspend fun insert(entry: OfflineQueueEntry)

    @Query("SELECT * FROM offline_queue ORDER BY id ASC LIMIT :limit")
    suspend fun dequeue(limit: Int): List<OfflineQueueEntry>

    @Query("DELETE FROM offline_queue WHERE id IN (:ids)")
    suspend fun deleteByIds(ids: List<Long>)

    @Query("SELECT COUNT(*) FROM offline_queue")
    suspend fun count(): Int

    @Query("SELECT COUNT(*) FROM offline_queue WHERE session_id = :sessionId")
    suspend fun countBySessionId(sessionId: String): Int

    @Query("SELECT COUNT(*) FROM offline_queue WHERE session_id = :sessionId AND substitutions = 0")
    suspend fun pendingPlateCount(sessionId: String): Int

    @Query("DELETE FROM offline_queue WHERE id IN (SELECT id FROM offline_queue ORDER BY id ASC LIMIT :count)")
    suspend fun deleteOldest(count: Int)

    @Query("DELETE FROM offline_queue")
    suspend fun deleteAll()

    @Query("DELETE FROM offline_queue WHERE timestamp < :cutoffMs")
    suspend fun deleteOlderThan(cutoffMs: Long)
}
