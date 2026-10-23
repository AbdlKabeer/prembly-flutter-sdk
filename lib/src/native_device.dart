import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Sent as `X-SDK-Version`. Kept equal to pubspec.yaml by a test.
const String premblySdkVersion = '0.1.1';

/// The only origin the widget hands the device data to.
const String premblyWidgetOrigin = 'https://sdk-live.prembly.com';

/// The channel the native side answers on. Every method returns JSON text.
const MethodChannel premblyDeviceChannel =
    MethodChannel('com.prembly.identity_kyc/device');

/// What the phone knows about itself, handed to the widget page as
/// `window.__PREMBLY_NATIVE_DEVICE__`.
class NativeDeviceData {
  const NativeDeviceData({
    required this.platform,
    required this.deviceId,
    required this.deviceIdSource,
    required this.platformDeviceId,
    required this.app,
    required this.signals,
  });

  /// `ios` or `android`.
  final String platform;

  /// The app-scoped random ID: Keychain on iOS (survives a reinstall), a no-backup file on Android.
  final String deviceId;

  /// Where [deviceId] is kept, so the backend knows how long it lasts.
  final String deviceIdSource;

  /// The ID the OS keeps for this app: `identifierForVendor` on iOS, `ANDROID_ID` on Android.
  final String? platformDeviceId;

  /// `{ appId, appVersion, appBuild }`.
  final Map<String, dynamic> app;

  /// The same sections and keys the Transaction Monitoring SDK sends. Location is never included.
  final Map<String, dynamic> signals;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'source': 'native',
        'platform': platform,
        'sdkVersion': premblySdkVersion,
        'deviceId': deviceId,
        'deviceIdSource': deviceIdSource,
        'platformDeviceId': platformDeviceId,
        'app': app,
        'signals': signals,
      };
}

Future<String> _call(String method, [Map<String, dynamic>? arguments]) async {
  final result =
      await premblyDeviceChannel.invokeMethod<String>(method, arguments);
  if (result == null) {
    throw PlatformException(code: 'empty', message: '$method returned nothing');
  }
  return result;
}

/// The app-scoped device ID, or `null` if it could not be read.
Future<String?> readNativeDeviceId() async {
  try {
    final id = await _call('getDeviceId');
    return id.isEmpty ? null : id;
  } catch (_) {
    return null;
  }
}

/// The signals the SDK would send. Throws if the native side cannot be read.
Future<Map<String, dynamic>> readNativeSignals({bool includeLocation = false}) async {
  final text = await _call('collectSignals', {'includeLocation': includeLocation});
  return Map<String, dynamic>.from(jsonDecode(text) as Map);
}

/// `{ appId, appVersion, appBuild }`. Throws if the native side cannot be read.
Future<Map<String, dynamic>> readNativeAppInfo() async {
  final text = await _call('getAppInfo');
  return Map<String, dynamic>.from(jsonDecode(text) as Map);
}

/// Read the device from the native side. Never throws and never waits longer than [timeout]:
/// `null` means "could not read it", and the widget then falls back to what the web page can see.
/// It reads no location and shows no prompt.
Future<NativeDeviceData?> collectNativeDevice({
  Duration timeout = const Duration(milliseconds: 2500),
}) async {
  final String platform;
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      platform = 'ios';
      break;
    case TargetPlatform.android:
      platform = 'android';
      break;
    default:
      return null;
  }

  try {
    final results = await Future.wait<Object>([
      _call('getDeviceId'),
      readNativeSignals(includeLocation: false),
      readNativeAppInfo(),
    ]).timeout(timeout);

    final deviceId = results[0] as String;
    if (deviceId.isEmpty) return null;
    final signals = results[1] as Map<String, dynamic>;
    final app = results[2] as Map<String, dynamic>;

    final device = signals['device'];
    final platformId = device is Map ? device['platform_device_id'] : null;

    return NativeDeviceData(
      platform: platform,
      deviceId: deviceId,
      deviceIdSource: platform == 'ios' ? 'ios_keychain' : 'android_file',
      platformDeviceId:
          platformId is String && platformId.isNotEmpty ? platformId : null,
      app: app,
      signals: signals,
    );
  } catch (_) {
    return null;
  }
}

/// JSON that is safe to place inside a script: no `</script>`, no line separators.
String premblySafeJson(Object? value) => jsonEncode(value)
    .replaceAll('<', r'\u003c')
    .replaceAll('\u2028', r'\u2028')
    .replaceAll('\u2029', r'\u2029');

/// The script the WebView runs to hand the device data to the widget page. It sets the data only
/// when the page's origin is exactly [origin] (the Prembly widget by default), so a page the widget
/// navigates to never receives it.
String buildNativeDeviceScript(NativeDeviceData data, {String origin = premblyWidgetOrigin}) {
  return '''(function () {
  try {
    if (window.location.origin === ${premblySafeJson(origin)}) {
      window.__PREMBLY_NATIVE_DEVICE__ = ${premblySafeJson(data.toJson())};
    }
  } catch (e) {}
})();
true;''';
}
