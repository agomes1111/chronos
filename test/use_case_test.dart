import 'package:chronos/chronos.dart';
import 'package:chronos/controller.dart';
import 'package:chronos/data/entity/confidence.dart';
import 'package:chronos/data/entity/true_time.dart';
import 'package:chronos/domain/calcs.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chronos/data/entity/time_integrity.dart';
import 'package:chronos/domain/time_integrity_checks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('chronos/uptime');
  late ChronosController controller;

  setUp(() {
    controller = ChronosController(Calcs(), TimeIntegrityChecks());
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  group('UseCaseTest - simultaneous consults', () {
    test('returns Trusted when hardware and OS deltas match exactly', () async {
      final uptimeQueue = [10000, 15000, 20000, 25000];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'getUptimeMs') {
              return uptimeQueue.removeAt(0);
            }
            return null;
          });

      final syncTime = DateTime.utc(2026, 10, 8, 12, 30, 30);
      await controller.sync(networkDateTime: syncTime, networkLatencyMs: 3000);

      // call 0
      TrueTime trueTime = await controller.getTrueTime();
      expect(
        trueTime.time,
        equals(
          DateTime.utc(2026, 10, 8, 12, 30, 35).add(
            /**network rtt/latency */
            const Duration(milliseconds: 3000),
          ),
        ),
      );
      expect(trueTime.confidence, isA<HighConfidence>());
      expect(trueTime.confidence.timeIntegrity, isA<Trusted>());

      // call 1
      trueTime = await controller.getTrueTime();
      expect(
        trueTime.time,
        equals(
          DateTime.utc(2026, 10, 8, 12, 30, 40).add(
            /**network rtt/latency */
            const Duration(milliseconds: 3000),
          ),
        ),
      );
      expect(trueTime.confidence, isA<HighConfidence>());
      expect(trueTime.confidence.timeIntegrity, isA<Trusted>());

      // call 2
      trueTime = await controller.getTrueTime();
      expect(
        trueTime.time,
        equals(
          DateTime.utc(2026, 10, 8, 12, 30, 45).add(
            /**network rtt/latency */
            const Duration(milliseconds: 3000),
          ),
        ),
      );
      expect(trueTime.confidence, isA<HighConfidence>());
      expect(trueTime.confidence.timeIntegrity, isA<Trusted>());
    });
  });
}
