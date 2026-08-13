import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/screens/splash/splash_screen.dart';

class SafeZoneApp extends StatelessWidget {
  const SafeZoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeZone - Collique',
      debugShowCheckedModeBanner: false,
      // Tema claro fijo: el modo oscuro se eliminó de la app.
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}
