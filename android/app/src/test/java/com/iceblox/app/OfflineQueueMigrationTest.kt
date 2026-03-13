package com.iceblox.app

import android.database.sqlite.SQLiteDatabase
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class OfflineQueueMigrationTest {

    private lateinit var dbFile: File
    private lateinit var db: SQLiteDatabase

    @Before
    fun setUp() {
        dbFile = File.createTempFile("test_offline_queue", ".db")
    }

    @After
    fun tearDown() {
        if (::db.isInitialized && db.isOpen) db.close()
        dbFile.delete()
    }

    @Test
    fun migration1to2AddsSessionIdColumn() {
        db = createV1Database()
        db.execSQL(
            "INSERT INTO offline_queue (plate_hash, timestamp, latitude, longitude) VALUES ('hash1', 1000, 1.0, 2.0)"
        )
        applyMigration1to2(db)

        val cursor = db.rawQuery("SELECT session_id FROM offline_queue", null)
        assertTrue(cursor.moveToFirst())
        assertEquals("", cursor.getString(0))
        cursor.close()
    }

    @Test
    fun migration2to3AddsSubstitutionsColumn() {
        db = createV1Database()
        applyMigration1to2(db)
        db.execSQL(
            "INSERT INTO offline_queue (plate_hash, timestamp, latitude, longitude, session_id) VALUES ('hash1', 1000, 1.0, 2.0, 'sess1')"
        )
        applyMigration2to3(db)

        val cursor = db.rawQuery("SELECT substitutions FROM offline_queue", null)
        assertTrue(cursor.moveToFirst())
        assertEquals(0, cursor.getInt(0))
        cursor.close()
    }

    @Test
    fun migration3to4AddsConfidenceAndIsPrimaryColumns() {
        db = createV1Database()
        applyMigration1to2(db)
        applyMigration2to3(db)
        db.execSQL(
            "INSERT INTO offline_queue (plate_hash, timestamp, latitude, longitude, session_id, substitutions) VALUES ('hash1', 1000, 1.0, 2.0, 'sess1', 0)"
        )
        applyMigration3to4(db)

        val cursor = db.rawQuery("SELECT confidence, is_primary FROM offline_queue", null)
        assertTrue(cursor.moveToFirst())
        assertEquals(0.0, cursor.getDouble(0), 0.001)
        assertEquals(0, cursor.getInt(1))
        cursor.close()
    }

    @Test
    fun migration4to5DropsSubstitutionsColumn() {
        db = createV1Database()
        applyMigration1to2(db)
        applyMigration2to3(db)
        applyMigration3to4(db)
        db.execSQL(
            "INSERT INTO offline_queue (plate_hash, timestamp, latitude, longitude, session_id, substitutions, confidence, is_primary) VALUES ('hash1', 1000, 1.0, 2.0, 'sess1', 3, 0.95, 1)"
        )
        applyMigration4to5(db)

        val columns = getColumnNames(db)
        assertFalse(columns.contains("substitutions"))
        assertTrue(columns.contains("confidence"))
        assertTrue(columns.contains("is_primary"))
        assertTrue(columns.contains("plate_hash"))
        assertTrue(columns.contains("session_id"))

        val cursor = db.rawQuery("SELECT plate_hash, confidence, is_primary FROM offline_queue", null)
        assertTrue(cursor.moveToFirst())
        assertEquals("hash1", cursor.getString(0))
        assertEquals(0.95, cursor.getDouble(1), 0.001)
        assertEquals(1, cursor.getInt(2))
        cursor.close()
    }

    @Test
    fun fullMigration1to5PreservesData() {
        db = createV1Database()
        db.execSQL(
            "INSERT INTO offline_queue (plate_hash, timestamp, latitude, longitude) VALUES ('hash1', 1000, 40.7, -74.0)"
        )
        applyMigration1to2(db)
        applyMigration2to3(db)
        applyMigration3to4(db)
        applyMigration4to5(db)

        val cursor = db.rawQuery(
            "SELECT plate_hash, timestamp, latitude, longitude, session_id, confidence, is_primary FROM offline_queue",
            null
        )
        assertTrue(cursor.moveToFirst())
        assertEquals("hash1", cursor.getString(0))
        assertEquals(1000L, cursor.getLong(1))
        assertEquals(40.7, cursor.getDouble(2), 0.001)
        assertEquals(-74.0, cursor.getDouble(3), 0.001)
        assertEquals("", cursor.getString(4))
        assertEquals(0.0, cursor.getDouble(5), 0.001)
        assertEquals(0, cursor.getInt(6))
        cursor.close()

        val columns = getColumnNames(db)
        assertFalse(columns.contains("substitutions"))
    }

    @Test
    fun entityColumnsMatchLatestSchema() {
        db = createV1Database()
        applyMigration1to2(db)
        applyMigration2to3(db)
        applyMigration3to4(db)
        applyMigration4to5(db)

        val dbColumns = getColumnNames(db)
        val entityColumns = setOf(
            "id",
            "plate_hash",
            "timestamp",
            "latitude",
            "longitude",
            "session_id",
            "confidence",
            "is_primary"
        )

        assertEquals(entityColumns, dbColumns)
    }

    private fun createV1Database(): SQLiteDatabase {
        val db = SQLiteDatabase.openOrCreateDatabase(dbFile, null)
        db.execSQL(
            """
            CREATE TABLE offline_queue (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                plate_hash TEXT NOT NULL,
                timestamp INTEGER NOT NULL,
                latitude REAL,
                longitude REAL
            )
            """.trimIndent()
        )
        return db
    }

    private fun applyMigration1to2(db: SQLiteDatabase) {
        db.execSQL("ALTER TABLE offline_queue ADD COLUMN session_id TEXT NOT NULL DEFAULT ''")
    }

    private fun applyMigration2to3(db: SQLiteDatabase) {
        db.execSQL("ALTER TABLE offline_queue ADD COLUMN substitutions INTEGER NOT NULL DEFAULT 0")
    }

    private fun applyMigration3to4(db: SQLiteDatabase) {
        db.execSQL("ALTER TABLE offline_queue ADD COLUMN confidence REAL NOT NULL DEFAULT 0")
        db.execSQL("ALTER TABLE offline_queue ADD COLUMN is_primary INTEGER NOT NULL DEFAULT 0")
    }

    private fun applyMigration4to5(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE offline_queue_new (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                plate_hash TEXT NOT NULL,
                timestamp INTEGER NOT NULL,
                latitude REAL,
                longitude REAL,
                session_id TEXT NOT NULL DEFAULT '',
                confidence REAL NOT NULL DEFAULT 0,
                is_primary INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent()
        )
        db.execSQL(
            """
            INSERT INTO offline_queue_new (id, plate_hash, timestamp, latitude, longitude, session_id, confidence, is_primary)
            SELECT id, plate_hash, timestamp, latitude, longitude, session_id, confidence, is_primary FROM offline_queue
            """.trimIndent()
        )
        db.execSQL("DROP TABLE offline_queue")
        db.execSQL("ALTER TABLE offline_queue_new RENAME TO offline_queue")
    }

    private fun getColumnNames(db: SQLiteDatabase): Set<String> {
        val cursor = db.rawQuery("PRAGMA table_info(offline_queue)", null)
        val columns = mutableSetOf<String>()
        while (cursor.moveToNext()) {
            columns.add(cursor.getString(cursor.getColumnIndexOrThrow("name")))
        }
        cursor.close()
        return columns
    }
}
