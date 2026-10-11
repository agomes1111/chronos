import 'package:flutter/foundation.dart' show immutable;

/// The anchor captured when the server time was synced. Every calculated
/// instant is this anchor plus the hardware uptime elapsed since the sync.
@immutable
class TimeReference {
  /// Hardware uptime (ms) read at the moment of the sync.
  final int hardwareUptimeMs;

  /// Real server instant at the sync, always UTC.
  final DateTime networkDateTime;

  /// Network latency (ms) to add to the calculated time. Null counts as 0.
  final int? networkLatency;

  /// Server UTC offset at the sync (e.g. `Duration(hours: -3)`). Only needed
  /// to build a `RemoteZonedTime`; null means the server zone is unknown.
  final Duration? serverUtcOffset;

  TimeReference({
    required this.hardwareUptimeMs,
    required this.networkDateTime,
    this.networkLatency,
    this.serverUtcOffset,
  }) : assert(
         networkDateTime.isUtc,
         'TimeReference.networkDateTime must be a UTC DateTime',
       );
}
