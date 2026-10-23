import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'native_device.dart';
import 'screen_watch.dart';
import 'workflow_core.dart';

/// Runs one of your workflows in the app: creates the session with the public key, opens it in a
/// WebView and gives the page the phone's real device ID and details.
class WorkflowWebView extends StatefulWidget {
  final WorkflowOptions options;

  /// Creates the workflow session. Tests replace it; the default calls the Prembly API.
  @visibleForTesting
  final Future<WorkflowSessionInfo> Function(WorkflowOptions options)? sessionCreator;

  /// How often the screen-recording flag is read while the workflow is open.
  @visibleForTesting
  final Duration screenWatchEvery;

  const WorkflowWebView({
    Key? key,
    required this.options,
    this.sessionCreator,
    this.screenWatchEvery = screenWatchInterval,
  }) : super(key: key);

  @override
  State<WorkflowWebView> createState() => _WorkflowWebViewState();
}

class _WorkflowWebViewState extends State<WorkflowWebView> {
  WebViewController? _controller;
  WorkflowSessionInfo? _session;
  NativeDeviceData? _nativeDevice;
  void Function()? _stopScreenWatch;
  String? _lastEvent;
  bool _hasEnded = false;
  bool _isLoading = true;
  String? _error;

  // Hands every message from the hosted app to Dart, which keeps only the workflow's own events.
  static const _messageBridgeJs = '''
    (function() {
      if (window._premblyWorkflowBridgeInstalled) return;
      window._premblyWorkflowBridgeInstalled = true;
      window.addEventListener("message", function(event) {
        try {
          var data = event.data;
          if (typeof data !== "string") data = JSON.stringify(data);
          FlutterChannel.postMessage(data);
        } catch (e) {}
      }, false);
    })();
  ''';

  void _finish(WorkflowResult result) {
    if (_hasEnded) return;
    _hasEnded = true;
    widget.options.callback(result);
  }

  void _closeWith(WorkflowResult result) {
    _finish(result);
    if (mounted && Navigator.canPop(context)) Navigator.pop(context);
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _stopScreenWatch?.call();
    _stopScreenWatch = null;
    super.dispose();
  }

  /// The origin the phone's data may go to: that of this session's link.
  String get _origin => originOf(_session?.link ?? '');

  void _injectNativeDevice(WebViewController controller) {
    final device = _nativeDevice;
    if (device == null) return;
    controller.runJavaScript(buildNativeDeviceScript(device, origin: _origin));
  }

  /// While the workflow is open, keep asking the phone whether the screen is being recorded or
  /// shared and tell the page, including a recording that started and stopped.
  void _startWatchingScreen(WebViewController controller) {
    final device = _nativeDevice;
    if (device == null || _stopScreenWatch != null) return;
    final scam = device.signals['scam_signals'];
    final alreadySeen = scam is Map && scam['is_screen_shared_or_recorded'] == true;
    _stopScreenWatch = startScreenWatch(
      (state) => controller.runJavaScript(buildScreenUpdateScript(state)),
      interval: widget.screenWatchEvery,
      alreadySeen: alreadySeen,
    );
  }

  Future<void> _start() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _hasEnded = false;
      _lastEvent = null;
      _controller = null;
      _session = null;
      _nativeDevice = null;
    });
    _stopScreenWatch?.call();
    _stopScreenWatch = null;

    // Read the phone while the session is created. It never fails and is time-limited.
    final devicePromise = widget.options.collectDeviceData
        ? collectNativeDevice()
        : Future<NativeDeviceData?>.value(null);

    try {
      final created = await (widget.sessionCreator?.call(widget.options) ??
          createWorkflowSession(
            widget.options,
            platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
          ));
      _nativeDevice = await devicePromise;
      if (!mounted) return;
      final hosted = widget.options.hostedUrl;
      _session = hosted == null
          ? created
          : WorkflowSessionInfo(
              sessionId: created.sessionId,
              link: withSession(hosted, created.sessionId),
            );
      await _setupWebView(_session!.link);
      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      final error = e is WorkflowError ? e : WorkflowError('network_error', e.toString());
      setState(() {
        _isLoading = false;
        _error = error.message;
      });
      _finish(WorkflowResult(
        status: 'failed',
        errorCode: error.code,
        errorMessage: error.message,
      ));
    }
  }

  void _handleMessage(String raw) {
    final event = parseWorkflowMessage(raw);
    // Only this session's events count; a message about another session is ignored.
    if (event == null || event.sessionId != _session?.sessionId) return;
    _lastEvent = event.type;
    widget.options.onEvent?.call(event);
    if (isWorkflowEndState(event.type)) {
      _closeWith(WorkflowResult(status: event.type, sessionId: event.sessionId));
    }
  }

  /// The person closes the flow. Before an end state that is a cancel, and `lastEvent` says
  /// whether the checks were still running (`processing`).
  void _close() {
    final session = _session;
    _closeWith(session == null
        ? const WorkflowResult(status: 'cancelled')
        : WorkflowResult(
            status: 'cancelled',
            sessionId: session.sessionId,
            lastEvent: _lastEvent,
          ));
  }

  /// Camera and microphone for a step that needs them. Asked when the page asks, not before.
  Future<bool> _allowResources(Iterable<WebViewPermissionResourceType> types) async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    final wanted = <Permission>[
      if (types.contains(WebViewPermissionResourceType.camera)) Permission.camera,
      if (types.contains(WebViewPermissionResourceType.microphone)) Permission.microphone,
    ];
    if (wanted.isEmpty) return true;
    final statuses = await wanted.request();
    return statuses.values.every((s) => s.isGranted);
  }

  Future<void> _setupWebView(String link) async {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(
      params,
      onPermissionRequest: (WebViewPermissionRequest request) async {
        if (await _allowResources(request.types)) {
          await request.grant();
        } else {
          await request.deny();
        }
      },
    );

    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setBackgroundColor(const Color(0x00000000));
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (url) {
          controller.runJavaScript(_messageBridgeJs);
          _injectNativeDevice(controller);
        },
        onPageFinished: (url) {
          controller.runJavaScript(_messageBridgeJs);
          _injectNativeDevice(controller);
          _startWatchingScreen(controller);
        },
      ),
    );
    await controller.addJavaScriptChannel(
      'FlutterChannel',
      onMessageReceived: (JavaScriptMessage message) => _handleMessage(message.message),
    );

    if (controller.platform is AndroidWebViewController) {
      await (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    await controller.loadRequest(Uri.parse(link));
    _controller = controller;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        // Backing out is a cancel, unless the flow already ended.
        _finish(WorkflowResult(
          status: 'cancelled',
          sessionId: _session?.sessionId,
          lastEvent: _lastEvent,
        ));
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Verification'),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: _close),
        ),
        body: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Initializing secure session...'),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Error: $_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red, fontSize: 16),
              ),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _start, child: const Text('Retry')),
              TextButton(onPressed: _close, child: const Text('Cancel')),
            ],
          ),
        ),
      );
    }
    if (_controller == null) return const SizedBox.shrink();
    return WebViewWidget(controller: _controller!);
  }
}
