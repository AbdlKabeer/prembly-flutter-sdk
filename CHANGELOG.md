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
