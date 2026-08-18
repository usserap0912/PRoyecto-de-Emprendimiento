import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safezone/services/sound_service.dart';

void main() {
  testWidgets('personal SOS alarm uses one separated replay cycle', (
    tester,
  ) async {
    var playCount = 0;
    var stopCount = 0;
    final controller = SosAlarmCycleController(
      playOnce: () async {
        playCount++;
        return true;
      },
      stopPlayback: () async => stopCount++,
      replayPause: const Duration(seconds: 3),
    );

    await controller.start();
    await controller.start();
    expect(playCount, 1, reason: 'A rebuild must not start a second cycle.');

    controller.playbackCompleted();
    await tester.pump(const Duration(milliseconds: 2999));
    expect(playCount, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(playCount, 2);

    controller.playbackCompleted();
    expect(controller.hasScheduledReplay, isTrue);
    await controller.stop();
    expect(controller.isActive, isFalse);
    expect(controller.hasScheduledReplay, isFalse);
    expect(stopCount, 1);

    await tester.pump(const Duration(seconds: 4));
    expect(playCount, 2, reason: 'No replay may survive SOS completion.');
  });

  testWidgets('blocked audio retries later without overlapping playback', (
    tester,
  ) async {
    var playCount = 0;
    final controller = SosAlarmCycleController(
      playOnce: () async {
        playCount++;
        return playCount > 1;
      },
      stopPlayback: () async {},
      replayPause: const Duration(seconds: 3),
    );

    await controller.start();
    expect(playCount, 1);
    expect(controller.hasScheduledReplay, isTrue);

    await tester.pump(const Duration(seconds: 3));
    expect(playCount, 2);
    expect(controller.hasScheduledReplay, isFalse);

    await controller.stop();
  });

  test('SOS uses the real MP3 assets and registers their actual folder', () {
    expect(SoundService.sosActivationAsset, 'sos/sos-activitation.mp3');
    expect(SoundService.sosReceivedAlertAsset, 'sos/sos-receiveddalert.mp3');
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

    expect(soundSource, contains('setVolume(1.0)'));
    expect(soundSource, isNot(contains('ReleaseMode.loop')));
    expect(sosScreenSource, contains('startSosActivationAlarm()'));
    expect(sosScreenSource, contains('stopSosActivationAlarm()'));
    expect(sosScreenSource, isNot(contains("play('sos_activation')")));
    expect(homeSource, contains('playSosReceivedAlert()'));
  });
}
