import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'identity_kyc_options.dart';

/// Mobile KYC flow aligned with
/// https://github.com/AbdlKabeer/prembly-react-native-identity-kyc
class IdentityKycWebView extends StatefulWidget {
  final IdentityKycOptions options;

  const IdentityKycWebView({Key? key, required this.options}) : super(key: key);

  @override
  State<IdentityKycWebView> createState() => _IdentityKycWebViewState();
}

class _IdentityKycWebViewState extends State<IdentityKycWebView> {
  // Same endpoint as PremblyIdentityWidget.tsx
  static const _sessionInitiateUrl =
      'https://api.prembly.com/api/v1/checker-widget/sdk/sessions/initiate/';

  WebViewController? _controller;
  bool _hasCalledBack = false;
  bool _isLoading = true;
  String? _error;

  // Mirrors RN injectedJavaScript message bridge
  static const _messageBridgeJs = '''
    (function() {
      if (window._premblyFlutterBridgeInstalled) return;
      window._premblyFlutterBridgeInstalled = true;
      window.addEventListener("message", function(event) {
        try {
          var payload = event.data;
          if (typeof payload !== "string") {
            payload = JSON.stringify(payload);
          }
          FlutterChannel.postMessage(payload);
        } catch (e) {}
      }, false);
    })();
  ''';

  void _triggerCallback(Map<String, dynamic> response) {
    if (_hasCalledBack) return;
    _hasCalledBack = true;
    widget.options.callback?.call(response);
  }

  void _closeWithResponse(Map<String, dynamic> response) {
    _triggerCallback(response);
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  void initState() {
    super.initState();
    _initializePremblyWidget();
  }

  Future<void> _initializePremblyWidget() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _hasCalledBack = false;
      _controller = null;
    });

    try {
      final sessionId = await _initiateSession();
      if (!mounted) return;
      _setupWebView(sessionId);
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      final status = message.startsWith('Network error')
          ? 'network_error'
          : 'api_error';
      setState(() {
        _isLoading = false;
        _error = message;
      });
      _triggerCallback({
        'status': status,
        'message': message,
      });
    }
  }

  Future<String> _initiateSession() async {
    final options = widget.options;
    final metadata = <String, dynamic>{
      if (options.userRef != null) 'user_id': options.userRef,
      ...?options.metadata,
    };

    final body = jsonEncode({
      'first_name': options.firstName,
      'last_name': options.lastName,
      'email': options.email,
      'phone': options.phone ?? '',
      'widget_key': options.widgetKey,
      'widget_id': options.widgetId,
      'metadata': metadata,
    });

    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(_sessionInitiateUrl));
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.write(body);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'API call failed with status: ${response.statusCode}. Response: $responseBody',
        );
      }

      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;

      // RN: responseData.data.session.session_id
      final sessionId = decoded['data']?['session']?['session_id'] ??
          decoded['data']?['session_id'];

      if (decoded['status'] == true && sessionId != null) {
        return sessionId.toString();
      }

      throw Exception(
        decoded['detail']?.toString() ??
            decoded['message']?.toString() ??
            'Failed to get widget session from API.',
      );
    } on SocketException catch (e) {
      throw Exception('Network error or data parsing error: ${e.message}');
    } on HttpException catch (e) {
      throw Exception('Network error or data parsing error: ${e.message}');
    } on FormatException catch (e) {
      throw Exception('Network error or data parsing error: ${e.message}');
    } finally {
      client.close();
    }
  }

  /// Matches PremblyIdentityWidget handleMessage event mapping.
  void _handleMessage(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _closeWithResponse({'status': 'unknown_payload', 'data': decoded});
        return;
      }

      final data = Map<String, dynamic>.from(decoded);
      final eventName = (data['event'] ?? data['status'])?.toString();

      if (eventName == null || eventName.isEmpty) {
        _closeWithResponse({'status': 'unknown_payload', 'data': data});
        return;
      }

      switch (eventName) {
        case 'closed':
          _closeWithResponse({'status': 'closed'});
          break;
        case 'error':
          _closeWithResponse({
            'status': 'error',
            'message': data['message'],
          });
          break;
        case 'verified':
        case 'success':
          _closeWithResponse({'status': 'success', 'data': data});
          break;
        default:
          debugPrint('Received unknown event from WebView: $eventName');
          _closeWithResponse({'status': eventName, 'data': data});
          break;
      }
    } catch (e) {
      debugPrint('Error decoding JSON from WebView: $e');
      _closeWithResponse({
        'status': 'error',
        'message': 'Failed to process message from WebView: $e',
      });
    }
  }

  void _setupWebView(String sessionId) {
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
      onPermissionRequest: (WebViewPermissionRequest request) {
        request.grant();
      },
    );

    // Same URL shape as RN: https://sdk-live.prembly.com/?session=${sessionId}
    final widgetUrl = Uri.parse(
      'https://sdk-live.prembly.com/?session=$sessionId',
    );

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            controller.runJavaScript(_messageBridgeJs);
          },
          onNavigationRequest: (NavigationRequest request) {
            final uri = Uri.tryParse(request.url);
            final host = uri?.host.toLowerCase() ?? '';
            final isPrembly = host.endsWith('prembly.com') ||
                host.endsWith('identitypass.com') ||
                host.endsWith('cloudfront.net') ||
                request.url == 'about:blank' ||
                request.url.startsWith('blob:');

            if (isPrembly) {
              return NavigationDecision.navigate;
            }

            // Keep completion in-app via callback instead of following dashboard redirect.
            debugPrint('Intercepted KYC redirect: ${request.url}');
            _closeWithResponse({
              'status': 'success',
              'data': {'redirect_url': request.url},
            });
            return NavigationDecision.prevent;
          },
        ),
      )
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (JavaScriptMessage message) {
          _handleMessage(message.message);
        },
      )
      ..loadRequest(widgetUrl);

    if (controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    _controller = controller;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _triggerCallback({'status': 'closed'});
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Identity Verification'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              _closeWithResponse({'status': 'closed'});
            },
          ),
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
              ElevatedButton(
                onPressed: _initializePremblyWidget,
                child: const Text('Retry'),
              ),
              TextButton(
                onPressed: () {
                  _closeWithResponse({'status': 'error_display_closed'});
                },
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      );
    }

    if (_controller == null) {
      return const SizedBox.shrink();
    }

    return WebViewWidget(controller: _controller!);
  }
}
