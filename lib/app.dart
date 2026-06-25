import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/screens/entry/zone_selection_screen.dart';

class SafeZoneApp extends StatefulWidget {
  const SafeZoneApp({super.key});

  /// Acceso global para toggle de tema desde cualquier screen
  static SafeZoneAppState? of(BuildContext context) {
    return context.findAncestorStateOfType<SafeZoneAppState>();
  }

  @override
  State<SafeZoneApp> createState() => SafeZoneAppState();
}

class SafeZoneAppState extends State<SafeZoneApp> {
  ThemeMode _themeMode = ThemeMode.light;

  /// Referencia estática para acceso sin BuildContext
  static SafeZoneAppState? instance;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    instance = this;
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('dark_mode') ?? false;
    if (mounted) {
      setState(() => _themeMode = isDark ? ThemeMode.dark : ThemeMode.light);
    }
  }

  void toggleTheme() {
    final newMode =
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    setState(() => _themeMode = newMode);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('dark_mode', newMode == ThemeMode.dark);
    });
  }

  @override
  void dispose() {
    instance = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeZone - Collique',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: const ZoneSelectionScreen(),
    );
  }
}
