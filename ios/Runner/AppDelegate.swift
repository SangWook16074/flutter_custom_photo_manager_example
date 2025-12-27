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
