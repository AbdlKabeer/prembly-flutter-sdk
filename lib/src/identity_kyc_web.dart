import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'identity_kyc_options.dart';

class IdentityKycWebView extends StatefulWidget {
  final IdentityKycOptions options;

  const IdentityKycWebView({Key? key, required this.options}) : super(key: key);

  @override
  State<IdentityKycWebView> createState() => _IdentityKycWebViewState();
}

class _IdentityKycWebViewState extends State<IdentityKycWebView> {
  bool _isLoading = true;
  html.EventListener? _listener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initWebWidget();
    });
  }

  void _initWebWidget() {
    final scriptId = 'prembly-identity-kyc-script';
    final existingScript = html.document.getElementById(scriptId) as html.ScriptElement?;
    
    if (existingScript == null) {
      final script = html.ScriptElement()
        ..id = scriptId
        ..src = 'https://js.prembly.com/v1/inline/widget-v3.js'
        ..async = true;
        
      script.onLoad.listen((_) {
        debugPrint('Prembly script loaded, waiting 500ms before launch...');
        Future.delayed(const Duration(milliseconds: 500), () {
          _launchWidget();
        });
      });
      
      script.onError.listen((_) {
        debugPrint('Error loading Prembly script');
        if (mounted) {
          setState(() { _isLoading = false; });
        }
      });
      html.document.head!.append(script);
    } else {
      // Small delay to ensure any previous widget cleanup finished
      Future.delayed(const Duration(milliseconds: 300), () {
        _launchWidget();
      });
    }
  }

  void _launchWidget() {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });

    final optionsJson = jsonEncode(widget.options.toJson());
    
    _listener = (html.Event e) {
       final ce = e as html.CustomEvent;
       try {
         // Some JS interop environments pass detail as JSON string
         final detailStr = ce.detail.toString();
         final map = jsonDecode(detailStr);
         widget.options.callback(map);
         if (mounted && Navigator.canPop(context)) {
            Navigator.pop(context);
         }
       } catch(err) {
         debugPrint('Error parsing callback: $err');
       }
    };
    
    html.window.addEventListener('prembly_kyc_callback', _listener);

    final inlineScriptId = 'prembly-inline-trigger';
    html.document.getElementById(inlineScriptId)?.remove();

    final inlineScript = html.ScriptElement()
      ..id = inlineScriptId
      ..text = '''
      (function() {
         var opts = $optionsJson;
         opts.callback = function(res) {
           var ev = new CustomEvent('prembly_kyc_callback', { detail: JSON.stringify(res) });
           window.dispatchEvent(ev);
         };
         
         // Clean up any existing widget DOM elements before launching again
         var existingWidget = document.getElementById('identity-pay-kyc-widget') || document.querySelector('.identity-pay-kyc-widget-container');
         if (existingWidget) {
            console.log("Flutter: Removing stale widget DOM");
            existingWidget.remove();
         }

         console.log("Flutter: Checking window.IdentityKYC...", window.IdentityKYC);
         if (window.IdentityKYC && typeof window.IdentityKYC.verify === 'function') {
           console.log("Flutter: Calling IdentityKYC.verify() with options:", opts);
           window.IdentityKYC.verify(opts);
         } else {
           console.error("Flutter: IdentityKYC script not loaded properly! window.IdentityKYC is: ", window.IdentityKYC);
         }
      })();
      ''';

    html.document.body!.append(inlineScript);
  }

  @override
  void dispose() {
    if (_listener != null) {
      html.window.removeEventListener('prembly_kyc_callback', _listener);
    }
    // Clean up DOM so next launch is fresh
    final inlineScript = html.document.getElementById('prembly-inline-trigger');
    inlineScript?.remove();
    
    // Attempt to remove Prembly's DOM elements to prevent them from blocking the next launch
    try {
      html.document.querySelectorAll('iframe[src*="prembly"], iframe[src*="identitypass"]').forEach((el) => el.remove());
      html.document.getElementById('identity-pay-kyc-widget')?.remove();
    } catch(e) {
      debugPrint('Cleanup error: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Identity Verification'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: _isLoading 
            ? const CircularProgressIndicator() 
            : const Text('Please complete the verification process in the dialog overlay...'),
      ),
    );
  }
}


