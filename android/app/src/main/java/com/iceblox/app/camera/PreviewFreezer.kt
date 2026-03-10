package com.iceblox.app.camera

import android.graphics.Bitmap
import com.iceblox.app.debug.DebugLog
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

class PreviewFreezer {
    private val _freezeState = MutableStateFlow<FreezeState>(FreezeState.Unfrozen)
    val freezeState: StateFlow<FreezeState> = _freezeState

    val isFrozen: Boolean get() = _freezeState.value !is FreezeState.Unfrozen

    fun freeze(bitmap: Bitmap?, debugMode: Boolean) {
        DebugLog.d(TAG, "freeze: debugMode=$debugMode, hasOverlayBitmap=${bitmap != null && !debugMode}")
        _freezeState.value = FreezeState.Frozen(
            overlayBitmap = if (!debugMode) bitmap else null,
            showIndicator = true
        )
    }

    fun unfreeze() {
        DebugLog.d(TAG, "unfreeze")
        _freezeState.value = FreezeState.Unfrozen
    }

    sealed class FreezeState {
        object Unfrozen : FreezeState()
        data class Frozen(
            val overlayBitmap: Bitmap?,
            val showIndicator: Boolean
        ) : FreezeState()
    }

    companion object {
        private const val TAG = "PreviewFreezer"
    }
}
