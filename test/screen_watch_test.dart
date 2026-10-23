import 'package:flutter_test/flutter_test.dart';
import 'package:prembly_identity_kyc/src/native_device.dart';
import 'package:prembly_identity_kyc/src/screen_watch.dart';

import 'helpers.dart';

const _tick = Duration(milliseconds: 20);

Future<void> _settle([int ticks = 3]) => Future.delayed(_tick * ticks, () {});

void main() {
  late FakeNative native;

  setUp(() => native = FakeNative()..install());
  tearDown(() => native.uninstall());

  group('readScreenCapture', () {
    test('reads true and false', () async {
      native.screenCapture = {'is_screen_shared_or_recorded': true};
      expect(await readScreenCapture(), isTrue);
      native.screenCapture = {'is_screen_shared_or_recorded': false};
      expect(await readScreenCapture(), isFalse);
    });

    test('gives null, never false, when it cannot be read', () async {
      native.screenCapture = Exception('boom');
      expect(await readScreenCapture(), isNull);
      native.screenCapture = 'not json';
      expect(await readScreenCapture(), isNull);
      native.screenCapture = {'is_screen_shared_or_recorded': 'yes'};
      expect(await readScreenCapture(), isNull);
    });
  });

  group('startScreenWatch', () {
    test('reports straight away and then on every interval', () async {
      final states = <ScreenCaptureState>[];
      final stop = startScreenWatch(states.add, interval: _tick);
      await _settle(5);
      stop();
      expect(states.length, greaterThanOrEqualTo(2));
    });

    test('keeps "seen" true after a recording that has stopped', () async {
      final states = <ScreenCaptureState>[];
      native.screenCapture = {'is_screen_shared_or_recorded': false};
      final stop = startScreenWatch(states.add, interval: _tick);
      await _settle(2);
      native.screenCapture = {'is_screen_shared_or_recorded': true};
      await _settle(3);
      native.screenCapture = {'is_screen_shared_or_recorded': false};
      await _settle(3);
      stop();

      expect(states.first, const ScreenCaptureState(current: false, seen: false));
      expect(states.any((s) => s.current && s.seen), isTrue);
      expect(states.last, const ScreenCaptureState(current: false, seen: true));
      // Once seen, never false again.
      final firstSeen = states.indexWhere((s) => s.seen);
      expect(states.skip(firstSeen).every((s) => s.seen), isTrue);
    });

    test('starts with "seen" true when the first snapshot already saw a recording', () async {
      final states = <ScreenCaptureState>[];
      final stop = startScreenWatch(states.add, interval: _tick, alreadySeen: true);
      await _settle(2);
      stop();
      expect(states.first, const ScreenCaptureState(current: false, seen: true));
    });

    test('skips a read that failed and carries on', () async {
      final states = <ScreenCaptureState>[];
      native.screenCapture = Exception('boom');
      final stop = startScreenWatch(states.add, interval: _tick);
      await _settle(3);
      expect(states, isEmpty);
      native.screenCapture = {'is_screen_shared_or_recorded': true};
      await _settle(3);
      stop();
      expect(states.last, const ScreenCaptureState(current: true, seen: true));
    });

    test('stops reading and reporting once stopped', () async {
      final states = <ScreenCaptureState>[];
      final stop = startScreenWatch(states.add, interval: _tick);
      await _settle(3);
      stop();
      final count = states.length;
      final reads = native.calls.where((c) => c.method == 'checkScreenCapture').length;
      await _settle(5);
      expect(states.length, count);
      expect(native.calls.where((c) => c.method == 'checkScreenCapture').length, reads);
    });
  });

  group('buildScreenUpdateScript', () {
    test('writes the current and the seen flags into the page data', () {
      final script = buildScreenUpdateScript(const ScreenCaptureState(current: true, seen: true));
      expect(script, contains('scam.is_screen_shared_or_recorded = true;'));
      expect(script, contains('scam.screen_capture_seen = true;'));
    });

    test('only acts on the widget origin and once the page has the data', () {
      final script = buildScreenUpdateScript(const ScreenCaptureState(current: false, seen: false));
      expect(script, contains('window.location.origin !== "$premblyWidgetOrigin" || !device'));
    });

    test('tells the page only when something changed', () {
      final script = buildScreenUpdateScript(const ScreenCaptureState(current: false, seen: true));
      expect(script, contains('if (changed) window.dispatchEvent'));
      expect(script, contains('prembly:native-device-update'));
    });

    test('ends with true so a WebView does not report a silent failure', () {
      final script = buildScreenUpdateScript(const ScreenCaptureState(current: false, seen: false));
      expect(script.trim().endsWith('true;'), isTrue);
    });
  });
}
