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
