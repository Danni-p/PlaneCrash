import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../engine/physics_engine.dart';
import '../l10n/app_localizations.dart';
import '../models/broadcast_message.dart';
import '../models/game_phase.dart';
import '../models/game_state.dart';
import '../models/weather_inputs.dart';
import '../services/audio_service.dart';
import '../services/room_code_generator.dart';
import '../services/supabase_service.dart';
import '../utils/labels.dart';
import '../utils/reconnect_guard.dart';
import '../widgets/artificial_horizon.dart';
import '../widgets/island_distance_overlay.dart';
import '../widgets/island_viewport_layout.dart';
import '../widgets/neon_display.dart';
import '../widgets/phase_scenery.dart';
import '../widgets/radar_display.dart';
import 'success_screen.dart';

/// The tablet cockpit: creates a room, runs the authoritative simulation and
/// renders the flight visuals for the whole group.
class CockpitScreen extends StatefulWidget {
  const CockpitScreen({super.key});

  @override
  State<CockpitScreen> createState() => _CockpitScreenState();
}

class _CockpitScreenState extends State<CockpitScreen>
    with SingleTickerProviderStateMixin {
  final GameState _gameState = GameState();
  final AudioService _audio = AudioService();
  final math.Random _random = math.Random();

  late final String _roomCode;
  late final Ticker _ticker;
  RoomConnection? _room;

  bool _realtimeReady = false;
  String? _realtimeError;
  bool _isReconnecting = false;
  final ReconnectGuard _reconnectGuard = ReconnectGuard();

  Duration _lastTick = Duration.zero;
  GamePhase _lastPhase = GamePhase.waiting;
  WeatherInputs _lastWeather = const WeatherInputs();
  bool _navigated = false;
  bool _waterImpactPlayed = false;
  double _flicker = 0.0;

  static const Duration _controllerHeartbeatInterval = Duration(seconds: 3);
  static const Duration _controllerHeartbeatTimeout = Duration(seconds: 12);

  String? _activeControllerSource;
  DateTime? _activeControllerLastHeartbeat;
  Timer? _controllerWatchdog;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _roomCode = RoomCodeGenerator.generate();
    _gameState.addListener(_onGameStateChanged);

    if (SupabaseService.isConfigured) {
      _openRoom();
    }

    _ticker = createTicker(_onTick)..start();
  }

  Future<void> _openRoom() async {
    final room = SupabaseService.openRoom(_roomCode);
    room.onControllerClaimRequest(
      (request) => _onControllerClaimRequest(room, request),
    );
    room.onControllerHeartbeat(_onControllerHeartbeat);
    room.onCounterUpdate((update) {
      if (!_isFromActiveController(update.source)) return;
      _gameState.applyCounterUpdate(update);
    });
    room.onWeatherUpdate((update) {
      if (!_isFromActiveController(update.source)) return;
      _gameState.applyWeatherUpdate(update);
    });
    room.onSettingsUpdate((update) {
      if (!_isFromActiveController(update.source)) return;
      _gameState.applySettingsUpdate(update);
    });
    room.onAltitudeBoost((boost) {
      if (!_isFromActiveController(boost.source)) return;
      _gameState.applyAltitudeBoost(boost);
    });
    room.onPhaseAction((message) {
      if (!_isFromActiveController(message.source)) return;
      debugPrint('Cockpit received phase action: ${message.action}');
      _gameState.applyPhaseAction(message.action);
    });
    room.onConnectionStateChanged(_onConnectionStateChanged);
    final ok = await room.connect();
    if (!mounted) return;
    setState(() {
      _room = room;
      _realtimeReady = ok;
      _realtimeError = ok ? null : (room.subscribeError ?? 'unknown');
    });

    if (ok) {
      _controllerWatchdog ??= Timer.periodic(
        _controllerHeartbeatInterval,
        (_) => _checkControllerTimeout(),
      );
    }
  }

  void _onConnectionStateChanged(bool connected, String? error) {
    if (!mounted) return;
    setState(() {
      _realtimeReady = connected;
      _realtimeError = connected ? null : error;
    });
    if (!connected && _room != null) {
      _reconnectRoom();
    }
  }

  Future<void> _reconnectRoom() async {
    final room = _room;
    if (room == null) return;

    await _reconnectGuard.run(() async {
      if (!mounted || _room == null) return;
      setState(() => _isReconnecting = true);
      final ok = await room.reconnect();
      if (!mounted) return;
      setState(() {
        _isReconnecting = false;
        _realtimeReady = ok;
        _realtimeError = ok ? null : (room.subscribeError ?? 'unknown');
      });
    });
  }

  bool _isFromActiveController(String source) {
    final active = _activeControllerSource;
    return active != null && source == active;
  }

  void _onControllerClaimRequest(
    RoomConnection room,
    ControllerClaimRequest request,
  ) {
    _checkControllerTimeout();

    final active = _activeControllerSource;
    if (active == null) {
      _activeControllerSource = request.source;
      _activeControllerLastHeartbeat = DateTime.now();
      debugPrint('Cockpit accepted controller claim: source=${request.source}');
      room.sendControllerClaimResponse(
        ControllerClaimResponse(
          targetSource: request.source,
          accepted: true,
          activeSource: request.source,
          expiresInMs: _controllerHeartbeatTimeout.inMilliseconds,
        ),
      );
      return;
    }

    debugPrint(
      'Cockpit rejected controller claim: source=${request.source} active=$active',
    );
    room.sendControllerClaimResponse(
      ControllerClaimResponse(
        targetSource: request.source,
        accepted: false,
        activeSource: active,
        expiresInMs: _controllerHeartbeatTimeout.inMilliseconds,
      ),
    );
  }

  void _onControllerHeartbeat(ControllerHeartbeat heartbeat) {
    if (!_isFromActiveController(heartbeat.source)) return;
    _activeControllerLastHeartbeat = DateTime.now();
  }

  void _checkControllerTimeout() {
    final active = _activeControllerSource;
    if (active == null) return;
    final last = _activeControllerLastHeartbeat;
    if (last == null) return;

    final now = DateTime.now();
    if (now.difference(last) <= _controllerHeartbeatTimeout) return;

    debugPrint('Cockpit released controller claim due to timeout: $active');
    _activeControllerSource = null;
    _activeControllerLastHeartbeat = null;
    _room?.sendControllerReleased(
      ControllerReleased(activeSource: active, reason: 'timeout'),
    );
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0 || _navigated) return;
    _gameState.advance(dt.clamp(0.0, 0.1));
    _updateStormEffects(dt);
  }

  void _updateStormEffects(double dt) {
    final intensity = _gameState.stormIntensity;
    // Lightning flashes decay quickly; randomly retrigger while it storms.
    _flicker = math.max(0.0, _flicker - dt * 4.0);
    if (intensity > 0.2 && _random.nextDouble() < 0.04 * intensity) {
      _flicker = 0.6 * intensity;
    }
  }

  void _onGameStateChanged() {
    final phase = _gameState.phase;
    final weather = _gameState.weather;
    final phaseChanged = phase != _lastPhase;

    if (phaseChanged) {
      final previous = _lastPhase;
      _lastPhase = phase;

      switch (phase) {
        case GamePhase.cruise:
          _audio.startCabinNoise();
        case GamePhase.malfunction:
          _runMalfunctionSequence();
        case GamePhase.briefing:
          _audio.stopDanger();
          _audio.playWarningSpeech();
        case GamePhase.emergency:
          _syncWeatherAudio(force: true);
        case GamePhase.finished:
          _handleFinished();
        case GamePhase.waiting:
          if (previous != GamePhase.waiting) {
            _audio.stopAll();
            _waterImpactPlayed = false;
            _lastWeather = const WeatherInputs();
          }
      }

      if (previous == GamePhase.emergency && phase != GamePhase.emergency) {
        _audio.setThunderstormActive(false);
        _audio.setWindActive(false);
        _lastWeather = weather;
      }
    } else if (phase == GamePhase.emergency) {
      _syncWeatherAudio();
    }
  }

  void _syncWeatherAudio({bool force = false}) {
    final weather = _gameState.weather;
    if (!force &&
        weather.thunderstorm == _lastWeather.thunderstorm &&
        weather.windLeft == _lastWeather.windLeft &&
        weather.windRight == _lastWeather.windRight) {
      return;
    }
    _lastWeather = weather;
    _audio.setThunderstormActive(weather.thunderstorm);
    _audio.setWindActive(weather.windLeft || weather.windRight);
  }

  Future<void> _runMalfunctionSequence() async {
    await _audio.startDanger();
    await Future.delayed(GameState.malfunctionDuration);
    if (mounted && _gameState.phase == GamePhase.malfunction) {
      _gameState.enterBriefing();
    }
  }

  Future<void> _handleFinished() async {
    if (_navigated) return;
    if (!_waterImpactPlayed && _gameState.distanceToIsland > 0) {
      _waterImpactPlayed = true;
      await _audio.playWaterImpact();
      await Future.delayed(const Duration(milliseconds: 300));
    }
    _goToSuccess();
  }

  void _goToSuccess() {
    if (_navigated) return;
    _navigated = true;
    _audio.stopAll();
    final stats = _gameState;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SuccessScreen(
          distanceToIsland: stats.distanceToIsland.round(),
          peakLeft: stats.peakLeft,
          peakRight: stats.peakRight,
          weatherAtEnd: stats.weather,
          durationSeconds: stats.elapsedSeconds,
          altitudeBoostTotal: stats.altitudeBoostTotal,
        ),
      ),
    );
  }

  Future<void> _endSession() async {
    await _room?.sendSessionCancel();
    await _room?.disconnect();
    _gameState.resetToWaiting();
    _audio.stopAll();
    if (!SupabaseService.isConfigured) return;
    await _openRoom();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _gameState.removeListener(_onGameStateChanged);
    _gameState.dispose();
    _room?.disconnect();
    _controllerWatchdog?.cancel();
    _audio.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: ListenableBuilder(
        listenable: _gameState,
        builder: (context, _) {
          final state = _gameState;
          final islandApproach = IslandViewportLayout.visualApproachFromDistance(
            distanceMeters: state.distanceToIsland,
            initialDistance: PhysicsEngine.initialDistance,
          );
          final shakeAmp = 6.0 * state.stormIntensity;
          final shake = Offset(
            (_random.nextDouble() * 2 - 1) * shakeAmp,
            (_random.nextDouble() * 2 - 1) * shakeAmp,
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              PhaseScenery(
                phase: state.phase,
                cruiseProgress: state.cruiseProgress,
                islandApproach: islandApproach,
                relativeBearing: state.relativeBearing,
                stormIntensity: state.stormIntensity,
                altitude: state.altitude,
                horizonReferenceAltitude: state.horizonReferenceAltitude,
              ),
              if (state.phase == GamePhase.emergency)
                IslandDistanceOverlay(
                  distanceMeters: state.distanceToIsland.round(),
                  relativeBearing: state.relativeBearing,
                  islandApproach: islandApproach,
                  altitude: state.altitude,
                  horizonReferenceAltitude: state.horizonReferenceAltitude,
                  unit: l10n.unitMeters,
                ),
              Transform.translate(
                offset: shake,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _buildPhaseContent(state, l10n),
                  ),
                ),
              ),
              if (_flicker > 0)
                IgnorePointer(
                  child: Container(
                    color: Colors.white.withValues(alpha: _flicker.clamp(0.0, 1.0)),
                  ),
                ),
              _buildTopBar(l10n),
              if (!SupabaseService.isConfigured) _buildConfigError(l10n),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTopBar(AppLocalizations l10n) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildRoomCodeBadge(l10n),
            OutlinedButton.icon(
              onPressed: _endSession,
              icon: const Icon(Icons.power_settings_new),
              label: Text(l10n.cockpitEndSession),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomCodeBadge(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.cockpitWaitingTitle.toUpperCase(),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _roomCode,
            style: const TextStyle(
              color: Color(0xFF39FF14),
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              shadows: [Shadow(color: Color(0xFF39FF14), blurRadius: 8)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigError(AppLocalizations l10n) {
    return Positioned(
      left: 24,
      right: 24,
      bottom: 24,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade900,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          l10n.cockpitConfigError,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildPhaseContent(GameState state, AppLocalizations l10n) {
    switch (state.phase) {
      case GamePhase.waiting:
        return _buildWaiting(l10n);
      case GamePhase.cruise:
        return _buildBanner(l10n.phaseCruiseBanner, Icons.flight_takeoff);
      case GamePhase.malfunction:
        return _buildMalfunction(l10n);
      case GamePhase.briefing:
        return _buildBriefing(l10n);
      case GamePhase.emergency:
        return _buildEmergencyHud(state, l10n);
      case GamePhase.finished:
        return const SizedBox.shrink();
    }
  }

  Widget _buildWaiting(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.cockpitWaitingTitle.toUpperCase(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 22,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _roomCode,
            style: const TextStyle(
              color: Color(0xFF39FF14),
              fontSize: 84,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              shadows: [Shadow(color: Color(0xFF39FF14), blurRadius: 24)],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.cockpitWaitingHint,
            style: const TextStyle(color: Colors.white70, fontSize: 18),
          ),
          const SizedBox(height: 16),
          if (SupabaseService.isConfigured) _buildRealtimeStatus(l10n),
        ],
      ),
    );
  }

  Widget _buildRealtimeStatus(AppLocalizations l10n) {
    if (_isReconnecting) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            l10n.cockpitReconnecting,
            style: const TextStyle(color: Colors.amberAccent),
          ),
        ],
      );
    }
    if (!_realtimeReady && _realtimeError == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            l10n.cockpitConnecting,
            style: const TextStyle(color: Colors.white54),
          ),
        ],
      );
    }
    if (_realtimeReady) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi, color: Color(0xFF39FF14), size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              l10n.cockpitRealtimeReady,
              style: const TextStyle(color: Color(0xFF39FF14), fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }
    return Text(
      l10n.cockpitRealtimeFailed(_realtimeError ?? '?'),
      style: const TextStyle(color: Colors.redAccent, fontSize: 14),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildBanner(String text, IconData icon) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMalfunction(AppLocalizations l10n) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade900.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.yellowAccent, width: 3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.yellowAccent, size: 48),
            const SizedBox(width: 16),
            Text(
              l10n.malfunctionWarning,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBriefing(AppLocalizations l10n) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.map, color: Color(0xFF39FF14), size: 56),
              const SizedBox(height: 16),
              Text(
                l10n.briefingTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.briefingBody,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 18),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.briefingWaiting,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmergencyHud(GameState state, AppLocalizations l10n) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Avoid RenderFlex overflows on smaller landscape heights by scaling the
        // HUD widgets (the original design used fixed pixel sizes).
        final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 600.0;
        final scale = (h / 520.0).clamp(0.65, 1.0);
        final horizonSize = (140.0 * scale).clamp(90.0, 140.0);

        return Stack(
          children: [
            if (state.weather.windLeft || state.weather.windRight)
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(top: 8 * scale),
                  child: _buildWindWarning(l10n, state, scale),
                ),
              ),
            if (kDebugMode)
              Positioned(
                top: 52 * scale,
                left: 8 * scale,
                child: Text(
                  'bank/person: ${state.bankPerPerson.toStringAsFixed(1)}°  '
                  'target: ${state.targetBankAngle.toStringAsFixed(1)}°  '
                  'display: ${state.displayBankAngle.toStringAsFixed(1)}°',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11 * scale,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            Align(
              alignment: Alignment.bottomLeft,
              child: NeonDisplay(
                label: l10n.labelAltitude,
                value: state.altitude.round().toString(),
                unit: l10n.unitMeters,
                scale: scale,
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadarDisplay(
                    relativeBearingRad: state.relativeBearing,
                    distanceMeters: state.distanceToIsland,
                    size: horizonSize,
                  ),
                  SizedBox(width: 8 * scale),
                  ArtificialHorizon(
                    bankAngleDegrees: state.displayBankAngle,
                    size: horizonSize,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWindWarning(
    AppLocalizations l10n,
    GameState state,
    double scale,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 20 * scale,
        vertical: 10 * scale,
      ),
      decoration: BoxDecoration(
        color: Colors.amber.shade900.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.yellowAccent, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.air, color: Colors.yellowAccent, size: 28 * scale),
          SizedBox(width: 12 * scale),
          Text(
            Labels.windWarning(l10n, state.weather),
            style: TextStyle(
              color: Colors.white,
              fontSize: 18 * scale,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
