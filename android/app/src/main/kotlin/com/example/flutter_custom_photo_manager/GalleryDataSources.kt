package com.example.flutter_custom_photo_manager

import android.content.Context
import android.provider.MediaStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class GalleryDataSources(private val context: Context) {
    
    // suspend 함수로 정의하여 호출자가 코루틴 스코프 내에서 호출하도록 강제하고,
    // 내부적으로는 IO 스레드를 사용하여 안전하게 실행합니다.
    suspend fun getImages(): List<String> = withContext(Dispatchers.IO) {
        val imagePaths = mutableListOf<String>()
        val projection = arrayOf(MediaStore.Images.Media.DATA, MediaStore.Images.Media.DATE_ADDED)
        val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC"

        try {
            val cursor = context.contentResolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                null,
                null,
                sortOrder
            )

            cursor?.use {
                val columnIndex = it.getColumnIndexOrThrow(MediaStore.Images.Media.DATA)
                while (it.moveToNext()) {
                    val path = it.getString(columnIndex)
                    if (!path.isNullOrEmpty()) {
                        imagePaths.add(path)
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
            // 에러 발생 시 빈 리스트 반환 (또는 필요에 따라 throw)
        }
        
        return@withContext imagePaths
    }
}
