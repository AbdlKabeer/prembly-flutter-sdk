import 'dart:async';
import 'dart:convert';


import 'native_device.dart';

/// How often the widget asks the phone whether the screen is being recorded or shared.
const Duration screenWatchInterval = Duration(seconds: 2);

class ScreenCaptureState {
  const ScreenCaptureState({required this.current, required this.seen});

  /// Being recorded, cast or mirrored right now.
  final bool current;

  /// Was recorded, cast or mirrored at any point since the verification opened. Never goes back
  /// to false.
  final bool seen;

  @override
  bool operator ==(Object other) =>
      other is ScreenCaptureState && other.current == current && other.seen == seen;

  @override
  int get hashCode => Object.hash(current, seen);

  @override
  String toString() => 'ScreenCaptureState(current: $current, seen: $seen)';
}

/// Whether the screen is being recorded or shared right now. `null` means it could not be read,
/// which is not the same as "no": the caller must not treat it as safe.
Future<bool?> readScreenCapture() async {
  try {
    final text = await premblyDeviceChannel.invokeMethod<String>('checkScreenCapture');
    if (text == null) return null;
    final flag = (jsonDecode(text) as Map)['is_screen_shared_or_recorded'];
    return flag is bool ? flag : null;
  } catch (_) {
    return null;
  }
}

/// Keep reading the screen-capture flag until the returned function is called, and report it every
/// time. A recording that starts after the first snapshot, even one that stops again, still shows
/// up: `seen` stays true. Reads never overlap, a failed read is skipped, and nothing here throws.
void Function() startScreenWatch(
  void Function(ScreenCaptureState state) onState, {
  Duration interval = screenWatchInterval,
  bool alreadySeen = false,
}) {
  var seen = alreadySeen;
  var stopped = false;
  var reading = false;

  Future<void> tick() async {
    if (stopped || reading) return;
    reading = true;
    try {
      final current = await readScreenCapture();
      if (stopped || current == null) return;
      if (current) seen = true;
      onState(ScreenCaptureState(current: current, seen: seen));
    } finally {
      reading = false;
    }
  }

  final timer = Timer.periodic(interval, (_) => tick());
  tick();

  return () {
    stopped = true;
    timer.cancel();
  };
}

/// The script the WebView runs to update what the page already holds in
/// `window.__PREMBLY_NATIVE_DEVICE__`. It does nothing on any other origin or before the page has
/// the data, and it tells the page (a `prembly:native-device-update` event) only when something
/// changed.
String buildScreenUpdateScript(ScreenCaptureState state) {
  return '''(function () {
  try {
    var device = window.__PREMBLY_NATIVE_DEVICE__;
    if (window.location.origin !== ${premblySafeJson(premblyWidgetOrigin)} || !device) return;
    var signals = (device.signals = device.signals || {});
    var scam = (signals.scam_signals = signals.scam_signals || {});
    var changed =
      scam.is_screen_shared_or_recorded !== ${state.current} ||
      scam.screen_capture_seen !== ${state.seen};
    scam.is_screen_shared_or_recorded = ${state.current};
    scam.screen_capture_seen = ${state.seen};
    if (changed) window.dispatchEvent(new CustomEvent('prembly:native-device-update'));
  } catch (e) {}
})();
true;''';
}
