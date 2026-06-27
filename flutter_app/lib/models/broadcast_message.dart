import '../engine/physics_engine.dart';
import 'game_phase.dart';
import 'weather_inputs.dart';

/// Names of the broadcast events exchanged on a room channel.
abstract final class BroadcastEvents {
  static const counterUpdate = 'counter_update';
  static const weatherUpdate = 'weather_update';
  static const settingsUpdate = 'settings_update';
  static const altitudeBoost = 'altitude_boost';
  static const phaseAction = 'phase_action';
  static const sessionCancel = 'session_cancel';
  static const controllerClaimRequest = 'controller_claim_request';
  static const controllerClaimResponse = 'controller_claim_response';
  static const controllerHeartbeat = 'controller_heartbeat';
  static const controllerReleased = 'controller_released';
}

/// A partial update of the cabin counters. Either side may be omitted so two
/// controllers (left and right) never overwrite each other's value.
class CounterUpdate {
  const CounterUpdate({this.counterLeft, this.counterRight, required this.source});

  final int? counterLeft;
  final int? counterRight;
  final String source;

  Map<String, dynamic> toJson() => {
        if (counterLeft != null) 'counterLeft': counterLeft,
        if (counterRight != null) 'counterRight': counterRight,
        'source': source,
      };

  factory CounterUpdate.fromJson(Map<String, dynamic> json) {
    return CounterUpdate(
      counterLeft: (json['counterLeft'] as num?)?.toInt(),
      counterRight: (json['counterRight'] as num?)?.toInt(),
      source: json['source'] as String? ?? 'unknown',
    );
  }
}

/// A full weather configuration update.
class WeatherUpdate {
  const WeatherUpdate({required this.weather, required this.source});

  final WeatherInputs weather;
  final String source;

  Map<String, dynamic> toJson() => {
        ...weather.toJson(),
        'source': source,
      };

  factory WeatherUpdate.fromJson(Map<String, dynamic> json) {
    return WeatherUpdate(
      weather: WeatherInputs.fromJson(json),
      source: json['source'] as String? ?? 'unknown',
    );
  }
}

/// An update to approach speed, bank sensitivity, and optional run initial altitude.
class SettingsUpdate {
  const SettingsUpdate({
    required this.distanceSpeed,
    required this.bankPerPerson,
    required this.source,
    this.initialAltitude,
  });

  final double distanceSpeed;
  final double bankPerPerson;
  final String source;

  /// Emergency start altitude in metres; applied once when Notlandung begins.
  final int? initialAltitude;

  Map<String, dynamic> toJson() => {
        'distanceSpeed': distanceSpeed,
        'bankPerPerson': bankPerPerson,
        if (initialAltitude != null) 'initialAltitude': initialAltitude,
        'source': source,
      };

  factory SettingsUpdate.fromJson(Map<String, dynamic> json) {
    return SettingsUpdate(
      distanceSpeed: (json['distanceSpeed'] as num?)?.toDouble() ??
          PhysicsEngine.defaultDistanceSpeed,
      bankPerPerson: (json['bankPerPerson'] as num?)?.toDouble() ??
          PhysicsEngine.defaultBankPerPerson,
      initialAltitude: (json['initialAltitude'] as num?)?.toInt(),
      source: json['source'] as String? ?? 'unknown',
    );
  }
}

/// Rescue mission completed: cockpit adds [PhysicsEngine.altitudeBoostAmount].
class AltitudeBoost {
  const AltitudeBoost({required this.source});

  final String source;

  Map<String, dynamic> toJson() => {'source': source};

  factory AltitudeBoost.fromJson(Map<String, dynamic> json) {
    return AltitudeBoost(
      source: json['source'] as String? ?? 'unknown',
    );
  }
}

/// A request to advance the game phase.
class PhaseActionMessage {
  const PhaseActionMessage({required this.action, required this.source});

  final PhaseAction action;
  final String source;

  Map<String, dynamic> toJson() => {
        'action': action.toJson(),
        'source': source,
      };

  /// Returns null if the payload does not contain a known action.
  static PhaseActionMessage? fromJson(Map<String, dynamic> json) {
    final action = PhaseAction.fromJson(json['action'] as String?);
    if (action == null) return null;
    return PhaseActionMessage(
      action: action,
      source: json['source'] as String? ?? 'unknown',
    );
  }
}

/// Requests exclusive control of a room from the cockpit.
class ControllerClaimRequest {
  const ControllerClaimRequest({required this.source, required this.requestedAtMs});

  final String source;
  final int requestedAtMs;

  Map<String, dynamic> toJson() => {
        'source': source,
        'requestedAtMs': requestedAtMs,
      };

  factory ControllerClaimRequest.fromJson(Map<String, dynamic> json) {
    return ControllerClaimRequest(
      source: json['source'] as String? ?? 'unknown',
      requestedAtMs: (json['requestedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Response to a [ControllerClaimRequest]. Only the controller whose
/// `targetSource` matches should act on it.
class ControllerClaimResponse {
  const ControllerClaimResponse({
    required this.targetSource,
    required this.accepted,
    required this.activeSource,
    this.expiresInMs,
  });

  final String targetSource;
  final bool accepted;
  final String activeSource;
  final int? expiresInMs;

  Map<String, dynamic> toJson() => {
        'targetSource': targetSource,
        'accepted': accepted,
        'activeSource': activeSource,
        if (expiresInMs != null) 'expiresInMs': expiresInMs,
      };

  factory ControllerClaimResponse.fromJson(Map<String, dynamic> json) {
    return ControllerClaimResponse(
      targetSource: json['targetSource'] as String? ?? 'unknown',
      accepted: json['accepted'] as bool? ?? false,
      activeSource: json['activeSource'] as String? ?? 'unknown',
      expiresInMs: (json['expiresInMs'] as num?)?.toInt(),
    );
  }
}

/// Periodic keepalive from the active controller so the cockpit can release the
/// lock if the controller disappears.
class ControllerHeartbeat {
  const ControllerHeartbeat({required this.source, required this.tMs});

  final String source;
  final int tMs;

  Map<String, dynamic> toJson() => {
        'source': source,
        'tMs': tMs,
      };

  factory ControllerHeartbeat.fromJson(Map<String, dynamic> json) {
    return ControllerHeartbeat(
      source: json['source'] as String? ?? 'unknown',
      tMs: (json['tMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Informational event broadcast by the cockpit when the active controller lock
/// expires or is released.
class ControllerReleased {
  const ControllerReleased({required this.activeSource, required this.reason});

  final String activeSource;
  final String reason;

  Map<String, dynamic> toJson() => {
        'activeSource': activeSource,
        'reason': reason,
      };

  factory ControllerReleased.fromJson(Map<String, dynamic> json) {
    return ControllerReleased(
      activeSource: json['activeSource'] as String? ?? 'unknown',
      reason: json['reason'] as String? ?? 'unknown',
    );
  }
}
