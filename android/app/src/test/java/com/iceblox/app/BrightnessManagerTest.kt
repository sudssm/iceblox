package com.iceblox.app

import com.iceblox.app.camera.BrightnessManager
import kotlinx.coroutines.test.TestScope
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class BrightnessManagerTest {

    @Test
    fun initialState() {
        val manager = BrightnessManager()
        assertFalse(manager.isDimmed)
        assertNull(manager.savedBrightness)
    }

    @Test
    fun dimWithNullActivityIsNoOp() {
        val manager = BrightnessManager()
        manager.dim(null)
        assertFalse(manager.isDimmed)
        assertNull(manager.savedBrightness)
    }

    @Test
    fun restoreWithNullActivityIsNoOp() {
        val manager = BrightnessManager()
        manager.restore(null)
        assertFalse(manager.isDimmed)
    }

    @Test
    fun teardownWithNullActivityClearsState() {
        val manager = BrightnessManager()
        manager.teardown(null)
        assertFalse(manager.isDimmed)
        assertNull(manager.savedBrightness)
    }

    @Test
    fun restoreWithoutDimIsNoOp() {
        val manager = BrightnessManager()
        manager.restore(null)
        assertFalse(manager.isDimmed)
        assertNull(manager.savedBrightness)
    }

    @Test
    fun temporarilyRestoreWithNullActivityIsNoOp() {
        val manager = BrightnessManager()
        manager.temporarilyRestore(null, TestScope())
        assertFalse(manager.isDimmed)
    }

    @Test
    fun multipleTeardownIsIdempotent() {
        val manager = BrightnessManager()
        manager.teardown(null)
        manager.teardown(null)
        assertFalse(manager.isDimmed)
        assertNull(manager.savedBrightness)
    }
}
