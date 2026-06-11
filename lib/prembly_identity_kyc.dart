library prembly_identity_kyc;

import 'package:flutter/material.dart';
import 'src/identity_kyc_options.dart';

import 'src/identity_kyc_stub.dart'
    if (dart.library.io) 'src/identity_kyc_mobile.dart'
    if (dart.library.html) 'src/identity_kyc_web.dart';

export 'src/identity_kyc_options.dart';

class PremblyIdentityKyc {
  /// Launches the Identity KYC flow in a full screen dialog/route.
  static void verify({
    required BuildContext context,
    required IdentityKycOptions options,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => IdentityKycWebView(options: options),
        fullscreenDialog: true,
      ),
    );
  }
}
