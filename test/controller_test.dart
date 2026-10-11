import 'package:chronos/data/server_time_parser.dart';
import 'package:chronos/data/service/cache_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chronos/controller.dart';
import 'package:chronos/data/entity/confidence.dart';
import 'package:chronos/data/entity/time_integrity.dart';
import 'package:chronos/domain/calcs.dart';
import 'package:chronos/domain/time_integrity_checks.dart';
import 'package:chronos/data/final.dart'; // TIME_REF_CACHE_KEY
import 'package:mocktail/mocktail.dart';

class MockCache extends Mock implements CacheService {}

/// Simulates what the device OS would report via DateTime.now(): a true
/// instant, a manual clock skew (user edits time in Settings) and a timezone
/// offset (user changes timezone / travels).
class FakeDeviceClock {
  FakeDeviceClock({
    required this.trueUtc,
    this.tzOffset = Duration.zero,
    this.skew = Duration.zero,
  });

  /// Real current instant (what the network would say).
  DateTime trueUtc;

  /// Timezone offset configured in the OS.
  Duration tzOffset;

  /// Manual clock change applied by the user in Settings.
  Duration skew;

  void advance(Duration d) => trueUtc = trueUtc.add(d);

  /// Instant the OS believes it is (affected by manual clock changes only).
  DateTime get instantNow => trueUtc.add(skew);

  /// Wall-clock fields shown to the user (instant + timezone offset).
  DateTime get wallClock => instantNow.add(tzOffset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('chronos/uptime');
  const minus3 = Duration(hours: -3);

  late ChronosController controller;
  late MockCache cache;
  late List<int> uptimeQueue;

  void stubCache(MockCache c, {String? stored}) {
    when(() => c.ensureInitialized()).thenAnswer((_) async {});
    when(() => c.getString(any())).thenAnswer((_) async => stored);
    when(
      () => c.storeString(
        k: any(named: 'k'),
        v: any(named: 'v'),
      ),
    ).thenAnswer((_) async => true);
  }

  setUp(() {
    uptimeQueue = [];
    cache = MockCache();
    stubCache(cache);
    controller = ChronosController(Calcs(), TimeIntegrityChecks(), cache);
  });
  final syncTime = DateTime.utc(2026, 10, 8, 12, 0, 0);

  /// Only the native side is mocked. Each `getUptimeMs` call consumes the
  /// next value from the queue: sync reads once, and every getter reads once.
  void mockUptime(List<int> values) {
    uptimeQueue = List<int>.of(values);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          if (call.method == 'getUptimeMs') {
            return uptimeQueue.removeAt(0);
          }
          return null;
        });
  }

  setUp(() {
    uptimeQueue = [];
    cache = MockCache();
    stubCache(cache);
    controller = ChronosController(Calcs(), TimeIntegrityChecks(), cache);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('ChronosController - cache', () {
    const apiDate = '2026-10-09 18:05:31.411065';
    const apiZone = 'America/Sao_Paulo';
    final apiUtc = DateTime.utc(2026, 10, 9, 21, 5, 31, 411, 65);

    String captureStored() =>
        verify(
              () => cache.storeString(
                k: TIME_REF_CACHE_KEY,
                v: captureAny(named: 'v'),
              ),
            ).captured.last
            as String;

    Future<ChronosController> restart(String? stored) async {
      final c = MockCache();
      stubCache(c, stored: stored);
      final restarted = ChronosController(Calcs(), TimeIntegrityChecks(), c);
      await restarted.ensureInitialized();
      return restarted;
    }

    test('ensureInitialized with an empty cache leaves no reference', () async {
      await controller.ensureInitialized();

      verify(() => cache.ensureInitialized()).called(1);
      verify(() => cache.getString(TIME_REF_CACHE_KEY)).called(1);
      expect(controller.ref, isNull);
    });

    test('sync persists the reference under the cache key', () async {
      mockUptime([10000]);

      await controller.sync(networkDateTime: syncTime, serverUtcOffset: minus3);

      verify(
        () => cache.storeString(
          k: TIME_REF_CACHE_KEY,
          v: any(named: 'v'),
        ),
      ).called(1);
    });

    test('syncFromString persists the reference under the cache key', () async {
      mockUptime([10000]);

      await controller.syncFromString(date: apiDate, timezone: apiZone);

      verify(
        () => cache.storeString(
          k: TIME_REF_CACHE_KEY,
          v: any(named: 'v'),
        ),
      ).called(1);
    });

    test('every sync overwrites the cache', () async {
      mockUptime([10000, 20000]);

      await controller.sync(networkDateTime: syncTime);
      await controller.sync(networkDateTime: syncTime);

      verify(
        () => cache.storeString(
          k: any(named: 'k'),
          v: any(named: 'v'),
        ),
      ).called(2);
    });

    test('a failed syncFromString does not touch the cache', () async {
      mockUptime([10000]);

      await expectLater(
        controller.syncFromString(date: 'not-a-date', timezone: apiZone),
        throwsFormatException,
      );

      verifyNever(
        () => cache.storeString(
          k: any(named: 'k'),
          v: any(named: 'v'),
        ),
      );
    });

    test('reads never write to the cache', () async {
      mockUptime([10000, 15000]);
      await controller.sync(networkDateTime: syncTime);
      clearInteractions(cache);

      await controller.getInstant();

      verifyNever(
        () => cache.storeString(
          k: any(named: 'k'),
          v: any(named: 'v'),
        ),
      );
    });

    test('a stored reference is restored with all its fields', () async {
      mockUptime([10000]);
      await controller.syncFromString(
        date: apiDate,
        timezone: apiZone,
        networkLatencyMs: 45,
      );
      final stored = captureStored();

      final restarted = await restart(stored);

      expect(restarted.ref, isNotNull);
      expect(restarted.ref!.hardwareUptimeMs, equals(10000));
      expect(restarted.ref!.networkDateTime, equals(apiUtc));
      expect(restarted.ref!.networkLatency, equals(45));
      expect(restarted.ref!.serverUtcOffset, equals(minus3));
      expect(restarted.ref!.serverUtcOffsetZoneName, equals(apiZone));
    });

    test('a corrupt cache starts unsynced instead of crashing', () async {
      final restarted = await restart('not-json');

      expect(restarted.ref, isNull);
      await expectLater(restarted.getInstant(), throwsStateError);
    });

    test('a cache with missing fields starts unsynced', () async {
      final restarted = await restart('{}');

      expect(restarted.ref, isNull);
    });

    test('after a corrupt cache, a new sync works normally', () async {
      final restarted = await restart('not-json');

      mockUptime([10000, 15000]);
      await restarted.sync(networkDateTime: syncTime);
      final instant = await restarted.getInstant();

      expect(instant.utc, equals(syncTime.add(const Duration(seconds: 5))));
    });

    test('a restored reference keeps calculating time', () async {
      mockUptime([10000]);
      await controller.syncFromString(date: apiDate, timezone: apiZone);
      final stored = captureStored();

      final restarted = await restart(stored);
      mockUptime([15000]); // same boot, 5s later
      final instant = await restarted.getInstant();

      expect(instant.utc, equals(apiUtc.add(const Duration(seconds: 5))));
      expect(instant.confidence, isA<HighConfidence>());
    });

    test('a restored reference after a reboot gives low confidence', () async {
      mockUptime([100000]);
      await controller.syncFromString(date: apiDate, timezone: apiZone);
      final stored = captureStored();

      final restarted = await restart(stored);
      mockUptime([2000]); // uptime restarted
      final instant = await restarted.getInstant();

      expect(instant.confidence, isA<LowConfidence>());
      expect(instant.confidence.timeIntegrity, isA<Inconsistent>());
    });

    test('a restored reference is replaced by a new sync', () async {
      mockUptime([10000]);
      await controller.sync(networkDateTime: syncTime);
      final restarted = await restart(captureStored());

      mockUptime([30000]);
      final newAnchor = DateTime.utc(2026, 10, 8, 14, 0, 0);
      await restarted.sync(networkDateTime: newAnchor);

      expect(restarted.ref!.networkDateTime, equals(newAnchor));
      expect(restarted.ref!.hardwareUptimeMs, equals(30000));
    });
  });

  group('ChronosController - before sync', () {
    test('all getters throw StateError when never synchronized', () async {
      mockUptime([1000, 1000, 1000]);

      final getters = <Future<Object> Function()>[
        controller.getInstant,
        controller.getRemoteZonedTime,
        controller.getLocalZonedTime,
      ];

      for (final getter in getters) {
        await expectLater(
          getter(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'network_time_reference_has_not_been_initialized',
            ),
          ),
        );
      }
    });
  });

  group('ChronosController - sync', () {
    test('stores uptime, UTC time, latency and server offset', () async {
      mockUptime([10000]);

      await controller.sync(
        networkDateTime: syncTime,
        networkLatencyMs: 3000,
        serverUtcOffset: minus3,
      );

      expect(controller.ref, isNotNull);
      expect(controller.ref!.hardwareUptimeMs, equals(10000));
      expect(controller.ref!.networkDateTime, equals(syncTime));
      expect(controller.ref!.networkLatency, equals(3000));
      expect(controller.ref!.serverUtcOffset, equals(minus3));
      expect(uptimeQueue, isEmpty);
    });

    test('a local DateTime is stored as UTC at the same instant', () async {
      mockUptime([10000]);
      final local = DateTime(2026, 10, 8, 9, 0, 0); // device-local

      await controller.sync(networkDateTime: local);

      expect(controller.ref!.networkDateTime.isUtc, isTrue);
      expect(controller.ref!.networkDateTime.isAtSameMomentAs(local), isTrue);
    });

    test('a second sync replaces the previous reference', () async {
      mockUptime([10000, 50000]);
      final later = syncTime.add(const Duration(hours: 1));

      await controller.sync(networkDateTime: syncTime);
      await controller.sync(
        networkDateTime: later,
        networkLatencyMs: 10,
        serverUtcOffset: minus3,
      );

      expect(controller.ref!.hardwareUptimeMs, equals(50000));
      expect(controller.ref!.networkDateTime, equals(later));
      expect(controller.ref!.networkLatency, equals(10));
      expect(controller.ref!.serverUtcOffset, equals(minus3));
    });
  });

  group('ChronosController - elapsed time calculation', () {
    test(
      'calculated now = anchor + elapsed, identical in the three entities',
      () async {
        // sync @ 10s, then each getter reads uptime @ 15s
        mockUptime([10000, 15000, 15000, 15000]);
        await controller.sync(
          networkDateTime: syncTime,
          serverUtcOffset: minus3,
        );

        final instant = await controller.getInstant();
        final remote = await controller.getRemoteZonedTime();
        final local = await controller.getLocalZonedTime();

        final expected = syncTime.add(const Duration(seconds: 5));

        expect(instant.utc, equals(expected));
        expect(remote.utc, equals(expected));
        expect(local.utc, equals(expected));

        expect(instant.epochMs, equals(expected.millisecondsSinceEpoch));
        expect(remote.epochMs, equals(instant.epochMs));
        expect(local.epochMs, equals(instant.epochMs));
        expect(uptimeQueue, isEmpty);
      },
    );

    // (elapsed uptime ms, network latency ms)
    final cases = <({int deltaMs, int latencyMs})>[
      (deltaMs: 0, latencyMs: 0),
      (deltaMs: 1, latencyMs: 0),
      (deltaMs: 1234, latencyMs: 0), // sub-second precision
      (deltaMs: 5000, latencyMs: 3000), // latency is added in full
      (deltaMs: 60000, latencyMs: 0), // 1 minute
      (deltaMs: 3600000, latencyMs: 45), // 1 hour
      (deltaMs: 864000000, latencyMs: 0), // 10 days (> 2^31 ms is fine)
    ];

    for (final c in cases) {
      test(
        'now = anchor + ${c.deltaMs}ms elapsed + ${c.latencyMs}ms latency',
        () async {
          mockUptime([
            10000,
            10000 + c.deltaMs,
            10000 + c.deltaMs,
            10000 + c.deltaMs,
          ]);
          await controller.sync(
            networkDateTime: syncTime,
            networkLatencyMs: c.latencyMs,
            serverUtcOffset: minus3,
          );

          final instant = await controller.getInstant();
          final remote = await controller.getRemoteZonedTime();
          final local = await controller.getLocalZonedTime();

          final expected = syncTime.add(
            Duration(milliseconds: c.deltaMs + c.latencyMs),
          );

          expect(instant.utc, equals(expected));
          expect(remote.utc, equals(expected));
          expect(local.utc, equals(expected));
          expect(instant.hwUptimeMsAtSync, equals(10000));
          expect(instant.hwUptimeMsNow, equals(10000 + c.deltaMs));
        },
      );
    }

    test('latency defaults to 0 when not provided', () async {
      mockUptime([10000, 15000]);

      await controller.sync(networkDateTime: syncTime);
      final instant = await controller.getInstant();

      expect(instant.utc, equals(syncTime.add(const Duration(seconds: 5))));
    });

    test('repeated reads are all relative to the same anchor', () async {
      mockUptime([10000, 15000, 30000]);

      await controller.sync(networkDateTime: syncTime);
      final first = await controller.getInstant();
      final second = await controller.getInstant();

      expect(first.utc, equals(syncTime.add(const Duration(seconds: 5))));
      expect(second.utc, equals(syncTime.add(const Duration(seconds: 20))));
      expect(second.hwUptimeMsAtSync, equals(first.hwUptimeMsAtSync));
      expect(second.utc.isAfter(first.utc), isTrue);
    });

    test('a new sync moves the anchor and restarts the elapsed time', () async {
      final newAnchor = DateTime.utc(2026, 10, 8, 13, 0, 0);
      mockUptime([10000, 15000, 20000, 22000]);

      await controller.sync(networkDateTime: syncTime);
      final before = await controller.getInstant(); // +5s on 12:00
      await controller.sync(networkDateTime: newAnchor);
      final after = await controller.getInstant(); // +2s on 13:00

      expect(before.utc, equals(DateTime.utc(2026, 10, 8, 12, 0, 5)));
      expect(after.utc, equals(DateTime.utc(2026, 10, 8, 13, 0, 2)));
      expect(after.hwUptimeMsAtSync, equals(20000));
    });

    test('each getter reads the hardware uptime exactly once', () async {
      mockUptime([10000, 15000, 15000, 15000]);
      await controller.sync(networkDateTime: syncTime, serverUtcOffset: minus3);

      await controller.getInstant();
      expect(uptimeQueue.length, equals(2));
      await controller.getRemoteZonedTime();
      expect(uptimeQueue.length, equals(1));
      await controller.getLocalZonedTime();
      expect(uptimeQueue, isEmpty);
    });

    test(
      'remote zoned time applies the server offset to the calculated now',
      () async {
        mockUptime([10000, 15000]);
        await controller.sync(
          networkDateTime: syncTime,
          serverUtcOffset: minus3,
        );

        final remote = await controller.getRemoteZonedTime();

        expect(remote.offset, equals(minus3));
        expect(remote.wallClock, equals(DateTime.utc(2026, 10, 8, 9, 0, 5)));
        expect(
          remote.toIso8601String(),
          equals('2026-10-08T09:00:05.000-03:00'),
        );
      },
    );

    test('server offset comes from sync, not hardcoded (Tokyo +9)', () async {
      mockUptime([10000, 15000]);
      await controller.sync(
        networkDateTime: syncTime,
        serverUtcOffset: const Duration(hours: 9),
      );

      final remote = await controller.getRemoteZonedTime();

      expect(remote.wallClock.hour, equals(21));
      expect(remote.toIso8601String(), equals('2026-10-08T21:00:05.000+09:00'));
      expect(remote.utc, equals(syncTime.add(const Duration(seconds: 5))));
    });

    test('local zoned time is the calculated now in the OS timezone', () async {
      mockUptime([10000, 15000]);
      await controller.sync(networkDateTime: syncTime);

      final local = await controller.getLocalZonedTime();
      final expected = syncTime.add(const Duration(seconds: 5));

      expect(local.dateTime.isUtc, isFalse);
      expect(local.dateTime.isAtSameMomentAs(expected), isTrue);
      // Wall fields follow whatever the OS timezone is (run with TZ=...).
      expect(local.dateTime.hour, equals(expected.toLocal().hour));
    });
  });

  group('ChronosController - confidence and offset availability', () {
    test(
      'the three entities share the same confidence for the same uptime',
      () async {
        mockUptime([10000, 15000, 15000, 15000]);
        await controller.sync(
          networkDateTime: syncTime,
          serverUtcOffset: minus3,
        );

        final instant = await controller.getInstant();
        final remote = await controller.getRemoteZonedTime();
        final local = await controller.getLocalZonedTime();

        expect(instant.confidence, isA<HighConfidence>());
        expect(instant.confidence.timeIntegrity, isA<Trusted>());
        expect(
          remote.confidence.runtimeType,
          equals(instant.confidence.runtimeType),
        );
        expect(
          local.confidence.runtimeType,
          equals(instant.confidence.runtimeType),
        );
      },
    );

    test(
      'reboot (uptime goes backwards) lowers confidence on every entity',
      () async {
        mockUptime([100000, 3000, 3000, 3000]);
        await controller.sync(
          networkDateTime: syncTime,
          serverUtcOffset: minus3,
        );

        final instant = await controller.getInstant();
        final remote = await controller.getRemoteZonedTime();
        final local = await controller.getLocalZonedTime();

        for (final confidence in [
          instant.confidence,
          remote.confidence,
          local.confidence,
        ]) {
          expect(confidence, isA<LowConfidence>());
          expect(confidence.timeIntegrity, isA<Inconsistent>());
          expect(confidence.timeIntegrity.tampered, isTrue);
        }
        expect(instant.hwUptimeMsNow, lessThan(instant.hwUptimeMsAtSync));
      },
    );

    test(
      'getRemoteZonedTime throws when sync had no serverUtcOffset',
      () async {
        mockUptime([10000, 15000]);
        await controller.sync(networkDateTime: syncTime);

        await expectLater(
          controller.getRemoteZonedTime(),
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

    test(
      'instant and local zoned time still work without a server offset',
      () async {
        mockUptime([10000, 15000, 15000]);
        await controller.sync(networkDateTime: syncTime);

        final instant = await controller.getInstant();
        final local = await controller.getLocalZonedTime();

        expect(instant.utc, equals(syncTime.add(const Duration(seconds: 5))));
        expect(local.utc, equals(instant.utc));
      },
    );
  });

  group('ChronosController - Real World Scenarios', () {
    test('untampered: +15s of hardware uptime', () async {
      mockUptime([10000, 25000]);

      await controller.sync(networkDateTime: syncTime, networkLatencyMs: 0);
      final instant = await controller.getInstant();

      expect(instant.utc, equals(syncTime.add(const Duration(seconds: 15))));
      expect(instant.confidence, isA<HighConfidence>());
      expect(instant.confidence.timeIntegrity.tampered, isFalse);
    });

    test(
      'device OS clock and timezone changes do not affect any entity',
      () async {
        // Simulated device OS: user is in Sao Paulo (UTC-3), clock is correct.
        final device = FakeDeviceClock(trueUtc: syncTime, tzOffset: minus3);
        final deviceWallAtSync = device.wallClock; // 09:00:00

        mockUptime([10000, 25000, 25000, 25000]); // +15s of hardware uptime
        await controller.sync(
          networkDateTime: syncTime,
          serverUtcOffset: minus3,
        );

        // 15 real seconds pass...
        device.advance(const Duration(seconds: 15));

        // ...and the user travels to Tokyo (UTC+9) AND sets the clock back 2h.
        device.tzOffset = const Duration(hours: 9);
        device.skew = const Duration(hours: -2);

        // Sanity: the simulation really changed what the OS reports.
        expect(device.wallClock, equals(DateTime.utc(2026, 10, 8, 19, 0, 15)));
        expect(
          device.wallClock.difference(deviceWallAtSync),
          isNot(equals(const Duration(seconds: 15))),
        );

        final instant = await controller.getInstant();
        final remote = await controller.getRemoteZonedTime();
        final local = await controller.getLocalZonedTime();
        final expected = syncTime.add(const Duration(seconds: 15));

        // Only server anchor + uptime delta count.
        expect(instant.utc, equals(expected));
        expect(remote.utc, equals(expected));
        expect(local.utc, equals(expected));
        expect(instant.confidence, isA<HighConfidence>());

        // Remote wall clock still shows the server's zone (09:00:15).
        expect(remote.wallClock, equals(DateTime.utc(2026, 10, 8, 9, 0, 15)));

        // A naive implementation reading the OS clock would be 2h off.
        expect(device.instantNow.isAtSameMomentAs(expected), isFalse);
        expect(
          expected.difference(device.instantNow),
          equals(const Duration(hours: 2)),
        );

        // The stored anchor was not mutated.
        expect(controller.ref!.networkDateTime, equals(syncTime));
      },
    );
  });

  group('ChronosController - syncFromString', () {
    // What the API returns: wall clock + zone name (case 3)
    const apiDate = '2026-10-09 18:05:31.411065';
    const apiZone = 'America/Sao_Paulo';
    final apiUtc = DateTime.utc(2026, 10, 9, 21, 5, 31, 411, 65);

    test(
      'API date + zone name stores the UTC instant, offset and uptime',
      () async {
        mockUptime([10000]);

        await controller.syncFromString(
          date: apiDate,
          timezone: apiZone,
          networkLatencyMs: 45,
        );

        expect(controller.ref!.hardwareUptimeMs, equals(10000));
        expect(controller.ref!.networkDateTime, equals(apiUtc));
        expect(controller.ref!.networkDateTime.isUtc, isTrue);
        expect(controller.ref!.networkLatency, equals(45));
        expect(controller.ref!.serverUtcOffset, equals(minus3));
        expect(uptimeQueue, isEmpty); // uptime read exactly once
      },
    );

    test('the three entities calculate from the parsed anchor', () async {
      mockUptime([10000, 15000, 15000, 15000]);

      await controller.syncFromString(date: apiDate, timezone: apiZone);

      final instant = await controller.getInstant();
      final remote = await controller.getRemoteZonedTime();
      final local = await controller.getLocalZonedTime();
      final expected = apiUtc.add(const Duration(seconds: 5));

      expect(instant.utc, equals(expected));
      expect(remote.utc, equals(expected));
      expect(local.utc, equals(expected));
      expect(
        remote.wallClock,
        equals(DateTime.utc(2026, 10, 9, 18, 5, 36, 411, 65)),
      );
      expect(
        remote.toIso8601String(),
        equals('2026-10-09T18:05:36.411065-03:00'),
      );
    });

    test('is equivalent to parsing manually and calling sync', () async {
      mockUptime([10000, 10000]);
      final parsed = ServerTimeParser.parse(date: apiDate, timezone: apiZone);

      await controller.syncFromString(date: apiDate, timezone: apiZone);
      final viaString = controller.ref!;
      await controller.sync(
        networkDateTime: parsed.utc,
        serverUtcOffset: parsed.offset,
      );
      final viaSync = controller.ref!;

      expect(viaString.hardwareUptimeMs, equals(viaSync.hardwareUptimeMs));
      expect(viaString.networkDateTime, equals(viaSync.networkDateTime));
      expect(viaString.serverUtcOffset, equals(viaSync.serverUtcOffset));
    });

    test(
      'zone given as an offset string is applied (no tz database)',
      () async {
        mockUptime([10000]);

        await controller.syncFromString(date: apiDate, timezone: '-03:00');

        expect(controller.ref!.networkDateTime, equals(apiUtc));
        expect(controller.ref!.serverUtcOffset, equals(minus3));
      },
    );

    test('date with Z needs no timezone and gives a zero offset', () async {
      mockUptime([10000, 15000]);

      await controller.syncFromString(date: '2026-10-09T21:05:31.411065Z');
      final remote = await controller.getRemoteZonedTime();

      expect(controller.ref!.networkDateTime, equals(apiUtc));
      expect(controller.ref!.serverUtcOffset, equals(Duration.zero));
      expect(remote.wallClock, equals(apiUtc.add(const Duration(seconds: 5))));
    });

    test(
      'date with an offset needs no timezone and keeps that offset',
      () async {
        mockUptime([10000]);

        await controller.syncFromString(
          date: '2026-10-09T18:05:31.411065-03:00',
        );

        expect(controller.ref!.networkDateTime, equals(apiUtc));
        expect(controller.ref!.serverUtcOffset, equals(minus3));
      },
    );

    test(
      'no offset and no timezone throws ArgumentError and sets no ref',
      () async {
        mockUptime([10000]);

        await expectLater(
          controller.syncFromString(date: apiDate),
          throwsArgumentError,
        );
        expect(controller.ref, isNull);
      },
    );

    test(
      'a malformed date throws and leaves the previous reference intact',
      () async {
        mockUptime([10000, 20000]);

        await controller.syncFromString(date: apiDate, timezone: apiZone);
        final previous = controller.ref;

        await expectLater(
          controller.syncFromString(date: 'not-a-date', timezone: apiZone),
          throwsFormatException,
        );
        expect(controller.ref, same(previous));
      },
    );

    test(
      'an unknown zone throws and leaves the previous reference intact',
      () async {
        mockUptime([10000, 20000]);

        await controller.syncFromString(date: apiDate, timezone: apiZone);
        final previous = controller.ref;

        await expectLater(
          controller.syncFromString(
            date: apiDate,
            timezone: 'Mars/Olympus_Mons',
          ),
          throwsA(anything),
        );
        expect(controller.ref, same(previous));
      },
    );
  });
}
