import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_custom_photo_manager/photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';

class PhotoGridView extends StatefulWidget {
  const PhotoGridView({super.key});

  @override
  State<PhotoGridView> createState() => _PhotoGridViewState();
}

class _PhotoGridViewState extends State<PhotoGridView> {
  late final PhotoManager _photoManager;

  @override
  void initState() {
    _photoManager = PhotoManagerImpl();
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<List<String>> _loadImages() async {
    if (Platform.isAndroid) {
      await [
        Permission.storage,
        Permission.photos,
      ].request();
    } else if (Platform.isIOS) {
      await Permission.photos.request();
    }

    return _photoManager.getImagePaths();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _loadImages(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else {
          if (snapshot.hasData && snapshot.data!.isNotEmpty) {
            return GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 1.0,
                crossAxisSpacing: 1.0,
              ),
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                final imagePath = snapshot.data![index];

                return Image.file(File(imagePath), fit: BoxFit.cover);
              },
            );
          } else {
            debugPrint("is empty");

            return Container();
          }
        }
      },
    );
  }
}
