import 'package:flutter/material.dart';
import 'package:flutter_custom_photo_manager/views/photo_grid_view.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(body: Center(child: PhotoGridView())),
    );
  }
}
