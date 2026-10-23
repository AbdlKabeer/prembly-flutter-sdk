# Prembly Identity KYC Flutter SDK

One Flutter package for two Prembly products, both reading the phone's real device ID:

- **Identity KYC widget** (`PremblyIdentityKyc.verify`): opens the verification flow in your app. iOS, Android and Web.
- **Transaction Monitoring** (`PremblyTM`): creates a short-lived device session you pass to your backend when you screen a transaction. iOS and Android.

## Features
- 🚀 **Cross-Platform**: Works natively on iOS, Android, and Flutter Web.
- 🔒 **Secure**: Direct integration with Prembly's secure verification infrastructure.
- ⚡ **Easy to Use**: Launch the KYC flow with just a few lines of code.

## Getting Started

Add the package to your `pubspec.yaml`:
```yaml
dependencies:
  prembly_identity_kyc: ^0.1.0
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

### Options

`IdentityKycOptions` takes `widgetKey`, `widgetId`, `firstName`, `lastName`, `email` (required), and `phone`, `userRef`, `isTest`, `metadata`, `callback`, and:

| Option | Default | |
|---|---|---|
| `collectDeviceData` | `true` | Read the phone's own device ID and details and give them to the widget. Turn it off to use only what the web page can see. Mobile only. |

### What the widget does with the device

While the verification session is created, the SDK reads the phone and gives the result to the widget page. The widget then reports the phone's real device ID instead of a guess made from the browser, which two identical phones would share.

- It never shows a permission prompt, and never reads location.
- The data goes only to the Prembly widget page (`https://sdk-live.prembly.com`), never in a URL.
- If the phone cannot be read, the widget carries on with what the web page can see.
- While the widget is open the SDK checks every 2 seconds whether the screen is being recorded or shared and tells the widget, including a recording that started and stopped.

### Staying in-app (callback vs redirect)

There is no special redirect URL that keeps KYC inside a mobile app. Use the `callback` option instead — the same approach as the [React Native SDK](https://github.com/AbdlKabeer/prembly-react-native-identity-kyc).

The Flutter SDK initiates a session, loads the widget in an in-app WebView, and forwards widget `postMessage` events to your `callback`. Dashboard redirect URLs are for browser flows and are intercepted on mobile so they do not take users out of the app.

## Transaction Monitoring

```dart
import 'package:prembly_identity_kyc/prembly_identity_kyc.dart';

// 1. Once, early (for example when the app starts). Use test_pk_... while developing.
PremblyTM.init(publishableKey: 'test_pk_xxxxxxxx');

// 2. When the customer signs in (and null when they sign out).
PremblyTM.identify('CUST-123');

// 3. Before a sensitive action: sign-in, payment, adding a beneficiary.
final session = await PremblyTM.getDeviceSession();

// 4. Send it with your normal request. deviceSessionId is null if no session could be created:
//    send the request anyway and your backend screens without it.
await http.post(
  Uri.parse('https://your-backend.example.com/payments'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({'amount': amount, 'to': to, 'deviceSessionId': session.deviceSessionId}),
);
```

Your backend then screens the transaction with your **secret** key and passes `device_session_id`. Never put a secret key (`live_sk_…` / `test_sk_…`) in an app: `init` throws if you try.

| Call | What it does |
|---|---|
| `PremblyTM.init(publishableKey:, baseUrl:, location:, timeout:, debug:)` | Set up once. Throws if the key is not a public key. |
| `PremblyTM.identify(customerId)` | Tell the SDK who is using the app (`null` on sign-out). |
| `PremblyTM.getDeviceSession(forceRefresh:)` | Returns a `DeviceSession` with `deviceSessionId`, `deviceId`, `isKnownDevice`, `expiresAt`, `error`. Never throws. |
| `PremblyTM.setLocationEnabled(bool)` | Turn location on or off, for example when consent changes. |
| `PremblyTM.getSignalsPreview()` | The signals that would be sent, without sending anything. |
| `PremblyTM.getDeviceId()` | The app-scoped device ID, or `null`. |
| `PremblyTM.reset()` | Forget the customer and the cached session. |

A session is reused until shortly before it expires (about 15 minutes). If it cannot be created, `deviceSessionId` is `null` and `error` is one of the `SessionError` values: `not_initialised`, `timeout`, `network_error`, `unauthorised`, `rate_limited`, `rejected`, `server_error` or `native_error`. **It fails open**: send the payment anyway.

## What is collected

| Section | Signals |
|---|---|
| `device` | Type, model, manufacturer, OS and version, app version and build, language, timezone, memory, CPU cores, screen size and density. Android also: brand, SDK level, security patch. |
| `integrity` | Rooted or jailbroken, emulator or simulator, debugger attached, screen lock set. Android also: developer options, USB debugging. |
| `network` | Connection type, VPN active, proxy configured |
| `scam_signals` | Screen shared or recorded; on Android, a known remote-access app's accessibility service enabled, and whether one is installed |
| `location` | Latitude, longitude, accuracy and whether it is mocked. **Only for Transaction Monitoring, and only when you turn it on**, and the app already holds the permission. |

**The device ID.** `deviceId` is a random ID the SDK creates once. On iOS it is kept in the Keychain, marked "this device only", so it survives a reinstall and is not copied to another device by a backup. On Android it is kept in a file the OS excludes from backup, so a reinstall gets a new one. `platformDeviceId` is the ID the OS keeps for the app: `identifierForVendor` on iOS and `ANDROID_ID` on Android.

Not collected: advertising ID, IMEI, MAC address, serial number, contacts, messages, clipboard, or a list of installed apps (only a short fixed list of remote-access and root-manager packages is checked).

## Permissions and privacy

- The SDK **never shows a permission prompt** for any of this.
- **Android** adds two normal permissions, neither of which prompts: `ACCESS_NETWORK_STATE` and `DETECT_SCREEN_RECORDING` (Android 15 and later). The manifest also lists a short, fixed set of packages with `<queries>` (remote-access apps and root managers). It does not use `QUERY_ALL_PACKAGES`; Google Play asks you to justify package visibility, and the reason is fraud prevention.
- Declare the data in your App Store privacy details and Google Play data-safety form: device identifiers, device and security information, and optionally location, used for fraud prevention.
- The iOS plugin needs iOS 13 or later. Android needs API 24 or later.

## Limits to know about

- Signals the app reports can be faked by a modified app. Treat them as evidence for scoring and review. Platform attestation (Play Integrity, App Attest) is not in this version.
- Root, jailbreak and emulator detection is best effort. iOS detects the Apple Simulator only.
- iOS cannot see which other apps are running, so `remote_access_app_running` is always `false` there.
- Screen recording: iOS reports recording, mirroring and AirPlay. Android 15 and later reports recording through the system. Older Android only sees a cast or mirrored display.
- A simulator or emulator reports its host machine's memory and CPU cores.
- On Web there is no native side: the widget uses what the browser can see, and `PremblyTM` returns a `native_error`.

## Additional information
For more information about Prembly and to get your API keys, visit [prembly.com](https://prembly.com).
