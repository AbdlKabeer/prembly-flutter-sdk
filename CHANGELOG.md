## 0.1.0

* The package now serves both the Identity KYC widget and Transaction Monitoring, and reads the phone's real device ID.
* New native layer (Android and iOS) behind a `com.prembly.identity_kyc/device` method channel. It reads the app-scoped device ID (Keychain on iOS, a no-backup file on Android), the ID the OS keeps for the app (`identifierForVendor` / `ANDROID_ID`), device info (memory, CPU cores, screen, and on Android brand, SDK level and security patch), and the integrity, network and scam signals. It never asks for a permission.
* The widget gives this to the verification page before it submits, so a check sees the real device and not a guess from the browser (a hash of user agent, platform and screen size, which two identical phones share). Only the Prembly widget origin receives it. If the phone cannot be read, the widget carries on with what the web page can see.
* New `IdentityKycOptions.collectDeviceData` (default `true`) to switch it off.
* Screen recording is detected on iOS and on Android 15 and later (`DETECT_SCREEN_RECORDING`, a normal permission), and watched every 2 seconds while the widget is open. A recording that starts and stops mid-session is still reported (`screen_capture_seen`).
* New `PremblyTM`: `init`, `identify`, `getDeviceSession`, `getSignalsPreview`, `getDeviceId`, `setLocationEnabled`, `reset`. Same wire format and stored IDs as `prembly-tm-native` and the React Native SDK.
* Adds the `http` dependency.
* Requires a native rebuild (`pod install` on iOS). Web is unchanged.

## 0.0.6

* Allow `permission_handler` 11.x–13.x so apps already on newer versions can resolve `prembly_identity_kyc`.

## 0.0.5

* Keep KYC completion in-app via callback handling, matching [prembly-react-native-identity-kyc](https://github.com/AbdlKabeer/prembly-react-native-identity-kyc).
* Mobile initiates sessions via `api.prembly.com`, loads `sdk-live.prembly.com/?session=...`, and bridges WebView `postMessage` events into `callback`.
* Callback statuses aligned with RN: `success`, `closed`, `error`, `api_error`, `network_error`, `error_display_closed`.
* Intercept dashboard redirect navigations so completion stays in-app.
* Request camera/microphone permissions before loading the WebView so KYC camera init does not hang.
* Web always attaches a JS callback bridge so the hosted widget prefers callback over redirect.

## 0.0.4

* Fixed an issue where Android WebViews were not correctly handling the camera permission request, which was causing the camera to not open even after system-level permission was granted.

## 0.0.3

* Made `callback` parameter optional in `IdentityKycOptions`.
* If `callback` is omitted, the SDK will automatically follow the dashboard's redirect URL after KYC completion instead of closing.

## 0.0.2

* Fixed an issue where the camera permissions were not automatically granted on Android WebViews.
* Added secure context for the WebView HTML loading to ensure camera API access.

## 0.0.1

* Initial release of the Prembly Identity KYC SDK.
* Support for iOS, Android, and Web platforms.
