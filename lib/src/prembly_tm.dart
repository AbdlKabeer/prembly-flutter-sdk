import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'native_device.dart';

const String _defaultBaseUrl = 'https://backend.prembly.com';
const String _sessionsPath = '/api/v1/fraud/transaction-monitoring/sdk/v1/sessions';
const Duration _defaultTimeout = Duration(milliseconds: 5000);

// Treat a session as expired a little early, so it is still valid when the backend screens.
const Duration _refreshMargin = Duration(seconds: 30);

/// Why there is no session, when `deviceSessionId` is null.
class SessionError {
  const SessionError._();
  static const notInitialised = 'not_initialised';
  static const timeout = 'timeout';
  static const networkError = 'network_error';
  static const unauthorised = 'unauthorised';
  static const rateLimited = 'rate_limited';
  static const rejected = 'rejected';
  static const serverError = 'server_error';
  static const nativeError = 'native_error';
}

class DeviceSession {
  const DeviceSession({
    required this.deviceSessionId,
    required this.deviceId,
    this.isKnownDevice,
    this.expiresAt,
    this.error,
  });

  /// Send this to your backend with the transaction, and pass it as `device_session_id` when you
  /// screen. Null when a session could not be created (the SDK fails open: screen without it).
  final String? deviceSessionId;

  /// The app-scoped device ID, when it could be read.
  final String? deviceId;

  /// Whether we had seen this device before. Only set when a session was created.
  final bool? isKnownDevice;

  /// When the session stops being usable. Only set when a session was created.
  final DateTime? expiresAt;

  /// Why there is no session, when [deviceSessionId] is null. One of the [SessionError] values.
  final String? error;
}

/// Device signals for Prembly Transaction Monitoring. Never holds your secret key and fails open:
/// a session that cannot be created comes back with a null `deviceSessionId`, so a payment is
/// never blocked by the SDK.
class PremblyTMClient {
  PremblyTMClient({http.Client? httpClient}) : _http = httpClient;

  final http.Client? _http;

  String? _publishableKey;
  String _baseUrl = _defaultBaseUrl;
  bool _location = false;
  Duration _timeout = _defaultTimeout;
  bool _debug = false;
  bool _initialised = false;

  String? _customerId;
  _Cached? _cached;
  Future<DeviceSession>? _inFlight;
  Map<String, dynamic>? _appInfo;

  /// Set up once, early (for example when the app starts). A bad key throws, because that is a
  /// mistake to fix while developing. Nothing after this throws.
  void init({
    required String publishableKey,
    String? baseUrl,
    bool location = false,
    Duration? timeout,
    bool debug = false,
  }) {
    final key = publishableKey.trim();
    if (!key.startsWith('live_pk_') && !key.startsWith('test_pk_')) {
      throw ArgumentError(
        'PremblyTM.init: publishableKey must be your public key (live_pk_... or test_pk_...). '
        'Never put a secret key (live_sk_ / test_sk_) in an app.',
      );
    }
    _publishableKey = key;
    _baseUrl = (baseUrl ?? _defaultBaseUrl).replaceAll(RegExp(r'/+$'), '');
    _location = location;
    _timeout = timeout ?? _defaultTimeout;
    _debug = debug;
    _initialised = true;
    _cached = null;
    _inFlight = null;
  }

  /// Tell the SDK which customer is using the app, or null when they sign out.
  void identify(String? customerId) {
    final next = customerId?.trim();
    final value = (next == null || next.isEmpty) ? null : next;
    if (value != _customerId) {
      _customerId = value;
      _cached = null;
    }
  }

  /// Turn location collection on or off, for example when the user changes their consent.
  void setLocationEnabled(bool enabled) {
    if (_initialised && _location != enabled) {
      _location = enabled;
      _cached = null;
    }
  }

  /// Forget the customer and any cached session (for example on sign-out).
  void reset() {
    _customerId = null;
    _cached = null;
    _inFlight = null;
  }

  /// The app-scoped device ID, or null if it could not be read.
  Future<String?> getDeviceId() => readNativeDeviceId();

  /// The signals the SDK would send, without sending anything. For testing and for showing users
  /// what is collected. Honours the location setting.
  Future<Map<String, dynamic>?> getSignalsPreview() async {
    try {
      return await readNativeSignals(includeLocation: _location);
    } catch (error) {
      _log('getSignalsPreview failed', error);
      return null;
    }
  }

  /// Collect the device signals and create a session. Call it before a sensitive action (sign-in,
  /// payment, adding a beneficiary) and send `deviceSessionId` to your backend. A session is
  /// reused until shortly before it expires. Never throws.
  Future<DeviceSession> getDeviceSession({bool forceRefresh = false}) {
    if (!_initialised) {
      return Future.value(_failed(SessionError.notInitialised, null));
    }
    if (!forceRefresh && _isCacheValid()) {
      return Future.value(_cached!.session);
    }
    // Share one request between callers that ask at the same moment.
    final running = _inFlight;
    if (running != null) return running;

    final request = _createSession().whenComplete(() => _inFlight = null);
    _inFlight = request;
    return request;
  }

  bool _isCacheValid() {
    final cached = _cached;
    return cached != null &&
        cached.customerId == _customerId &&
        cached.includeLocation == _location &&
        cached.expiresAt.subtract(_refreshMargin).isAfter(DateTime.now());
  }

  Future<DeviceSession> _createSession() async {
    String? deviceId;
    final Map<String, dynamic> body;
    final Map<String, dynamic> app;
    try {
      deviceId = await _readDeviceIdOrThrow();
      final signals = await readNativeSignals(includeLocation: _location);
      app = _appInfo ??= await readNativeAppInfo();
      body = {
        ...signals,
        'device_id': deviceId,
        if (_customerId != null) 'customer_id': _customerId,
        'consent': {'location': _location},
        'collected_at': DateTime.now().toUtc().toIso8601String(),
      };
    } catch (error) {
      _log('collecting signals failed', error);
      return _failed(SessionError.nativeError, deviceId);
    }

    final client = _http ?? http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('$_baseUrl$_sessionsPath'),
            headers: {
              'Content-Type': 'application/json',
              'X-Publishable-Key': _publishableKey!,
              'X-App-Id': (app['appId'] ?? '').toString(),
              'X-SDK-Platform': _platformName(),
              'X-SDK-Version': premblySdkVersion,
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _failed(_errorForStatus(response.statusCode), deviceId);
      }
      final payload = jsonDecode(response.body);
      final data = payload is Map ? payload['data'] : null;
      final sessionId = data is Map ? data['device_session_id'] : null;
      if (data is! Map || sessionId == null) {
        return _failed(SessionError.serverError, deviceId);
      }

      final expiresAt = DateTime.tryParse((data['expires_at'] ?? '').toString());
      final session = DeviceSession(
        deviceSessionId: sessionId.toString(),
        deviceId: (data['device_id'] ?? deviceId)?.toString(),
        isKnownDevice: data['is_known_device'] == true,
        expiresAt: expiresAt,
      );
      if (expiresAt != null) {
        _cached = _Cached(
          customerId: _customerId,
          includeLocation: _location,
          session: session,
          expiresAt: expiresAt,
        );
      }
      return session;
    } on TimeoutException catch (error) {
      _log('session request timed out', error);
      return _failed(SessionError.timeout, deviceId);
    } catch (error) {
      _log('session request failed', error);
      return _failed(SessionError.networkError, deviceId);
    } finally {
      if (_http == null) client.close();
    }
  }

  Future<String> _readDeviceIdOrThrow() async {
    final id = await readNativeDeviceId();
    if (id == null) throw StateError('the device ID could not be read');
    return id;
  }

  String _platformName() =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  String _errorForStatus(int status) {
    if (status == 401 || status == 403) return SessionError.unauthorised;
    if (status == 429) return SessionError.rateLimited;
    if (status >= 400 && status < 500) return SessionError.rejected;
    return SessionError.serverError;
  }

  DeviceSession _failed(String error, String? deviceId) {
    _log('no device session: $error');
    return DeviceSession(deviceSessionId: null, deviceId: deviceId, error: error);
  }

  void _log(String message, [Object? detail]) {
    if (_debug) debugPrint('[PremblyTM] $message ${detail ?? ''}');
  }
}

class _Cached {
  _Cached({
    required this.customerId,
    required this.includeLocation,
    required this.session,
    required this.expiresAt,
  });

  final String? customerId;
  final bool includeLocation;
  final DeviceSession session;
  final DateTime expiresAt;
}

/// The Transaction Monitoring entry point: `PremblyTM.init(...)`, `PremblyTM.identify(...)`,
/// `await PremblyTM.getDeviceSession()`.
class PremblyTM {
  PremblyTM._();

  static final PremblyTMClient _client = PremblyTMClient();

  static void init({
    required String publishableKey,
    String? baseUrl,
    bool location = false,
    Duration? timeout,
    bool debug = false,
  }) =>
      _client.init(
        publishableKey: publishableKey,
        baseUrl: baseUrl,
        location: location,
        timeout: timeout,
        debug: debug,
      );

  static void identify(String? customerId) => _client.identify(customerId);

  static void setLocationEnabled(bool enabled) => _client.setLocationEnabled(enabled);

  static void reset() => _client.reset();

  static Future<String?> getDeviceId() => _client.getDeviceId();

  static Future<Map<String, dynamic>?> getSignalsPreview() => _client.getSignalsPreview();

  static Future<DeviceSession> getDeviceSession({bool forceRefresh = false}) =>
      _client.getDeviceSession(forceRefresh: forceRefresh);
}
