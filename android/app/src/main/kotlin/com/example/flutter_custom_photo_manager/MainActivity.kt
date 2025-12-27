package com.example.flutter_custom_photo_manager

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.flutterCustomPhotoManager/photoManager"
    
    // GalleryDataSources 인스턴스를 지연 초기화합니다.
    private val galleryDataSources by lazy { GalleryDataSources(this) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getImagePaths") {
                if (hasPermissions()) {
                    fetchImages(result)
                } else {
                    result.error("PERMISSION_DENIED", "Permissions not granted", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun hasPermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= 33) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun fetchImages(result: MethodChannel.Result) {
        // Main Dispatcher에서 코루틴을 시작하여 UI 스레드에서 result.success를 호출할 수 있게 합니다.
        CoroutineScope(Dispatchers.Main).launch {
            try {
                // 실제 데이터 로딩은 IO 스레드(GalleryDataSources 내부)에서 수행됩니다.
                val images = galleryDataSources.getImages()
                result.success(images)
            } catch (e: Exception) {
                result.error("QUERY_FAILED", e.message, null)
            }
        }
    }
}
