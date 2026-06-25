import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/broadcast_message.dart';

/// Result of attempting to deliver a broadcast message to Supabase Realtime.
enum BroadcastSendResult { ok, error }

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
    await Supabase.initialize(url: url, publishableKey: anonKey);
    _configured = true;
    return true;
  }

  /// Creates a connection to the given room. Register listeners before calling
  /// [RoomConnection.connect].
  static RoomConnection openRoom(String roomCode) => RoomConnection._(roomCode);
}

/// A typed wrapper around a single room's realtime broadcast channel.
///
/// Receiving requires a successful [connect] (WebSocket subscribed). Sending uses
/// the REST broadcast API ([RealtimeChannel.httpSend]), which matches the curl
/// path that returns HTTP 202 and does not depend on join completing first.
class RoomConnection {
  RoomConnection._(this.roomCode)
      : _channel = Supabase.instance.client.channel('room-$roomCode');

  final String roomCode;
  final RealtimeChannel _channel;

  bool _connectStarted = false;
  bool _subscribed = false;
  String? _subscribeError;
  Completer<bool>? _subscribeCompleter;

  /// Whether the WebSocket channel join completed successfully.
  bool get isSubscribed => _subscribed;

  /// Human-readable subscribe failure, if [connect] returned false.
  String? get subscribeError => _subscribeError;

  /// Subscribes to the channel for incoming broadcasts. Returns true once
  /// [RealtimeSubscribeStatus.subscribed] is reached. Register listeners first.
  Future<bool> connect() async {
    if (_subscribed) return true;
    if (_connectStarted && _subscribeCompleter != null) {
      return _subscribeCompleter!.future;
    }
    _connectStarted = true;
    _subscribeCompleter = Completer<bool>();

    _channel.subscribe((status, error) {
      debugPrint('RoomConnection[$roomCode] subscribe status=$status error=$error');
      if (status == RealtimeSubscribeStatus.subscribed) {
        _subscribed = true;
        _subscribeError = null;
        if (!(_subscribeCompleter?.isCompleted ?? true)) {
          _subscribeCompleter!.complete(true);
        }
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        _subscribed = false;
        _subscribeError = error?.toString() ?? status.name;
        if (!(_subscribeCompleter?.isCompleted ?? true)) {
          _subscribeCompleter!.complete(false);
        }
      }
    });

    try {
      return await _subscribeCompleter!.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          _subscribeError = 'subscribe_timeout';
          return false;
        },
      );
    } catch (e) {
      _subscribeError = e.toString();
      return false;
    }
  }

  Future<void> disconnect() async {
    await Supabase.instance.client.removeChannel(_channel);
    _connectStarted = false;
    _subscribed = false;
    _subscribeCompleter = null;
  }

  // --- Listeners (register before connect) ---

  void onCounterUpdate(void Function(CounterUpdate update) callback) {
    _channel.onBroadcast(
      event: BroadcastEvents.counterUpdate,
      callback: (raw) => _dispatch(
        event: BroadcastEvents.counterUpdate,
        raw: raw,
        parse: CounterUpdate.fromJson,
        deliver: callback,
      ),
    );
  }

  void onWeatherUpdate(void Function(WeatherUpdate update) callback) {
    _channel.onBroadcast(
      event: BroadcastEvents.weatherUpdate,
      callback: (raw) => _dispatch(
        event: BroadcastEvents.weatherUpdate,
        raw: raw,
        parse: WeatherUpdate.fromJson,
        deliver: callback,
      ),
    );
  }

  void onSettingsUpdate(void Function(SettingsUpdate update) callback) {
    _channel.onBroadcast(
      event: BroadcastEvents.settingsUpdate,
      callback: (raw) => _dispatch(
        event: BroadcastEvents.settingsUpdate,
        raw: raw,
        parse: SettingsUpdate.fromJson,
        deliver: callback,
      ),
    );
  }

  void onPhaseAction(void Function(PhaseActionMessage message) callback) {
    _channel.onBroadcast(
      event: BroadcastEvents.phaseAction,
      callback: (raw) {
        debugPrint('RoomConnection[$roomCode] recv ${BroadcastEvents.phaseAction} raw=$raw');
        final data = _unwrap(raw);
        debugPrint('RoomConnection[$roomCode] recv ${BroadcastEvents.phaseAction} data=$data');
        final message = PhaseActionMessage.fromJson(data);
        if (message != null) {
          callback(message);
        } else {
          debugPrint(
            'RoomConnection[$roomCode] could not parse ${BroadcastEvents.phaseAction}',
          );
        }
      },
    );
  }

  void onSessionCancel(void Function() callback) {
    _channel.onBroadcast(
      event: BroadcastEvents.sessionCancel,
      callback: (raw) {
        debugPrint('RoomConnection[$roomCode] recv ${BroadcastEvents.sessionCancel}');
        callback();
      },
    );
  }

  void _dispatch<T>({
    required String event,
    required Map<String, dynamic> raw,
    required T Function(Map<String, dynamic>) parse,
    required void Function(T) deliver,
  }) {
    debugPrint('RoomConnection[$roomCode] recv $event raw=$raw');
    deliver(parse(_unwrap(raw)));
  }

  // --- Senders (REST — reliable even before WebSocket join completes) ---

  Future<BroadcastSendResult> sendCounterUpdate(CounterUpdate update) =>
      _send(BroadcastEvents.counterUpdate, update.toJson());

  Future<BroadcastSendResult> sendWeatherUpdate(WeatherUpdate update) =>
      _send(BroadcastEvents.weatherUpdate, update.toJson());

  Future<BroadcastSendResult> sendSettingsUpdate(SettingsUpdate update) =>
      _send(BroadcastEvents.settingsUpdate, update.toJson());

  Future<BroadcastSendResult> sendPhaseAction(PhaseActionMessage message) =>
      _send(BroadcastEvents.phaseAction, message.toJson());

  Future<BroadcastSendResult> sendSessionCancel() =>
      _send(BroadcastEvents.sessionCancel, const {});

  Future<BroadcastSendResult> _send(
    String event,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _channel.httpSend(event: event, payload: payload);
      debugPrint('RoomConnection[$roomCode] sent $event payload=$payload');
      return BroadcastSendResult.ok;
    } catch (e, stack) {
      debugPrint('RoomConnection[$roomCode] send $event failed: $e\n$stack');
      return BroadcastSendResult.error;
    }
  }

  /// Unwraps nested `{payload: ...}` envelopes from Realtime broadcast frames.
  static Map<String, dynamic> _unwrap(Map<String, dynamic> message) {
    Object? current = message;
    for (var depth = 0; depth < 4; depth++) {
      if (current is! Map) break;
      final map = Map<String, dynamic>.from(current);
      if (_looksLikeAppPayload(map)) return map;
      final inner = map['payload'];
      if (inner is Map) {
        current = inner;
        continue;
      }
      return map;
    }
    return Map<String, dynamic>.from(message);
  }

  static bool _looksLikeAppPayload(Map<String, dynamic> map) {
    return map.containsKey('action') ||
        map.containsKey('counterLeft') ||
        map.containsKey('counterRight') ||
        map.containsKey('thunderstorm') ||
        map.containsKey('windLeft') ||
        map.containsKey('distanceSpeed');
  }
}
