import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safezone/app.dart';
import 'package:safezone/models/report.dart';

void main() {
  testWidgets('SafeZone app loads with title', (WidgetTester tester) async {
    await tester.pumpWidget(const SafeZoneApp());
    expect(find.text('SafeZone'), findsOneWidget);
  });

  testWidgets('ZoneSelectionScreen has zones and continue button',
      (WidgetTester tester) async {
    await tester.pumpWidget(const SafeZoneApp());
    // El título SafeZone aparece
    expect(find.text('SafeZone'), findsOneWidget);
    // El botón CONTINUAR existe
    expect(find.text('CONTINUAR'), findsOneWidget);
    // Al menos las primeras zonas existen en el árbol
    expect(find.text('Zona 1'), findsWidgets);
    expect(find.text('Zona 2'), findsWidgets);
  });

  group('Report model', () {
    test('fromMap creates Report correctly', () {
      final now = DateTime.now();
      final map = {
        'id': 'test-1',
        'user_code': 'User-A1B2',
        'zone': 3,
        'category': 'robo',
        'description': 'Test description',
        'image_url': null,
        'video_url': null,
        'latitude': -11.9325,
        'longitude': -77.0734,
        'address': 'Av. Collique',
        'tag': 'rojo',
        'status': 'activo',
        'created_at': now.toIso8601String(),
        'shield_count': 5,
        'alert_count': 3,
        'check_count': 1,
      };

      final report = Report.fromMap(map);
      expect(report.id, 'test-1');
      expect(report.userCode, 'User-A1B2');
      expect(report.zone, 3);
      expect(report.category, 'robo');
      expect(report.tag, 'rojo');
      expect(report.shieldCount, 5);
      expect(report.alertCount, 3);
      expect(report.checkCount, 1);
    });

    test('tagColorFor returns correct colors', () {
      expect(Report.tagColorFor('rojo'), const Color(0xFFD32F2F));
      expect(Report.tagColorFor('amarillo'), const Color(0xFFFFA000));
      expect(Report.tagColorFor('verde'), const Color(0xFF388E3C));
      expect(Report.tagColorFor('otro'), Colors.grey);
    });

    test('categoryLabelFor returns correct labels', () {
      expect(Report.categoryLabelFor('robo'), 'Robo');
      expect(Report.categoryLabelFor('sospechoso'), 'Sospechoso');
      expect(Report.categoryLabelFor('extorsion'), 'Extorsión');
      expect(Report.categoryLabelFor('alumbrado'), 'Alumbrado');
      expect(Report.categoryLabelFor('otros'), 'Otros');
    });

    test('tagLabel returns correct labels', () {
      final now = DateTime.now();
      final report = Report(
        id: 'test',
        userCode: 'User-A1',
        zone: 1,
        category: 'robo',
        description: 'test',
        tag: 'rojo',
        createdAt: now,
      );
      expect(report.tagLabel, 'Peligro Grave');

      final report2 = Report(
        id: 'test2',
        userCode: 'User-A2',
        zone: 1,
        category: 'robo',
        description: 'test',
        tag: 'verde',
        createdAt: now,
      );
      expect(report2.tagLabel, 'Buena Noticia');
    });

    test('toMap and fromMap round-trip', () {
      final now = DateTime.now();
      final report = Report(
        id: 'test-id',
        userCode: 'User-X9Y8',
        zone: 5,
        category: 'sospechoso',
        description: 'Persona sospechosa merodeando',
        latitude: -11.9350,
        longitude: -77.0750,
        address: 'Av. Revolución',
        tag: 'amarillo',
        status: 'activo',
        createdAt: now,
        shieldCount: 10,
        alertCount: 5,
        checkCount: 2,
      );

      final map = report.toMap();
      final restored = Report.fromMap(map);

      expect(restored.id, report.id);
      expect(restored.userCode, report.userCode);
      expect(restored.zone, report.zone);
      expect(restored.category, report.category);
      expect(restored.description, report.description);
      expect(restored.latitude, report.latitude);
      expect(restored.longitude, report.longitude);
      expect(restored.tag, report.tag);
      expect(restored.status, report.status);
      expect(restored.shieldCount, report.shieldCount);
    });
  });
}
