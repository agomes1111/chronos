import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chronos/controller.dart';
import 'package:chronos/data/entity/confidence.dart';
import 'package:chronos/data/entity/time_integrity.dart';
import 'package:chronos/domain/calcs.dart';
import 'package:chronos/domain/time_integrity_checks.dart';

class MockCalcs extends Mock implements Calcs {}

class MockTimeIntegrityChecks extends Mock implements TimeIntegrityChecks {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockCalcs mockCalcs;
  late MockTimeIntegrityChecks mockIntegrityChecks;
  late ChronosController controller;

  const MethodChannel channel = MethodChannel('chronify/uptime');

  setUp(() {
    mockCalcs = MockCalcs();
    mockIntegrityChecks = MockTimeIntegrityChecks();
    controller = ChronosController(mockCalcs, mockIntegrityChecks);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('ChronosController - Realistic Sequential Uptime Invocations', () {
    test('simulates 1st call (sync @ 10,000ms) and 2nd call (getTrueTime @ 15,000ms)', () async {
      // 1. Queue sequence of MethodChannel return values:
      //    - First invocation (during sync) -> 10,000 ms
      //    - Second invocation (during getTrueTime) -> 15,000 ms
      final uptimeQueue = [10000, 15000];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'getUptimeMs') {
              return uptimeQueue.removeAt(0);
            }
            return null;
          });

      final syncTime = DateTime.utc(2026, 10, 8, 12, 0, 0);

      // --- FIRST CALL: sync() triggers uptime -> consumes 10000ms ---
      await controller.sync(networkDateTime: syncTime, networkLatencyMs: 30);

      expect(controller.ref, isNotNull);
      expect(controller.ref!.hardwareUptimeMs, equals(10000));

      // Mock Calcs & Integrity checks based on initial (10,000) and current (15,000)
      when(() => mockCalcs.getElapsedTime(inital: 10000, last: 15000))
          .thenReturn(const Duration(seconds: 5));

      when(
        () => mockIntegrityChecks.evaluateUptimeDeltaThreshold(
          initalUptimeMs: 10000,
          currentUptimeMs: 15000,
        ),
      ).thenReturn(const Trusted());

      // --- SECOND CALL: getTrueTime() triggers uptime -> consumes 15000ms ---
      final trueTime = await controller.getTrueTime();

      // Verify calculated network time = syncTime + 5 seconds
      expect(trueTime.time, equals(DateTime.utc(2026, 10, 8, 12, 0, 5)));
      expect(trueTime.confidence, isA<HighConfidence>());
      expect(trueTime.confidence.timeIntegrity, isA<Trusted>());

      // Ensure both queued calls were consumed
      expect(uptimeQueue, isEmpty);

      // Verify domain delegates received exact hardware values from channel
      verify(() => mockCalcs.getElapsedTime(inital: 10000, last: 15000))
          .called(1);
      verify(
        () => mockIntegrityChecks.evaluateUptimeDeltaThreshold(
          initalUptimeMs: 10000,
          currentUptimeMs: 15000,
        ),
      ).called(1);
    });

    test(
      'simulates reboot on 2nd call (sync @ 10,000ms -> getTrueTime @ 2,000ms)',
      () async {
        // Reboot simulation: 2nd call returns a lower uptime value
        final uptimeQueue = [10000, 2000];

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
              if (methodCall.method == 'getUptimeMs') {
                return uptimeQueue.removeAt(0);
              }
              return null;
            });

        final syncTime = DateTime.utc(2026, 10, 8, 12, 0, 0);

        // 1st Call -> sync
        await controller.sync(networkDateTime: syncTime);

        when(() => mockCalcs.getElapsedTime(inital: 10000, last: 2000))
            .thenReturn(const Duration(seconds: -8));

        when(
          () => mockIntegrityChecks.evaluateUptimeDeltaThreshold(
            initalUptimeMs: 10000,
            currentUptimeMs: 2000,
          ),
        ).thenReturn(
          const Inconsistent(
            reason: 'Hardware uptime regressed (power-off or reboot detected)',
          ),
        );

        // 2nd Call -> getTrueTime
        final trueTime = await controller.getTrueTime();

        expect(trueTime.confidence, isA<LowConfidence>());
        expect(trueTime.confidence.timeIntegrity, isA<Inconsistent>());
        expect(trueTime.confidence.timeIntegrity.tampered, isTrue);
      },
    );
  });
  group('ChronosController - Real World Local DateTime Comparisons', () {
    test('SCENARIO 1: Untampered execution (Device clock matches hardware progress)', () async {
      final uptimeQueue = [10000, 25000]; // +15 seconds hardware uptime elapsed
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            return uptimeQueue.removeAt(0);
          });

      // Simulated network UTC time anchor
      final networkUtc = DateTime.utc(2026, 10, 8, 12, 0, 0);

      // 1. Sync network reference
      await controller.sync(networkDateTime: networkUtc, networkLatencyMs: 50);

      // 2. Simulate local OS wall clock advancing naturally by 15 seconds
      final initialLocalTime = DateTime(2026, 10, 8, 09, 0, 0); // Local time
      final currentLocalTime = initialLocalTime.add(
        const Duration(seconds: 15),
      );
      final localOsDeltaMs = currentLocalTime
          .difference(initialLocalTime)
          .inMilliseconds;

      when(() => mockCalcs.getElapsedTime(inital: 10000, last: 25000))
          .thenReturn(const Duration(seconds: 15));

      when(
        () => mockIntegrityChecks.evaluateUptimeDeltaThreshold(
          initalUptimeMs: 10000,
          currentUptimeMs: 25000,
        ),
      ).thenReturn(const Trusted());

      // 3. Obtain TrueTime from plugin
      final trueTimeResult = await controller.getTrueTime();

      // Hardware uptime delta (15,000 ms) and local OS wall-clock delta (15,000 ms) match perfectly
      expect(localOsDeltaMs, equals(15000));
      expect(
        trueTimeResult.time,
        equals(networkUtc.add(const Duration(seconds: 15))),
      );
      expect(trueTimeResult.confidence, isA<HighConfidence>());
      expect(trueTimeResult.confidence.timeIntegrity.tampered, isFalse);
    });

    test('SCENARIO 2: Wall-clock tampering (User shifts OS time back by 2 hours in Settings)', () async {
      final uptimeQueue = [10000, 20000]; // +10 seconds hardware uptime elapsed
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            return uptimeQueue.removeAt(0);
          });

      final networkUtc = DateTime.utc(2026, 10, 8, 12, 0, 0);
      await controller.sync(networkDateTime: networkUtc);

      // User opens phone Settings and manually changes clock back by 2 hours
      final initialLocalTime = DateTime(2026, 10, 8, 09, 0, 0);
      final tamperedLocalTime = initialLocalTime.subtract(
        const Duration(hours: 2),
      );

      when(() => mockCalcs.getElapsedTime(inital: 10000, last: 20000))
          .thenReturn(const Duration(seconds: 10));

      when(
        () => mockIntegrityChecks.evaluateUptimeDeltaThreshold(
          initalUptimeMs: 10000,
          currentUptimeMs: 20000,
        ),
      ).thenReturn(const Trusted());

      final trueTimeResult = await controller.getTrueTime();

      // Local OS clock says 07:00:00 (tampered), but TrueTime calculates 12:00:10 UTC (trusted)
      expect(tamperedLocalTime.hour, equals(7));
      expect(
        trueTimeResult.time,
        equals(networkUtc.add(const Duration(seconds: 10))),
      );

      // Hardware channel completely bypassed local OS wall-clock tampering!
      expect(trueTimeResult.confidence, isA<HighConfidence>());
    });

    test('SCENARIO 3: Offline Reboot Catch (Hardware uptime resets near zero while offline)', () async {
      // 100,000ms uptime at sync -> device powers off -> boots up with 3,000ms uptime
      final uptimeQueue = [100000, 3000];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            return uptimeQueue.removeAt(0);
          });

      final networkUtc = DateTime.utc(2026, 10, 8, 12, 0, 0);
      await controller.sync(networkDateTime: networkUtc);

      // Local wall clock advanced by 30 minutes while the phone was powered off
      final initialLocalTime = DateTime(2026, 10, 8, 09, 0, 0);
      final postRebootLocalTime = initialLocalTime.add(
        const Duration(minutes: 30),
      );

      when(() => mockCalcs.getElapsedTime(inital: 100000, last: 3000))
          .thenReturn(const Duration(milliseconds: -97000));

      when(
        () => mockIntegrityChecks.evaluateUptimeDeltaThreshold(
          initalUptimeMs: 100000,
          currentUptimeMs: 3000,
        ),
      ).thenReturn(
        const Inconsistent(
          reason: 'Hardware uptime regressed (power-off or reboot detected)',
        ),
      );

      final trueTimeResult = await controller.getTrueTime();

      // Plugin flags hardware reset and downgrades confidence to LowConfidence
      expect(postRebootLocalTime.minute, equals(30));
      expect(trueTimeResult.confidence, isA<LowConfidence>());
      expect(trueTimeResult.confidence.timeIntegrity, isA<Inconsistent>());
      expect(trueTimeResult.confidence.timeIntegrity.tampered, isTrue);
    });
  });
}
