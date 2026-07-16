import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

// ============================================================
// SOUND SERVICE — Efectos de sonido profesionales
// ============================================================
// Sintetiza WAV en memoria para toda la app:
//
//   ZoneBot:    thinking / happy / idle
//   Navegación: nav_tap (click suave al cambiar tab)
//               button_click (botones generales)
//   SOS:        sos_alarm (sirena urgente)
//               sos_sent (confirmación de alerta)
//   Sistema:    welcome (entrada a la app)
//               report_sent (reporte exitoso)
//               zonebot_open (abrir chat ZoneBot)
// ============================================================

/// Servicio de efectos de sonido para toda la app SafeZone.
class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  final AudioPlayer _player = AudioPlayer();
  final AudioPlayer _loopingPlayer = AudioPlayer();
  bool _isMuted = false;

  // WAV sintetizados en memoria
  Uint8List? _thinkingWav;
  Uint8List? _happyWav;
  Uint8List? _idleWav;
  Uint8List? _navTapWav;
  Uint8List? _buttonClickWav;
  Uint8List? _sosAlarmWav;
  Uint8List? _sosSentWav;
  Uint8List? _welcomeWav;
  Uint8List? _reportSentWav;
  Uint8List? _zonebotOpenWav;
  Uint8List? _fanfareWav;

  bool _initialized = false;

  /// Inicializa el servicio sintetizando todos los WAV en memoria.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _thinkingWav = _generateThinkingChime();
      _happyWav = _generateHappyJingle();
      _idleWav = _generateIdlePulse();
      _navTapWav = _generateNavTap();
      _buttonClickWav = _generateButtonClick();
      _sosAlarmWav = _generateSosAlarm();
      _sosSentWav = _generateSosSent();
      _welcomeWav = _generateWelcome();
      _reportSentWav = _generateReportSent();
      _zonebotOpenWav = _generateZonebotOpen();
      _fanfareWav = _generateFanfare();
      _initialized = true;
      debugPrint('SoundService: ${11} sonidos sintetizados correctamente');
    } catch (e) {
      debugPrint('SoundService: Error inicializando: $e');
    }
  }

  void setMuted(bool value) {
    _isMuted = value;
    if (value) {
      _player.stop();
      _loopingPlayer.stop();
    }
  }

  bool get isMuted => _isMuted;

  /// Reproduce un sonido por nombre.
  Future<void> play(String soundName) async {
    if (_isMuted || !_initialized) return;
    try {
      Uint8List? wavData;
      switch (soundName) {
        case 'thinking':    wavData = _thinkingWav; break;
        case 'happy':       wavData = _happyWav; break;
        case 'idle':        wavData = _idleWav; break;
        case 'nav_tap':     wavData = _navTapWav; break;
        case 'button_click': wavData = _buttonClickWav; break;
        case 'sos_alarm':   wavData = _sosAlarmWav; break;
        case 'sos_sent':    wavData = _sosSentWav; break;
        case 'welcome':     wavData = _welcomeWav; break;
        case 'report_sent': wavData = _reportSentWav; break;
        case 'zonebot_open': wavData = _zonebotOpenWav; break;
        case 'fanfare':     wavData = _fanfareWav; break;
        default:            wavData = _idleWav;
      }
      if (wavData == null) return;
      await _player.stop();
      await _player.play(BytesSource(wavData));
    } catch (e) {
      debugPrint('SoundService: Error reproduciendo $soundName: $e');
    }
  }

  /// Reproduce la alarma SOS en loop continuo (alta intensidad).
  /// Usa un segundo AudioPlayer dedicado para no interrumpir otros sonidos.
  Future<void> playLoopingSosAlarm() async {
    if (_isMuted || !_initialized) return;
    try {
      await _loopingPlayer.stop();
      await _loopingPlayer.setVolume(1.0);
      await _loopingPlayer.setReleaseMode(ReleaseMode.loop);
      if (_sosAlarmWav != null) {
        await _loopingPlayer.play(BytesSource(_sosAlarmWav!));
      }
    } catch (e) {
      debugPrint('SoundService: Error reproduciendo alarma loop: $e');
    }
  }

  /// Detiene la alarma SOS loop y cualquier otro sonido.
  Future<void> stop({bool stopLooping = true}) async {
    try {
      await _player.stop();
      if (stopLooping) {
        await _loopingPlayer.stop();
        await _loopingPlayer.setReleaseMode(ReleaseMode.stop);
      }
    } catch (e) {
      debugPrint('SoundService: Error deteniendo sonido: $e');
    }
  }

  /// Atajo para reproducir sonido de estado de ZoneBot.
  Future<void> playStateSound(String state) => play(state);

  // ============================================================
  // SÍNTESIS WAV — Generación de formas de onda
  // ============================================================

  Uint8List _encodeWav(List<double> samples, {int sampleRate = 44100}) {
    const numChannels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    final dataSize = samples.length * bitsPerSample ~/ 8;
    final fileSize = 44 + dataSize;
    final buffer = ByteData(fileSize);

    // RIFF header
    buffer.setUint8(0, 0x52); buffer.setUint8(1, 0x49);
    buffer.setUint8(2, 0x46); buffer.setUint8(3, 0x46);
    buffer.setUint32(4, fileSize - 8, Endian.little);
    buffer.setUint8(8, 0x57); buffer.setUint8(9, 0x41);
    buffer.setUint8(10, 0x56); buffer.setUint8(11, 0x45);

    // fmt chunk
    buffer.setUint8(12, 0x66); buffer.setUint8(13, 0x6D);
    buffer.setUint8(14, 0x74); buffer.setUint8(15, 0x20);
    buffer.setUint32(16, 16, Endian.little);
    buffer.setUint16(20, 1, Endian.little);
    buffer.setUint16(22, numChannels, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, byteRate, Endian.little);
    buffer.setUint16(32, numChannels * bitsPerSample ~/ 8, Endian.little);
    buffer.setUint16(34, bitsPerSample, Endian.little);

    // data chunk
    buffer.setUint8(36, 0x64); buffer.setUint8(37, 0x61);
    buffer.setUint8(38, 0x74); buffer.setUint8(39, 0x61);
    buffer.setUint32(40, dataSize, Endian.little);

    for (int i = 0; i < samples.length; i++) {
      final sample = (samples[i] * 32767).clamp(-32767, 32767).toInt();
      buffer.setInt16(44 + i * 2, sample, Endian.little);
    }
    return buffer.buffer.asUint8List();
  }

  /// Helper: genera una onda senoidal con envelope.
  List<double> _sineTone({
    required double freq,
    required double durationSec,
    double amplitude = 0.3,
    int sampleRate = 44100,
    double attack = 0.02,
    double release = 0.05,
  }) {
    final n = (sampleRate * durationSec).toInt();
    return List.generate(n, (i) {
      final t = i / sampleRate;
      final env = math.min(1.0, t / attack) * math.min(1.0, (durationSec - t) / release);
      return amplitude * env * math.sin(2 * math.pi * freq * t);
    });
  }

  /// ============================================================
  // 1. Thinking Chime: ascendente 400→800 Hz, 0.3s
  // ============================================================
  Uint8List _generateThinkingChime() {
    const sr = 44100, dur = 0.3;
    final n = (sr * dur).toInt();
    return _encodeWav(List.generate(n, (i) {
      final t = i / sr, p = i / n;
      return 0.3 * (1 - p * 0.5) * math.sin(2 * math.pi * (400 + p * 400) * t);
    }));
  }

  /// ============================================================
  // 2. Happy Jingle: C5→E5→G5, 0.8s
  // ============================================================
  Uint8List _generateHappyJingle() {
    const sr = 44100;
    final notes = [523.25, 659.25, 783.99];
    final dur = 0.8, noteLen = dur / notes.length;
    final n = (sr * dur).toInt();
    final s = List.filled(n, 0.0);
    for (int k = 0; k < notes.length; k++) {
      final start = (k * noteLen * sr).toInt();
      final end = ((k + 1) * noteLen * sr).toInt().clamp(0, n);
      for (int i = start; i < end; i++) {
        final p = (i - start) / (end - start);
        s[i] = 0.25 * (1 - p * 0.6) * math.sin(2 * math.pi * notes[k] * (i / sr));
      }
    }
    return _encodeWav(s);
  }

  /// ============================================================
  // 3. Idle Pulse: 220 Hz suave, 1s
  // ============================================================
  Uint8List _generateIdlePulse() {
    const sr = 44100, dur = 1.0;
    final n = (sr * dur).toInt();
    return _encodeWav(List.generate(n, (i) {
      final t = i / sr, p = i / n;
      return 0.15 * math.sin(math.pi * p) * math.sin(2 * math.pi * 220 * t);
    }));
  }

  /// ============================================================
  // 4. Nav Tap: click corto 1kHz, 50ms
  // ============================================================
  Uint8List _generateNavTap() {
    const sr = 44100, dur = 0.05;
    final n = (sr * dur).toInt();
    return _encodeWav(List.generate(n, (i) {
      final t = i / sr, p = i / n;
      return 0.2 * (1 - p) * math.sin(2 * math.pi * 1000 * t);
    }));
  }

  /// ============================================================
  // 5. Button Click: 1.5 kHz + ruido, 30ms
  // ============================================================
  Uint8List _generateButtonClick() {
    const sr = 44100, dur = 0.03;
    final n = (sr * dur).toInt();
    final rng = math.Random(42);
    return _encodeWav(List.generate(n, (i) {
      final t = i / sr, p = i / n;
      final tone = 0.15 * (1 - p) * math.sin(2 * math.pi * 1500 * t);
      final noise = 0.08 * (1 - p) * (rng.nextDouble() * 2 - 1);
      return tone + noise;
    }));
  }

  /// ============================================================
  // 6. SOS Alarm: sirena ondulante 600→900 Hz, 1.5s
  // ============================================================
  Uint8List _generateSosAlarm() {
    const sr = 44100, dur = 1.5;
    final n = (sr * dur).toInt();
    return _encodeWav(List.generate(n, (i) {
      final t = i / sr, p = i / n;
      // Ondulación lenta: 600↔900 Hz cada 0.3s
      final wobble = 600 + 300 * (math.sin(2 * math.pi * (1 / 0.3) * t) + 1) / 2;
      final env = 1.0 - p * 0.3;
      return 0.35 * env * math.sin(2 * math.pi * wobble * t);
    }));
  }

  /// ============================================================
  // 7. SOS Sent: dos tonos ascendentes, 0.6s
  // ============================================================
  Uint8List _generateSosSent() {
    const sr = 44100, dur = 0.6;
    final n = (sr * dur).toInt();
    final s = List.filled(n, 0.0);
    // Primer tono: 800 Hz, segundo: 1200 Hz
    for (int k = 0; k < 2; k++) {
      final start = (k * dur / 2 * sr).toInt();
      final end = ((k + 1) * dur / 2 * sr).toInt().clamp(0, n);
      final freq = 800.0 + k * 400;
      for (int i = start; i < end; i++) {
        final p = (i - start) / (end - start);
        s[i] = 0.3 * (1 - p * 0.4) * math.sin(2 * math.pi * freq * (i / sr));
      }
    }
    return _encodeWav(s);
  }

  /// ============================================================
  // 8. Welcome: arpegio ascendente (C4→E4→G4→C5), 1.2s
  // ============================================================
  Uint8List _generateWelcome() {
    const sr = 44100;
    final notes = [261.63, 329.63, 392.00, 523.25]; // C4 E4 G4 C5
    final dur = 1.2, noteLen = dur / notes.length;
    final n = (sr * dur).toInt();
    final s = List.filled(n, 0.0);
    for (int k = 0; k < notes.length; k++) {
      final start = (k * noteLen * sr).toInt();
      final end = ((k + 1) * noteLen * sr).toInt().clamp(0, n);
      for (int i = start; i < end; i++) {
        final p = (i - start) / (end - start);
        final env = math.sin(math.pi * p); // campana suave
        s[i] = 0.2 * env * math.sin(2 * math.pi * notes[k] * (i / sr));
      }
    }
    return _encodeWav(s);
  }

  /// ============================================================
  // 9. Report Sent: nota corta de confirmación (880 Hz), 0.25s
  // ============================================================
  Uint8List _generateReportSent() {
    return _encodeWav(_sineTone(freq: 880, durationSec: 0.25, amplitude: 0.25));
  }

  /// ============================================================
  // 11. Fanfare: acorde festivo ascendente para celebración de canje, 1.0s
  // ============================================================
  Uint8List _generateFanfare() {
    const sr = 44100, dur = 1.0;
    final n = (sr * dur).toInt();
    final s = List.filled(n, 0.0);
    // Acorde mayor: C4 (261.63) + E4 (329.63) + G4 (392.00) + C5 (523.25)
    final chord = [261.63, 329.63, 392.00, 523.25];
    for (int k = 0; k < chord.length; k++) {
      for (int i = 0; i < n; i++) {
        final t = i / sr, p = i / n;
        final env = math.sin(math.pi * p); // campana suave
        // Cada nota entra escalonadamente
        final delay = k * 0.08;
        final localP = ((t - delay) / dur).clamp(0.0, 1.0);
        final localEnv = localP > 0 ? env : 0.0;
        s[i] += 0.12 * localEnv * math.sin(2 * math.pi * chord[k] * t);
      }
    }
    return _encodeWav(s);
  }

  /// ============================================================
  // 10. ZoneBot Open: dos notas ascendentes (600→900 Hz), 0.3s
  // ============================================================
  Uint8List _generateZonebotOpen() {
    const sr = 44100, dur = 0.3;
    final n = (sr * dur).toInt();
    return _encodeWav(List.generate(n, (i) {
      final t = i / sr, p = i / n;
      final freq = 600 + p * 300;
      return 0.25 * (1 - p * 0.3) * math.sin(2 * math.pi * freq * t);
    }));
  }
}
