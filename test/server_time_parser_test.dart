import 'package:chronos/data/server_time_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Real server response: wall clock in America/Sao_Paulo (UTC-3, no DST).
  const sampleDate = '2026-10-09 18:05:31.411065';
  const sampleZone = 'America/Sao_Paulo';

  // 18:05:31.411065 at UTC-3 == 21:05:31.411065Z
  final expectedUtc = DateTime.utc(2026, 10, 9, 21, 5, 31, 411, 65);

  group('case 3: no offset in the string (wall clock + zone name)', () {
    test('converts the real server sample to UTC and offset', () {
      final result = ServerTimeParser.parse(
        date: sampleDate,
        timezone: sampleZone,
      );

      expect(result.utc, equals(expectedUtc));
      expect(result.utc.isUtc, isTrue);
      expect(result.offset, equals(const Duration(hours: -3)));
    });

    test('keeps millisecond and microsecond precision', () {
      final result = ServerTimeParser.parse(
        date: sampleDate,
        timezone: sampleZone,
      );

      expect(result.utc.millisecond, equals(411));
      expect(result.utc.microsecond, equals(65));
    });

    test('same wall-clock fields resolve differently per zone', () {
      final utc = ServerTimeParser.parse(date: sampleDate, timezone: 'UTC');
      final tokyo = ServerTimeParser.parse(
        date: sampleDate,
        timezone: 'Asia/Tokyo',
      );

      expect(utc.utc, equals(DateTime.utc(2026, 10, 9, 18, 5, 31, 411, 65)));
      expect(utc.offset, equals(Duration.zero));
      expect(tokyo.utc, equals(DateTime.utc(2026, 10, 9, 9, 5, 31, 411, 65)));
      expect(tokyo.offset, equals(const Duration(hours: 9)));
    });

    test('honours DST of the server zone', () {
      // New York: EDT (UTC-4) in October, EST (UTC-5) in January.
      final october = ServerTimeParser.parse(
        date: '2026-10-09 18:05:31',
        timezone: 'America/New_York',
      );
      final january = ServerTimeParser.parse(
        date: '2026-01-15 18:05:31',
        timezone: 'America/New_York',
      );

      expect(october.utc, equals(DateTime.utc(2026, 10, 9, 22, 5, 31)));
      expect(october.offset, equals(const Duration(hours: -4)));
      expect(january.utc, equals(DateTime.utc(2026, 1, 15, 23, 5, 31)));
      expect(january.offset, equals(const Duration(hours: -5)));
    });

    test('a "T" without an offset is still wall clock', () {
      final result = ServerTimeParser.parse(
        date: '2026-10-09T18:05:31.411065',
        timezone: sampleZone,
      );

      expect(result.utc, equals(expectedUtc));
      expect(result.offset, equals(const Duration(hours: -3)));
    });

    test('missing timezone throws ArgumentError', () {
      expect(
        () => ServerTimeParser.parse(date: sampleDate),
        throwsArgumentError,
      );
    });

    test('unknown timezone name throws', () {
      expect(
        () => ServerTimeParser.parse(
          date: sampleDate,
          timezone: 'Mars/Olympus_Mons',
        ),
        throwsA(anything),
      );
    });

    test('malformed date throws FormatException', () {
      expect(
        () => ServerTimeParser.parse(date: 'not-a-date', timezone: sampleZone),
        throwsFormatException,
      );
    });
  });

  group('case 1: Z suffix', () {
    test('is UTC with zero offset and needs no timezone', () {
      final result = ServerTimeParser.parse(
        date: '2026-10-09T21:05:31.411065Z',
      );

      expect(result.utc, equals(expectedUtc));
      expect(result.utc.isUtc, isTrue);
      expect(result.offset, equals(Duration.zero));
    });

    test('lowercase z and space separator are accepted', () {
      final result = ServerTimeParser.parse(
        date: '2026-10-09 21:05:31.411065z',
      );

      expect(result.utc, equals(expectedUtc));
      expect(result.offset, equals(Duration.zero));
    });
  });

  group('case 2: numeric offset in the string', () {
    test('±hh:mm gives the same instant and keeps the offset', () {
      final result = ServerTimeParser.parse(
        date: '2026-10-09T18:05:31.411065-03:00',
      );

      expect(result.utc, equals(expectedUtc));
      expect(result.offset, equals(const Duration(hours: -3)));
    });

    test('±hhmm and ±hh are accepted', () {
      expect(
        ServerTimeParser.parse(date: '2026-10-09T18:05:31.411065-0300').offset,
        equals(const Duration(hours: -3)),
      );
      expect(
        ServerTimeParser.parse(date: '2026-10-09T18:05:31.411065-03').offset,
        equals(const Duration(hours: -3)),
      );
    });

    test('space separator works with an offset', () {
      final result = ServerTimeParser.parse(
        date: '2026-10-09 18:05:31.411065-03:00',
      );

      expect(result.utc, equals(expectedUtc));
    });

    test('half-hour offsets keep sign on the minutes', () {
      final india = ServerTimeParser.parse(date: '2026-10-09T18:05:31+05:30');
      final newfoundland = ServerTimeParser.parse(
        date: '2026-10-09T18:05:31-03:30',
      );

      expect(india.utc, equals(DateTime.utc(2026, 10, 9, 12, 35, 31)));
      expect(india.offset, equals(const Duration(hours: 5, minutes: 30)));
      expect(newfoundland.utc, equals(DateTime.utc(2026, 10, 9, 21, 35, 31)));
      expect(
        newfoundland.offset,
        equals(const Duration(hours: -3, minutes: -30)),
      );
    });

    test('the offset in the string wins over a given timezone name', () {
      final result = ServerTimeParser.parse(
        date: '2026-10-09T18:05:31.411065-03:00',
        timezone: 'Asia/Tokyo',
      );

      expect(result.utc, equals(expectedUtc));
      expect(result.offset, equals(const Duration(hours: -3)));
    });

    test('epoch is identical to the same instant written with Z', () {
      final withOffset = ServerTimeParser.parse(
        date: '2026-10-09T18:05:31-03:00',
      ).utc;
      final withZ = ServerTimeParser.parse(date: '2026-10-09T21:05:31Z').utc;

      expect(
        withOffset.millisecondsSinceEpoch,
        equals(withZ.millisecondsSinceEpoch),
      );
    });
  });

  group('OS timezone independence', () {
    test(
      'naive DateTime.parse(...).toUtc() is only right in the server zone',
      () {
        // This is the bug the parser avoids. Under an OS timezone other than
        // UTC-3 the naive approach is wrong, e.g. run with TZ=Asia/Tokyo.
        final osOffset = DateTime.parse(sampleDate).timeZoneOffset;
        if (osOffset == const Duration(hours: -3)) {
          markTestSkipped(
            'OS timezone equals the server zone; run with TZ=Asia/Tokyo',
          );
          return;
        }

        final naive = DateTime.parse(sampleDate).toUtc();
        expect(naive, isNot(equals(expectedUtc)));

        // ...while the parser is still correct.
        expect(
          ServerTimeParser.parse(date: sampleDate, timezone: sampleZone).utc,
          equals(expectedUtc),
        );
      },
    );
  });

  group('case 3 with an offset-style zone (e.g. PHP timezone_type 1)', () {
    test('a ±hh:mm zone is applied as a fixed offset', () {
      final result = ServerTimeParser.parse(
        date: sampleDate,
        timezone: '-03:00',
      );

      expect(result.utc, equals(expectedUtc));
      expect(result.offset, equals(const Duration(hours: -3)));
    });

    test('±hhmm, ±hh and half-hour zones are accepted', () {
      expect(
        ServerTimeParser.parse(date: sampleDate, timezone: '-0300').utc,
        equals(expectedUtc),
      );
      expect(
        ServerTimeParser.parse(date: sampleDate, timezone: '-03').utc,
        equals(expectedUtc),
      );

      final india = ServerTimeParser.parse(
        date: '2026-10-09 18:05:31',
        timezone: '+0530',
      );
      expect(india.utc, equals(DateTime.utc(2026, 10, 9, 12, 35, 31)));
      expect(india.offset, equals(const Duration(hours: 5, minutes: 30)));
    });

    test('a positive offset zone subtracts from the wall clock', () {
      final result = ServerTimeParser.parse(
        date: '2026-10-09 18:05:31',
        timezone: '+09:00',
      );

      expect(result.utc, equals(DateTime.utc(2026, 10, 9, 9, 5, 31)));
      expect(result.offset, equals(const Duration(hours: 9)));
    });

    test('gives the same result as the equivalent IANA zone', () {
      final byOffset = ServerTimeParser.parse(
        date: sampleDate,
        timezone: '-03:00',
      );
      final byName = ServerTimeParser.parse(
        date: sampleDate,
        timezone: sampleZone,
      );

      expect(byOffset.utc, equals(byName.utc));
      expect(byOffset.offset, equals(byName.offset));
    });
  });
}
