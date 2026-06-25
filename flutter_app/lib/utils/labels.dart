import '../l10n/app_localizations.dart';
import '../models/weather_inputs.dart';
import '../models/wind_strength.dart';

/// Localized label helpers shared between the controller and success screens.
abstract final class Labels {
  static String windStrength(AppLocalizations l10n, WindStrength strength) {
    return switch (strength) {
      WindStrength.breeze => l10n.windStrengthBreeze,
      WindStrength.moderate => l10n.windStrengthModerate,
      WindStrength.strong => l10n.windStrengthStrong,
      WindStrength.storm => l10n.windStrengthStorm,
    };
  }

  /// A short human summary of the active weather, for example
  /// "Thunderstorm, wind from left" or "Calm".
  static String weatherSummary(AppLocalizations l10n, WeatherInputs weather) {
    final parts = <String>[
      if (weather.thunderstorm) l10n.weatherThunderstorm,
      if (weather.windLeft) l10n.weatherWindLeft,
      if (weather.windRight) l10n.weatherWindRight,
    ];
    if (parts.isEmpty) return l10n.weatherNone;
    return parts.join(', ');
  }
}
