import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safezone/services/identity_service.dart';

class _MemoryIdentityStore implements IdentityStore {
  _MemoryIdentityStore({this.userCode, this.zone});

  String? userCode;
  int? zone;
  int saveCount = 0;

  @override
  Future<String?> readUserCode() async => userCode;

  @override
  Future<int?> readZone() async => zone;

  @override
  Future<void> saveIdentity({
    required String userCode,
    required int zone,
  }) async {
    this.userCode = userCode;
    this.zone = zone;
    saveCount++;
  }
}

class _FakeIdentityGateway implements IdentityGateway {
  _FakeIdentityGateway({
    required this.resolution,
    this.createdProfile = const {
      'status': 'created',
      'auth_user_id': 'auth-new',
      'user_code': 'User-A1B2C3',
      'zone': 3,
    },
    this.authUserId = 'auth-new',
    this.error,
  });

  final Map<String, dynamic> resolution;
  final Map<String, dynamic> createdProfile;
  final Object? error;
  String? authUserId;
  int signInCount = 0;
  int resolveCount = 0;
  int createCount = 0;
  int legacyCreateCount = 0;
  String? receivedLegacyCode;
  String? receivedPreferredCode;

  @override
  String? get currentAuthUserId => authUserId;

  @override
  Future<String> ensureAnonymousSession() async {
    signInCount++;
    if (error != null) throw error!;
    return authUserId!;
  }

  @override
  Future<Map<String, dynamic>> resolveIdentity(String? legacyUserCode) async {
    resolveCount++;
    receivedLegacyCode = legacyUserCode;
    if (error != null) throw error!;
    return resolution;
  }

  @override
  Future<Map<String, dynamic>> createProfile({
    required int zone,
    String? preferredUserCode,
  }) async {
    createCount++;
    receivedPreferredCode = preferredUserCode;
    if (error != null) throw error!;
    return {...createdProfile, 'zone': zone};
  }

  @override
  Future<void> createLegacyProfile({
    required String userCode,
    required int zone,
  }) async {
    legacyCreateCount++;
    if (error != null) throw error!;
  }
}

void main() {
  test('new anonymous user creates one linked pseudonymous profile', () async {
    final gateway = _FakeIdentityGateway(
      resolution: const {'status': 'needs_profile'},
    );
    final store = _MemoryIdentityStore();
    final service = IdentityService.test(gateway: gateway, store: store);

    await service.initialize();
    expect(service.status, IdentityStatus.needsProfile);

    final profile = await service.createProfile(zone: 3);

    expect(profile.userCode, 'User-A1B2C3');
    expect(profile.authUserId, 'auth-new');
    expect(service.canWriteRemotely, isTrue);
    expect(gateway.signInCount, 1);
    expect(gateway.createCount, 1);
    expect(store.userCode, profile.userCode);
  });

  test(
    'zones IX and X supported by the selector can create profiles',
    () async {
      for (final zone in const [9, 10]) {
        final gateway = _FakeIdentityGateway(
          resolution: const {'status': 'needs_profile'},
        );
        final service = IdentityService.test(
          gateway: gateway,
          store: _MemoryIdentityStore(),
        );

        await service.initialize();
        final profile = await service.createProfile(zone: zone);

        expect(profile.zone, zone);
        expect(service.status, IdentityStatus.ready);
      }
    },
  );

  test(
    'existing linked session reuses identity without creating a profile',
    () async {
      final gateway = _FakeIdentityGateway(
        authUserId: 'auth-existing',
        resolution: const {
          'status': 'linked',
          'auth_user_id': 'auth-existing',
          'user_code': 'User-B7Z0',
          'zone': 4,
        },
      );
      final service = IdentityService.test(
        gateway: gateway,
        store: _MemoryIdentityStore(userCode: 'User-B7Z0', zone: 4),
      );

      await service.initialize();
      await service.initialize();

      expect(service.status, IdentityStatus.ready);
      expect(service.userCode, 'User-B7Z0');
      expect(service.authUserId, 'auth-existing');
      expect(gateway.signInCount, 1);
      expect(gateway.resolveCount, 1);
      expect(gateway.createCount, 0);
    },
  );

  test('rebuild and concurrent initialization share one operation', () async {
    final gateway = _FakeIdentityGateway(
      resolution: const {'status': 'needs_profile'},
    );
    final service = IdentityService.test(
      gateway: gateway,
      store: _MemoryIdentityStore(),
    );

    await Future.wait([service.initialize(), service.initialize()]);

    expect(gateway.signInCount, 1);
    expect(gateway.resolveCount, 1);
  });

  test('legacy code is preserved but never automatically claimed', () async {
    final gateway = _FakeIdentityGateway(
      resolution: const {
        'status': 'legacy_unverified',
        'user_code': 'User-B7Z0',
        'zone': 4,
      },
    );
    final store = _MemoryIdentityStore(userCode: 'User-B7Z0', zone: 4);
    final service = IdentityService.test(gateway: gateway, store: store);

    await service.initialize();

    expect(service.status, IdentityStatus.legacyUnverified);
    expect(service.userCode, 'User-B7Z0');
    expect(service.canWriteRemotely, isFalse);
    expect(gateway.receivedLegacyCode, 'User-B7Z0');
    expect(gateway.createCount, 0);
  });

  test(
    'local code absent on backend is securely bound to current auth user',
    () async {
      final gateway = _FakeIdentityGateway(
        resolution: const {'status': 'needs_profile'},
        createdProfile: const {
          'status': 'created',
          'auth_user_id': 'auth-new',
          'user_code': 'User-C3D4',
          'zone': 2,
        },
      );
      final service = IdentityService.test(
        gateway: gateway,
        store: _MemoryIdentityStore(userCode: 'User-C3D4', zone: 2),
      );

      await service.initialize();

      expect(service.status, IdentityStatus.ready);
      expect(service.userCode, 'User-C3D4');
      expect(gateway.receivedPreferredCode, 'User-C3D4');
      expect(gateway.createCount, 1);
    },
  );

  test(
    'offline startup preserves cached identity without creating another',
    () async {
      final gateway = _FakeIdentityGateway(
        resolution: const {'status': 'needs_profile'},
        error: TimeoutException('offline'),
      );
      final service = IdentityService.test(
        gateway: gateway,
        store: _MemoryIdentityStore(userCode: 'User-B7Z0', zone: 4),
      );

      await service.initialize();

      expect(service.status, IdentityStatus.offlineCached);
      expect(service.userCode, 'User-B7Z0');
      expect(service.canWriteRemotely, isFalse);
      expect(gateway.createCount, 0);
    },
  );

  test(
    'missing auth migration creates and reuses one local User code',
    () async {
      final gateway = _FakeIdentityGateway(
        resolution: const {'status': 'needs_profile'},
        error: const IdentityException('rpc_not_available'),
      );
      final store = _MemoryIdentityStore();
      final service = IdentityService.test(gateway: gateway, store: store);

      await service.initialize();
      final first = await service.createProfile(zone: 3);
      final second = await service.createProfile(zone: 3);

      expect(first.userCode, matches(r'^User-[A-Z0-9]{4}$'));
      expect(second.userCode, first.userCode);
      expect(store.userCode, first.userCode);
      expect(store.zone, 3);
      expect(store.saveCount, 1);
      expect(service.status, IdentityStatus.localFallback);
    },
  );

  test('fallback preserves an existing User code', () async {
    final gateway = _FakeIdentityGateway(
      resolution: const {'status': 'needs_profile'},
      error: const IdentityException('rpc_not_available'),
    );
    final store = _MemoryIdentityStore(userCode: 'User-B7Z0', zone: 4);
    final service = IdentityService.test(gateway: gateway, store: store);

    await service.initialize();
    final profile = await service.createProfile(zone: 4);

    expect(profile.userCode, 'User-B7Z0');
    expect(store.userCode, 'User-B7Z0');
  });

  test(
    'SQL derives protected authors from auth uid and blocks legacy RPCs',
    () {
      final identitySql = File(
        'supabase/migrations/anonymous_auth_identity.sql',
      ).readAsStringSync();
      final wallSql = File(
        'supabase/migrations/wall_interactions_and_history.sql',
      ).readAsStringSync();

      expect(identitySql, contains('NEW.auth_user_id := current_auth_user_id'));
      expect(identitySql, contains('NEW.user_code := current_user_code'));
      expect(identitySql, contains('legacy_unverified'));
      expect(identitySql, contains('auth_user_id = (SELECT auth.uid())'));
      expect(identitySql, contains('p_zone > 10'));
      expect(
        identitySql,
        contains('NEW.user_code IS NOT DISTINCT FROM OLD.user_code'),
      );
      expect(
        identitySql,
        contains('REVOKE ALL ON FUNCTION public.add_vecino_points'),
      );
      expect(wallSql, isNot(contains('p_user_code TEXT')));
      expect(wallSql, contains('WHERE auth_user_id = current_auth_user_id'));
      expect(wallSql, contains('TO authenticated'));
    },
  );

  test('identity source never logs tokens or service role credentials', () {
    final source = File(
      'lib/services/identity_service.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('access_token')));
    expect(source, isNot(contains('refresh_token')));
    expect(source, isNot(contains('service_role')));
    expect(source, isNot(contains('currentSession?.accessToken')));
  });

  test('legacy demo writes keep user code until auth migration is applied', () {
    final reportSource = File(
      'lib/services/report_service.dart',
    ).readAsStringSync();
    final sosSource = File(
      'lib/services/supabase_service.dart',
    ).readAsStringSync();
    final paymentSource = File(
      'lib/services/payment_service.dart',
    ).readAsStringSync();

    expect(reportSource, contains("'user_code': userCode"));
    expect(sosSource, contains("'user_code': userCode"));
    expect(paymentSource, isNot(contains("'userCode': userCode")));
  });

  test('premium Edge Function derives profile from the authenticated JWT', () {
    final source = File(
      'supabase/functions/mercadopago-premium/index.ts',
    ).readAsStringSync();

    expect(source, contains('supabase.auth.getUser(token)'));
    expect(source, contains('.eq("auth_user_id", authData.user.id)'));
    expect(source, contains('profile.userCode'));
    expect(source, isNot(contains('const { userCode } = await req.json()')));
  });
}
