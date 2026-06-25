/// The phases a PlaneCrash run moves through, in order.
///
/// The simulation is cinematic: it does not start sinking immediately. The
/// cockpit walks through [waiting] -> [cruise] -> [malfunction] -> [briefing]
/// before the actual gameplay in [emergency], and finally [finished].
enum GamePhase {
  waiting,
  cruise,
  malfunction,
  briefing,
  emergency,
  finished;

  /// Whether the per-frame physics loop should run in this phase.
  bool get isSimulating => this == GamePhase.emergency;

  String toJson() => name;

  static GamePhase fromJson(String? value) {
    return GamePhase.values.firstWhere(
      (phase) => phase.name == value,
      orElse: () => GamePhase.waiting,
    );
  }
}

/// Phase transitions a controller can request. The cockpit decides whether the
/// transition is valid for the current [GamePhase].
enum PhaseAction {
  startCruise,
  engineMalfunction,
  startEmergency;

  String toJson() => name;

  static PhaseAction? fromJson(String? value) {
    for (final action in PhaseAction.values) {
      if (action.name == value) return action;
    }
    return null;
  }
}
