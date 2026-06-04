import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/screens/entry/zone_selection_screen.dart';

class SafeZoneApp extends StatefulWidget {
  const SafeZoneApp({super.key});

  @override
  State<SafeZoneApp> createState() => _SafeZoneAppState();
}

class _SafeZoneAppState extends State<SafeZoneApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeZone - Collique',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const ZoneSelectionScreen(),
    );
  }
}
