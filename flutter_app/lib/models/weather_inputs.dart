import 'wind_strength.dart';

/// The weather configuration sent by controllers. Effects are independent
/// toggles and can be combined (for example a thunderstorm with wind from the
/// left). The wind strength applies to whichever wind direction is active.
class WeatherInputs {
  const WeatherInputs({
    this.thunderstorm = false,
    this.windLeft = false,
    this.windRight = false,
    this.windStrength = WindStrength.breeze,
  });

  final bool thunderstorm;
  final bool windLeft;
  final bool windRight;
  final WindStrength windStrength;

  /// Net horizontal wind direction: -1 (left), +1 (right), 0 (none/cancelled).
  int get windDirection => (windRight ? 1 : 0) - (windLeft ? 1 : 0);

  /// Whether any weather effect is active.
  bool get isActive => thunderstorm || windLeft || windRight;

  WeatherInputs copyWith({
    bool? thunderstorm,
    bool? windLeft,
    bool? windRight,
    WindStrength? windStrength,
  }) {
    return WeatherInputs(
      thunderstorm: thunderstorm ?? this.thunderstorm,
      windLeft: windLeft ?? this.windLeft,
      windRight: windRight ?? this.windRight,
      windStrength: windStrength ?? this.windStrength,
    );
  }

  Map<String, dynamic> toJson() => {
        'thunderstorm': thunderstorm,
        'windLeft': windLeft,
        'windRight': windRight,
        'windStrength': windStrength.toJson(),
      };

  factory WeatherInputs.fromJson(Map<String, dynamic> json) {
    return WeatherInputs(
      thunderstorm: json['thunderstorm'] as bool? ?? false,
      windLeft: json['windLeft'] as bool? ?? false,
      windRight: json['windRight'] as bool? ?? false,
      windStrength: WindStrength.fromJson(json['windStrength'] as String?),
    );
  }
}
