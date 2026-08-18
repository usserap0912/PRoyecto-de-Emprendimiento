import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('report video exposes standard controls without autoplay', () {
    final source = File(
      'lib/widgets/report_video_player.dart',
    ).readAsStringSync();

    expect(source, contains('Icons.play_arrow'));
    expect(source, contains('Icons.pause'));
    expect(
      source,
      contains("tooltip: _isMuted ? 'Activar sonido' : 'Silenciar'"),
    );
    expect(source, contains('await _controller.setVolume(0)'));
    expect(source, contains('Duration(milliseconds: position.round())'));
    expect(source, contains('_format(value.position)'));
    expect(
      source,
      isNot(contains('initialize().then((_) {\n        _controller.play()')),
    );
  });

  test('video playback is stopped and controller released on dispose', () {
    final source = File(
      'lib/widgets/report_video_player.dart',
    ).readAsStringSync();

    expect(source, contains('_controller.pause()'));
    expect(source, contains('_controller.dispose()'));
  });
}
