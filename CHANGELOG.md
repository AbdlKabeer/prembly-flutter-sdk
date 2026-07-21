## 0.0.5

* Keep KYC completion in-app via callback handling, matching [prembly-react-native-identity-kyc](https://github.com/AbdlKabeer/prembly-react-native-identity-kyc).
* Mobile initiates sessions via `api.prembly.com`, loads `sdk-live.prembly.com/?session=...`, and bridges WebView `postMessage` events into `callback`.
* Callback statuses aligned with RN: `success`, `closed`, `error`, `api_error`, `network_error`, `error_display_closed`.
* Intercept dashboard redirect navigations so completion stays in-app.
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
