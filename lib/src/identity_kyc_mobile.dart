import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
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

  // Mirrors RN injectedJavaScript message bridge, but only forwards KYC events
  static const _messageBridgeJs = '''
    (function() {
      if (window._premblyFlutterBridgeInstalled) return;
      window._premblyFlutterBridgeInstalled = true;
      window.addEventListener("message", function(event) {
        try {
          var data = event.data;
          if (typeof data === "string") {
            try { data = JSON.parse(data); } catch (e) { return; }
          }
          if (!data || typeof data !== "object") return;
          var eventName = data.event || data.status;
          if (!eventName) return;
          FlutterChannel.postMessage(JSON.stringify(data));
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

  Future<bool> _ensureMediaPermissions() async {
    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    final cameraGranted = statuses[Permission.camera]?.isGranted ?? false;
    final micGranted = statuses[Permission.microphone]?.isGranted ?? false;

    if (cameraGranted) {
      return true;
    }

    // Mic is preferred for liveness, but camera is required to proceed.
    if (statuses[Permission.camera]?.isPermanentlyDenied ?? false) {
      throw Exception(
        'Camera permission is required for verification. Enable it in Settings.',
      );
    }

    throw Exception(
      'Camera permission is required for verification.${micGranted ? '' : ' Microphone permission is also recommended.'}',
    );
  }

  Future<void> _initializePremblyWidget() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _hasCalledBack = false;
      _controller = null;
    });

    try {
      await _ensureMediaPermissions();
      final sessionId = await _initiateSession();
      if (!mounted) return;
      await _setupWebView(sessionId);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      String status = 'api_error';
      if (message.startsWith('Network error')) {
        status = 'network_error';
      } else if (message.toLowerCase().contains('camera permission')) {
        status = 'error';
      }
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
      final payload = utf8.encode(body);

      // Explicit length + bytes so the server receives the JSON body
      // (string write alone can arrive empty on some platforms).
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      request.contentLength = payload.length;
      request.add(payload);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_formatApiError(response.statusCode, decoded, responseBody));
      }

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

  String _formatApiError(
    int statusCode,
    Map<String, dynamic> decoded,
    String raw,
  ) {
    final message = decoded['message']?.toString();
    final errors = decoded['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final details = errors.entries.map((entry) {
        final value = entry.value;
        final text = value is List ? value.join(', ') : value.toString();
        return '${entry.key}: $text';
      }).join('; ');
      return 'API call failed with status: $statusCode. ${message ?? ''} $details'
          .trim();
    }
    return 'API call failed with status: $statusCode. ${message ?? raw}';
  }

  /// Matches PremblyIdentityWidget handleMessage event mapping.
  void _handleMessage(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final data = Map<String, dynamic>.from(decoded);
      final eventName = (data['event'] ?? data['status'])?.toString();

      if (eventName == null || eventName.isEmpty) return;

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
          // Forward unknown KYC events without closing the flow early.
          debugPrint('Received unknown event from WebView: $eventName');
          widget.options.callback?.call({'status': eventName, 'data': data});
          break;
      }
    } catch (e) {
      debugPrint('Error decoding JSON from WebView: $e');
    }
  }

  Future<void> _setupWebView(String sessionId) async {
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
        // Grant camera/mic requests coming from the hosted KYC page.
        request.grant();
      },
    );

    // Same URL shape as RN: https://sdk-live.prembly.com/?session=${sessionId}
    final widgetUrl = Uri.parse(
      'https://sdk-live.prembly.com/?session=$sessionId',
    );

    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setBackgroundColor(const Color(0x00000000));
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (url) {
          controller.runJavaScript(_messageBridgeJs);
        },
        onNavigationRequest: (NavigationRequest request) {
          final url = request.url;
          final uri = Uri.tryParse(url);
          final scheme = uri?.scheme.toLowerCase() ?? '';
          final host = uri?.host.toLowerCase() ?? '';

          // Allow WebView internals and Prembly hosts. Do NOT treat
          // about:srcdoc / about:blank as completion redirects.
          final isInternal = scheme.isEmpty ||
              scheme == 'about' ||
              scheme == 'blob' ||
              scheme == 'data' ||
              url.startsWith('about:') ||
              url.startsWith('blob:');
          final isPrembly = host.endsWith('prembly.com') ||
              host.endsWith('identitypass.com') ||
              host.endsWith('cloudfront.net');

          if (isInternal || isPrembly) {
            return NavigationDecision.navigate;
          }

          // Only intercept real http(s) navigations away from Prembly.
          if (scheme == 'http' || scheme == 'https') {
            debugPrint('Intercepted KYC redirect: $url');
            _closeWithResponse({
              'status': 'success',
              'data': {'redirect_url': url},
            });
            return NavigationDecision.prevent;
          }

          return NavigationDecision.navigate;
        },
      ),
    );
    await controller.addJavaScriptChannel(
      'FlutterChannel',
      onMessageReceived: (JavaScriptMessage message) {
        _handleMessage(message.message);
      },
    );

    if (controller.platform is AndroidWebViewController) {
      final androidController = controller.platform as AndroidWebViewController;
      AndroidWebViewController.enableDebugging(true);
      await androidController.setMediaPlaybackRequiresUserGesture(false);
      await androidController.setOnPlatformPermissionRequest(
        (PlatformWebViewPermissionRequest request) {
          request.grant();
        },
      );
    }

    await controller.loadRequest(widgetUrl);
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
      final isCameraError = _error!.toLowerCase().contains('camera permission');
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
              if (isCameraError)
                TextButton(
                  onPressed: openAppSettings,
                  child: const Text('Open Settings'),
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
