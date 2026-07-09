import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

// ============================================================
// SOUND SERVICE
// ============================================================
// Genera y reproduce efectos de sonido para ZoneBot:
//   'thinking' → Chime ascendente corto
//   'happy'    → Jingle alegre (notas ascendentes)
//   'idle'     → Pulso suave ambiente
//
// Los sonidos se sintetizan como WAV en memoria (sin archivos).
// ============================================================

/// Servicio de efectos de sonido para ZoneBot.
///
/// Genera archivos WAV inline usando síntesis de ondas senoidales
/// y los reproduce con audioplayers sin necesidad de archivos externos.
class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  final AudioPlayer _player = AudioPlayer();
  bool _isMuted = false;

  // WAV sintetizados en memoria (BytesData)
  Uint8List? _thinkingWav;
  Uint8List? _happyWav;
  Uint8List? _idleWav;

  bool _initialized = false;

  /// Inicializa el servicio sintetizando los WAV en memoria.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      _thinkingWav = _generateThinkingChime();
      _happyWav = _generateHappyJingle();
      _idleWav = _generateIdlePulse();

      _initialized = true;
      debugPrint('SoundService: Sonidos sintetizados correctamente');
    } catch (e) {
      debugPrint('SoundService: Error inicializando: $e');
    }
  }

  /// Activa/desactiva el sonido.
  void setMuted(bool value) {
    _isMuted = value;
    if (value) _player.stop();
  }

  bool get isMuted => _isMuted;

  /// Reproduce el sonido correspondiente al estado de animación.
  Future<void> playStateSound(String state) async {
    if (_isMuted || !_initialized) return;

    try {
      Uint8List? wavData;
      switch (state) {
        case 'thinking':
          wavData = _thinkingWav;
          break;
        case 'happy':
          wavData = _happyWav;
          break;
        default:
          wavData = _idleWav;
          break;
      }

      if (wavData == null) return;

      // Reproducir desde bytes en memoria
      final source = BytesSource(wavData);
      await _player.stop();
      await _player.play(source);
    } catch (e) {
      debugPrint('SoundService: Error reproduciendo sonido: $e');
    }
  }

  // ============================================================
  // SÍNTESIS WAV
  // ============================================================

  /// Genera un archivo WAV en memoria.
  ///
  /// [samples] son los samples de audio normalizados entre -1.0 y 1.0.
  /// [sampleRate] frecuencia de muestreo (por defecto 44100).
  Uint8List _encodeWav(List<double> samples, {int sampleRate = 44100}) {
    final numChannels = 1;
    final bitsPerSample = 16;
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;

    final dataSize = samples.length * bitsPerSample ~/ 8;
    final fileSize = 44 + dataSize;

    final buffer = ByteData(fileSize);

    // RIFF header
    buffer.setUint8(0, 0x52); // R
    buffer.setUint8(1, 0x49); // I
    buffer.setUint8(2, 0x46); // F
    buffer.setUint8(3, 0x46); // F
    buffer.setUint32(4, fileSize - 8, Endian.little);
    buffer.setUint8(8, 0x57); // W
    buffer.setUint8(9, 0x41); // A
    buffer.setUint8(10, 0x56); // V
    buffer.setUint8(11, 0x45); // E

    // fmt chunk
    buffer.setUint8(12, 0x66); // f
    buffer.setUint8(13, 0x6D); // m
    buffer.setUint8(14, 0x74); // t
    buffer.setUint8(15, 0x20); // (space)
    buffer.setUint32(16, 16, Endian.little); // chunk size
    buffer.setUint16(20, 1, Endian.little); // PCM format
    buffer.setUint16(22, numChannels, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, byteRate, Endian.little);
    buffer.setUint16(32, numChannels * bitsPerSample ~/ 8, Endian.little);
    buffer.setUint16(34, bitsPerSample, Endian.little);

    // data chunk
    buffer.setUint8(36, 0x64); // d
    buffer.setUint8(37, 0x61); // a
    buffer.setUint8(38, 0x74); // t
    buffer.setUint8(39, 0x61); // a
    buffer.setUint32(40, dataSize, Endian.little);

    for (int i = 0; i < samples.length; i++) {
      final sample = (samples[i] * 32767).clamp(-32767, 32767).toInt();
      buffer.setInt16(44 + i * 2, sample, Endian.little);
    }

    return buffer.buffer.asUint8List();
  }

  /// Thinking Chime: tono ascendente rápido (400Hz → 800Hz en 0.3s)
  Uint8List _generateThinkingChime() {
    final sampleRate = 44100;
    final duration = 0.3;
    final nSamples = (sampleRate * duration).toInt();
    final samples = List.filled(nSamples, 0.0);

    for (int i = 0; i < nSamples; i++) {
      final t = i / sampleRate;
      final progress = i / nSamples; // 0.0 → 1.0
      final freq = 400 + progress * 400; // 400Hz → 800Hz
      final envelope = 1.0 - progress * 0.5; // fade out
      samples[i] = 0.3 * envelope * math.sin(2 * math.pi * freq * t);
    }

    return _encodeWav(samples);
  }

  /// Happy Jingle: tres notas ascendentes (C5, E5, G5) en 0.6s
  Uint8List _generateHappyJingle() {
    final sampleRate = 44100;
    final noteDuration = 0.2;
    final totalDuration = 0.8;
    final nSamples = (sampleRate * totalDuration).toInt();
    final samples = List.filled(nSamples, 0.0);

    final notes = [523.25, 659.25, 783.99]; // C5, E5, G5

    for (int note = 0; note < notes.length; note++) {
      final startSample = (note * noteDuration * sampleRate).toInt();
      final endSample =
          ((note + 1) * noteDuration * sampleRate).toInt().clamp(0, nSamples);

      for (int i = startSample; i < endSample; i++) {
        final t = i / sampleRate;
        final noteProgress = (i - startSample) / (endSample - startSample);
        final envelope = 1.0 - noteProgress * 0.6; // fade out por nota
        samples[i] = 0.25 * envelope * math.sin(2 * math.pi * notes[note] * t);
      }
    }

    return _encodeWav(samples);
  }

  /// Idle Pulse: pulso suave y lento (220Hz con fade in/out, 1s)
  Uint8List _generateIdlePulse() {
    final sampleRate = 44100;
    final duration = 1.0;
    final nSamples = (sampleRate * duration).toInt();
    final samples = List.filled(nSamples, 0.0);

    for (int i = 0; i < nSamples; i++) {
      final t = i / sampleRate;
      final progress = i / nSamples;
      // Envelope tipo respiración: sube y baja suavemente
      final envelope = math.sin(math.pi * progress) * 0.5;
      samples[i] = 0.15 * envelope * math.sin(2 * math.pi * 220 * t);
    }

    return _encodeWav(samples);
  }
}
