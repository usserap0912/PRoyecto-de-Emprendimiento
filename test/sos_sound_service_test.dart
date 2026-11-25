import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safezone/services/sound_service.dart';

void main() {
  test('SOS uses the new MP3 assets and registers their actual folder', () {
    expect(SoundService.sosActivationAsset, 'sos/alarma-activacion.mp3');
    expect(SoundService.sosReceivedAlertAsset, 'sos/alarma-recepcion.mp3');
    expect(
      File('assets/${SoundService.sosActivationAsset}').existsSync(),
      isTrue,
    );
    expect(
      File('assets/${SoundService.sosReceivedAlertAsset}').existsSync(),
      isTrue,
    );

    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/sos/'));
  });

  test('activation alarm loops continuously at maximum volume', () {
    final source = File('lib/services/sound_service.dart').readAsStringSync();

    expect(source, contains('ReleaseMode.loop'));
    expect(source, contains('setVolume(1.0)'));
    expect(source, contains('AndroidUsageType.alarm'));
    expect(source, contains('stayAwake: true'));
    expect(source, contains('HapticFeedback.vibrate()'));
    expect(source, contains('Timer.periodic'));
    // El aviso de emergencia no debe silenciarse con el Modo Ahorro.
    expect(source, isNot(contains('SosAlarmCycleController')));
  });

  test('SOS integration has explicit start, stop and receiver methods', () {
    final soundSource = File(
      'lib/services/sound_service.dart',
    ).readAsStringSync();
    final sosScreenSource = File(
      'lib/screens/sos/sos_screen.dart',
    ).readAsStringSync();
    final homeSource = File(
      'lib/screens/home/home_screen.dart',
    ).readAsStringSync();

    expect(soundSource, contains('startSosActivationAlarm'));
    expect(soundSource, contains('stopSosActivationAlarm'));
    expect(sosScreenSource, contains('startSosActivationAlarm()'));
    expect(sosScreenSource, contains('stopSosActivationAlarm()'));
    expect(sosScreenSource, isNot(contains("play('sos_activation')")));
    expect(homeSource, contains('playSosReceivedAlert()'));
  });
}
