package com.iceblox.app.camera

import android.content.Context
import android.util.Size
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.iceblox.app.debug.DebugLog
import java.util.concurrent.Executor

object CameraCaptureBinder {
    private const val TAG = "CameraCaptureBinder"

    @Volatile
    var camera: Camera? = null
        private set

    fun bindPreviewAndAnalysis(
        context: Context,
        lifecycleOwner: LifecycleOwner,
        previewView: PreviewView,
        analyzer: ImageAnalysis.Analyzer?,
        analysisExecutor: Executor
    ) {
        withCameraProvider(context) { cameraProvider ->
            val preview = Preview.Builder()
                .setResolutionSelector(defaultResolutionSelector())
                .build()
                .also { it.surfaceProvider = previewView.surfaceProvider }

            val imageAnalysis = buildImageAnalysis(analyzer, analysisExecutor)

            cameraProvider.unbindAll()
            camera = cameraProvider.bindToLifecycle(
                lifecycleOwner,
                CameraSelector.DEFAULT_BACK_CAMERA,
                preview,
                imageAnalysis
            )
            DebugLog.d(TAG, "Preview + analysis bound")
        }
    }

    fun bindAnalysisOnly(
        context: Context,
        lifecycleOwner: LifecycleOwner,
        analyzer: ImageAnalysis.Analyzer,
        analysisExecutor: Executor
    ) {
        withCameraProvider(context) { cameraProvider ->
            val imageAnalysis = buildImageAnalysis(analyzer, analysisExecutor)

            cameraProvider.unbindAll()
            cameraProvider.bindToLifecycle(
                lifecycleOwner,
                CameraSelector.DEFAULT_BACK_CAMERA,
                imageAnalysis
            )
            DebugLog.d(TAG, "Background analysis bound")
        }
    }

    fun unbindAll(context: Context) {
        withCameraProvider(context) { cameraProvider ->
            cameraProvider.unbindAll()
            DebugLog.d(TAG, "Camera unbound")
        }
    }

    private fun buildImageAnalysis(analyzer: ImageAnalysis.Analyzer?, analysisExecutor: Executor): ImageAnalysis =
        ImageAnalysis.Builder()
            .setResolutionSelector(defaultResolutionSelector())
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()
            .also { useCase ->
                if (analyzer != null) {
                    useCase.setAnalyzer(analysisExecutor, analyzer)
                }
            }

    private fun defaultResolutionSelector(): ResolutionSelector = ResolutionSelector.Builder()
        .setResolutionStrategy(
            ResolutionStrategy(
                Size(1920, 1080),
                ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
            )
        )
        .build()

    private fun withCameraProvider(context: Context, action: (ProcessCameraProvider) -> Unit) {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener(
            {
                try {
                    action(cameraProviderFuture.get())
                } catch (e: Exception) {
                    DebugLog.e(TAG, "Camera bind failed", e)
                }
            },
            ContextCompat.getMainExecutor(context)
        )
    }
}
