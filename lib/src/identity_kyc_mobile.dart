import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'identity_kyc_options.dart';

class IdentityKycWebView extends StatefulWidget {
  final IdentityKycOptions options;

  const IdentityKycWebView({Key? key, required this.options}) : super(key: key);

  @override
  State<IdentityKycWebView> createState() => _IdentityKycWebViewState();
}

class _IdentityKycWebViewState extends State<IdentityKycWebView> {
  late final WebViewController _controller;

  bool _hasCalledBack = false;

  void _triggerCallback(Map<String, dynamic> response) {
    if (!_hasCalledBack && widget.options.callback != null) {
      _hasCalledBack = true;
      widget.options.callback!(response);
    }
  }

  @override
  void initState() {
    super.initState();
    
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final WebViewController controller =
        WebViewController.fromPlatformCreationParams(
      params,
      onPermissionRequest: (WebViewPermissionRequest request) {
        request.grant();
      },
    );

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (JavaScriptMessage message) {
          try {
            final Map<String, dynamic> response = jsonDecode(message.message);
            _triggerCallback(response);
            if (mounted && Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          } catch (e) {
            debugPrint('Error parsing KYC callback: $e');
          }
        },
      )
      ..loadHtmlString(_buildHtmlString(), baseUrl: 'https://js.prembly.com');

    if (controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    _controller = controller;
  }

  String _buildHtmlString() {
    final optionsJson = jsonEncode(widget.options.toJson());
    
    return '''
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Identity KYC</title>
      <script src="https://js.prembly.com/v1/inline/widget-v3.js"></script>
      <style>
        body { margin: 0; padding: 0; background: transparent; }
        #identity-container { width: 100vw; height: 100vh; }
      </style>
    </head>
    <body>
      <div id="identity-container"></div>
      <script>
        function invokeKYC() {
          const options = $optionsJson;
          
          if (${widget.options.callback != null}) {
             options.callback = function(response) {
                FlutterChannel.postMessage(JSON.stringify(response));
             };
          }
          
          // Fallback interval to detect if the widget closes itself without emitting an event
          var checkInterval = setInterval(function() {
             var iframe = document.getElementById('identity-frame-component');
             var container = document.getElementById('identity-frame-container');
             var isHidden = iframe && (iframe.style.display === 'none' || iframe.style.visibility === 'hidden');
             
             if (window._premblyIframeSeen && ((!container && !iframe) || isHidden)) {
                clearInterval(checkInterval);
                if (typeof options.callback === 'function') {
                   options.callback({ status: "cancelled", message: "Verification closed" });
                }
             } else if (iframe && !isHidden) {
                window._premblyIframeSeen = true;
             }
          }, 1000);
          
          // Verify
          if (window.IdentityKYC && typeof window.IdentityKYC.verify === 'function') {
            window.IdentityKYC.verify(options);
          } else {
             FlutterChannel.postMessage(JSON.stringify({ error: "SDK script not loaded" }));
          }
        }

        // Wait a slight moment for script to attach if needed, or invoke directly onload
        window.onload = function() {
          setTimeout(invokeKYC, 100);
        };
      </script>
    </body>
    </html>
    ''';
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _triggerCallback({"status": "cancelled", "message": "User closed the verification window"});
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Identity Verification'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              _triggerCallback({"status": "cancelled", "message": "User closed the verification window"});
              Navigator.pop(context);
            },
          ),
        ),
        body: SafeArea(
          child: WebViewWidget(controller: _controller),
        ),
      ),
    );
  }
}
