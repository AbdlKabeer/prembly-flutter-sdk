library prembly_identity_kyc;

import 'package:flutter/material.dart';
import 'src/identity_kyc_options.dart';
import 'src/workflow_core.dart';

import 'src/identity_kyc_stub.dart'
    if (dart.library.io) 'src/identity_kyc_mobile.dart'
    if (dart.library.html) 'src/identity_kyc_web.dart';

export 'src/identity_kyc_options.dart';
export 'src/prembly_tm.dart'
    show PremblyTM, PremblyTMClient, DeviceSession, SessionError;
export 'src/native_device.dart' show premblySdkVersion;
export 'src/workflow_core.dart'
    show WorkflowCustomer, WorkflowEvent, WorkflowOptions, WorkflowResult;

import 'src/workflow_stub.dart'
    if (dart.library.io) 'src/workflow_mobile.dart';

/// Runs one of your compliance workflows in the app.
class PremblyWorkflow {
  /// Starts the workflow in a full screen route. Creates the session with the public key, opens
  /// it, and calls `options.callback` once when it ends: `completed`, `failed`, `manual_review`,
  /// `expired` or `cancelled` (or `failed` with an error code if it could not start).
  static void start({
    required BuildContext context,
    required WorkflowOptions options,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => WorkflowWebView(options: options),
        fullscreenDialog: true,
      ),
    );
  }
}

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
