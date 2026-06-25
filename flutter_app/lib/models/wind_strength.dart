/// Discrete wind strength steps the controller can pick. The numeric [value]
/// (0-100) feeds the physics and visual ramp; the localized label is resolved
/// in the UI layer.
enum WindStrength {
  breeze(25),
  moderate(50),
  strong(75),
  storm(100);

  const WindStrength(this.value);

  /// Strength on a 0-100 scale.
  final int value;

  String toJson() => name;

  static WindStrength fromJson(String? value) {
    return WindStrength.values.firstWhere(
      (step) => step.name == value,
      orElse: () => WindStrength.breeze,
    );
  }
}
