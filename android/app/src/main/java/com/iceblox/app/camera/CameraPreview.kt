package com.iceblox.app.camera

import android.os.Handler
import android.os.Looper
import androidx.camera.core.ImageAnalysis
import androidx.camera.view.PreviewView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import java.util.concurrent.Executors

@Composable
fun CameraPreview(
    modifier: Modifier = Modifier,
    analyzer: ImageAnalysis.Analyzer? = null,
    zoomController: ZoomController? = null
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val analysisExecutor = remember { Executors.newSingleThreadExecutor() }
    val previewViewRef = remember { arrayOfNulls<PreviewView>(1) }
    val mainHandler = remember { Handler(Looper.getMainLooper()) }

    DisposableEffect(lifecycleOwner, analyzer) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                val previewView = previewViewRef[0] ?: return@LifecycleEventObserver
                // Post to ensure this runs after BackgroundCaptureService.onDestroy() unbindAll()
                mainHandler.post {
                    CameraCaptureBinder.bindPreviewAndAnalysis(
                        context = context,
                        lifecycleOwner = lifecycleOwner,
                        previewView = previewView,
                        analyzer = analyzer,
                        analysisExecutor = analysisExecutor,
                        onCameraBound = { camera ->
                            zoomController?.setCamera(camera)
                        }
                    )
                }
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)

        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            CameraCaptureBinder.unbindAll(context)
            analysisExecutor.shutdown()
        }
    }

    AndroidView(
        factory = { ctx ->
            PreviewView(ctx).also { previewView ->
                previewView.implementationMode = PreviewView.ImplementationMode.PERFORMANCE
                previewView.scaleType = PreviewView.ScaleType.FILL_CENTER
                previewViewRef[0] = previewView

                CameraCaptureBinder.bindPreviewAndAnalysis(
                    context = ctx,
                    lifecycleOwner = lifecycleOwner,
                    previewView = previewView,
                    analyzer = analyzer,
                    analysisExecutor = analysisExecutor,
                    onCameraBound = { camera ->
                        zoomController?.setCamera(camera)
                    }
                )
            }
        },
        modifier = modifier
    )
}
