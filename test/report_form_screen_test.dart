import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safezone/models/report_submission.dart';
import 'package:safezone/screens/report/report_form_screen.dart';
import 'package:safezone/services/report_service.dart';

class _MissingProfileGateway implements ReportGateway {
  int insertCalls = 0;

  @override
  Future<Map<String, dynamic>> insertReport(
    Map<String, dynamic> payload,
  ) async {
    insertCalls++;
    throw StateError('insert must not run without a profile');
  }

  @override
  Future<bool> profileExists(String userCode) async => false;

  @override
  Future<String?> uploadEvidence(String path, {required bool isVideo}) async {
    throw StateError('upload must not run without a profile');
  }
}

void main() {
  testWidgets('failed send preserves the completed form for retry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _MissingProfileGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: ReportFormScreen(
          userCode: 'VEC-001',
          zone: 4,
          reportService: ReportService(gateway: gateway),
          locationResolver: () async => const ReportCoordinates(
            latitude: -11.9130804,
            longitude: -77.0161997,
          ),
          storageReadyResolver: () async => true,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Robo'));
    await tester.tap(find.text('Peligro grave'));
    await tester.enterText(
      find.byType(TextField),
      'Descripción que debe conservarse',
    );
    await tester.scrollUntilVisible(
      find.text('ENVIAR REPORTE'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('ENVIAR REPORTE'));
    await tester.pump();

    expect(find.textContaining('No pudimos validar tu perfil'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Descripción que debe conservarse',
    );
    expect(find.text('¡Reporte Enviado!'), findsNothing);
    expect(gateway.insertCalls, 0);
  });
}
