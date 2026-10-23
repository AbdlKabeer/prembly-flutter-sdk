import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prembly_identity_kyc/src/native_device.dart';
import 'package:prembly_identity_kyc/src/workflow_core.dart';
import 'package:prembly_identity_kyc/src/workflow_mobile.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'fake_webview.dart';
import 'helpers.dart';

const _customer = WorkflowCustomer(firstName: 'Ada', lastName: 'Obi', email: 'ada@example.com');
const _link = 'https://hosted.example.com/?session=wf_session_1';
const _every = Duration(milliseconds: 100);

WorkflowOptions _options({
  String key = 'test_pk_abc',
  WorkflowCustomer customer = _customer,
  void Function(WorkflowResult)? callback,
  void Function(WorkflowEvent)? onEvent,
  String? hostedUrl,
  bool collectDeviceData = true,
  Map<String, dynamic>? metadata,
}) =>
    WorkflowOptions(
      publishableKey: key,
      workflowId: 'wf_1',
      customer: customer,
      metadata: metadata,
      hostedUrl: hostedUrl,
      collectDeviceData: collectDeviceData,
      onEvent: onEvent,
      callback: callback ?? (_) {},
    );

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void widgetTest(String name, WidgetTesterCallback body) => testWidgets(
      name,
      body,
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

void main() {
  group('createWorkflowSession', () {
    test('posts the web SDK request and returns the session', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return _json(201, {
          'status': true,
          'data': {'session_id': 'wf_session_1', 'link': _link},
        });
      });
      final session = await createWorkflowSession(
        _options(metadata: {'a': 1}),
        client: client,
        platform: 'ios',
      );
      expect(session.sessionId, 'wf_session_1');
      expect(seen.url.toString(),
          'https://backend.prembly.com/api/v1/compliance-workflow/sdk/v1/sessions/');
      expect(seen.headers['X-Publishable-Key'], 'test_pk_abc');
      expect(seen.headers['X-SDK-Platform'], 'ios');
      expect(seen.headers['X-App-Id'], isNull);
      expect(jsonDecode(seen.body), {
        'workflow_id': 'wf_1',
        'customer': {'first_name': 'Ada', 'last_name': 'Obi', 'email': 'ada@example.com'},
        'metadata': {'a': 1},
      });
    });

    test('refuses a secret key before any request', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return _json(201, {});
      });
      await expectLater(
        createWorkflowSession(_options(key: 'live_sk_x'), client: client),
        throwsA(isA<WorkflowError>().having((e) => e.code, 'code', 'invalid_key')),
      );
      expect(called, isFalse);
    });

    test('validates the customer', () async {
      await expectLater(
        createWorkflowSession(
          _options(
              customer: const WorkflowCustomer(firstName: 'A', lastName: 'B', email: 'nope')),
        ),
        throwsA(isA<WorkflowError>().having((e) => e.code, 'code', 'invalid_request')),
      );
    });

    for (final entry in {
      401: 'unauthorised',
      404: 'not_found',
      429: 'rate_limited',
      400: 'invalid_request',
      500: 'server_error',
    }.entries) {
      test('maps HTTP ${entry.key} to ${entry.value}', () async {
        final client = MockClient((_) async => _json(entry.key, {'status': false, 'message': 'm'}));
        await expectLater(
          createWorkflowSession(_options(), client: client),
          throwsA(isA<WorkflowError>()
              .having((e) => e.code, 'code', entry.value)
              .having((e) => e.message, 'message', 'm')),
        );
      });
    }

    test('rejects an incomplete success body', () async {
      final client = MockClient((_) async => _json(201, {'data': {'session_id': 'x'}}));
      await expectLater(
        createWorkflowSession(_options(), client: client),
        throwsA(isA<WorkflowError>().having((e) => e.code, 'code', 'server_error')),
      );
    });

    test('reports a network failure', () async {
      final client = MockClient((_) async => throw Exception('offline'));
      await expectLater(
        createWorkflowSession(_options(), client: client),
        throwsA(isA<WorkflowError>().having((e) => e.code, 'code', 'network_error')),
      );
    });
  });

  group('parseWorkflowMessage', () {
    test('reads the current and the legacy envelope', () {
      final current = parseWorkflowMessage(jsonEncode({
        'source': 'prembly-sdk',
        'product': 'workflow',
        'type': 'step_started',
        'session_id': 's',
        'node_id': 'n',
      }))!;
      expect([current.type, current.sessionId, current.nodeId], ['step_started', 's', 'n']);
      final legacy = parseWorkflowMessage(
          jsonEncode({'source': 'prembly-workflow-sdk', 'type': 'completed', 'session_id': 's'}))!;
      expect(legacy.type, 'completed');
      expect(legacy.nodeId, isNull);
    });

    test('ignores other sources, products and bad input', () {
      expect(parseWorkflowMessage('not json'), isNull);
      expect(parseWorkflowMessage(jsonEncode({'source': 'x', 'type': 'a', 'session_id': 's'})), isNull);
      expect(
        parseWorkflowMessage(jsonEncode(
            {'source': 'prembly-sdk', 'product': 'tm', 'type': 'a', 'session_id': 's'})),
        isNull,
      );
    });

    test('knows the end states', () {
      expect(['completed', 'failed', 'manual_review', 'expired'].every(isWorkflowEndState), isTrue);
      expect(isWorkflowEndState('processing'), isFalse);
    });
  });

  group('links', () {
    test('originOf keeps scheme, host and a non-default port only', () {
      expect(originOf('http://localhost:3010/?session=x'), 'http://localhost:3010');
      expect(originOf('https://SDK-Live.Prembly.com/a/b#c'), 'https://sdk-live.prembly.com');
      expect(originOf('https://sdk-live.prembly.com:443/'), 'https://sdk-live.prembly.com');
      expect(originOf('javascript:alert(1)'), '');
      expect(originOf('not a url'), '');
    });

    test('withSession adds the session and keeps the rest', () {
      expect(withSession('http://localhost:3010/', 'wf_s1'), 'http://localhost:3010/?session=wf_s1');
      expect(withSession('https://h.example/p?a=1&session=old', 'wf_s1'),
          'https://h.example/p?a=1&session=wf_s1');
    });
  });

  group('the workflow screen', () {
    late FakeNative native;
    late FakeWebViewPlatform web;
    late List<WorkflowResult> results;
    late List<WorkflowEvent> events;

    setUp(() {
      native = FakeNative()..install();
      web = FakeWebViewPlatform();
      WebViewPlatform.instance = web;
      results = [];
      events = [];
    });

    tearDown(() => native.uninstall());

    Future<FakeWebViewController?> open(
      WidgetTester tester, {
      WorkflowOptions? options,
      Future<WorkflowSessionInfo> Function(WorkflowOptions)? creator,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WorkflowWebView(
                  options: options ??
                      _options(callback: results.add, onEvent: events.add),
                  sessionCreator: creator ??
                      (_) async => const WorkflowSessionInfo(sessionId: 'wf_session_1', link: _link),
                  screenWatchEvery: _every,
                ),
              )),
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      return web.controller;
    }

    void post(FakeWebViewController c, String raw) =>
        c.channelHandlers['FlutterChannel']!(JavaScriptMessage(message: raw));

    String message(String type, {String session = 'wf_session_1'}) => jsonEncode({
          'source': 'prembly-sdk',
          'product': 'workflow',
          'type': type,
          'session_id': session,
        });

    Iterable<String> deviceScripts(FakeWebViewController c) =>
        c.scripts.where((s) => s.contains('__PREMBLY_NATIVE_DEVICE__ ='));

    widgetTest('opens the session link and hands the phone to that origin only', (tester) async {
      final c = (await open(tester))!;
      expect(c.loaded.map((u) => u.toString()), [_link]);
      expect(c.channels, contains('FlutterChannel'));

      web.delegate!.onStarted!(_link);
      await tester.pump();
      expect(deviceScripts(c), hasLength(1));
      expect(deviceScripts(c).single, contains('"deviceId":"dev-1"'));
      expect(deviceScripts(c).single,
          contains('window.location.origin === "https://hosted.example.com"'));
      expect(deviceScripts(c).single, isNot(contains(premblyWidgetOrigin)));
      expect(deviceScripts(c).single, isNot(contains('"location"')));
    });

    widgetTest('hostedUrl opens the session at that hosted app, and trusts its origin',
        (tester) async {
      final c = (await open(tester,
          options: _options(
              hostedUrl: 'http://localhost:3010/', callback: results.add, onEvent: events.add)))!;
      expect(c.loaded.single.toString(), 'http://localhost:3010/?session=wf_session_1');
      web.delegate!.onStarted!('http://localhost:3010/');
      await tester.pump();
      expect(deviceScripts(c).single,
          contains('window.location.origin === "http://localhost:3010"'));
    });

    widgetTest('hands over nothing when collectDeviceData is off', (tester) async {
      final c = (await open(tester,
          options: _options(collectDeviceData: false, callback: results.add)))!;
      web.delegate!.onStarted!(_link);
      await tester.pump();
      expect(deviceScripts(c), isEmpty);
      expect(native.calls.where((m) => m.method == 'collectSignals'), isEmpty);
    });

    widgetTest('reports the screen to the page once it has loaded', (tester) async {
      final c = (await open(tester))!;
      web.delegate!.onFinished!(_link);
      await tester.pump(_every * 3);
      expect(c.scripts.where((s) => s.contains('scam.screen_capture_seen =')), isNotEmpty);
    });

    widgetTest('passes events on and ends once on an end state', (tester) async {
      final c = (await open(tester))!;
      post(c, message('step_started'));
      post(c, message('processing'));
      expect(events.map((e) => e.type), ['step_started', 'processing']);
      expect(results, isEmpty);

      post(c, message('completed'));
      await tester.pumpAndSettle();
      expect(results.single.status, 'completed');
      expect(results.single.sessionId, 'wf_session_1');
      expect(find.byType(WorkflowWebView), findsNothing);

      // Nothing more is reported after the end.
      post(c, message('failed'));
      expect(results, hasLength(1));
    });

    widgetTest('reports each end state it is sent', (tester) async {
      for (final state in ['failed', 'manual_review', 'expired']) {
        results.clear();
        final c = (await open(tester))!;
        post(c, message(state));
        await tester.pumpAndSettle();
        expect(results.single.status, state);
      }
    });

    widgetTest('ignores messages about another session, other sources and bad input',
        (tester) async {
      final c = (await open(tester))!;
      post(c, message('completed', session: 'someone_else'));
      post(c, jsonEncode({'source': 'other', 'type': 'completed', 'session_id': 'wf_session_1'}));
      post(c, 'not json');
      expect(events, isEmpty);
      expect(results, isEmpty);
    });

    widgetTest('closing before an end state is a cancel with the last event', (tester) async {
      final c = (await open(tester))!;
      post(c, message('processing'));
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(results.single.status, 'cancelled');
      expect(results.single.sessionId, 'wf_session_1');
      expect(results.single.lastEvent, 'processing');
      expect(find.byType(WorkflowWebView), findsNothing);
    });

    widgetTest('closing after the end does not report a second result', (tester) async {
      final c = (await open(tester))!;
      post(c, message('completed'));
      await tester.pumpAndSettle();
      expect(results.map((r) => r.status), ['completed']);
    });

    widgetTest('a session that cannot be created fails with its code', (tester) async {
      await open(tester,
          creator: (_) async => throw const WorkflowError('unauthorised', 'bad key'));
      expect(results.single.status, 'failed');
      expect(results.single.errorCode, 'unauthorised');
      expect(find.textContaining('bad key'), findsOneWidget);
    });
  });
}
