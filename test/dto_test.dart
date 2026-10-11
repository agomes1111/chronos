import 'dart:convert';

import 'package:chronos/data/entity/time_reference.dart';
import 'package:chronos/data/time_reference_dto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final utc = DateTime.utc(2026, 10, 9, 21, 5, 31, 411, 65);

  TimeReference full() => TimeReference(
    hardwareUptimeMs: 10000,
    networkDateTime: utc,
    networkLatency: 45,
    serverUtcOffset: const Duration(hours: -3),
    serverUtcOffsetZoneName: 'America/Sao_Paulo',
  );

  group('TimeReferenceDto', () {
    test('round trip keeps every field', () {
      final r = TimeReferenceDto.fromCache(TimeReferenceDto.toCache(full()));

      expect(r.hardwareUptimeMs, equals(10000));
      expect(r.networkDateTime, equals(utc));
      expect(r.networkDateTime.isUtc, isTrue);
      expect(r.networkLatency, equals(45));
      expect(r.serverUtcOffset, equals(const Duration(hours: -3)));
      expect(r.serverUtcOffsetZoneName, equals('America/Sao_Paulo'));
    });

    test('round trip keeps microsecond precision', () {
      final r = TimeReferenceDto.fromCache(TimeReferenceDto.toCache(full()));
      expect(
        r.networkDateTime.microsecondsSinceEpoch,
        equals(utc.microsecondsSinceEpoch),
      );
    });

    test('round trip with null optionals', () {
      final ref = TimeReference(hardwareUptimeMs: 1, networkDateTime: utc);
      final r = TimeReferenceDto.fromCache(TimeReferenceDto.toCache(ref));

      expect(r.networkLatency, isNull);
      expect(r.serverUtcOffset, isNull);
      expect(r.serverUtcOffsetZoneName, isNull);
    });

    test('offsets that are not whole hours survive (India +5:30)', () {
      final ref = TimeReference(
        hardwareUptimeMs: 1,
        networkDateTime: utc,
        serverUtcOffset: const Duration(hours: 5, minutes: 30),
      );
      final r = TimeReferenceDto.fromCache(TimeReferenceDto.toCache(ref));

      expect(r.serverUtcOffset, equals(const Duration(hours: 5, minutes: 30)));
    });

    test('the offset is stored in milliseconds', () {
      final json = jsonDecode(TimeReferenceDto.toCache(full()));
      expect(json['server_utc_offset'], equals(-10800000));
    });

    test('garbage throws FormatException', () {
      expect(() => TimeReferenceDto.fromCache('%%%'), throwsFormatException);
    });

    test('valid JSON with missing fields throws', () {
      expect(() => TimeReferenceDto.fromCache('{}'), throwsA(anything));
    });
  });
}
