import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safezone/models/report_form_config.dart';
import 'package:safezone/models/report_submission.dart';
import 'package:safezone/services/report_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeReportGateway implements ReportGateway {
  bool hasProfile = true;
  int profileCalls = 0;
  int insertCalls = 0;
  int uploadCalls = 0;
  Object? insertError;
  String? uploadResult = 'https://example.test/evidence.jpg';
  Completer<Map<String, dynamic>>? pendingInsert;
  Map<String, dynamic>? lastPayload;

  @override
  Future<bool> profileExists(String userCode) async {
    profileCalls++;
    return hasProfile;
  }

  @override
  Future<String?> uploadEvidence(String path, {required bool isVideo}) async {
    uploadCalls++;
    return uploadResult;
  }

  @override
  Future<Map<String, dynamic>> insertReport(
    Map<String, dynamic> payload,
  ) async {
    insertCalls++;
    lastPayload = payload;
    final error = insertError;
    if (error != null) throw error;
    final pending = pendingInsert;
    if (pending != null) return pending.future;
    return _insertedRow(payload);
  }
}

Map<String, dynamic> _insertedRow(Map<String, dynamic> payload) {
  return <String, dynamic>{
    'id': 'report-001',
    'user_code': 'VEC-001',
    ...payload,
    'image_url': payload['image_url'],
    'video_url': payload['video_url'],
    'latitude': payload['latitude'],
    'longitude': payload['longitude'],
    'address': null,
    'created_at': '2026-08-17T12:00:00.000Z',
    'shield_count': 0,
    'alert_count': 0,
    'check_count': 0,
  };
}

const _validDraft = ReportDraft(
  userCode: 'VEC-001',
  zone: 4,
  category: 'robo',
  description: 'Incidente de prueba',
  severity: 'rojo',
  latitude: -11.9130804,
  longitude: -77.0161997,
);

void main() {
  test('uses the exact reports schema and confirms the inserted row', () async {
    final gateway = _FakeReportGateway();
    final service = ReportService(gateway: gateway);

    final result = await service.createReport(_validDraft);

    expect(result.isSuccess, isTrue);
    expect(result.report?.id, 'report-001');
    expect(gateway.insertCalls, 1);
    expect(gateway.lastPayload, <String, dynamic>{
      'user_code': 'VEC-001',
      'zone': 4,
      'category': 'robo',
      'description': 'Incidente de prueba',
      'tag': 'rojo',
      'status': 'activo',
      'latitude': -11.9130804,
      'longitude': -77.0161997,
    });
    expect(
      gateway.lastPayload!.keys,
      isNot(
        containsAll(<String>[
          'risk_level',
          'zone_number',
          'lat',
          'lng',
          'media_url',
        ]),
      ),
    );
  });

  test('publishes a confirmed report to the local wall event stream', () async {
    final gateway = _FakeReportGateway();
    final service = ReportService(gateway: gateway);
    final created = service.createdReports.first;

    final result = await service.createReport(_validDraft);

    expect(result.isSuccess, isTrue);
    expect((await created).id, 'report-001');
  });

  test(
    'missing profile preserves a specific failure and skips insert',
    () async {
      final gateway = _FakeReportGateway()..hasProfile = false;
      final result = await ReportService(
        gateway: gateway,
      ).createReport(_validDraft);

      expect(result.failure, ReportSubmissionFailure.missingProfile);
      expect(result.message, isNot(contains('enviado')));
      expect(gateway.insertCalls, 0);
    },
  );

  test('foreign-key rejection is identified as a missing profile', () async {
    final gateway = _FakeReportGateway()
      ..insertError = const PostgrestException(
        message: 'violates foreign key constraint',
        code: '23503',
      );

    final result = await ReportService(
      gateway: gateway,
    ).createReport(_validDraft);

    expect(result.failure, ReportSubmissionFailure.missingProfile);
    expect(result.technicalCode, '23503');
  });

  test('schema rejection is not reported as success', () async {
    final gateway = _FakeReportGateway()
      ..insertError = const PostgrestException(
        message: 'column does not exist',
        code: '42703',
      );

    final result = await ReportService(
      gateway: gateway,
    ).createReport(_validDraft);

    expect(result.failure, ReportSubmissionFailure.schema);
    expect(result.message, contains('actualización'));
  });

  test('invalid category is rejected before contacting Supabase', () async {
    final gateway = _FakeReportGateway();
    const draft = ReportDraft(
      userCode: 'VEC-001',
      zone: 4,
      category: 'categoria_inventada',
      description: 'Incidente de prueba',
      severity: 'rojo',
    );

    final result = await ReportService(gateway: gateway).createReport(draft);

    expect(result.failure, ReportSubmissionFailure.invalidCategory);
    expect(gateway.profileCalls, 0);
    expect(gateway.insertCalls, 0);
  });

  test('failed media upload blocks the report insert', () async {
    final gateway = _FakeReportGateway()..uploadResult = null;

    final result = await ReportService(
      gateway: gateway,
    ).createReport(_validDraft, localImagePath: 'photo.jpg');

    expect(result.failure, ReportSubmissionFailure.mediaUpload);
    expect(gateway.uploadCalls, 1);
    expect(gateway.insertCalls, 0);
  });

  test('only one submission can be active per form service', () async {
    final gateway = _FakeReportGateway()
      ..pendingInsert = Completer<Map<String, dynamic>>();
    final service = ReportService(gateway: gateway);

    final first = service.createReport(_validDraft);
    await Future<void>.delayed(Duration.zero);
    final duplicate = await service.createReport(_validDraft);

    expect(duplicate.failure, ReportSubmissionFailure.duplicate);
    expect(gateway.insertCalls, 1);
    gateway.pendingInsert!.complete(_insertedRow(gateway.lastPayload!));
    expect((await first).isSuccess, isTrue);
  });

  test('the visual category catalog keeps the approved internal mapping', () {
    expect(
      ReportFormConfig.categories
          .map((category) => '${category.label}|${category.value}')
          .toList(),
      <String>[
        'Robo|robo',
        'Actividad sospechosa|sospechoso',
        'Extorsión / Amenaza|extorsion',
        'Falla de alumbrado|alumbrado',
        'Otros|otros',
      ],
    );
    expect(
      ReportFormConfig.categories.every(
        (category) => category.illustrationAsset == null,
      ),
      isTrue,
      reason: 'No definitive illustration assets were supplied.',
    );
  });

  test('production report flow has no legacy risk-level dependency', () {
    const paths = <String>[
      'lib/models/report.dart',
      'lib/models/report_submission.dart',
      'lib/services/report_service.dart',
      'lib/screens/report/report_form_screen.dart',
      'lib/screens/wall/wall_screen.dart',
      'lib/screens/map/risk_map_screen.dart',
    ];

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('risk_level')), reason: path);
      expect(source, isNot(contains('riskLevel')), reason: path);
      expect(source, isNot(contains('Nivel de Riesgo')), reason: path);
    }
    final formSource = File(
      'lib/screens/report/report_form_screen.dart',
    ).readAsStringSync();
    expect(formSource, contains("'Nivel de gravedad'"));
  });

  test('production wall flow does not inject sample reports', () {
    final serviceSource = File(
      'lib/services/report_service.dart',
    ).readAsStringSync();
    final wallSource = File(
      'lib/screens/wall/wall_screen.dart',
    ).readAsStringSync();

    expect(serviceSource, isNot(contains('_getSampleReports')));
    expect(wallSource, isNot(contains('_getSampleReports')));
    expect(wallSource, isNot(contains("id: 'sample-")));
  });
}
