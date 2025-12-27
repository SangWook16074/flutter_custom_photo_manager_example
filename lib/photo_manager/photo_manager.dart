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
