import 'package:flutter/material.dart';
import 'package:offline_navigator/map/map_screen.dart';

class OfflineNavigatorApp extends StatelessWidget {
  const OfflineNavigatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline Navigator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFFFF6A1A)),
      home: const MapScreen(),
    );
  }
}
