import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chronos/chronos.dart'; // <- adjust path of the facade
import 'package:chronos/controller.dart';
import 'package:chronos/data/entity/confidence.dart';
import 'package:chronos/data/entity/time_integrity.dart';
import 'package:chronos/domain/calcs.dart';
import 'package:chronos/domain/time_integrity_checks.dart';

/// Simulates what the device OS would report via DateTime.now(): a true
/// instant, a manual clock skew (user edits time in Settings) and a timezone
/// offset (user changes timezone / travels).
class FakeDeviceClock {
  FakeDeviceClock({
    required this.trueUtc,
    this.tzOffset = Duration.zero,
    this.skew = Duration.zero,
  });

  DateTime trueUtc;
  Duration tzOffset;
  Duration skew;

  void advance(Duration d) => trueUtc = trueUtc.add(d);

  /// Instant the OS believes it is (affected by manual clock changes only).
  DateTime get instantNow => trueUtc.add(skew);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('chronos/uptime');

  // What the API returns: wall clock in Sao Paulo (UTC-3) + zone name.
  const apiDate = '2026-10-09 18:05:31.411065';
  const apiZone = 'America/Sao_Paulo';
  final apiUtc = DateTime.utc(2026, 10, 9, 21, 5, 31, 411, 65);

  late Chronos chronos;

  // Only the native side is mocked: a hardware uptime that "time passes" on.
  var uptimeMs = 0;

  void passTime(Duration d) => uptimeMs += d.inMilliseconds;

  /// TOTP time step (RFC 6238, 30s) derived from the instant's epoch seconds.
  int totpCounter(int epochSeconds) => epochSeconds ~/ 30;

  setUp(() {
    uptimeMs = 10000;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          return call.method == 'getUptimeMs' ? uptimeMs : null;
        });

    // Fresh engine per test: the real controller and real collaborators.
    chronos = Chronos.withController(
      ChronosController(Calcs(), TimeIntegrityChecks()),
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('Use case: app start, before the first sync', () {
    test('is not synced and every read fails with a StateError', () async {
      expect(chronos.isSynced, isFalse);
      expect(chronos.reference, isNull);

      await expectLater(chronos.now(), throwsStateError);
      await expectLater(chronos.nowRemoteZoned(), throwsStateError);
      await expectLater(chronos.nowLocalZoned(), throwsStateError);
    });

    test('Chronos.instance is a singleton', () {
      expect(Chronos.instance, same(Chronos.instance));
    });
  });

  group('Use case: sync from the API response and read the time', () {
    test('syncFromString anchors the app on the server time', () async {
      await chronos.syncFromString(
        date: apiDate,
        timezone: apiZone,
        networkLatencyMs: 0,
      );

      expect(chronos.isSynced, isTrue);
      expect(chronos.reference!.networkDateTime, equals(apiUtc));
      expect(
        chronos.reference!.serverUtcOffset,
        equals(const Duration(hours: -3)),
      );
      expect(chronos.reference!.hardwareUptimeMs, equals(10000));
    });

    test('now() keeps flowing from the anchor as time passes', () async {
      await chronos.syncFromString(date: apiDate, timezone: apiZone);

      passTime(const Duration(seconds: 5));
      final first = await chronos.now();
      passTime(const Duration(seconds: 25));
      final second = await chronos.now();

      expect(first.utc, equals(apiUtc.add(const Duration(seconds: 5))));
      expect(second.utc, equals(apiUtc.add(const Duration(seconds: 30))));
      expect(first.confidence, isA<HighConfidence>());
      expect(first.hwUptimeMsAtSync, equals(10000));
      expect(first.hwUptimeMsNow, equals(15000));
    });

    test('network latency is added to the calculated time', () async {
      await chronos.syncFromString(
        date: apiDate,
        timezone: apiZone,
        networkLatencyMs: 300,
      );

      passTime(const Duration(seconds: 5));
      final now = await chronos.now();

      expect(now.utc, equals(apiUtc.add(const Duration(milliseconds: 5300))));
    });

    test(
      'the app was in the background for 2 hours: time kept flowing',
      () async {
        await chronos.syncFromString(date: apiDate, timezone: apiZone);

        passTime(const Duration(hours: 2));
        final now = await chronos.now();

        expect(now.utc, equals(apiUtc.add(const Duration(hours: 2))));
      },
    );
  });

  group('Use case: show the time to the user', () {
    test('server zone and device zone are views of the same instant', () async {
      await chronos.syncFromString(date: apiDate, timezone: apiZone);
      passTime(const Duration(seconds: 5));

      final instant = await chronos.now();
      final remote = await chronos.nowRemoteZoned();
      final local = await chronos.nowLocalZoned();

      // Server zone shows the server's wall clock.
      expect(
        remote.toIso8601String(),
        equals('2026-10-09T18:05:36.411065-03:00'),
      );
      expect(remote.offset, equals(const Duration(hours: -3)));

      // Device zone follows the OS timezone, but it is the same moment.
      expect(
        DateTime.parse(local.toIso8601String()).isAtSameMomentAs(instant.utc),
        isTrue,
      );

      // Same epoch whatever the zone it is shown in.
      expect(remote.epochMs, equals(instant.epochMs));
      expect(local.epochMs, equals(instant.epochMs));
    });

    test(
      'a server that answers in UTC (Z) shows a zero server offset',
      () async {
        await chronos.syncFromString(date: '2026-10-09T21:05:31.411065Z');
        passTime(const Duration(seconds: 5));

        final remote = await chronos.nowRemoteZoned();

        expect(remote.offset, equals(Duration.zero));
        expect(
          remote.toIso8601String(),
          equals('2026-10-09T21:05:36.411065+00:00'),
        );
      },
    );

    test(
      'a sync without a server offset hides only the server-zone view',
      () async {
        // e.g. the instant comes from an NTP server, no zone info.
        await chronos.sync(networkDateTime: apiUtc);
        passTime(const Duration(seconds: 5));

        final instant = await chronos.now();
        final local = await chronos.nowLocalZoned();

        expect(instant.utc, equals(apiUtc.add(const Duration(seconds: 5))));
        expect(local.utc, equals(instant.utc));
        await expectLater(
          chronos.nowRemoteZoned(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'server_utc_offset_was_not_provided_on_sync',
            ),
          ),
        );
      },
    );
  });

  group('Use case: TOTP', () {
    test('the counter changes exactly on the server\'s 30s boundary', () async {
      // Synced at 21:05:31.411Z -> the current step started at 21:05:30,
      // the next one starts at 21:06:00.
      await chronos.syncFromString(date: apiDate, timezone: apiZone);
      final stepStart = DateTime.utc(2026, 10, 9, 21, 5, 30);
      final expectedCounter = totpCounter(
        stepStart.millisecondsSinceEpoch ~/ 1000,
      );

      final atSync = await chronos.now();
      expect(totpCounter(atSync.epochSeconds), equals(expectedCounter));

      passTime(const Duration(seconds: 28)); // 21:05:59.411
      final lastMomentOfStep = await chronos.now();
      expect(
        totpCounter(lastMomentOfStep.epochSeconds),
        equals(expectedCounter),
      );

      passTime(const Duration(seconds: 1)); // 21:06:00.411
      final nextStep = await chronos.now();
      expect(totpCounter(nextStep.epochSeconds), equals(expectedCounter + 1));
    });

    test('the counter is the same in every zone view', () async {
      await chronos.syncFromString(date: apiDate, timezone: apiZone);
      passTime(const Duration(seconds: 5));

      final instant = await chronos.now();
      final remote = await chronos.nowRemoteZoned();
      final local = await chronos.nowLocalZoned();

      expect(
        totpCounter(remote.epochSeconds),
        equals(totpCounter(instant.epochSeconds)),
      );
      expect(
        totpCounter(local.epochSeconds),
        equals(totpCounter(instant.epochSeconds)),
      );
    });

    test('changing the device clock and timezone does not change the counter', () async {
      final device = FakeDeviceClock(
        trueUtc: apiUtc,
        tzOffset: const Duration(hours: -3),
      );
      await chronos.syncFromString(date: apiDate, timezone: apiZone);

      // 5 real seconds pass...
      passTime(const Duration(seconds: 5));
      device.advance(const Duration(seconds: 5));

      // ...and the user travels to Tokyo and sets the clock back 2 hours.
      device.tzOffset = const Duration(hours: 9);
      device.skew = const Duration(hours: -2);

      final instant = await chronos.now();
      final expectedCounter = totpCounter(
        apiUtc.add(const Duration(seconds: 5)).millisecondsSinceEpoch ~/ 1000,
      );
      final naiveCounter = totpCounter(
        device.instantNow.millisecondsSinceEpoch ~/ 1000,
      );

      expect(totpCounter(instant.epochSeconds), equals(expectedCounter));
      // A naive implementation reading the device clock is 2h = 240 steps off.
      expect(naiveCounter, equals(expectedCounter - 240));
    });
  });

  group('Use case: time-gated feature', () {
    // The feature opens at 21:10:00Z (18:10:00 in the server zone).
    final gateOpensAt = DateTime.utc(2026, 10, 9, 21, 10, 0);
    bool isOpen(DateTime now) => !now.isBefore(gateOpensAt);

    test('opens exactly when the server time reaches the gate', () async {
      await chronos.syncFromString(date: apiDate, timezone: apiZone);

      passTime(const Duration(seconds: 268)); // 21:09:59.411
      expect(isOpen((await chronos.now()).utc), isFalse);

      passTime(const Duration(seconds: 1)); // 21:10:00.411
      expect(isOpen((await chronos.now()).utc), isTrue);
    });

    test(
      'moving the device clock forward does not open the gate early',
      () async {
        final device = FakeDeviceClock(trueUtc: apiUtc);
        await chronos.syncFromString(date: apiDate, timezone: apiZone);

        passTime(const Duration(seconds: 5));
        device.advance(const Duration(seconds: 5));
        device.skew = const Duration(hours: 1); // user cheats: +1 hour

        expect(isOpen(device.instantNow), isTrue); // what a naive app would see
        expect(isOpen((await chronos.now()).utc), isFalse); // Chronos
      },
    );
  });

  group('Use case: resilience', () {
    test(
      'a malformed API payload keeps the last good anchor working',
      () async {
        await chronos.syncFromString(date: apiDate, timezone: apiZone);

        passTime(const Duration(seconds: 5));
        await expectLater(
          chronos.syncFromString(date: 'not-a-date', timezone: apiZone),
          throwsFormatException,
        );

        passTime(const Duration(seconds: 5));
        final now = await chronos.now();

        expect(chronos.isSynced, isTrue);
        expect(now.utc, equals(apiUtc.add(const Duration(seconds: 10))));
      },
    );

    test('a payload with no offset and no zone is rejected', () async {
      await expectLater(
        chronos.syncFromString(date: apiDate),
        throwsArgumentError,
      );

      expect(chronos.isSynced, isFalse);
    });

    test(
      'device reboot lowers the confidence until the app re-syncs',
      () async {
        uptimeMs = 100000;
        await chronos.syncFromString(date: apiDate, timezone: apiZone);

        // Reboot: the hardware uptime starts again from a small value.
        uptimeMs = 3000;
        final afterReboot = await chronos.now();

        expect(afterReboot.confidence, isA<LowConfidence>());
        expect(afterReboot.confidence.timeIntegrity, isA<Inconsistent>());
        expect(
          afterReboot.hwUptimeMsNow,
          lessThan(afterReboot.hwUptimeMsAtSync),
        );

        // The app notices the low confidence and syncs again with the server.
        await chronos.syncFromString(
          date: '2026-10-09 19:30:00', // 22:30:00Z
          timezone: apiZone,
        );
        passTime(const Duration(seconds: 5));
        final recovered = await chronos.now();

        expect(recovered.utc, equals(DateTime.utc(2026, 10, 9, 22, 30, 5)));
        expect(recovered.confidence, isA<HighConfidence>());
        expect(recovered.hwUptimeMsAtSync, equals(3000));
      },
    );

    test(
      'a new sync replaces the anchor and restarts the elapsed time',
      () async {
        await chronos.syncFromString(date: apiDate, timezone: apiZone);
        passTime(const Duration(minutes: 10));

        await chronos.syncFromString(
          date: '2026-10-09 18:30:00', // 21:30:00Z
          timezone: apiZone,
        );
        passTime(const Duration(seconds: 2));
        final now = await chronos.now();

        expect(now.utc, equals(DateTime.utc(2026, 10, 9, 21, 30, 2)));
      },
    );
  });
}
