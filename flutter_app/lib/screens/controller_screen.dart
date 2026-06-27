import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/broadcast_message.dart';
import '../models/game_phase.dart';
import '../models/game_state.dart';
import '../models/weather_inputs.dart';
import '../models/wind_strength.dart';
import '../engine/physics_engine.dart';
import '../services/room_code_generator.dart';
import '../services/supabase_service.dart';
import '../utils/labels.dart';
import '../utils/reconnect_guard.dart';

/// The phone controller: joins a room by code and sends partial updates. Cabin
/// controls (counters, approach speed) can be pre-set locally; weather toggles
/// activate only during the emergency phase. Any controller can advance flight phases.
class ControllerScreen extends StatefulWidget {
  const ControllerScreen({super.key});

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  final TextEditingController _codeController = TextEditingController();
  // Web note: JS bit-shifts are 32-bit; (1 << 32) becomes 0, which would crash
  // Random().nextInt(max). Use a time+random suffix instead.
  final String _source =
      'ctrl-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-'
      '${Random().nextInt(0x7fffffff).toRadixString(16)}';

  RoomConnection? _room;
  String? _roomCode;
  String? _joinError;
  bool _sessionEnded = false;
  bool _isJoining = false;
  bool _isSubscribed = false;
  bool _isActiveController = false;
  bool _isClaimPending = false;
  bool _isReconnecting = false;
  int _heartbeatFailures = 0;
  Timer? _heartbeatTimer;
  final ReconnectGuard _reconnectGuard = ReconnectGuard();

  // Local mirror of the game phase, kept in sync via observed phase actions.
  GamePhase _phase = GamePhase.waiting;
  Timer? _briefingTimer;

  int _counterLeft = 0;
  int _counterRight = 0;
  WeatherInputs _weather = const WeatherInputs();
  double _distanceSpeed = PhysicsEngine.defaultDistanceSpeed;
  double _bankPerPerson = PhysicsEngine.defaultBankPerPerson;
  int _initialAltitude = PhysicsEngine.defaultRunInitialAltitude.round();
  bool _altitudeBoostReady = false;
  Timer? _altitudeBoostTimer;

  bool get _controlsActive => _phase == GamePhase.emergency;
  bool get _canSendControlUpdates => _isActiveController && _controlsActive;
  bool get _canEditInitialAltitude =>
      _phase != GamePhase.emergency && _phase != GamePhase.finished;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  void dispose() {
    _briefingTimer?.cancel();
    _heartbeatTimer?.cancel();
    _altitudeBoostTimer?.cancel();
    _codeController.dispose();
    _room?.disconnect();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  Future<void> _join() async {
    final input = _codeController.text;
    final l10n = AppLocalizations.of(context)!;
    if (!SupabaseService.isConfigured) {
      setState(() => _joinError = l10n.cockpitConfigError);
      return;
    }
    if (!RoomCodeGenerator.isValid(input)) {
      setState(() => _joinError = l10n.controllerInvalidCode);
      return;
    }
    final code = RoomCodeGenerator.normalize(input);
    setState(() {
      _isJoining = true;
      _joinError = null;
    });

    final room = SupabaseService.openRoom(code)
      ..onPhaseAction((message) => _observePhaseAction(message.action))
      ..onControllerClaimResponse(_onControllerClaimResponse)
      ..onControllerReleased(_onControllerReleased)
      ..onConnectionStateChanged(_onConnectionStateChanged)
      ..onSessionCancel(_onSessionCancelled);

    final ok = await room.connect();
    if (!mounted) return;

    if (!ok) {
      await room.disconnect();
      setState(() {
        _isJoining = false;
        _isSubscribed = false;
        _joinError = l10n.controllerSubscribeFailed;
      });
      return;
    }

    setState(() {
      _room = room;
      _roomCode = code;
      _joinError = null;
      _sessionEnded = false;
      _isJoining = false;
      _isSubscribed = true;
      _isActiveController = false;
      _isClaimPending = true;
      _resetLocalState();
    });

    _requestControllerClaim();
  }

  void _requestControllerClaim() {
    final room = _room;
    if (room == null) return;
    room.sendControllerClaimRequest(
      ControllerClaimRequest(
        source: _source,
        requestedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  void _onControllerReleased(ControllerReleased released) {
    if (released.activeSource != _source || _room == null || _sessionEnded) return;
    _heartbeatTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _isActiveController = false;
      _isClaimPending = true;
      _heartbeatFailures = 0;
    });
    _reconnectAndReclaim();
  }

  void _onConnectionStateChanged(bool connected, String? error) {
    if (!mounted || _room == null || _sessionEnded) return;
    setState(() => _isSubscribed = connected);
    if (!connected) {
      _reconnectAndReclaim();
    }
  }

  Future<void> _reconnectAndReclaim() async {
    final room = _room;
    if (room == null || _sessionEnded) return;

    await _reconnectGuard.run(() async {
      if (!mounted || _room == null || _sessionEnded) return;
      setState(() {
        _isReconnecting = true;
        _isClaimPending = true;
        _isActiveController = false;
      });
      _heartbeatTimer?.cancel();

      final ok = await room.reconnect();
      if (!mounted || _room == null) return;

      setState(() {
        _isSubscribed = ok;
        _isReconnecting = false;
      });

      if (!ok) return;
      _requestControllerClaim();
    });
  }

  void _onControllerClaimResponse(ControllerClaimResponse response) async {
    if (response.targetSource != _source) return;
    if (!mounted) return;

    if (!response.accepted) {
      final l10n = AppLocalizations.of(context)!;
      final room = _room;
      _heartbeatTimer?.cancel();
      await room?.disconnect();
      if (!mounted) return;
      setState(() {
        _room = null;
        _roomCode = null;
        _isSubscribed = false;
        _isActiveController = false;
        _isClaimPending = false;
        _joinError = l10n.controllerAlreadyActive;
        _resetLocalState();
      });
      return;
    }

    setState(() {
      _isActiveController = true;
      _isClaimPending = false;
      _isReconnecting = false;
      _heartbeatFailures = 0;
    });

    _flushAllControls();
    _startHeartbeatTimer();
  }

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final room = _room;
      if (!_isActiveController || room == null) return;

      final result = await room.sendControllerHeartbeat(
        ControllerHeartbeat(
          source: _source,
          tMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (!mounted || !_isActiveController) return;

      if (result == BroadcastSendResult.ok) {
        _heartbeatFailures = 0;
        return;
      }

      _heartbeatFailures++;
      if (_heartbeatFailures >= 2) {
        _heartbeatFailures = 0;
        _reconnectAndReclaim();
      }
    });
  }

  void _resetLocalState() {
    _phase = GamePhase.waiting;
    _counterLeft = 0;
    _counterRight = 0;
    _weather = const WeatherInputs();
    _distanceSpeed = PhysicsEngine.defaultDistanceSpeed;
    _bankPerPerson = PhysicsEngine.defaultBankPerPerson;
    _initialAltitude = PhysicsEngine.defaultRunInitialAltitude.round();
    _altitudeBoostReady = false;
    _briefingTimer?.cancel();
    _altitudeBoostTimer?.cancel();
  }

  void _onSessionCancelled() {
    _briefingTimer?.cancel();
    _heartbeatTimer?.cancel();
    final room = _room;
    _room = null;
    room?.disconnect();
    setState(() {
      _roomCode = null;
      _sessionEnded = true;
      _isSubscribed = false;
      _isActiveController = false;
      _isClaimPending = false;
      _resetLocalState();
    });
  }

  /// Applies a phase transition observed from any controller (including this
  /// one) so every phone's local phase stays aligned with the cockpit.
  void _observePhaseAction(PhaseAction action) {
    final before = _phase;
    setState(() {
      switch (action) {
        case PhaseAction.startCruise:
          if (_phase == GamePhase.waiting) _phase = GamePhase.cruise;
        case PhaseAction.engineMalfunction:
          if (_phase == GamePhase.cruise) {
            _phase = GamePhase.malfunction;
            _briefingTimer?.cancel();
            _briefingTimer = Timer(GameState.malfunctionDuration, () {
              if (mounted && _phase == GamePhase.malfunction) {
                setState(() => _phase = GamePhase.briefing);
              }
            });
          }
        case PhaseAction.startEmergency:
          if (_phase == GamePhase.briefing) _phase = GamePhase.emergency;
      }
    });

    if (before != GamePhase.emergency && _phase == GamePhase.emergency) {
      _startAltitudeBoostDelay();
      _flushAllControls();
    }
  }

  void _startAltitudeBoostDelay() {
    _altitudeBoostTimer?.cancel();
    setState(() => _altitudeBoostReady = false);
    _altitudeBoostTimer = Timer(
      Duration(
        milliseconds:
            (PhysicsEngine.altitudeCountdownSeconds * 1000).round(),
      ),
      () {
        if (mounted) setState(() => _altitudeBoostReady = true);
      },
    );
  }

  void _flushAllControls() {
    if (!_isSubscribed || !_isActiveController || _room == null) return;
    _room!.sendCounterUpdate(
      CounterUpdate(
        counterLeft: _counterLeft,
        counterRight: _counterRight,
        source: _source,
      ),
    );
    _room!.sendWeatherUpdate(
      WeatherUpdate(weather: _weather, source: _source),
    );
    _room!.sendSettingsUpdate(
      SettingsUpdate(
        distanceSpeed: _distanceSpeed,
        bankPerPerson: _bankPerPerson,
        initialAltitude: _initialAltitude,
        source: _source,
      ),
    );
  }

  Future<void> _sendAltitudeBoost() async {
    if (!_isSubscribed || !_isActiveController || _room == null) return;
    if (!_controlsActive || !_altitudeBoostReady) return;
    HapticFeedback.mediumImpact();
    await _room!.sendAltitudeBoost(AltitudeBoost(source: _source));
  }

  Future<void> _sendPhaseAction(PhaseAction action) async {
    if (!_isSubscribed || !_isActiveController || _room == null) return;
    HapticFeedback.mediumImpact();

    if (action == PhaseAction.startEmergency) {
      final settingsResult = await _room!.sendSettingsUpdate(
        SettingsUpdate(
          distanceSpeed: _distanceSpeed,
          bankPerPerson: _bankPerPerson,
          initialAltitude: _initialAltitude,
          source: _source,
        ),
      );
      if (!mounted) return;
      if (settingsResult != BroadcastSendResult.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.controllerSendFailed),
          ),
        );
        return;
      }
    }

    final result = await _room!.sendPhaseAction(
      PhaseActionMessage(action: action, source: _source),
    );
    if (!mounted) return;
    if (result == BroadcastSendResult.ok) {
      _observePhaseAction(action);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.controllerSendFailed)),
      );
    }
  }

  void _changeCounter({required bool left, required int delta}) {
    HapticFeedback.lightImpact();
    setState(() {
      if (left) {
        _counterLeft = max(0, _counterLeft + delta);
      } else {
        _counterRight = max(0, _counterRight + delta);
      }
    });
    if (!_canSendControlUpdates) return;
    _room?.sendCounterUpdate(
      CounterUpdate(
        counterLeft: left ? _counterLeft : null,
        counterRight: left ? null : _counterRight,
        source: _source,
      ),
    );
  }

  void _updateWeather(WeatherInputs weather) {
    HapticFeedback.lightImpact();
    setState(() => _weather = weather);
    if (!_canSendControlUpdates) return;
    _room?.sendWeatherUpdate(WeatherUpdate(weather: weather, source: _source));
  }

  void _changeDistanceSpeed(double value) {
    setState(() => _distanceSpeed = value);
    if (!_canSendControlUpdates) return;
    _room?.sendSettingsUpdate(_settingsUpdate(distanceSpeed: value));
  }

  void _changeBankPerPerson(double value) {
    setState(() => _bankPerPerson = value);
    if (!_canSendControlUpdates) return;
    _room?.sendSettingsUpdate(_settingsUpdate(bankPerPerson: value));
  }

  SettingsUpdate _settingsUpdate({double? distanceSpeed, double? bankPerPerson}) {
    return SettingsUpdate(
      distanceSpeed: distanceSpeed ?? _distanceSpeed,
      bankPerPerson: bankPerPerson ?? _bankPerPerson,
      initialAltitude: _initialAltitude,
      source: _source,
    );
  }

  void _changeInitialAltitude(int delta) {
    setState(() {
      _initialAltitude = _initialAltitude + delta;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        backgroundColor: Colors.black,
      ),
      body: SafeArea(
        child: _isJoining
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(l10n.controllerConnecting),
                  ],
                ),
              )
            : _room == null
                ? _buildJoin(l10n)
                : (_isClaimPending || !_isActiveController)
                    ? _buildClaiming(l10n)
                    : _buildControls(l10n),
      ),
    );
  }

  Widget _buildClaiming(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              _isReconnecting
                  ? l10n.controllerReconnecting
                  : l10n.controllerClaiming,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoin(AppLocalizations l10n) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.meeting_room, size: 72, color: Color(0xFF39FF14)),
            const SizedBox(height: 16),
            Text(
              l10n.controllerJoinTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _codeController,
              autocorrect: false,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _join(),
              decoration: InputDecoration(
                labelText: l10n.controllerRoomCodeHint,
                border: const OutlineInputBorder(),
                errorText: _joinError,
              ),
            ),
            if (_sessionEnded) ...[
              const SizedBox(height: 12),
              Text(
                l10n.controllerSessionEnded,
                style: const TextStyle(color: Colors.amberAccent),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isJoining ? null : _join,
                icon: const Icon(Icons.login),
                label: Text(l10n.controllerJoinButton),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l10n.controllerConnected(_roomCode ?? ''),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _isSubscribed
                    ? const Color(0xFF39FF14)
                    : Colors.amberAccent,
                fontWeight: FontWeight.bold,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        _buildPhaseSection(l10n),
        const SizedBox(height: 16),
        _buildInitialAltitude(l10n),
        const SizedBox(height: 24),
        if (!_controlsActive)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              l10n.controllerControlsLockedHint,
              style: const TextStyle(color: Colors.amberAccent),
              textAlign: TextAlign.center,
            ),
          ),
        _buildCounters(l10n),
        const SizedBox(height: 24),
        _buildWeather(l10n),
        const SizedBox(height: 24),
        _buildDistanceSpeed(l10n),
        const SizedBox(height: 24),
        _buildBankPerPerson(l10n),
        if (_controlsActive) ...[
          const SizedBox(height: 24),
          _buildAltitudeBoost(l10n),
        ],
      ],
    );
  }

  Widget _buildInitialAltitude(AppLocalizations l10n) {
    final enabled = _isActiveController && _canEditInitialAltitude;
    return _Section(
      title: l10n.controllerInitialAltitude,
      child: Row(
        children: [
          IconButton(
            onPressed: enabled ? () => _changeInitialAltitude(-100) : null,
            icon: const Icon(Icons.remove),
          ),
          Expanded(
            child: Text(
              '$_initialAltitude ${l10n.unitMeters}',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            onPressed: enabled ? () => _changeInitialAltitude(100) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Widget _buildAltitudeBoost(AppLocalizations l10n) {
    final enabled = _isActiveController && _altitudeBoostReady;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: enabled ? _sendAltitudeBoost : null,
        icon: const Icon(Icons.fitness_center),
        label: Text(l10n.controllerAltitudeBoost),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: const Color(0xFF39FF14),
          foregroundColor: Colors.black,
        ),
      ),
    );
  }

  Widget _buildPhaseSection(AppLocalizations l10n) {
    return _Section(
      title: l10n.controllerPhaseSection,
      child: Column(
        children: [
          _PhaseButton(
            label: l10n.phaseButtonStartFlight,
            icon: Icons.flight_takeoff,
            enabled: _isSubscribed && _isActiveController && _phase == GamePhase.waiting,
            onPressed: () => _sendPhaseAction(PhaseAction.startCruise),
          ),
          const SizedBox(height: 8),
          _PhaseButton(
            label: l10n.phaseButtonEngineFailure,
            icon: Icons.warning_amber_rounded,
            color: Colors.redAccent,
            enabled: _isSubscribed && _isActiveController && _phase == GamePhase.cruise,
            onPressed: () => _sendPhaseAction(PhaseAction.engineMalfunction),
          ),
          const SizedBox(height: 8),
          _PhaseButton(
            label: l10n.phaseButtonStartEmergency,
            icon: Icons.flight_land,
            color: Colors.orangeAccent,
            enabled: _isSubscribed && _isActiveController && _phase == GamePhase.briefing,
            onPressed: () => _sendPhaseAction(PhaseAction.startEmergency),
          ),
        ],
      ),
    );
  }

  Widget _buildCounters(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: _CounterCard(
            label: l10n.controllerLeftCounter,
            value: _counterLeft,
            enabled: _isActiveController,
            onIncrement: () => _changeCounter(left: true, delta: 1),
            onDecrement: () => _changeCounter(left: true, delta: -1),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _CounterCard(
            label: l10n.controllerRightCounter,
            value: _counterRight,
            enabled: _isActiveController,
            onIncrement: () => _changeCounter(left: false, delta: 1),
            onDecrement: () => _changeCounter(left: false, delta: -1),
          ),
        ),
      ],
    );
  }

  Widget _buildWeather(AppLocalizations l10n) {
    final weatherEnabled = _controlsActive && _isActiveController;
    return _Section(
      title: l10n.controllerWeatherSection,
      child: Column(
        children: [
          SwitchListTile(
            title: Text(l10n.weatherThunderstorm),
            value: _weather.thunderstorm,
            onChanged: weatherEnabled
                ? (v) => _updateWeather(_weather.copyWith(thunderstorm: v))
                : null,
          ),
          SwitchListTile(
            title: Text(l10n.weatherWindLeft),
            value: _weather.windLeft,
            onChanged: weatherEnabled
                ? (v) => _updateWeather(_weather.copyWith(windLeft: v))
                : null,
          ),
          SwitchListTile(
            title: Text(l10n.weatherWindRight),
            value: _weather.windRight,
            onChanged: weatherEnabled
                ? (v) => _updateWeather(_weather.copyWith(windRight: v))
                : null,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(l10n.windStrengthLabel,
                style: Theme.of(context).textTheme.labelLarge),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: WindStrength.values.map((strength) {
              return ChoiceChip(
                label: Text(Labels.windStrength(l10n, strength)),
                selected: _weather.windStrength == strength,
                onSelected: weatherEnabled
                    ? (_) =>
                        _updateWeather(_weather.copyWith(windStrength: strength))
                    : null,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDistanceSpeed(AppLocalizations l10n) {
    return _Section(
      title: l10n.controllerDistanceSpeed,
      child: Column(
        children: [
          Text(
            '${_distanceSpeed.round()} ${l10n.unitMeters}/s',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Slider(
            value: _distanceSpeed,
            min: 5,
            max: 100,
            divisions: 95,
            label: '${_distanceSpeed.round()}',
            onChanged: _isActiveController ? _changeDistanceSpeed : null,
          ),
        ],
      ),
    );
  }

  Widget _buildBankPerPerson(AppLocalizations l10n) {
    return _Section(
      title: l10n.controllerBankPerPerson,
      child: Column(
        children: [
          Text(
            '${_bankPerPerson.toStringAsFixed(1)}°',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Slider(
            value: _bankPerPerson,
            min: PhysicsEngine.minBankPerPerson,
            max: PhysicsEngine.maxBankPerPerson,
            divisions: ((PhysicsEngine.maxBankPerPerson - PhysicsEngine.minBankPerPerson) * 2)
                .round(),
            label: _bankPerPerson.toStringAsFixed(1),
            onChanged: _isActiveController ? _changeBankPerPerson : null,
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    letterSpacing: 1.5,
                    color: Colors.white70,
                  ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _PhaseButton extends StatelessWidget {
  const _PhaseButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
    this.color,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}

class _CounterCard extends StatelessWidget {
  const _CounterCard({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onIncrement,
    required this.onDecrement,
  });

  final String label;
  final int value;
  final bool enabled;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '$value',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF39FF14),
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _RoundButton(
                  icon: Icons.remove,
                  onPressed: enabled ? onDecrement : null,
                ),
                _RoundButton(
                  icon: Icons.add,
                  onPressed: enabled ? onIncrement : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
        child: Icon(icon, size: 28),
      ),
    );
  }
}
