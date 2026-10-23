import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prembly_identity_kyc/src/native_device.dart';
import 'package:prembly_identity_kyc/src/prembly_tm.dart';

import 'helpers.dart';

http.Response _created({Map<String, dynamic>? overrides}) => http.Response(
      jsonEncode({
        'status': true,
        'data': {
          'device_session_id': 'dsess_abc',
          'device_id': 'dev-1',
          'is_known_device': false,
          'expires_at':
              DateTime.now().add(const Duration(minutes: 15)).toUtc().toIso8601String(),
          ...?overrides,
        },
      }),
      201,
    );

void main() {
  late FakeNative native;
  late List<http.Request> requests;
  late http.Response Function(http.Request) respond;

  PremblyTMClient client({Duration? timeout}) {
    final tm = PremblyTMClient(
      httpClient: MockClient((request) async {
        requests.add(request);
        return respond(request);
      }),
    );
    tm.init(publishableKey: 'test_pk_abc', timeout: timeout);
    return tm;
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    native = FakeNative()..install();
    requests = [];
    respond = (_) => _created();
  });

  tearDown(() {
    native.uninstall();
    debugDefaultTargetPlatformOverride = null;
  });

  test('matches the version in pubspec.yaml', () {
    // Run from the package root, as `flutter test` does.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(premblySdkVersion, version);
  });

  group('init', () {
    test('rejects a secret key', () {
      expect(() => PremblyTMClient().init(publishableKey: 'live_sk_abc'), throwsArgumentError);
      expect(() => PremblyTMClient().init(publishableKey: 'test_sk_abc'), throwsArgumentError);
    });

    test('accepts live and test public keys', () {
      PremblyTMClient().init(publishableKey: 'live_pk_abc');
      PremblyTMClient().init(publishableKey: ' test_pk_abc ');
    });
  });

  group('getDeviceSession', () {
    test('says not_initialised before init, without calling anything', () async {
      final session = await PremblyTMClient().getDeviceSession();
      expect(session.deviceSessionId, isNull);
      expect(session.error, SessionError.notInitialised);
      expect(native.calls, isEmpty);
    });

    test('creates a session with the right URL, headers and body', () async {
      final tm = client()..identify('CUST-1');
      final session = await tm.getDeviceSession();

      expect(session.deviceSessionId, 'dsess_abc');
      expect(session.error, isNull);
      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.url.toString(),
          'https://backend.prembly.com/api/v1/fraud/transaction-monitoring/sdk/v1/sessions');
      expect(request.headers['X-Publishable-Key'], 'test_pk_abc');
      expect(request.headers['X-App-Id'], 'com.bank.app');
      expect(request.headers['X-SDK-Platform'], 'android');
      expect(request.headers['X-SDK-Version'], premblySdkVersion);

      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['device_id'], 'dev-1');
      expect(body['customer_id'], 'CUST-1');
      expect(body['consent'], {'location': false});
      expect(body['device'], isA<Map>());
      expect(body['integrity'], isA<Map>());
      expect(body.containsKey('collected_at'), isTrue);
    });

    test('sends only device_id and the sections when nobody is identified', () async {
      await client().getDeviceSession();
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body.containsKey('customer_id'), isFalse);
    });

    test('reuses a valid session and makes a new one on forceRefresh', () async {
      final tm = client();
      await tm.getDeviceSession();
      await tm.getDeviceSession();
      expect(requests, hasLength(1));
      await tm.getDeviceSession(forceRefresh: true);
      expect(requests, hasLength(2));
    });

    test('makes a new session when the customer changes', () async {
      final tm = client();
      await tm.getDeviceSession();
      tm.identify('CUST-2');
      await tm.getDeviceSession();
      expect(requests, hasLength(2));
    });

    test('shares one request between callers that ask at the same moment', () async {
      final tm = client();
      final results = await Future.wait([tm.getDeviceSession(), tm.getDeviceSession()]);
      expect(requests, hasLength(1));
      expect(results[0].deviceSessionId, results[1].deviceSessionId);
    });

    test('does not reuse a session that is about to expire', () async {
      respond = (_) => _created(overrides: {
            'expires_at':
                DateTime.now().add(const Duration(seconds: 10)).toUtc().toIso8601String(),
          });
      final tm = client();
      await tm.getDeviceSession();
      await tm.getDeviceSession();
      expect(requests, hasLength(2));
    });

    test('includes location only when turned on, and says so in consent', () async {
      final tm = PremblyTMClient(
        httpClient: MockClient((r) async {
          requests.add(r);
          return _created();
        }),
      )..init(publishableKey: 'test_pk_abc', location: true);
      await tm.getDeviceSession();
      final call = native.calls.firstWhere((c) => c.method == 'collectSignals');
      expect(call.arguments['includeLocation'], true);
      expect((jsonDecode(requests.single.body) as Map)['consent'], {'location': true});
    });

    for (final entry in {
      401: SessionError.unauthorised,
      403: SessionError.unauthorised,
      429: SessionError.rateLimited,
      400: SessionError.rejected,
      404: SessionError.rejected,
      500: SessionError.serverError,
      503: SessionError.serverError,
    }.entries) {
      test('fails open with ${entry.value} on HTTP ${entry.key}', () async {
        respond = (_) => http.Response('', entry.key);
        final session = await client().getDeviceSession();
        expect(session.deviceSessionId, isNull);
        expect(session.error, entry.value);
        expect(session.deviceId, 'dev-1');
      });
    }

    test('fails open with server_error when the reply has no session', () async {
      respond = (_) => http.Response(jsonEncode({'data': {}}), 200);
      expect((await client().getDeviceSession()).error, SessionError.serverError);
    });

    test('fails open with network_error when the request cannot be made', () async {
      final tm = PremblyTMClient(
        httpClient: MockClient((_) async => throw http.ClientException('offline')),
      )..init(publishableKey: 'test_pk_abc');
      expect((await tm.getDeviceSession()).error, SessionError.networkError);
    });

    test('fails open with timeout when the server is too slow', () async {
      final tm = PremblyTMClient(
        httpClient: MockClient((_) => Completer<http.Response>().future),
      )..init(publishableKey: 'test_pk_abc', timeout: const Duration(milliseconds: 30));
      expect((await tm.getDeviceSession()).error, SessionError.timeout);
    });

    test('fails open with native_error when the phone cannot be read', () async {
      native.failWith = Exception('boom');
      final session = await client().getDeviceSession();
      expect(session.deviceSessionId, isNull);
      expect(session.error, SessionError.nativeError);
      expect(requests, isEmpty);
    });

    test('never lets a failure after one success reuse the old session wrongly', () async {
      final tm = client();
      await tm.getDeviceSession();
      tm.reset();
      respond = (_) => http.Response('', 500);
      final session = await tm.getDeviceSession();
      expect(session.deviceSessionId, isNull);
    });
  });

  group('helpers', () {
    test('getDeviceId returns the device ID, or null when it cannot be read', () async {
      expect(await client().getDeviceId(), 'dev-1');
      native.failWith = Exception('boom');
      expect(await client().getDeviceId(), isNull);
    });

    test('getSignalsPreview sends nothing', () async {
      final preview = await client().getSignalsPreview();
      expect(preview!['device'], isA<Map>());
      expect(requests, isEmpty);
    });

    test('getSignalsPreview gives null when the phone cannot be read', () async {
      native.failWith = Exception('boom');
      expect(await client().getSignalsPreview(), isNull);
    });
  });
}
