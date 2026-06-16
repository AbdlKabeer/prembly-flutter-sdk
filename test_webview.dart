import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  var controller = WebViewController();
  controller.setOnPlatformPermissionRequest((request) {
    request.grant();
  });
}
