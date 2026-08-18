import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('entry uses the stored legacy pseudonym without Anonymous Auth', () {
    final splash = File(
      'lib/screens/splash/splash_screen.dart',
    ).readAsStringSync();
    final assignment = File(
      'lib/screens/entry/code_assignment_screen.dart',
    ).readAsStringSync();

    expect(splash, contains("getString('user_device_code')"));
    expect(splash, contains('ensureLegacyProfile'));
    expect(splash, isNot(contains('IdentityService()')));
    expect(assignment, contains('existingCode ?? _generateCode()'));
    expect(assignment, contains("setString('user_device_code', _userCode)"));
    expect(assignment, contains('ensureLegacyProfile'));
    expect(assignment, isNot(contains('create_current_profile')));
  });

  test('active report, comments and SOS writes use the current schema', () {
    final reportModel = File(
      'lib/models/report_submission.dart',
    ).readAsStringSync();
    final reportService = File(
      'lib/services/report_service.dart',
    ).readAsStringSync();
    final supabaseService = File(
      'lib/services/supabase_service.dart',
    ).readAsStringSync();

    expect(reportModel, contains("'user_code': userCode"));
    expect(reportModel, contains("'tag': severity"));
    expect(reportModel, contains("'latitude': ?latitude"));
    expect(reportModel, contains("'longitude': ?longitude"));
    expect(reportService, contains(".eq('user_code', userCode)"));
    expect(reportService, isNot(contains(".eq('auth_user_id'")));
    expect(supabaseService, contains("'user_code': userCode"));
    expect(supabaseService, isNot(contains('do_current_safe_checkin')));
  });
}
