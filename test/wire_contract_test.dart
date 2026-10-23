import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The signal keys each native collector sends. If a key is added, renamed or dropped, this test
/// and contract/signals.contract.json change with it, and so does the backend.
void main() {
  final contract = jsonDecode(File('contract/signals.contract.json').readAsStringSync())
      as Map<String, dynamic>;
  final kotlin = File(
          'android/src/main/kotlin/com/prembly/prembly_identity_kyc/SignalCollector.kt')
      .readAsStringSync();
  final objc = File('ios/Classes/TMSignalCollector.m').readAsStringSync();

  Set<String> keysIn(String source, RegExp pattern) =>
      pattern.allMatches(source).map((m) => m.group(1)!).toSet();

  Set<String> expected(String platform) => {
        ...(contract['sections'] as List).cast<String>(),
        for (final keys in (contract[platform] as Map).values) ...(keys as List).cast<String>(),
      };

  test('Android sends exactly the contract keys', () {
    // .put("key", ...) calls; camelCase keys (appId, appVersion) belong to getAppInfo, not signals.
    final found = keysIn(kotlin, RegExp(r'\.put\("([a-z_]+)"'));
    expect(found, expected('android'));
  });

  test('iOS sends exactly the contract keys', () {
    // Dictionary keys at the start of a line (@"key" : value) and signals[@"section"] assignments.
    final found = {
      ...keysIn(objc, RegExp(r'^\s*@"([a-z_]+)"\s*:', multiLine: true)),
      ...keysIn(objc, RegExp(r'signals\[@"([a-z_]+)"\]')),
    };
    expect(found, expected('ios'));
  });

  test('both platforms answer every channel method the Dart side calls', () {
    final plugin = File(
            'android/src/main/kotlin/com/prembly/prembly_identity_kyc/PremblyIdentityKycPlugin.kt')
        .readAsStringSync();
    final pluginIos = File('ios/Classes/PremblyIdentityKycPlugin.m').readAsStringSync();
    for (final method in ['getAppInfo', 'getDeviceId', 'collectSignals', 'checkScreenCapture']) {
      expect(plugin, contains('"$method"'), reason: 'Android $method');
      expect(pluginIos, contains('@"$method"'), reason: 'iOS $method');
    }
  });
}
