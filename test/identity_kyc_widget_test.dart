import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prembly_identity_kyc/src/identity_kyc_mobile.dart';
import 'package:prembly_identity_kyc/src/identity_kyc_options.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'fake_webview.dart';
import 'helpers.dart';

const _pageUrl = 'https://sdk-live.prembly.com/?session=sess_1';
const _every = Duration(milliseconds: 100);

/// Runs on the Android platform, and puts the platform back by itself (a widget test must not
/// end with the platform override changed).
void widgetTest(String name, WidgetTesterCallback body) => testWidgets(
      name,
      body,
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

void main() {
  late FakeNative native;
  late FakeWebViewPlatform web;
  late List<Map<String, dynamic>> callbacks;

  setUp(() {
    native = FakeNative()..install();
    web = FakeWebViewPlatform();
    WebViewPlatform.instance = web;
    callbacks = [];
  });

  tearDown(() => native.uninstall());

  IdentityKycOptions options({bool collectDeviceData = true}) => IdentityKycOptions(
        firstName: 'Ada',
        lastName: 'Obi',
        email: 'ada@example.com',
        widgetKey: 'key',
        widgetId: 'id',
        collectDeviceData: collectDeviceData,
        callback: callbacks.add,
      );

  /// Opens the widget and lets it finish setting up (device read, session, WebView).
  Future<FakeWebViewController> open(
    WidgetTester tester, {
    IdentityKycOptions? opts,
    Future<String> Function(IdentityKycOptions)? initiator,
    Future<void> Function()? permissions,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: IdentityKycWebView(
        options: opts ?? options(),
        sessionInitiator: initiator ?? (_) async => 'sess_1',
        permissionRequester: permissions ?? () async {},
        screenWatchEvery: _every,
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    return web.controller!;
  }

  Iterable<String> deviceScripts(FakeWebViewController c) =>
      c.scripts.where((s) => s.contains('__PREMBLY_NATIVE_DEVICE__ ='));

  Iterable<String> updateScripts(FakeWebViewController c) =>
      c.scripts.where((s) => s.contains('scam.screen_capture_seen ='));

  int reads(String method) => native.calls.where((c) => c.method == method).length;

  group('the phone is read and handed to the page', () {
    widgetTest('loads the widget page for the session', (tester) async {
      final c = await open(tester);
      expect(c.loaded.map((u) => u.toString()), [_pageUrl]);
    });

    widgetTest('gives nothing to the page until it has started loading', (tester) async {
      final c = await open(tester);
      expect(deviceScripts(c), isEmpty);
    });

    widgetTest('injects the real device ID as the page starts, and again when it has loaded',
        (tester) async {
      final c = await open(tester);

      web.delegate!.onStarted!(_pageUrl);
      await tester.pump();
      expect(deviceScripts(c), hasLength(1));
      expect(deviceScripts(c).single, contains('"deviceId":"dev-1"'));
      expect(deviceScripts(c).single, contains('"platformDeviceId":"9774d56d682e549c"'));
      expect(deviceScripts(c).single, contains('window.location.origin === "https://sdk-live.prembly.com"'));

      web.delegate!.onFinished!(_pageUrl);
      await tester.pump();
      expect(deviceScripts(c), hasLength(2));
      // The message bridge for the widget's own events is still installed.
      expect(c.scripts.any((s) => s.contains('_premblyFlutterBridgeInstalled')), isTrue);
      expect(c.channels, contains('FlutterChannel'));
    });

    widgetTest('never puts location in what it hands over', (tester) async {
      final c = await open(tester);
      web.delegate!.onStarted!(_pageUrl);
      await tester.pump();
      expect(reads('collectSignals'), 1);
      expect(native.calls.firstWhere((m) => m.method == 'collectSignals').arguments['includeLocation'], false);
      expect(deviceScripts(c).single, isNot(contains('"location"')));
    });
  });

  group('the screen is watched while the widget is open', () {
    widgetTest('does not start before the page has loaded', (tester) async {
      await open(tester);
      await tester.pump(_every * 3);
      expect(reads('checkScreenCapture'), 0);
    });

    widgetTest('reports the screen to the page once it has loaded', (tester) async {
      final c = await open(tester);
      web.delegate!.onFinished!(_pageUrl);
      await tester.pump(_every * 3);
      expect(updateScripts(c), isNotEmpty);
      expect(updateScripts(c).last, contains('scam.is_screen_shared_or_recorded = false;'));
      expect(updateScripts(c).last, contains('scam.screen_capture_seen = false;'));
    });

    widgetTest('tells the page when a recording starts, and remembers it after it stops',
        (tester) async {
      final c = await open(tester);
      web.delegate!.onFinished!(_pageUrl);
      await tester.pump(_every * 2);

      native.screenCapture = {'is_screen_shared_or_recorded': true};
      await tester.pump(_every * 3);
      expect(updateScripts(c).last, contains('scam.is_screen_shared_or_recorded = true;'));
      expect(updateScripts(c).last, contains('scam.screen_capture_seen = true;'));

      native.screenCapture = {'is_screen_shared_or_recorded': false};
      await tester.pump(_every * 3);
      expect(updateScripts(c).last, contains('scam.is_screen_shared_or_recorded = false;'));
      expect(updateScripts(c).last, contains('scam.screen_capture_seen = true;'));
    });

    widgetTest('starts with "seen" true when the first snapshot already saw a recording',
        (tester) async {
      native.signals = {
        ...native.signals,
        'scam_signals': {'is_screen_shared_or_recorded': true},
      };
      native.screenCapture = {'is_screen_shared_or_recorded': false};
      final c = await open(tester);
      web.delegate!.onFinished!(_pageUrl);
      await tester.pump(_every * 3);
      expect(updateScripts(c).last, contains('scam.screen_capture_seen = true;'));
    });

    widgetTest('starts the watch only once, however many pages load', (tester) async {
      await open(tester);
      web.delegate!.onFinished!(_pageUrl);
      web.delegate!.onFinished!(_pageUrl);
      await tester.pump(_every * 3);
      final first = reads('checkScreenCapture');
      await tester.pump(_every * 4);
      // One watcher reads about once per interval, not twice.
      expect(reads('checkScreenCapture') - first, lessThanOrEqualTo(5));
    });

    widgetTest('stops reading when the widget is closed', (tester) async {
      await open(tester);
      web.delegate!.onFinished!(_pageUrl);
      await tester.pump(_every * 3);
      expect(reads('checkScreenCapture'), greaterThan(0));

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(_every);
      final before = reads('checkScreenCapture');
      await tester.pump(_every * 6);
      expect(reads('checkScreenCapture'), before);
    });
  });

  group('it carries on when the phone is not read', () {
    widgetTest('collectDeviceData: false reads nothing and gives nothing', (tester) async {
      final c = await open(tester, opts: options(collectDeviceData: false));
      web.delegate!.onStarted!(_pageUrl);
      web.delegate!.onFinished!(_pageUrl);
      await tester.pump(_every * 3);

      expect(c.loaded, hasLength(1));
      expect(native.calls, isEmpty);
      expect(deviceScripts(c), isEmpty);
      expect(updateScripts(c), isEmpty);
      expect(c.scripts.any((s) => s.contains('_premblyFlutterBridgeInstalled')), isTrue);
    });

    widgetTest('a phone that cannot be read does not stop the page loading', (tester) async {
      native.failWith = Exception('boom');
      final c = await open(tester);
      web.delegate!.onStarted!(_pageUrl);
      web.delegate!.onFinished!(_pageUrl);
      await tester.pump(_every * 3);

      expect(c.loaded.map((u) => u.toString()), [_pageUrl]);
      expect(deviceScripts(c), isEmpty);
      expect(reads('checkScreenCapture'), 0);
      expect(callbacks, isEmpty);
    });
  });

  group('the widget still does what it did before', () {
    widgetTest('reports api_error when the session cannot be created', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: IdentityKycWebView(
          options: options(),
          sessionInitiator: (_) async => throw Exception('API call failed with status: 400.'),
          permissionRequester: () async {},
          screenWatchEvery: _every,
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(callbacks.single['status'], 'api_error');
      expect(find.textContaining('Error:'), findsOneWidget);
      expect(web.controller, isNull);
    });

    widgetTest('reports a camera problem as error, without creating a session', (tester) async {
      var sessionStarted = false;
      await tester.pumpWidget(MaterialApp(
        home: IdentityKycWebView(
          options: options(),
          sessionInitiator: (_) async {
            sessionStarted = true;
            return 'sess_1';
          },
          permissionRequester: () async =>
              throw Exception('Camera permission is required for verification.'),
          screenWatchEvery: _every,
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(callbacks.single['status'], 'error');
      expect(sessionStarted, isFalse);
    });

    widgetTest('closing the widget reports closed', (tester) async {
      await open(tester);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(callbacks.single['status'], 'closed');
    });
  });
}
