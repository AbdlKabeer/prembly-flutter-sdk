import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prembly_identity_kyc/src/native_device.dart';

import 'helpers.dart';

void main() {
  late FakeNative native;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    native = FakeNative()..install();
  });

  tearDown(() {
    native.uninstall();
    debugDefaultTargetPlatformOverride = null;
  });

  group('collectNativeDevice', () {
    test('returns the device ID, the OS-kept ID and the signals', () async {
      final data = await collectNativeDevice();
      expect(data, isNotNull);
      expect(data!.deviceId, 'dev-1');
      expect(data.platformDeviceId, '9774d56d682e549c');
      expect(data.platform, 'android');
      expect(data.deviceIdSource, 'android_file');
      expect(data.app['appId'], 'com.bank.app');
      expect(data.signals['integrity'], {'is_rooted': false, 'is_emulator': false});
    });

    test('reports where an iOS ID is kept', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final data = await collectNativeDevice();
      expect(data!.platform, 'ios');
      expect(data.deviceIdSource, 'ios_keychain');
    });

    test('never asks the native side for location', () async {
      await collectNativeDevice();
      final call = native.calls.firstWhere((c) => c.method == 'collectSignals');
      expect(call.arguments['includeLocation'], false);
    });

    test('leaves the OS-kept ID empty when the phone gave none', () async {
      native.signals = {'device': {'model': 'Pixel 8'}};
      expect((await collectNativeDevice())!.platformDeviceId, isNull);
    });

    test('gives null, not an error, when the native side fails', () async {
      native.failWith = Exception('boom');
      expect(await collectNativeDevice(), isNull);
    });

    test('gives null when there is no device ID', () async {
      native.deviceId = '';
      expect(await collectNativeDevice(), isNull);
    });

    test('gives null on a platform that has no native side', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(await collectNativeDevice(), isNull);
    });

    test('toJson carries the fields the widget page reads', () async {
      final json = (await collectNativeDevice())!.toJson();
      expect(json['version'], 1);
      expect(json['source'], 'native');
      expect(json['deviceId'], 'dev-1');
      expect(json['deviceIdSource'], 'android_file');
      expect(json['platformDeviceId'], '9774d56d682e549c');
      expect(json['sdkVersion'], premblySdkVersion);
    });
  });

  group('buildNativeDeviceScript', () {
    NativeDeviceData data({String model = 'Pixel 8'}) => NativeDeviceData(
          platform: 'android',
          deviceId: 'dev-1',
          deviceIdSource: 'android_file',
          platformDeviceId: 'abc',
          app: const {'appId': 'a'},
          signals: {
            'device': {'model': model}
          },
        );

    test('sets the global only on the Prembly widget origin', () {
      final script = buildNativeDeviceScript(data());
      expect(script, contains('window.location.origin === "$premblyWidgetOrigin"'));
      expect(script, contains('window.__PREMBLY_NATIVE_DEVICE__ ='));
    });

    test('cannot be broken out of by text in a device field', () {
      final script = buildNativeDeviceScript(data(model: '</script><script>alert(1)</script>'));
      expect(script, isNot(contains('</script>')));
      expect(script, contains(r'\u003c/script>'));
    });

    test('escapes line separators', () {
      final script = buildNativeDeviceScript(data(model: 'a\u2028b\u2029c'));
      expect(script, isNot(contains('\u2028')));
      expect(script, isNot(contains('\u2029')));
    });

    test('ends with true so a WebView does not report a silent failure', () {
      expect(buildNativeDeviceScript(data()).trim().endsWith('true;'), isTrue);
    });
  });
}
