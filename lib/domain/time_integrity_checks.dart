import 'package:chronos/data/entity/time_integrity.dart';

class TimeIntegrityChecks {
  TimeIntegrity compareSideDelta({
    required int hwUptimeDelta,
    required int osDateTimeDelta,
    required int tolerance,
  }) {
    final Duration hwDelta = Duration(milliseconds: hwUptimeDelta);
    final Duration osDelta = Duration(milliseconds: osDateTimeDelta);

    final int diffMs = (hwDelta.inMilliseconds - osDelta.inMilliseconds).abs();

    if (diffMs == 0) {
      return const Trusted();
    } else if (diffMs < tolerance) {
      return const UpRight();
    } else {
      return const Inconsistent();
    }
  }

  TimeIntegrity evaluateUptimeDeltaThreshold({
    required int initalUptimeMs,
    required int currentUptimeMs,
    int threshold = 1000,
  }) {
    final int elapsed = currentUptimeMs - initalUptimeMs;

    // 1. Monotonic Regression Check (1) NEGATIVE DELTA
    // - usually means device reboot / reset
    if (elapsed < 0) {
      return const Inconsistent(
        reason: 'Hardware uptime regressed (power-off or reboot detected): negative uptimeMS delta',
      );
    }
    // 2. Monotonic Regression Check (2) minimum threshold (def: 1000 ms [1s])
    // - evaluates abnormallys
    if (elapsed >= threshold) {
      return const Trusted();
    }

    return const UpRight();
  }
}
