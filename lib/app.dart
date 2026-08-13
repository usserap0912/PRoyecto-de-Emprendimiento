import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/screens/splash/splash_screen.dart';
import 'package:safezone/services/power_saver_service.dart';

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

  // ================================================================
  // MODO OSCURO AUTOMÁTICO
  // ================================================================
  // Si el usuario NUNCA ha cambiado el tema manualmente, se usa el
  // modo oscuro automático según la hora:
  //   - 7:00 PM – 7:00 AM → Oscuro
  //   - 7:00 AM – 7:00 PM → Claro
  // ================================================================
  static const String _prefsManualTheme = 'dark_mode_manual';
  bool _userHasManuallySet = false;

  /// Timer del refresco automático del tema (día/noche).
  Timer? _autoRefreshTimer;

  /// Determina si es de noche (entre 7PM y 7AM)
  static bool _isNightTime() {
    final hour = DateTime.now().hour;
    return hour >= 19 || hour < 7;
  }

  /// Calcula el ThemeMode según la hora actual
  static ThemeMode _autoThemeMode() {
    return _isNightTime() ? ThemeMode.dark : ThemeMode.light;
  }

  @override
  void initState() {
    super.initState();
    instance = this;
    _loadThemePreference();
    // Inicializar Modo Ahorro
    PowerSaverService().initialize();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();

    // Migrar clave antigua 'dark_mode' → 'dark_mode_manual'
    if (!prefs.containsKey(_prefsManualTheme)) {
      final legacyDark = prefs.getBool('dark_mode');
      if (legacyDark != null) {
        await prefs.setBool(_prefsManualTheme, legacyDark);
        await prefs.remove('dark_mode');
      }
    }

    // Verificar si el usuario ha cambiado el tema manualmente alguna vez
    _userHasManuallySet = prefs.containsKey(_prefsManualTheme);

    if (_userHasManuallySet) {
      // Usuario tiene preferencia manual → respetarla
      final isDark = prefs.getBool(_prefsManualTheme) ?? false;
      if (mounted) {
        setState(() => _themeMode = isDark ? ThemeMode.dark : ThemeMode.light);
      }
    } else {
      // Primera vez → modo automático según la hora
      if (mounted) {
        setState(() => _themeMode = _autoThemeMode());
      }
    }

    // Actualizar el tema cada 30 minutos para seguir el ciclo día/noche
    _scheduleAutoRefresh();
  }

  /// Programa una actualización del tema automático cada 30 minutos.
  /// Solo aplica si el usuario no ha configurado manualmente.
  void _scheduleAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer(const Duration(minutes: 30), () {
      if (!mounted) return;
      if (!_userHasManuallySet) {
        final auto = _autoThemeMode();
        if (_themeMode != auto) {
          setState(() => _themeMode = auto);
        }
      }
      _scheduleAutoRefresh(); // refrescar cada 30 min
    });
  }

  /// Cambia el tema manualmente (toggle).
  /// Al hacerlo, se DESACTIVA el modo automático.
  void toggleTheme() {
    final newMode =
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    setState(() {
      _themeMode = newMode;
      _userHasManuallySet = true;
    });
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool(_prefsManualTheme, newMode == ThemeMode.dark);
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
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
      home: const SplashScreen(),
    );
  }
}
