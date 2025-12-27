### **들어가며**
>
Flutter에서 이미지 데이터를 불러오기 위해서 `image_picker`, `photo_manager`같은 플러그인을 자주 사용합니다.
>
하지만 실제로 그 내부에서 어떤 일이 일어나는지, 
왜 `Info.plist`를 수정해야 하고 `AndroidManifest.xml`에 권한을 추가해야 하는지 명확히 알기 어렵습니다.
>
이 프로젝트는 기존 플러그인에 의존하지 않고, 
**Flutter의 MethodChannel을 통해 Native(Android/iOS)의 갤러리 이미지 데이터에 직접 접근하는 과정**을 구현한 예제입니다.
>
직접 코드를 작성해보며 **OS별로 상이한 이미지 접근 방식**과 **권한 처리**, 그리고 **Native 레벨의 비동기 프로그래밍**을 깊이 있게 이해해봅시다.


### **Architecture & Flow**
>
Flutter는 UI를 담당하고, 실제 데이터 로딩은 각 플랫폼의 Native API를 호출하여 수행합니다.
>
전체적인 데이터 흐름은 다음과 같습니다.
>
1.  **Flutter UI**에서 `MethodChannel`을 통해 `'getImagePaths'` 메서드를 호출합니다.
2.  이 호출은 각 플랫폼의 **Native 코드**로 전달됩니다.
    *   **Android (Kotlin)**: `ContentResolver`를 사용하여 `MediaStore`에서 이미지 데이터를 조회합니다.
    *   **iOS (Swift)**: `PHImageManager`를 사용하여 `PhotoLibrary`에서 이미지 데이터를 처리합니다.
3.  Native 코드에서 처리된 `List<String>` 형태의 이미지 경로가 다시 `MethodChannel`을 통해 **Flutter UI**로 반환됩니다.


### **Native Implementation**
>
이 프로젝트의 핵심은 `MainActivity`나 `AppDelegate`를 비대하게 만들지 않고, 
**데이터 로딩 로직을 별도 클래스로 분리**하여 관리하는 것입니다.

#### **Android: `GalleryDataSources.kt`**
>
안드로이드는 **데이터베이스 쿼리** 방식입니다. 
파일 시스템에 직접 접근하는 대신 `ContentResolver`를 통해 `MediaStore`를 조회합니다.
>
- **Coroutine:** 수천 장의 이미지를 불러올 때 UI가 멈추지 않도록 `Dispatchers.IO` 스레드에서 비동기로 실행합니다.
- **AndroidManifest.xml 설정 (권한)**
    *   Android 앱이 갤러리 사진에 접근하려면 `AndroidManifest.xml` 파일에 권한을 명시해야 합니다.
    *   API 33(Android 13) 이상은 `READ_MEDIA_IMAGES` 권한, 그 이하는 `READ_EXTERNAL_STORAGE` 권한을 사용합니다.
    
    
```xml
	...
	<manifest xmlns:android="http://schemas.android.com/apk/res/android">
        <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
        <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
        <!-- ... 나머지 설정 ... -->
    </manifest>
```

```kotlin
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

```

#### **iOS: `GalleryDatasource.swift`**
>
iOS는 **객체 기반(Object-Oriented)**이며 보안이 훨씬 엄격합니다. 
`PHAsset`이라는 메타데이터 객체만 제공하며, 실제 이미지 파일의 경로는 바로 알 수 없습니다.
>
따라서 **이미지를 메모리에 로드한 뒤, 임시 파일로 저장하여 경로를 생성**하는 과정이 필요합니다.
>
- **DispatchGroup:** iOS의 이미지 로딩(`requestImage`)은 비동기적으로 작동합니다. 
반복문이 끝났다고 해서 로딩이 끝난 것이 아니기 때문에, `DispatchGroup`을 사용하여 모든 작업이 완료될 때까지 기다려야 합니다.
- **FileManager:** `PHAsset`을 직접 경로로 바꿀 수 없어 `tmp` 디렉토리에 파일을 쓰고 그 경로를 반환합니다.
>
- **Info.plist 설정 (개인정보 보호 문구)**
    *   iOS 앱이 사진 라이브러리에 접근하려면 `Info.plist` 파일에 접근 목적을 명시해야 합니다. 
    * 해당 문구가 없을 경우, 사진 라이브러리에 접근하는 시점에 iOS가 앱을 종료시킵니다.
    
    
```xml
	...
    <key>NSPhotoLibraryUsageDescription</key>
    <string>앱에서 사진을 선택하여 프로필 이미지 등으로 사용하기 위함입니다.</string>
```

```swift
import Photos
import UIKit

final class GalleryDatasource {
    static let shared = GalleryDatasource()
    private init() {}
}

extension GalleryDatasource {
    func fetchImagePaths(completion : @escaping ([String]) -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                completion([])
                return
            }
            
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            
            let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            let manager = PHImageManager.default()
            
            var paths = [String]()
            let group = DispatchGroup()
            let queue = DispatchQueue(label: "com.example.photoManager.pathsQueue")
            
            if assets.count == 0 {
                completion([])
                return
            }
            
            assets.enumerateObjects { asset, _, _ in
                group.enter()
                let options = PHImageRequestOptions()
                options.isSynchronous = false
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .fast
                options.isNetworkAccessAllowed = true
                
                let scale = UIScreen.main.scale
                let size = CGSize(width: 200 * scale, height: 200 * scale)
                
                manager.requestImage(
                    for: asset,
                    targetSize: size,
                    contentMode: .aspectFill,
                    options: options
                ) { image, _ in
                    
                    guard
                        let image,
                        let data = image.jpegData(compressionQuality: 0.8)
                    else {
                        group.leave()
                        return
                    }
                    
                    let fileName = UUID().uuidString + ".jpg"
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                    
                    do {
                        try data.write(to: url)
                        queue.async {
                            paths.append(url.path)
                            group.leave()
                        }
                    } catch {
                        group.leave()
                    }
                }
            }
            
            group.notify(queue: .main) {
                completion(paths)
            }
        }
    }
}
```

### **Flutter Integration**
>
Native가 준비되었어도, **권한 요청 트리거**는 Flutter 쪽에서 제어하는 것이 UX 관점에서 유리합니다.

```dart
// lib/views/photo_grid_view.dart

Future<List<String>> _loadImages() async {
  // 1. 플랫폼별 권한 요청 (permission_handler 사용)
  if (Platform.isAndroid) {
    await [Permission.storage, Permission.photos].request();
  } else if (Platform.isIOS) {
    await Permission.photos.request();
  }

  // 2. 권한 승인 후 Native MethodChannel 호출
  return _photoManager.getImagePaths();
}
```

>
결과적으로 다음과 같이 이미지로 UI를 제작할 수 있습니다.

<center>
<table>
  	<th>iOS</th>
  	<th>Android</th>
	<tr>
  		<td>
          <img src=https://velog.velcdn.com/images/qazws78941/post/b8c4da1f-e5fa-414c-82e6-5e9c0275a229/image.png width =250>
		</td>
  		<td>
      <img src=https://velog.velcdn.com/images/qazws78941/post/2417f92a-80a9-436e-b2c8-74ce7ad09b9d/image.png width =250>
		</td>
  	</tr>
</table>
</center>



### **결론**
>
이번 구현을 통해 플러그인을 사용하는 것보다, Native 코드가 실제로 어떻게 동작하는지를 이해하는 것이 중요하다는 점을 느꼈습니다.
>
Flutter가 많은 부분을 추상화해주지만, 파일 접근이나 권한 관리처럼 중요한 영역은 결국 각 OS의 정책을 그대로 따릅니다.
각 Native의 구조를 이해하고 있으면, 플랫폼 이슈가 발생했을 때 더 빠르고 안정적으로 대응할 수 있습니다.
