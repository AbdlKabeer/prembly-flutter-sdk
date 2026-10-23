import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// A WebView that records what the widget does to it, so the widget's own code can be tested
/// without a real browser.
class FakeWebViewPlatform extends WebViewPlatform {
  FakeWebViewController? controller;
  FakeNavigationDelegate? delegate;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) =>
      controller = FakeWebViewController(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) =>
      delegate = FakeNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) =>
      FakeWebViewWidget(params);
}

class FakeWebViewController extends PlatformWebViewController {
  FakeWebViewController(super.params) : super.implementation();

  /// Every script the widget ran in the page, in order.
  final List<String> scripts = [];
  final List<Uri> loaded = [];
  final List<String> channels = [];

  /// What the page can post to, by channel name, so a test can send the widget a message.
  final Map<String, void Function(JavaScriptMessage)> channelHandlers = {};

  @override
  Future<void> runJavaScript(String javaScript) async => scripts.add(javaScript);

  @override
  Future<void> loadRequest(LoadRequestParams params) async => loaded.add(params.uri);

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams javaScriptChannelParams) async {
    channels.add(javaScriptChannelParams.name);
    channelHandlers[javaScriptChannelParams.name] = javaScriptChannelParams.onMessageReceived;
  }

  @override
  Future<void> setPlatformNavigationDelegate(PlatformNavigationDelegate handler) async {}

  @override
  Future<void> setOnPlatformPermissionRequest(
    void Function(PlatformWebViewPermissionRequest request) onPermissionRequest,
  ) async {}
}

class FakeNavigationDelegate extends PlatformNavigationDelegate {
  FakeNavigationDelegate(super.params) : super.implementation();

  PageEventCallback? onStarted;
  PageEventCallback? onFinished;
  NavigationRequestCallback? onRequest;

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async =>
      onStarted = onPageStarted;

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async =>
      onFinished = onPageFinished;

  @override
  Future<void> setOnNavigationRequest(NavigationRequestCallback onNavigationRequest) async =>
      onRequest = onNavigationRequest;
}

class FakeWebViewWidget extends PlatformWebViewWidget {
  FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox(key: Key('fake-webview'));
}
