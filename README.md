# Prembly Identity KYC Flutter SDK

A powerful and seamless Flutter SDK for integrating Prembly's Identity KYC verification into your iOS, Android, and Web applications.

## Features
- 🚀 **Cross-Platform**: Works natively on iOS, Android, and Flutter Web.
- 🔒 **Secure**: Direct integration with Prembly's secure verification infrastructure.
- ⚡ **Easy to Use**: Launch the KYC flow with just a few lines of code.

## Getting Started

Add the package to your `pubspec.yaml`:
```yaml
dependencies:
  prembly_identity_kyc: ^0.0.5
```

### Platform Configuration

Since the Identity KYC flow requires the user to take a selfie and scan ID documents, you must add camera permissions to your application.

#### iOS
Add the following keys to your `ios/Runner/Info.plist` file:
```xml
<key>NSCameraUsageDescription</key>
<string>This app requires access to the camera to verify your identity.</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app requires access to the microphone for liveness checks.</string>
```

#### Android
Add the following permissions to your `android/app/src/main/AndroidManifest.xml` just above the `<application>` tag:
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.INTERNET" />
```
*Note: Ensure your `minSdkVersion` in `android/app/build.gradle` is at least `19`.*

#### Web
No extra configuration is required. The browser will automatically request camera permissions from the user when the flow starts.

## Usage

Import the package and call `PremblyIdentityKyc.verify` passing the necessary options.

```dart
import 'package:prembly_identity_kyc/prembly_identity_kyc.dart';

void startVerification(BuildContext context) {
  PremblyIdentityKyc.verify(
    context: context,
    options: IdentityKycOptions(
      widgetKey: 'your_widget_key_here',
      widgetId: 'your_widget_id_here',
      firstName: 'John',
      lastName: 'Doe',
      email: 'john@example.com',
      phone: '+2348012345678',
      isTest: true,
      metadata: {
        'transaction_id': 'txn_123',
      },
      callback: (response) {
        print('Verification Result: $response');
        // Typical statuses (same as React Native SDK):
        // success | closed | error | api_error | network_error | error_display_closed
      },
    ),
  );
}
```

### Staying in-app (callback vs redirect)

There is no special redirect URL that keeps KYC inside a mobile app. Use the `callback` option instead — the same approach as the [React Native SDK](https://github.com/AbdlKabeer/prembly-react-native-identity-kyc).

The Flutter SDK initiates a session, loads the widget in an in-app WebView, and forwards widget `postMessage` events to your `callback`. Dashboard redirect URLs are for browser flows and are intercepted on mobile so they do not take users out of the app.

## Additional information
For more information about Prembly and to get your API keys, visit [prembly.com](https://prembly.com).
