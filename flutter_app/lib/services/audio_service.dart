import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays cabin ambience, malfunction danger, weather loops, and one-shot cues.
///
/// Audio assets are optional: if a file is missing, playback is silently skipped
/// so the game still runs without bundled sound.
class AudioService {
  static const Duration _fadeDuration = Duration(milliseconds: 2000);
  static const Duration _oneShotGrace = Duration(seconds: 1);

  static const double _cabinVolume = 0.25;
  static const double _dangerVolume = 0.45;
  static const double _weatherVolume = 0.35;
  static const double _oneShotVolume = 0.5;

  final AudioPlayer _cabin = AudioPlayer();
  final AudioPlayer _danger = AudioPlayer();
  final AudioPlayer _thunderstorm = AudioPlayer();
  final AudioPlayer _wind = AudioPlayer();
  final AudioPlayer _oneShot = AudioPlayer();

  Future<void>? _configureFuture;

  Object? _cabinFadeToken;
  Object? _thunderFadeToken;
  Object? _windFadeToken;

  bool _cabinPlaying = false;
  bool _dangerPlaying = false;
  bool _thunderActive = false;
  bool _windActive = false;
  bool _protectOneShot = false;
  Timer? _oneShotProtectTimer;

  /// Starts a looping cabin hum at a low volume.
  Future<void> startCabinNoise() async {
    if (_cabinPlaying) return;
    await _ensureConfigured();
    await _safe(() async {
      _cabinPlaying = true;
      await _cabin.setReleaseMode(ReleaseMode.loop);
      await _cabin.setVolume(0);
      await _cabin.play(AssetSource('audio/cabine-noise.mp3'));
      _cabinFadeToken = Object();
      await _fadeVolume(
        _cabin,
        from: 0,
        to: _cabinVolume,
        token: _cabinFadeToken,
      );
    });
  }

  Future<void> stopCabinNoise() async {
    if (!_cabinPlaying) return;
    await _safe(() async {
      _cabinPlaying = false;
      _cabinFadeToken = null;
      await _cabin.stop();
    });
  }

  /// Loops danger alarm during the malfunction phase.
  Future<void> startDanger() async {
    if (_dangerPlaying) return;
    await _ensureConfigured();
    await _safe(() async {
      _dangerPlaying = true;
      await _danger.setReleaseMode(ReleaseMode.loop);
      await _danger.setVolume(_dangerVolume);
      await _danger.play(AssetSource('audio/danger.mp3'));
    });
  }

  Future<void> stopDanger() async {
    if (!_dangerPlaying) return;
    await _safe(() async {
      _dangerPlaying = false;
      await _danger.stop();
    });
  }

  /// Plays the German warning voice-over once during briefing.
  Future<void> playWarningSpeech() async {
    await _ensureConfigured();
    await _safe(() async {
      await _oneShot.stop();
      await _oneShot.setReleaseMode(ReleaseMode.release);
      await _oneShot.setVolume(_oneShotVolume);
      await _oneShot.play(AssetSource('audio/warningSpeach.mp3'));
    });
  }

  /// Fades thunderstorm loop in/out when the controller toggles the storm.
  Future<void> setThunderstormActive(bool active) async {
    if (_thunderActive == active) return;
    await _ensureConfigured();
    _thunderActive = active;
    if (active) {
      await _fadeInLoop(
        player: _thunderstorm,
        asset: 'audio/thunderstorm.mp3',
        targetVolume: _weatherVolume,
        tokenRef: () => _thunderFadeToken,
        setToken: (t) => _thunderFadeToken = t,
      );
    } else {
      await _fadeOutLoop(
        player: _thunderstorm,
        fromVolume: _weatherVolume,
        tokenRef: () => _thunderFadeToken,
        setToken: (t) => _thunderFadeToken = t,
      );
    }
  }

  /// Fades wind loop in/out when any wind direction is active.
  Future<void> setWindActive(bool active) async {
    if (_windActive == active) return;
    await _ensureConfigured();
    _windActive = active;
    if (active) {
      await _fadeInLoop(
        player: _wind,
        asset: 'audio/wind.mp3',
        targetVolume: _weatherVolume,
        tokenRef: () => _windFadeToken,
        setToken: (t) => _windFadeToken = t,
      );
    } else {
      await _fadeOutLoop(
        player: _wind,
        fromVolume: _weatherVolume,
        tokenRef: () => _windFadeToken,
        setToken: (t) => _windFadeToken = t,
      );
    }
  }

  /// One-shot splash when the plane hits water away from the island.
  Future<void> playWaterImpact() async {
    await _ensureConfigured();
    await _safe(() async {
      _protectOneShot = true;
      _oneShotProtectTimer?.cancel();
      _oneShotProtectTimer = Timer(_oneShotGrace, () {
        _protectOneShot = false;
      });
      await _oneShot.stop();
      await _oneShot.setReleaseMode(ReleaseMode.release);
      await _oneShot.setVolume(_oneShotVolume);
      await _oneShot.play(AssetSource('audio/water-impact.mp3'));
    });
  }

  Future<void> stopAll() async {
    _cabinFadeToken = null;
    _thunderFadeToken = null;
    _windFadeToken = null;
    _cabinPlaying = false;
    _dangerPlaying = false;
    _thunderActive = false;
    _windActive = false;
    _oneShotProtectTimer?.cancel();
    _oneShotProtectTimer = null;

    final protectOneShot = _protectOneShot;
    _protectOneShot = false;

    await _safe(_cabin.stop);
    await _safe(_danger.stop);
    await _safe(_thunderstorm.stop);
    await _safe(_wind.stop);
    if (!protectOneShot) {
      await _safe(_oneShot.stop);
    }
  }

  void dispose() {
    _cabinFadeToken = null;
    _thunderFadeToken = null;
    _windFadeToken = null;
    _oneShotProtectTimer?.cancel();
    _cabin.dispose();
    _danger.dispose();
    _thunderstorm.dispose();
    _wind.dispose();
    _oneShot.dispose();
  }

  Future<void> _fadeInLoop({
    required AudioPlayer player,
    required String asset,
    required double targetVolume,
    required Object? Function() tokenRef,
    required void Function(Object?) setToken,
  }) async {
    await _safe(() async {
      final token = Object();
      setToken(token);
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(0);
      await player.play(AssetSource(asset));
      await _fadeVolume(
        player,
        from: 0,
        to: targetVolume,
        token: token,
        isCancelled: () => tokenRef() != token,
      );
    });
  }

  Future<void> _fadeOutLoop({
    required AudioPlayer player,
    required double fromVolume,
    required Object? Function() tokenRef,
    required void Function(Object?) setToken,
  }) async {
    await _safe(() async {
      final token = Object();
      setToken(token);
      await _fadeVolume(
        player,
        from: fromVolume,
        to: 0,
        token: token,
        isCancelled: () => tokenRef() != token,
      );
      if (tokenRef() == token) {
        await player.stop();
        setToken(null);
      }
    });
  }

  Future<void> _fadeVolume(
    AudioPlayer player, {
    required double from,
    required double to,
    required Object? token,
    bool Function()? isCancelled,
  }) async {
    const steps = 20;
    final stepDuration = _fadeDuration ~/ steps;
    for (var i = 1; i <= steps; i++) {
      if (isCancelled?.call() == true) return;
      final volume = from + (to - from) * (i / steps);
      await player.setVolume(volume.clamp(0.0, 1.0));
      await Future.delayed(stepDuration);
    }
    if (isCancelled?.call() != true) {
      await player.setVolume(to.clamp(0.0, 1.0));
    }
  }

  Future<void> _ensureConfigured() {
    return _configureFuture ??= _configureAudioContext();
  }

  /// audioplayers 6+ takes exclusive audio focus by default; allow layering.
  Future<void> _configureAudioContext() async {
    await _safe(() async {
      final context = AudioContextConfig(
        focus: AudioContextConfigFocus.mixWithOthers,
      ).build();
      await AudioPlayer.global.setAudioContext(context);
      for (final player in [_cabin, _danger, _thunderstorm, _wind, _oneShot]) {
        await player.setAudioContext(context);
      }
    });
  }

  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      debugPrint('AudioService: skipped playback ($error)');
    }
  }
}
