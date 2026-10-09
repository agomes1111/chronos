import 'package:chronos/data/entity/confidence.dart';
import 'package:chronos/data/entity/time_integrity.dart';
import 'package:chronos/data/entity/time_reference.dart';
import 'package:chronos/data/entity/true_time.dart';
import 'package:chronos/data/service/uptime_method_channel.dart';
import 'package:chronos/domain/calcs.dart';
import 'package:chronos/domain/time_integrity_checks.dart';

class ChronosController {
  final Calcs calcs;
  final TimeIntegrityChecks integrityChecks;

  ChronosController(this.calcs, this.integrityChecks);

  TimeReference? ref;

  Future<int> get uptime async =>
      await UptimeMethodChannel.instance.getUptimeMs();

  Future<void> sync({
    required DateTime networkDateTime,
    int? networkLatencyMs,
  }) async {
    ref = TimeReference(
      hardwareUptimeMs: await uptime,
      networkDateTime: networkDateTime,
      networkLatency: networkLatencyMs,
    );
  }

  Future<TrueTime> getTrueTime() async {
    final _ref = ref;
    if (_ref == null) {
      throw StateError('network_time_reference_has_not_been_initialized');
    }

    final int _currentUptime = await uptime;

    final Duration elapsed = calcs.getElapsedTime(
      initial: _ref.hardwareUptimeMs,
      last: _currentUptime,
    );

    final DateTime calculatedTime = calcs.evaluateTrueTime(
      ref: _ref.networkDateTime,
      elapsed: elapsed,
      networkLatencyMs: _ref.networkLatency ?? 0,
    );

    final TimeIntegrity integrity = integrityChecks
        .evaluateUptimeDeltaThreshold(
          initalUptimeMs: _ref.hardwareUptimeMs,
          currentUptimeMs: _currentUptime,
        );

    final Confidence confidence = switch (integrity) {
      Inconsistent() => LowConfidence(timeIntegrity: integrity),
      Tampered() => LowestConfidence(timeIntegrity: integrity),
      UpRight() => MediumConfidence(timeIntegrity: integrity),
      Trusted() => HighConfidence(timeIntegrity: integrity),
    };

    return TrueTime(time: calculatedTime, confidence: confidence);
  }
}
