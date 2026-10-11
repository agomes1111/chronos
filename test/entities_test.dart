import 'package:flutter_test/flutter_test.dart';

import 'package:chronos/data/entity/confidence.dart';
import 'package:chronos/data/entity/instant.dart'; // <- adjust paths
import 'package:chronos/data/entity/local_zoned_time.dart';
import 'package:chronos/data/entity/remote_zoned_time.dart';
import 'package:chronos/data/entity/time_integrity.dart';

void main() {
  // 18:05:31.411065 in Sao Paulo (UTC-3) == 21:05:31.411065Z
  final utc = DateTime.utc(2026, 10, 9, 21, 5, 31, 411, 65);
  final confidence = HighConfidence(timeIntegrity: Trusted());

  Instant makeInstant() => Instant(
    utc: utc,
    hwUptimeMsAtSync: 10000,
    hwUptimeMsNow: 15000,
    confidence: confidence,
  );

  group('Instant', () {
    test('keeps the utc date time, both uptimes and confidence', () {
      final instant = makeInstant();

      expect(instant.utc, equals(utc));
      expect(instant.utc.isUtc, isTrue);
      expect(instant.hwUptimeMsAtSync, equals(10000));
      expect(instant.hwUptimeMsNow, equals(15000));
      expect(instant.confidence, same(confidence));
    });

    test('allows uptime now below uptime at sync (reboot case)', () {
      final instant = Instant(
        utc: utc,
        hwUptimeMsAtSync: 100000,
        hwUptimeMsNow: 3000,
        confidence: LowConfidence(timeIntegrity: Inconsistent()),
      );

      expect(instant.hwUptimeMsNow, lessThan(instant.hwUptimeMsAtSync));
    });

    test('exposes epoch milliseconds and seconds', () {
      final instant = makeInstant();

      expect(instant.epochMs, equals(utc.millisecondsSinceEpoch));
      expect(instant.epochSeconds, equals(utc.millisecondsSinceEpoch ~/ 1000));
    });

    test('rejects a non-UTC DateTime', () {
      expect(
        () => Instant(
          utc: DateTime(2026, 10, 9, 18, 5, 31), // local, isUtc == false
          hwUptimeMsAtSync: 10000,
          hwUptimeMsNow: 15000,
          confidence: confidence,
        ),
        throwsAssertionError,
      );
    });
  });

  group('RemoteZonedTime', () {
    RemoteZonedTime at(Duration offset) =>
        RemoteZonedTime(instant: makeInstant(), offset: offset);

    test('is composed of the same Instant and delegates to it', () {
      final instant = makeInstant();
      final remote = RemoteZonedTime(
        instant: instant,
        offset: const Duration(hours: -3),
      );

      expect(remote.instant, same(instant));
      expect(remote.utc, equals(instant.utc));
      expect(remote.epochMs, equals(instant.epochMs));
      expect(remote.epochSeconds, equals(instant.epochSeconds));
      expect(remote.confidence, same(instant.confidence));
    });

    test('wall clock shows the server zone fields', () {
      final remote = at(const Duration(hours: -3));

      expect(remote.wallClock.hour, equals(18));
      expect(remote.wallClock.minute, equals(5));
      expect(remote.wallClock.second, equals(31));
      expect(remote.wallClock.microsecond, equals(65));
    });

    test('epoch comes from the instant, not from the wall clock', () {
      final remote = at(const Duration(hours: -3));

      expect(remote.epochMs, equals(utc.millisecondsSinceEpoch));
      expect(
        remote.wallClock.millisecondsSinceEpoch,
        isNot(equals(remote.epochMs)),
      );
    });

    test('formats a negative offset', () {
      expect(
        at(const Duration(hours: -3)).toIso8601String(),
        equals('2026-10-09T18:05:31.411065-03:00'),
      );
    });

    test('formats a positive half-hour offset', () {
      expect(
        at(const Duration(hours: 5, minutes: 30)).toIso8601String(),
        equals('2026-10-10T02:35:31.411065+05:30'),
      );
    });

    test('formats a negative half-hour offset', () {
      expect(
        at(const Duration(hours: -3, minutes: -30)).toIso8601String(),
        equals('2026-10-09T17:35:31.411065-03:30'),
      );
    });

    test('formats a zero offset', () {
      expect(
        at(Duration.zero).toIso8601String(),
        equals('2026-10-09T21:05:31.411065+00:00'),
      );
    });

    test('ISO string round-trips to the same instant for any offset', () {
      for (final offset in [
        const Duration(hours: -3),
        const Duration(hours: 9),
        const Duration(hours: 5, minutes: 30),
        const Duration(hours: -3, minutes: -30),
        Duration.zero,
      ]) {
        final parsed = DateTime.parse(at(offset).toIso8601String());

        expect(parsed.isAtSameMomentAs(utc), isTrue, reason: '$offset');
      }
    });
  });

  group('LocalZonedTime', () {
    // Assertions are relative to the OS timezone, so they hold under any TZ.
    test('is composed of the same Instant and delegates to it', () {
      final instant = makeInstant();
      final local = LocalZonedTime.fromInstant(instant);

      expect(local.instant, same(instant));
      expect(local.utc, equals(instant.utc));
      expect(local.epochMs, equals(instant.epochMs));
      expect(local.epochSeconds, equals(instant.epochSeconds));
      expect(local.confidence, same(instant.confidence));
    });

    test('dateTime is the same moment as the instant, in local time', () {
      final local = LocalZonedTime.fromInstant(makeInstant());

      expect(local.dateTime.isUtc, isFalse);
      expect(local.dateTime.isAtSameMomentAs(utc), isTrue);
      expect(local.dateTime.hour, equals(utc.toLocal().hour));
    });

    test('offset is the OS offset at that instant', () {
      final local = LocalZonedTime.fromInstant(makeInstant());

      expect(local.offset, equals(utc.toLocal().timeZoneOffset));
      expect(local.timeZoneName, equals(utc.toLocal().timeZoneName));
    });

    test('ISO string carries the OS offset and round-trips to the instant', () {
      final local = LocalZonedTime.fromInstant(makeInstant());
      final iso = local.toIso8601String();

      expect(iso, startsWith(local.dateTime.toIso8601String()));
      expect(DateTime.parse(iso).isAtSameMomentAs(utc), isTrue);
    });
  });

  group('Remote and Local from the same Instant', () {
    test('share the same epoch and instant', () {
      final instant = makeInstant();
      final remote = RemoteZonedTime(
        instant: instant,
        offset: const Duration(hours: -3),
      );
      final local = LocalZonedTime.fromInstant(instant);

      expect(remote.epochMs, equals(local.epochMs));
      expect(remote.utc, equals(local.utc));
      expect(remote.instant, same(local.instant));
    });
  });

  group('millisecondsSinceEpoch is the same across zones', () {
    final offsets = <Duration>[
      const Duration(hours: -12),
      const Duration(hours: -3),
      const Duration(hours: -3, minutes: -30),
      Duration.zero,
      const Duration(hours: 5, minutes: 30),
      const Duration(hours: 9),
      const Duration(hours: 14),
    ];

    test(
      'Instant, RemoteZonedTime (any offset) and LocalZonedTime share epochMs',
      () {
        final instant = makeInstant();
        final local = LocalZonedTime.fromInstant(instant);

        expect(instant.epochMs, equals(utc.millisecondsSinceEpoch));
        expect(local.epochMs, equals(instant.epochMs));

        for (final offset in offsets) {
          final remote = RemoteZonedTime(instant: instant, offset: offset);

          expect(remote.epochMs, equals(instant.epochMs), reason: '$offset');
          expect(remote.epochMs, equals(local.epochMs), reason: '$offset');
        }
      },
    );

    test('epochSeconds (TOTP input) is the same in the three entities', () {
      final instant = makeInstant();
      final local = LocalZonedTime.fromInstant(instant);

      for (final offset in offsets) {
        final remote = RemoteZonedTime(instant: instant, offset: offset);

        expect(remote.epochSeconds, equals(instant.epochSeconds));
        expect(local.epochSeconds, equals(instant.epochSeconds));
      }
    });

    test('epoch parsed back from every ISO string matches the instant', () {
      final instant = makeInstant();

      final isoStrings = <String>[
        for (final offset in offsets)
          RemoteZonedTime(instant: instant, offset: offset).toIso8601String(),
        LocalZonedTime.fromInstant(instant).toIso8601String(),
      ];

      for (final iso in isoStrings) {
        expect(
          DateTime.parse(iso).millisecondsSinceEpoch,
          equals(instant.epochMs),
          reason: iso,
        );
      }
    });

    test('same instant written in different zones gives the same epoch', () {
      final inputs = <String>[
        '2026-10-09T18:05:31.411065-03:00', // Sao Paulo
        '2026-10-10T06:05:31.411065+09:00', // Tokyo (next day)
        '2026-10-10T02:35:31.411065+05:30', // India (next day)
        '2026-10-09T21:05:31.411065Z', // UTC
      ];

      for (final input in inputs) {
        final instant = Instant(
          utc: DateTime.parse(input).toUtc(),
          hwUptimeMsAtSync: 10000,
          hwUptimeMsNow: 15000,
          confidence: confidence,
        );
        final remote = RemoteZonedTime(
          instant: instant,
          offset: const Duration(hours: 9),
        );
        final local = LocalZonedTime.fromInstant(instant);

        expect(
          instant.epochMs,
          equals(utc.millisecondsSinceEpoch),
          reason: input,
        );
        expect(
          remote.epochMs,
          equals(utc.millisecondsSinceEpoch),
          reason: input,
        );
        expect(
          local.epochMs,
          equals(utc.millisecondsSinceEpoch),
          reason: input,
        );
      }
    });

    test('wall-clock fields differ by zone but the epoch does not', () {
      final instant = makeInstant();
      final saoPaulo = RemoteZonedTime(
        instant: instant,
        offset: const Duration(hours: -3),
      );
      final tokyo = RemoteZonedTime(
        instant: instant,
        offset: const Duration(hours: 9),
      );

      expect(saoPaulo.wallClock.hour, equals(18));
      expect(tokyo.wallClock.hour, equals(6)); // next day
      expect(saoPaulo.wallClock.day, isNot(equals(tokyo.wallClock.day)));
      expect(saoPaulo.epochMs, equals(tokyo.epochMs));
    });

    test('the wall clock must never be used as the epoch', () {
      final instant = makeInstant();

      for (final offset in offsets.where((o) => o != Duration.zero)) {
        final remote = RemoteZonedTime(instant: instant, offset: offset);

        expect(
          remote.wallClock.millisecondsSinceEpoch - remote.epochMs,
          equals(offset.inMilliseconds),
          reason: '$offset',
        );
      }
    });
  });
}
