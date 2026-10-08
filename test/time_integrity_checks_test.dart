import 'package:flutter_test/flutter_test.dart';
import 'package:chronos/data/entity/time_integrity.dart';
import 'package:chronos/domain/time_integrity_checks.dart';

void main() {
  late TimeIntegrityChecks validator;

  setUp(() {
    validator = TimeIntegrityChecks();
  });

  group('TimeIntegrityChecks - compareSideDelta', () {
    test('returns Trusted when hardware and OS deltas match exactly', () {
      final result = validator.compareSideDelta(
        hwUptimeDelta: 5000,
        osDateTimeDelta: 5000,
        tolerance: 100,
      );

      expect(result, isA<Trusted>());
      expect(result.tampered, isFalse);
      expect(result.reason, equals('accurate'));
    });

    test('returns UpRight when absolute difference is within tolerance', () {
      // Diff = 50ms, Tolerance = 100ms
      final result = validator.compareSideDelta(
        hwUptimeDelta: 5050,
        osDateTimeDelta: 5000,
        tolerance: 100,
      );

      expect(result, isA<UpRight>());
      expect(result.tampered, isFalse);
      expect(result.reason, equals('upright'));
    });

    test(
      'returns UpRight when OS delta leads hardware delta within tolerance',
      () {
        // Diff = -40ms -> abs() = 40ms, Tolerance = 100ms
        final result = validator.compareSideDelta(
          hwUptimeDelta: 4960,
          osDateTimeDelta: 5000,
          tolerance: 100,
        );

        expect(result, isA<UpRight>());
        expect(result.tampered, isFalse);
      },
    );

    test('returns Inconsistent when difference equals tolerance boundary', () {
      // Note: `diffMs < tolerance` means exact tolerance match is Inconsistent
      final result = validator.compareSideDelta(
        hwUptimeDelta: 5100,
        osDateTimeDelta: 5000,
        tolerance: 100,
      );

      expect(result, isA<Inconsistent>());
      expect(result.tampered, isTrue);
      expect(result.reason, equals('inconsistent'));
    });

    test('returns Inconsistent when difference exceeds tolerance', () {
      // Diff = 500ms, Tolerance = 100ms
      final result = validator.compareSideDelta(
        hwUptimeDelta: 5500,
        osDateTimeDelta: 5000,
        tolerance: 100,
      );

      expect(result, isA<Inconsistent>());
      expect(result.tampered, isTrue);
    });

    test('handles zero tolerance correctly', () {
      final exactResult = validator.compareSideDelta(
        hwUptimeDelta: 1000,
        osDateTimeDelta: 1000,
        tolerance: 0,
      );
      expect(exactResult, isA<Trusted>());

      final driftedResult = validator.compareSideDelta(
        hwUptimeDelta: 1001,
        osDateTimeDelta: 1000,
        tolerance: 0,
      );
      expect(driftedResult, isA<Inconsistent>());
    });
  });

  group('evaluateUptimeDeltaThreshold', () {
    test('returns Inconsistent when hardware uptime regresses (reboot)', () {
      final result = validator.evaluateUptimeDeltaThreshold(
        initalUptimeMs: 3600000, // 1 hour uptime saved
        currentUptimeMs: 12000, // Booted 12 seconds ago
      );

      expect(result, isA<Inconsistent>());
      expect(result.tampered, isTrue);
      expect(result.reason, contains('negative uptimeMS delta'));
    });

    test('returns UpRight when elapsed duration is less than threshold (0 to 999 ms)', () {
      final result = validator.evaluateUptimeDeltaThreshold(
        initalUptimeMs: 5000000,
        currentUptimeMs: 5000450, // 450ms elapsed
        threshold: 1000,
      );

      expect(result, isA<UpRight>());
      expect(result.tampered, isFalse);
      expect(result.reason, equals('upright'));
    });

    test('returns UpRight when elapsed duration is exactly 0 ms', () {
      final result = validator.evaluateUptimeDeltaThreshold(
        initalUptimeMs: 5000000,
        currentUptimeMs: 5000000, // 0ms elapsed
      );

      expect(result, isA<UpRight>());
      expect(result.tampered, isFalse);
    });

    test('returns Trusted when elapsed duration equals threshold boundary (1000 ms)', () {
      final result = validator.evaluateUptimeDeltaThreshold(
        initalUptimeMs: 5000000,
        currentUptimeMs: 5001000, // Exactly 1000ms elapsed
        threshold: 1000,
      );

      expect(result, isA<Trusted>());
      expect(result.tampered, isFalse);
      expect(result.reason, equals('accurate'));
    });

    test('returns Trusted when elapsed duration exceeds threshold', () {
      final result = validator.evaluateUptimeDeltaThreshold(
        initalUptimeMs: 5000000,
        currentUptimeMs: 5005000, // 5000ms elapsed
        threshold: 1000,
      );

      expect(result, isA<Trusted>());
      expect(result.tampered, isFalse);
    });

    test('respects custom threshold parameter', () {
      final result = validator.evaluateUptimeDeltaThreshold(
        initalUptimeMs: 1000,
        currentUptimeMs: 1200, // 200ms elapsed
        threshold: 200, // Custom threshold = 200ms
      );

      expect(result, isA<Trusted>());
      expect(result.tampered, isFalse);
    });
  });
}
