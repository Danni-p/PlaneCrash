import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Plays ambient flight sound, one-shot effects (alarm, thunder) and the German
/// emergency voice line.
///
/// Audio assets are optional: if a file is missing, playback is silently skipped
/// so the game still runs without bundled sound. The spoken line falls back to
/// the device text-to-speech engine.
class AudioService {
  final AudioPlayer _ambient = AudioPlayer();
  final AudioPlayer _effect = AudioPlayer();
  final FlutterTts _tts = FlutterTts();

  bool _ttsReady = false;

  /// Starts a looping engine hum at a low volume.
  Future<void> startEngineHum() async {
    await _safe(() async {
      await _ambient.setReleaseMode(ReleaseMode.loop);
      await _ambient.setVolume(0.4);
      await _ambient.play(AssetSource('audio/engine.mp3'));
    });
  }

  Future<void> stopEngineHum() async {
    await _safe(_ambient.stop);
  }

  Future<void> playAlarm() async {
    await _safe(() => _effect.play(AssetSource('audio/alarm.mp3')));
  }

  Future<void> playThunder() async {
    await _safe(() => _effect.play(AssetSource('audio/thunder.mp3')));
  }

  /// Speaks [text] in German.
  Future<void> speak(String text) async {
    await _safe(() async {
      if (!_ttsReady) {
        await _tts.setLanguage('de-DE');
        await _tts.setSpeechRate(0.45);
        _ttsReady = true;
      }
      await _tts.stop();
      await _tts.speak(text);
    });
  }

  Future<void> stopAll() async {
    await _safe(_ambient.stop);
    await _safe(_effect.stop);
    await _safe(_tts.stop);
  }

  void dispose() {
    _ambient.dispose();
    _effect.dispose();
    _tts.stop();
  }

  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      // Missing asset or unavailable engine: degrade gracefully to silence.
      debugPrint('AudioService: skipped playback ($error)');
    }
  }
}
