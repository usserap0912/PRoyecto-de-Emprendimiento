import 'package:flutter/material.dart';

/// Logo oficial de SafeZone dentro de un círculo blanco.
///
/// El logo tiene fondo transparente, así que el círculo garantiza contraste
/// tanto sobre el rojo de marca como sobre fondos claros u oscuros.
class SafeZoneLogoMark extends StatelessWidget {
  final double size;
  final Color background;
  final bool showShadow;

  const SafeZoneLogoMark({
    super.key,
    this.size = 32,
    this.background = Colors.white,
    this.showShadow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.06),
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: size * 0.22,
                  offset: Offset(0, size * 0.06),
                ),
              ]
            : null,
      ),
      child: Image.asset(
        'assets/icons/logo-app.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
