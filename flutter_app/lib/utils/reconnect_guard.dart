import 'dart:async';

/// Ensures only one reconnect attempt runs at a time per screen.
class ReconnectGuard {
  Future<void>? _inFlight;

  Future<void> run(Future<void> Function() action) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = action().whenComplete(() => _inFlight = null);
    _inFlight = future;
    return future;
  }
}
