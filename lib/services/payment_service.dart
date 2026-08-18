import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:safezone/services/zonebot_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// PAYMENT SERVICE
// ============================================================
// Maneja la suscripción premium usando:
//   - Mercado Pago Checkout Pro (suscripción mensual en soles)
//   - Supabase Edge Function para crear suscripciones y verificar estado
//   - Supabase Database para persistir el estado premium
//
// ⚠️ MODO DEMO: por defecto los pagos son REALES.
// Para compilar una versión de prueba SIN pagar (activa Premium
// localmente), ejecuta con:
//   flutter run --dart-define=DEMO_PREMIUM=true
// ============================================================

/// Resultado de una operación de compra premium.
enum PaymentResult {
  /// Compra exitosa (modo demo o pago confirmado)
  success,

  /// Redirigido a Mercado Pago Checkout (pendiente de confirmación)
  redirected,

  /// Error en el proceso de pago
  failed,
}

/// Servicio de pagos para SafeZone Premium.
class PaymentService {
  static const String _functionBaseUrl =
      'https://kpkdgejbjgmrbyemubmx.supabase.co/functions/v1/mercadopago-premium';

  /// Modo demo (sin pago real). Solo se activa compilando con
  /// --dart-define=DEMO_PREMIUM=true
  static const bool _demoMode = bool.fromEnvironment(
    'DEMO_PREMIUM',
    defaultValue: false,
  );

  static bool get isDemoMode => _demoMode;

  Map<String, String>? _authorizedHeaders() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) return null;
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  /// Inicia el flujo de compra premium (suscripción mensual).
  Future<PaymentResult> purchasePremium({
    required String userCode,
    required int zone,
  }) async {
    // Modo demo: activar premium localmente sin pago real
    if (_demoMode) {
      debugPrint('PaymentService: Modo demo - activando premium sin pago');
      ZoneBotService.setPremium(true);
      return PaymentResult.success;
    }

    // Modo real: Mercado Pago Checkout Pro
    try {
      final headers = _authorizedHeaders();
      if (headers == null) return PaymentResult.failed;
      final response = await http.post(
        Uri.parse('$_functionBaseUrl/checkout'),
        headers: headers,
        body: jsonEncode(<String, dynamic>{}),
      );

      if (response.statusCode != 200) {
        debugPrint('PaymentService: Error creando checkout: ${response.body}');
        return PaymentResult.failed;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final checkoutUrl = data['url'] as String?;

      if (checkoutUrl == null) {
        debugPrint('PaymentService: No se recibió URL de checkout');
        return PaymentResult.failed;
      }

      // Abrir Mercado Pago Checkout en el navegador
      final uri = Uri.parse(checkoutUrl);
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return PaymentResult.redirected;
      } catch (e) {
        debugPrint('PaymentService: Error abriendo checkout: $e');
        return PaymentResult.failed;
      }
    } catch (e) {
      debugPrint('PaymentService: Error en compra premium: $e');
      return PaymentResult.failed;
    }
  }

  /// Verifica si un usuario tiene premium activo.
  Future<bool> checkPremiumStatus({required String userCode}) async {
    if (_demoMode) {
      return ZoneBotService.isPremium;
    }

    try {
      final headers = _authorizedHeaders();
      if (headers == null) return false;
      final response = await http.get(
        Uri.parse('$_functionBaseUrl/status'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['is_premium'] as bool? ?? false;
      }
    } catch (e) {
      debugPrint('PaymentService: Error verificando premium: $e');
    }

    return ZoneBotService.isPremium;
  }

  /// Cancela la suscripción Premium de Mercado Pago.
  /// Retorna true si se canceló correctamente.
  Future<bool> cancelPremiumSubscription({required String userCode}) async {
    if (_demoMode) return false;

    try {
      final headers = _authorizedHeaders();
      if (headers == null) return false;
      final response = await http.post(
        Uri.parse('$_functionBaseUrl/cancel'),
        headers: headers,
        body: jsonEncode(<String, dynamic>{}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('PaymentService: Error cancelando suscripción: $e');
      return false;
    }
  }

  /// Sincroniza el estado premium verificando contra Mercado Pago
  /// (a través de la Edge Function /status). Usado por "Restaurar compras"
  /// para auto-repararse si algún webhook se perdió.
  static Future<void> syncPremiumStatus({required String userCode}) async {
    if (_demoMode) return;

    try {
      final service = PaymentService();
      final isPremium = await service.checkPremiumStatus(userCode: userCode);
      ZoneBotService.setPremium(isPremium);
      debugPrint('PaymentService: Premium sincronizado: $isPremium');
    } catch (e) {
      debugPrint('PaymentService: Error sincronizando premium: $e');
    }
  }
}
