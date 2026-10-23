import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prembly_identity_kyc/src/native_device.dart';

/// Stand-in for the native side. Each handler returns JSON text, like the real plugin.
class FakeNative {
  FakeNative({
    this.deviceId = 'dev-1',
    Map<String, dynamic>? signals,
    Map<String, dynamic>? app,
  })  : signals = signals ??
            {
              'device': {
                'model': 'Pixel 8',
                'os_name': 'android',
                'platform_device_id': '9774d56d682e549c',
              },
              'integrity': {'is_rooted': false, 'is_emulator': false},
              'network': {'type': 'wifi', 'is_vpn_active': false},
              'scam_signals': {'is_screen_shared_or_recorded': false},
            },
        app = app ??
            {'appId': 'com.bank.app', 'appVersion': '3.4.1', 'appBuild': '341'};

  String deviceId;
  Map<String, dynamic> signals;
  Map<String, dynamic> app;
  Object? failWith;
  Object? screenCapture = {'is_screen_shared_or_recorded': false};
  final List<MethodCall> calls = [];

  void install() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(premblyDeviceChannel, (call) async {
      calls.add(call);
      if (failWith != null) throw failWith!;
      switch (call.method) {
        case 'getDeviceId':
          return deviceId;
        case 'collectSignals':
          return jsonEncode(signals);
        case 'getAppInfo':
          return jsonEncode(app);
        case 'checkScreenCapture':
          final value = screenCapture;
          if (value is Exception) throw value;
          return value is String ? value : jsonEncode(value);
      }
      throw MissingPluginException();
    });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(premblyDeviceChannel, null);
  }
}
