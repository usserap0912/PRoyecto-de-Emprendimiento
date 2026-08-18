import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:safezone/models/identity_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum IdentityStatus {
  uninitialized,
  loading,
  needsProfile,
  ready,
  legacyUnverified,
  offlineCached,
  localFallback,
  unavailable,
}

abstract interface class IdentityGateway {
  String? get currentAuthUserId;

  Future<String> ensureAnonymousSession();

  Future<Map<String, dynamic>> resolveIdentity(String? legacyUserCode);

  Future<Map<String, dynamic>> createProfile({
    required int zone,
    String? preferredUserCode,
  });

  Future<void> createLegacyProfile({
    required String userCode,
    required int zone,
  });
}

class SupabaseIdentityGateway implements IdentityGateway {
  SupabaseIdentityGateway({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static const _timeout = Duration(seconds: 10);
  final SupabaseClient _client;

  @override
  String? get currentAuthUserId => _client.auth.currentSession?.user.id;

  @override
  Future<String> ensureAnonymousSession() async {
    final existingUser = _client.auth.currentSession?.user;
    if (existingUser != null) return existingUser.id;

    final response = await _client.auth.signInAnonymously().timeout(_timeout);
    final user = response.user;
    if (user == null) {
      throw const IdentityException('anonymous_session_missing');
    }
    return user.id;
  }

  @override
  Future<Map<String, dynamic>> resolveIdentity(String? legacyUserCode) async {
    final response = await _client
        .rpc(
          'get_current_identity',
          params: {'p_legacy_user_code': legacyUserCode},
        )
        .timeout(_timeout);
    return Map<String, dynamic>.from(response as Map);
  }

  @override
  Future<Map<String, dynamic>> createProfile({
    required int zone,
    String? preferredUserCode,
  }) async {
    final response = await _client
        .rpc(
          'create_current_profile',
          params: {'p_zone': zone, 'p_preferred_user_code': preferredUserCode},
        )
        .timeout(_timeout);
    return Map<String, dynamic>.from(response as Map);
  }

  @override
  Future<void> createLegacyProfile({
    required String userCode,
    required int zone,
  }) async {
    await _client
        .from('profiles')
        .insert({'user_code': userCode, 'zone': zone})
        .timeout(_timeout);
  }
}

abstract interface class IdentityStore {
  Future<String?> readUserCode();

  Future<int?> readZone();

  Future<void> saveIdentity({required String userCode, required int zone});
}

class SharedPreferencesIdentityStore implements IdentityStore {
  static const userCodeKey = 'user_device_code';
  static const zoneKey = 'user_zone';

  @override
  Future<String?> readUserCode() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(userCodeKey);
  }

  @override
  Future<int?> readZone() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getInt(zoneKey);
  }

  @override
  Future<void> saveIdentity({
    required String userCode,
    required int zone,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(userCodeKey, userCode);
    await preferences.setInt(zoneKey, zone);
  }
}

class IdentityException implements Exception {
  const IdentityException(this.code);

  final String code;

  @override
  String toString() => 'IdentityException($code)';
}

class IdentityService extends ChangeNotifier {
  factory IdentityService() => _instance;

  factory IdentityService.test({
    required IdentityGateway gateway,
    required IdentityStore store,
  }) => IdentityService._test(gateway, store);

  IdentityService._() : _store = SharedPreferencesIdentityStore();

  IdentityService._test(this._gateway, this._store);

  static final IdentityService _instance = IdentityService._();

  IdentityGateway? _gateway;
  final IdentityStore _store;
  Future<void>? _initialization;
  IdentityStatus _status = IdentityStatus.uninitialized;
  IdentityProfile? _profile;
  String? _authUserId;

  IdentityStatus get status => _status;
  IdentityProfile? get profile => _profile;
  String? get authUserId => _authUserId;
  String? get userCode => _profile?.userCode;
  int? get zone => _profile?.zone;
  bool get isReady => switch (_status) {
    IdentityStatus.ready ||
    IdentityStatus.legacyUnverified ||
    IdentityStatus.offlineCached ||
    IdentityStatus.localFallback => true,
    _ => false,
  };
  bool get canWriteRemotely => _status == IdentityStatus.ready;

  IdentityGateway get _resolvedGateway =>
      _gateway ??= SupabaseIdentityGateway();

  Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  Future<void> retry() {
    _initialization = null;
    return initialize();
  }

  Future<void> _initialize() async {
    _entryLog('identity_initialization_started');
    _setStatus(IdentityStatus.loading);
    final cachedCode = await _store.readUserCode();
    final cachedZone = await _store.readZone();

    try {
      _authUserId = await _resolvedGateway.ensureAnonymousSession();
      final resolution = await _resolvedGateway.resolveIdentity(cachedCode);
      final remoteStatus = resolution['status'] as String?;

      if (remoteStatus == 'linked') {
        await _acceptRemoteProfile(resolution);
        _entryLog('linked_identity_restored');
        return;
      }
      if (remoteStatus == 'legacy_unverified' &&
          cachedCode != null &&
          cachedZone != null) {
        _profile = IdentityProfile(userCode: cachedCode, zone: cachedZone);
        _setStatus(IdentityStatus.legacyUnverified);
        _entryLog('legacy_identity_restored');
        return;
      }
      if (remoteStatus == 'needs_profile' &&
          cachedCode != null &&
          _isSelectableZone(cachedZone)) {
        final created = await _resolvedGateway.createProfile(
          zone: cachedZone!,
          preferredUserCode: cachedCode,
        );
        await _acceptRemoteProfile(created);
        _entryLog('cached_identity_linked');
        return;
      }

      _profile = null;
      _setStatus(IdentityStatus.needsProfile);
    } catch (error) {
      _logFailure('initialize', error);
      if (cachedCode != null && _isSelectableZone(cachedZone)) {
        _profile = IdentityProfile(userCode: cachedCode, zone: cachedZone!);
        _setStatus(
          _requiresLocalFallback(error)
              ? IdentityStatus.localFallback
              : IdentityStatus.offlineCached,
        );
        _entryLog('cached_identity_available');
      } else {
        _profile = null;
        _setStatus(IdentityStatus.unavailable);
      }
    }
  }

  Future<IdentityProfile> createProfile({required int zone}) async {
    if (!_isSelectableZone(zone)) {
      throw const IdentityException('invalid_zone');
    }
    if (_status == IdentityStatus.legacyUnverified) {
      throw const IdentityException('legacy_profile_requires_verification');
    }

    if (_profile != null &&
        (_status == IdentityStatus.localFallback ||
            _status == IdentityStatus.offlineCached)) {
      return _profile!;
    }

    try {
      _authUserId ??= await _resolvedGateway.ensureAnonymousSession();
      final preferredCode = await _store.readUserCode();
      final created = await _resolvedGateway.createProfile(
        zone: zone,
        preferredUserCode: preferredCode,
      );
      await _acceptRemoteProfile(created);
      _entryLog('remote_identity_created');
      return _profile!;
    } catch (error) {
      _logFailure('create_profile', error);
      return _createLocalFallbackProfile(zone);
    }
  }

  Future<IdentityProfile> _createLocalFallbackProfile(int zone) async {
    final cachedCode = await _store.readUserCode();
    final canReuseCachedCode = _isValidUserCode(cachedCode);
    var userCode = canReuseCachedCode ? cachedCode! : _generateUserCode();

    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        await _resolvedGateway.createLegacyProfile(
          userCode: userCode,
          zone: zone,
        );
        break;
      } on PostgrestException catch (error) {
        if (error.code == '23505') {
          if (canReuseCachedCode) break;
          userCode = _generateUserCode();
          continue;
        }
        _logFailure('legacy_profile_persistence', error);
        break;
      } catch (error) {
        _logFailure('legacy_profile_persistence', error);
        break;
      }
    }

    final profile = IdentityProfile(userCode: userCode, zone: zone);
    _profile = profile;
    await _store.saveIdentity(userCode: userCode, zone: zone);
    _setStatus(IdentityStatus.localFallback);
    _entryLog('local_fallback_identity_ready');
    return profile;
  }

  Future<void> _acceptRemoteProfile(Map<String, dynamic> data) async {
    final accepted = IdentityProfile.fromMap(data);
    _profile = accepted;
    _authUserId = accepted.authUserId ?? _resolvedGateway.currentAuthUserId;
    await _store.saveIdentity(userCode: accepted.userCode, zone: accepted.zone);
    _setStatus(IdentityStatus.ready);
  }

  bool _isSelectableZone(int? value) =>
      value != null && value >= 1 && value <= 10;

  bool _isValidUserCode(String? value) =>
      value != null && RegExp(r'^User-[A-Z0-9]{4,12}$').hasMatch(value);

  String _generateUserCode() {
    const characters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final suffix = List.generate(
      4,
      (_) => characters[random.nextInt(characters.length)],
    ).join();
    return 'User-$suffix';
  }

  bool _requiresLocalFallback(Object error) =>
      error is PostgrestException || error is AuthException;

  void _setStatus(IdentityStatus value) {
    _status = value;
    notifyListeners();
  }

  void _logFailure(String operation, Object error) {
    if (!kDebugMode) return;
    final technicalCode = switch (error) {
      AuthException authError => authError.statusCode ?? authError.code,
      PostgrestException postgrestError => postgrestError.code,
      TimeoutException _ => 'timeout',
      IdentityException identityError => identityError.code,
      _ => error.runtimeType.toString(),
    };
    debugPrint('[ENTRY] $operation failed [$technicalCode]');
  }

  void _entryLog(String step) {
    if (kDebugMode) debugPrint('[ENTRY] $step');
  }
}
