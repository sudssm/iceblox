package com.iceblox.app

import android.app.Application
import com.iceblox.app.motion.MotionState
import com.iceblox.app.motion.MotionStateManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

@RunWith(RobolectricTestRunner::class)
class MotionStateManagerTest {

    private lateinit var manager: MotionStateManager

    @Before
    fun setUp() {
        val context = RuntimeEnvironment.getApplication()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        manager = MotionStateManager(context, scope)
    }

    @Test
    fun initialStateIsUnknownAndNotPaused() {
        assertEquals(MotionState.UNKNOWN, manager.motionState.value)
        assertFalse(manager.isMotionPaused.value)
    }

    @Test
    fun manualResumeClearsPausedState() {
        manager.manualResume()
        assertFalse(manager.isMotionPaused.value)
    }

    @Test
    fun stopMonitoringResetsAllState() {
        manager.stopMonitoring()
        assertEquals(MotionState.UNKNOWN, manager.motionState.value)
        assertFalse(manager.isMotionPaused.value)
    }
}
