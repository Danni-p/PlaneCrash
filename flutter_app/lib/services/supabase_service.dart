import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/broadcast_message.dart';

/// Initializes Supabase from `.env` and opens per-room realtime channels.
///
/// PlaneCrash uses Realtime Broadcast only: there are no database tables, no
/// auth, and nothing is persisted. Each room maps to a channel `room-{code}`.
abstract final class SupabaseService {
  static bool _configured = false;

  /// Whether valid credentials were found and Supabase was initialized.
  static bool get isConfigured => _configured;

  /// Reads credentials from `.env` and initializes Supabase. Returns false (and
  /// skips initialization) when the credentials are missing so the app can still
  /// boot and show a clear configuration error instead of crashing.
  static Future<bool> initialize() async {
    final url = dotenv.maybeGet('SUPABASE_URL') ?? '';
    final anonKey = dotenv.maybeGet('SUPABASE_ANON_KEY') ?? '';
    if (url.isEmpty || anonKey.isEmpty) {
      _configured = false;
      return false;
    }
    // The anon key is Supabase's publishable key; pass it as publishableKey to
    // avoid the deprecated anonKey parameter.
    await Supabase.initialize(url: url, publishableKey: anonKey);
    _configured = true;
    return true;
  }

  /// Creates a connection to the given room. Register listeners before calling
  /// [RoomConnection.connect].
  static RoomConnection openRoom(String roomCode) => RoomConnection._(roomCode);
}

/// A typed wrapper around a single room's realtime broadcast channel. Both the
/// cockpit and the controllers use this; they simply subscribe to and send the
/// subset of events relevant to their role.
class RoomConnection {
  RoomConnection._(this.roomCode)
      : _channel = Supabase.instance.client.channel('room-$roomCode');

  final String roomCode;
  final RealtimeChannel _channel;
  bool _connected = false;

  /// Subscribes to the channel. Must be called after registering listeners.
  void connect() {
    if (_connected) return;
    _channel.subscribe();
    _connected = true;
  }

  Future<void> disconnect() async {
    await Supabase.instance.client.removeChannel(_channel);
    _connected = false;
  }

  // --- Listeners (register before connect) ---

  void onCounterUpdate(void Function(CounterUpdate update) callback) {
    _channel.onBroadcast(
      event: BroadcastEvents.counterUpdate,
      callback: (payload) => callback(CounterUpdate.fromJson(_unwrap(payload))),
    );
  }

  void onWeatherUpdate(void Function(WeatherUpdate update) callback) {
    _channel.onBroadcast(
      event: BroadcastEvents.weatherUpdate,
      callback: (payload) => callback(WeatherUpdate.fromJson(_unwrap(payload))),
    );
  }

  void onSettingsUpdate(void Function(SettingsUpdate update) callback) {
    _channel.onBroadcast(
      event: BroadcastEvents.settingsUpdate,
      callback: (payload) => callback(SettingsUpdate.fromJson(_unwrap(payload))),
    );
  }

  void onPhaseAction(void Function(PhaseActionMessage message) callback) {
    _channel.onBroadcast(
      event: BroadcastEvents.phaseAction,
      callback: (payload) {
        final message = PhaseActionMessage.fromJson(_unwrap(payload));
        if (message != null) callback(message);
      },
    );
  }

  void onSessionCancel(void Function() callback) {
    _channel.onBroadcast(
      event: BroadcastEvents.sessionCancel,
      callback: (_) => callback(),
    );
  }

  // --- Senders ---

  Future<void> sendCounterUpdate(CounterUpdate update) =>
      _send(BroadcastEvents.counterUpdate, update.toJson());

  Future<void> sendWeatherUpdate(WeatherUpdate update) =>
      _send(BroadcastEvents.weatherUpdate, update.toJson());

  Future<void> sendSettingsUpdate(SettingsUpdate update) =>
      _send(BroadcastEvents.settingsUpdate, update.toJson());

  Future<void> sendPhaseAction(PhaseActionMessage message) =>
      _send(BroadcastEvents.phaseAction, message.toJson());

  Future<void> sendSessionCancel() =>
      _send(BroadcastEvents.sessionCancel, const {});

  Future<void> _send(String event, Map<String, dynamic> payload) {
    return _channel.sendBroadcastMessage(event: event, payload: payload);
  }

  /// Incoming broadcast messages arrive wrapped as
  /// `{event, type, payload}`; this extracts the inner payload map.
  static Map<String, dynamic> _unwrap(Map<String, dynamic> message) {
    final inner = message['payload'];
    if (inner is Map<String, dynamic>) return inner;
    if (inner is Map) return Map<String, dynamic>.from(inner);
    return message;
  }
}
