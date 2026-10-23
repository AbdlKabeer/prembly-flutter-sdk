// ignore_for_file: implementation_imports
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:prembly_identity_kyc/prembly_identity_kyc.dart';
// Internals, imported by path because the example exercises exactly what the widget calls.
import 'package:prembly_identity_kyc/src/native_device.dart';
import 'package:prembly_identity_kyc/src/screen_watch.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  runApp(const MyApp());
}

// A page served as if it came from the Prembly widget origin, so the origin check in the injected
// script passes without a real verification session. It prints what the page receives.
const _testPage = '''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>body{font:12px Menlo,monospace;padding:8px;word-break:break-all}b{color:#0f766e}</style></head><body>
<div><b>origin:</b> <span id="o"></span></div>
<div><b>global present:</b> <span id="p">checking…</span></div>
<div><b>screen now / seen:</b> <span id="s">-</span></div>
<div><b>updates received:</b> <span id="u">0</span></div>
<pre id="d" style="white-space:pre-wrap"></pre>
<script>
var n = 0;
function render() {
  var d = window.__PREMBLY_NATIVE_DEVICE__;
  document.getElementById('o').textContent = location.origin;
  document.getElementById('p').textContent = d ? 'YES' : 'NO';
  if (d) {
    var sc = (d.signals && d.signals.scam_signals) || {};
    document.getElementById('s').textContent = sc.is_screen_shared_or_recorded + ' / ' + sc.screen_capture_seen;
    document.getElementById('d').textContent = JSON.stringify({ deviceId: d.deviceId, deviceIdSource: d.deviceIdSource, platformDeviceId: d.platformDeviceId, platform: d.platform }, null, 1);
  }
}
window.addEventListener('prembly:native-device-update', function () { n++; document.getElementById('u').textContent = n; render(); });
setInterval(render, 500);
</script></body></html>''';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Identity KYC Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _result = 'Waiting for verification...';
  NativeDeviceData? _device;
  bool _reading = false;
  String _deviceIdAgain = '';
  WebViewController? _page;
  void Function()? _stopWatch;

  void _startVerification() {
    PremblyIdentityKyc.verify(
      context: context,
      options: IdentityKycOptions(
        firstName: 'John',
        lastName: 'Doe',
        email: 'john@example.com',
        phone: '+2348012345678',
        widgetKey: 'wdgt_44dbb67791344ca7b30644787ada3f00',
        widgetId: 'ee7c80fb-c0cc-4762-b7a7-a4045d262e74',
        metadata: {
          'transaction_id': 'txn_123',
        },
        callback: (response) {
          setState(() {
            _result = 'Result: $response';
          });
        },
      ),
    );
  }

  Future<void> _readDevice() async {
    setState(() => _reading = true);
    final device = await collectNativeDevice();
    final again = await PremblyTM.getDeviceId();
    setState(() {
      _device = device;
      _deviceIdAgain = again ?? 'null';
      _reading = false;
    });
  }

  void _openTestPage() {
    final device = _device;
    if (device == null) return;
    _stopWatch?.call();

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    controller.setNavigationDelegate(NavigationDelegate(
      onPageStarted: (_) => controller.runJavaScript(buildNativeDeviceScript(device)),
      onPageFinished: (_) {
        controller.runJavaScript(buildNativeDeviceScript(device));
        _stopWatch ??= startScreenWatch(
          (state) => controller.runJavaScript(buildScreenUpdateScript(state)),
          interval: const Duration(seconds: 1),
          alreadySeen: (device.signals['scam_signals'] as Map?)?['is_screen_shared_or_recorded'] == true,
        );
      },
    ));
    controller.loadHtmlString(_testPage, baseUrl: premblyWidgetOrigin);
    setState(() => _page = controller);
  }

  @override
  void dispose() {
    _stopWatch?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final device = _device;
    return Scaffold(
      appBar: AppBar(title: const Text('Device hand-off test')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FilledButton(
              key: const Key('read'),
              onPressed: _reading ? null : _readDevice,
              child: const Text('1. Read the device'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('open'),
              onPressed: device == null ? null : _openTestPage,
              child: const Text('2. Open the test page (widget origin)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _startVerification,
              child: const Text('Start KYC verification'),
            ),
            if (_page != null)
              Container(
                height: 230,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(border: Border.all(color: Colors.teal)),
                child: WebViewWidget(controller: _page!),
              ),
            const SizedBox(height: 12),
            SelectableText(
              _reading
                  ? 'reading…'
                  : device == null
                      ? 'Tap 1.\n$_result'
                      : 'deviceId (via PremblyTM.getDeviceId): $_deviceIdAgain\n\n'
                          '${const JsonEncoder.withIndent('  ').convert(device.toJson())}',
              style: const TextStyle(fontFamily: 'Menlo', fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
