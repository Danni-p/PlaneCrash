import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/broadcast_message.dart';

/// Result of attempting to deliver a broadcast message to Supabase Realtime.
enum BroadcastSendResult { ok, error }

typedef ConnectionStateCallback = void Function(bool connected, String? error);

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
  RoomConnection._(this.roomCode) {
    _channel = _createChannel();
  }

  final String roomCode;
  late RealtimeChannel _channel;

  bool _broadcastListenersAttached = false;
  bool _connectStarted = false;
  bool _subscribed = false;
  String? _subscribeError;
  Completer<bool>? _subscribeCompleter;
  ConnectionStateCallback? _onConnectionStateChanged;

  void Function(CounterUpdate update)? _onCounterUpdate;
  void Function(WeatherUpdate update)? _onWeatherUpdate;
  void Function(SettingsUpdate update)? _onSettingsUpdate;
  void Function(AltitudeBoost boost)? _onAltitudeBoost;
  void Function(PhaseActionMessage message)? _onPhaseAction;
  void Function()? _onSessionCancel;
  void Function(ControllerClaimRequest request)? _onControllerClaimRequest;
  void Function(ControllerClaimResponse response)? _onControllerClaimResponse;
  void Function(ControllerHeartbeat heartbeat)? _onControllerHeartbeat;
  void Function(ControllerReleased released)? _onControllerReleased;

  /// Whether the WebSocket channel join completed successfully.
  bool get isSubscribed => _subscribed;

  /// Human-readable subscribe failure, if [connect] returned false.
  String? get subscribeError => _subscribeError;

  RealtimeChannel _createChannel() =>
      Supabase.instance.client.channel('room-$roomCode');

  void _attachBroadcastListeners() {
    if (_broadcastListenersAttached) return;
    _broadcastListenersAttached = true;

    if (_onCounterUpdate != null) {
      _channel.onBroadcast(
        event: BroadcastEvents.counterUpdate,
        callback: (raw) => _dispatch(
          event: BroadcastEvents.counterUpdate,
          raw: raw,
          parse: CounterUpdate.fromJson,
          deliver: _onCounterUpdate!,
        ),
      );
    }
    if (_onWeatherUpdate != null) {
      _channel.onBroadcast(
        event: BroadcastEvents.weatherUpdate,
        callback: (raw) => _dispatch(
          event: BroadcastEvents.weatherUpdate,
          raw: raw,
          parse: WeatherUpdate.fromJson,
          deliver: _onWeatherUpdate!,
        ),
      );
    }
    if (_onSettingsUpdate != null) {
      _channel.onBroadcast(
        event: BroadcastEvents.settingsUpdate,
        callback: (raw) => _dispatch(
          event: BroadcastEvents.settingsUpdate,
          raw: raw,
          parse: SettingsUpdate.fromJson,
          deliver: _onSettingsUpdate!,
        ),
      );
    }
    if (_onAltitudeBoost != null) {
      _channel.onBroadcast(
        event: BroadcastEvents.altitudeBoost,
        callback: (raw) => _dispatch(
          event: BroadcastEvents.altitudeBoost,
          raw: raw,
          parse: AltitudeBoost.fromJson,
          deliver: _onAltitudeBoost!,
        ),
      );
    }
    if (_onPhaseAction != null) {
      final callback = _onPhaseAction!;
      _channel.onBroadcast(
        event: BroadcastEvents.phaseAction,
        callback: (raw) {
          debugPrint(
            'RoomConnection[$roomCode] recv ${BroadcastEvents.phaseAction} raw=$raw',
          );
          final data = _unwrap(raw);
          debugPrint(
            'RoomConnection[$roomCode] recv ${BroadcastEvents.phaseAction} data=$data',
          );
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
    if (_onSessionCancel != null) {
      final callback = _onSessionCancel!;
      _channel.onBroadcast(
        event: BroadcastEvents.sessionCancel,
        callback: (raw) {
          debugPrint('RoomConnection[$roomCode] recv ${BroadcastEvents.sessionCancel}');
          callback();
        },
      );
    }
    if (_onControllerClaimRequest != null) {
      _channel.onBroadcast(
        event: BroadcastEvents.controllerClaimRequest,
        callback: (raw) => _dispatch(
          event: BroadcastEvents.controllerClaimRequest,
          raw: raw,
          parse: ControllerClaimRequest.fromJson,
          deliver: _onControllerClaimRequest!,
        ),
      );
    }
    if (_onControllerClaimResponse != null) {
      _channel.onBroadcast(
        event: BroadcastEvents.controllerClaimResponse,
        callback: (raw) => _dispatch(
          event: BroadcastEvents.controllerClaimResponse,
          raw: raw,
          parse: ControllerClaimResponse.fromJson,
          deliver: _onControllerClaimResponse!,
        ),
      );
    }
    if (_onControllerHeartbeat != null) {
      _channel.onBroadcast(
        event: BroadcastEvents.controllerHeartbeat,
        callback: (raw) => _dispatch(
          event: BroadcastEvents.controllerHeartbeat,
          raw: raw,
          parse: ControllerHeartbeat.fromJson,
          deliver: _onControllerHeartbeat!,
        ),
      );
    }
    if (_onControllerReleased != null) {
      _channel.onBroadcast(
        event: BroadcastEvents.controllerReleased,
        callback: (raw) => _dispatch(
          event: BroadcastEvents.controllerReleased,
          raw: raw,
          parse: ControllerReleased.fromJson,
          deliver: _onControllerReleased!,
        ),
      );
    }
  }

  void _handleSubscribeStatus(RealtimeSubscribeStatus status, Object? error) {
    debugPrint('RoomConnection[$roomCode] subscribe status=$status error=$error');
    final wasSubscribed = _subscribed;

    if (status == RealtimeSubscribeStatus.subscribed) {
      _subscribed = true;
      _subscribeError = null;
      if (!(_subscribeCompleter?.isCompleted ?? true)) {
        _subscribeCompleter!.complete(true);
      }
    } else if (_isDisconnectedStatus(status)) {
      _subscribed = false;
      _subscribeError = error?.toString() ?? status.name;
      if (!(_subscribeCompleter?.isCompleted ?? true)) {
        _subscribeCompleter!.complete(false);
      }
    }

    if (wasSubscribed != _subscribed) {
      _onConnectionStateChanged?.call(_subscribed, _subscribeError);
    }
  }

  bool _isDisconnectedStatus(RealtimeSubscribeStatus status) {
    return status == RealtimeSubscribeStatus.channelError ||
        status == RealtimeSubscribeStatus.timedOut ||
        status == RealtimeSubscribeStatus.closed;
  }

  /// Subscribes to the channel for incoming broadcasts. Returns true once
  /// [RealtimeSubscribeStatus.subscribed] is reached. Register listeners first.
  Future<bool> connect() async {
    _attachBroadcastListeners();
    if (_subscribed) return true;
    if (_connectStarted && _subscribeCompleter != null) {
      return _subscribeCompleter!.future;
    }
    _connectStarted = true;
    _subscribeCompleter = Completer<bool>();

    _channel.subscribe(_handleSubscribeStatus);

    try {
      return await _subscribeCompleter!.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          _subscribeError = 'subscribe_timeout';
          _subscribed = false;
          _onConnectionStateChanged?.call(false, _subscribeError);
          return false;
        },
      );
    } catch (e) {
      _subscribeError = e.toString();
      _subscribed = false;
      _onConnectionStateChanged?.call(false, _subscribeError);
      return false;
    }
  }

  /// Tears down the current channel and opens a fresh subscription.
  Future<bool> reconnect() async {
    await Supabase.instance.client.removeChannel(_channel);
    _connectStarted = false;
    _subscribed = false;
    _subscribeCompleter = null;
    _broadcastListenersAttached = false;
    _channel = _createChannel();
    return connect();
  }

  Future<void> disconnect() async {
    await Supabase.instance.client.removeChannel(_channel);
    _connectStarted = false;
    if (_subscribed) {
      _subscribed = false;
      _onConnectionStateChanged?.call(false, null);
    }
    _subscribeCompleter = null;
  }

  void onConnectionStateChanged(ConnectionStateCallback callback) {
    _onConnectionStateChanged = callback;
  }

  // --- Listeners (register before connect) ---

  void onCounterUpdate(void Function(CounterUpdate update) callback) {
    _onCounterUpdate = callback;
  }

  void onWeatherUpdate(void Function(WeatherUpdate update) callback) {
    _onWeatherUpdate = callback;
  }

  void onSettingsUpdate(void Function(SettingsUpdate update) callback) {
    _onSettingsUpdate = callback;
  }

  void onAltitudeBoost(void Function(AltitudeBoost boost) callback) {
    _onAltitudeBoost = callback;
  }

  void onPhaseAction(void Function(PhaseActionMessage message) callback) {
    _onPhaseAction = callback;
  }

  void onSessionCancel(void Function() callback) {
    _onSessionCancel = callback;
  }

  void onControllerClaimRequest(
    void Function(ControllerClaimRequest request) callback,
  ) {
    _onControllerClaimRequest = callback;
  }

  void onControllerClaimResponse(
    void Function(ControllerClaimResponse response) callback,
  ) {
    _onControllerClaimResponse = callback;
  }

  void onControllerHeartbeat(
    void Function(ControllerHeartbeat heartbeat) callback,
  ) {
    _onControllerHeartbeat = callback;
  }

  void onControllerReleased(
    void Function(ControllerReleased released) callback,
  ) {
    _onControllerReleased = callback;
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

  Future<BroadcastSendResult> sendAltitudeBoost(AltitudeBoost boost) =>
      _send(BroadcastEvents.altitudeBoost, boost.toJson());

  Future<BroadcastSendResult> sendPhaseAction(PhaseActionMessage message) =>
      _send(BroadcastEvents.phaseAction, message.toJson());

  Future<BroadcastSendResult> sendSessionCancel() =>
      _send(BroadcastEvents.sessionCancel, const {});

  Future<BroadcastSendResult> sendControllerClaimRequest(
    ControllerClaimRequest request,
  ) =>
      _send(BroadcastEvents.controllerClaimRequest, request.toJson());

  Future<BroadcastSendResult> sendControllerClaimResponse(
    ControllerClaimResponse response,
  ) =>
      _send(BroadcastEvents.controllerClaimResponse, response.toJson());

  Future<BroadcastSendResult> sendControllerHeartbeat(
    ControllerHeartbeat heartbeat,
  ) =>
      _send(BroadcastEvents.controllerHeartbeat, heartbeat.toJson());

  Future<BroadcastSendResult> sendControllerReleased(
    ControllerReleased released,
  ) =>
      _send(BroadcastEvents.controllerReleased, released.toJson());

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
        map.containsKey('distanceSpeed') ||
        map.containsKey('bankPerPerson') ||
        map.containsKey('requestedAtMs') ||
        map.containsKey('targetSource') ||
        map.containsKey('accepted') ||
        map.containsKey('activeSource') ||
        map.containsKey('tMs') ||
        map.containsKey('reason');
  }
}
