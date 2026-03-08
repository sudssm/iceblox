package com.iceblox.app.debug

import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

enum class LogLevel { DEBUG, WARNING, ERROR }

data class LogEntry(
    val timestamp: Long = System.currentTimeMillis(),
    val level: LogLevel,
    val tag: String,
    val message: String
)

object DebugLog {
    private const val MAX_ENTRIES = 50

    private val buffer = ArrayDeque<LogEntry>(MAX_ENTRIES)
    private val _entries = MutableStateFlow<List<LogEntry>>(emptyList())
    val entries: StateFlow<List<LogEntry>> = _entries

    fun d(tag: String, message: String) {
        Log.d(tag, message)
        add(LogEntry(level = LogLevel.DEBUG, tag = tag, message = message))
    }

    fun w(tag: String, message: String) {
        Log.w(tag, message)
        add(LogEntry(level = LogLevel.WARNING, tag = tag, message = message))
    }

    fun e(tag: String, message: String) {
        Log.e(tag, message)
        add(LogEntry(level = LogLevel.ERROR, tag = tag, message = message))
    }

    fun d(tag: String, message: String, tr: Throwable) {
        Log.d(tag, message, tr)
        add(LogEntry(level = LogLevel.DEBUG, tag = tag, message = "$message: ${tr.message}"))
    }

    fun w(tag: String, message: String, tr: Throwable) {
        Log.w(tag, message, tr)
        add(LogEntry(level = LogLevel.WARNING, tag = tag, message = "$message: ${tr.message}"))
    }

    fun e(tag: String, message: String, tr: Throwable) {
        Log.e(tag, message, tr)
        add(LogEntry(level = LogLevel.ERROR, tag = tag, message = "$message: ${tr.message}"))
    }

    @Synchronized
    private fun add(entry: LogEntry) {
        if (buffer.size >= MAX_ENTRIES) buffer.removeFirst()
        buffer.addLast(entry)
        _entries.value = buffer.toList()
    }
}
