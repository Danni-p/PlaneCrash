import 'game_phase.dart';
import 'weather_inputs.dart';

/// Names of the broadcast events exchanged on a room channel.
abstract final class BroadcastEvents {
  static const counterUpdate = 'counter_update';
  static const weatherUpdate = 'weather_update';
  static const settingsUpdate = 'settings_update';
  static const phaseAction = 'phase_action';
  static const sessionCancel = 'session_cancel';
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

/// An update to the island approach (distance) speed in metres per second.
class SettingsUpdate {
  const SettingsUpdate({required this.distanceSpeed, required this.source});

  final double distanceSpeed;
  final String source;

  Map<String, dynamic> toJson() => {
        'distanceSpeed': distanceSpeed,
        'source': source,
      };

  factory SettingsUpdate.fromJson(Map<String, dynamic> json) {
    return SettingsUpdate(
      distanceSpeed: (json['distanceSpeed'] as num?)?.toDouble() ?? 15.0,
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
