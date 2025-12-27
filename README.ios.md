# Flutter에서 Native iOS(PhotoLibrary) 연동하여 커스텀 갤러리 만들기

Flutter 개발을 하다 보면 기존 패키지(`image_picker` 등)로는 원하는 커스텀 기능을 구현하기 어려울 때가 있습니다. 이 글에서는 **MethodChannel**을 사용하여 iOS의 **PHPhotoLibrary**에 직접 접근하고, 기기의 사진을 불러오는 커스텀 포토 매니저를 구현하는 과정을 정리합니다.

---

## 1. 아키텍처 개요

구현할 구조는 다음과 같습니다.

1.  **Flutter**: UI를 그리고, `MethodChannel`을 통해 iOS 네이티브 계층에 "사진 가져와"라고 요청을 보냅니다.
2.  **iOS (Swift)**:
    *   `PHPhotoLibrary`를 통해 기기의 사진 에셋을 조회합니다.
    *   `PHImageManager`로 썸네일/원본 이미지를 로드합니다.
    *   이미지 데이터를 `TemporaryDirectory`에 파일로 저장합니다. (Flutter는 `File` 객체로 접근하는 것이 효율적이기 때문)
    *   저장된 파일 경로(`String`)들의 리스트를 Flutter로 반환합니다.

---

## 2. Flutter 설정 (MethodChannel)

먼저 iOS와 통신할 인터페이스를 정의합니다.

### `lib/photo_manager/photo_manager.dart`

**핵심 포인트**: MethodChannel은 데이터를 받을 때 기본적으로 `List<dynamic>` 타입을 반환합니다. 이를 `List<String>`으로 바로 받으려 하면 타입 에러가 발생할 수 있으므로, `cast<String>()`을 사용하는 것이 안전합니다.

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract class PhotoManager {
  Future<List<String>> getImagePaths();
}

class PhotoManagerImpl implements PhotoManager {
  @visibleForTesting
  static const platform = MethodChannel(
    'com.example.flutterCustomPhotoManager/photoManager',
  );

  @override
  Future<List<String>> getImagePaths() async {
    try {
      // [주의] List<String>으로 바로 받지 말고 dynamic으로 받은 후 변환
      final paths = await platform.invokeMethod<List<dynamic>>("getImagePaths");

      if (paths == null) {
        return [];
      }

      return paths.cast<String>();
    } catch (e) {
      return [];
    }
  }
}
```

---

## 3. iOS 설정 (Swift)

### 3.1 권한 설정 (`Info.plist`)

사진에 접근하기 위해 `ios/Runner/Info.plist`에 권한 요청 문구를 추가해야 합니다.

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>앱에서 갤러리 사진을 불러오기 위해 권한이 필요합니다.</string>
```

### 3.2 데이터 소스 구현 (`GalleryDatasource.swift`)

가장 중요한 부분입니다. `PHAsset`을 가져오는 과정은 비동기적이고, 여러 이미지를 동시에 처리해야 하므로 **DispatchGroup**을 사용하여 동기화를 맞추어 주어야 합니다.

**구현 시 주의사항**:
*   `deliveryMode`: `.opportunistic`을 쓰면 썸네일과 원본이 두 번 올 수 있어 로직이 꼬일 수 있습니다. `.highQualityFormat`을 사용합니다.
*   **Thread Safety**: 여러 스레드에서 동시에 배열(`paths`)에 접근하면 크래시가 날 수 있으므로 `Serial Queue`로 보호해야 합니다.
*   **DispatchGroup**: 모든 이미지 변환이 끝난 후(`group.notify`)에 Flutter로 응답을 보내야 합니다.

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
            // 배열 접근 동기화를 위한 큐
            let queue = DispatchQueue(label: "com.example.photoManager.pathsQueue")
            
            if assets.count == 0 {
                completion([])
                return
            }

            assets.enumerateObjects { asset, _, _ in
                group.enter()
                
                let options = PHImageRequestOptions()
                options.isSynchronous = false // 비동기 처리
                options.deliveryMode = .highQualityFormat // 고화질 1회 전송 보장
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
                        let image = image,
                        let data = image.jpegData(compressionQuality: 0.8)
                    else {
                        group.leave()
                        return
                    }
                    
                    let fileName = UUID().uuidString + ".jpg"
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                    
                    do {
                        try data.write(to: url)
                        // Thread-Safe 하게 경로 추가
                        queue.async {
                            paths.append(url.path)
                            group.leave()
                        }
                    } catch {
                        group.leave()
                    }
                }
            }
            
            // 모든 작업이 끝나면 호출
            group.notify(queue: .main) {
                completion(paths)
            }
        }
    }
}
```

### 3.3 AppDelegate 연결 (`AppDelegate.swift`)

Flutter 엔진이 시작될 때 채널을 등록하고 핸들러를 연결합니다.

```swift
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
      
      let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
      let photoManagerChannel = FlutterMethodChannel(name: "com.example.flutterCustomPhotoManager/photoManager",
                                                      binaryMessenger: controller.binaryMessenger)
      
      photoManagerChannel.setMethodCallHandler({
            [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
          switch call.method {
          case "getImagePaths":
              GalleryDatasource.shared.fetchImagePaths { paths in
                  DispatchQueue.main.async {
                    result(paths)
                  }
              }
          default: result(FlutterMethodNotImplemented)
          }
      })
      
      GeneratedPluginRegistrant.register(with: self)
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

---

## 4. 트러블 슈팅 (개발 팁)

이 기능을 구현하면서 겪을 수 있는 대표적인 문제들과 해결책입니다.

### Q1. Flutter에서 빈 리스트만 받아와요. (`[]`)
**원인**: Swift의 비동기 처리 타이밍 문제일 수 있습니다. `DispatchGroup`의 `leave()`가 이미지가 저장되기도 전에 호출되면, `group.notify`가 너무 일찍 실행되어 빈 배열을 반환합니다.
**해결**: `manager.requestImage`의 completion 블록 안에서, **파일 쓰기 작업이 완료된 후**에 `group.leave()`를 호출해야 합니다.

### Q2. `TypeError: type 'List<dynamic>' is not a subtype of type 'List<String>'` 에러 발생
**원인**: MethodChannel을 통해 넘어온 데이터는 Dart에서 런타임에 `List<dynamic>`으로 인식됩니다.
**해결**: `invokeMethod<List<String>>` 대신 `invokeMethod<List<dynamic>>`으로 받은 후 `.cast<String>()` 메서드를 사용하세요.

### Q3. 시뮬레이터에서 이미지가 안 나와요.
**원인 1**: 시뮬레이터 앨범이 비어있을 수 있습니다. 사파리에서 이미지를 저장해보세요.
**원인 2**: 아이클라우드(iCloud) 사진인 경우 다운로드가 필요한데, 시뮬레이터나 기기 네트워크 설정 문제로 다운로드가 실패하면 `image`가 `nil`이 될 수 있습니다.

---

## 5. 마무리

이렇게 직접 Native 코드를 연동하면 패키지 의존성을 줄이고 앱의 요구사항에 딱 맞는 갤러리 기능을 구현할 수 있습니다. 안드로이드 또한 `ContentResolver`와 `MediaStore`를 사용하여 비슷한 방식으로 구현이 가능합니다.
