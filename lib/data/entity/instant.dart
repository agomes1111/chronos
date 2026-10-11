import 'package:flutter/foundation.dart' show immutable;

import 'package:chronos/data/entity/confidence.dart';

/// A true-time instant, independent of any zone (remote or local).
///
/// Calculated from the server time anchor plus the hardware uptime elapsed
/// since the sync. It is the base of [RemoteZonedTime] and [LocalZonedTime],
/// which wrap it with a zone offset for presentation.
///
/// Use this one for TOTP, expiry and any time-gated logic.
@immutable
class Instant {
  /// The instant as an immutable UTC [DateTime].
  final DateTime utc;

  /// Hardware uptime (ms) captured when the server time was synced.
  final int hwUptimeMsAtSync;

  /// Hardware uptime (ms) captured when the server time was synced.
  final int hwUptimeMsNow;

  /// Integrity/confidence of this calculation.
  final Confidence confidence;

  Instant({
    required this.utc,
    required this.hwUptimeMsAtSync,
    required this.hwUptimeMsNow,
    required this.confidence,
  }) : assert(utc.isUtc, 'Instant.utc must be a UTC DateTime');

  /// Milliseconds since the Unix epoch (what TOTP needs).
  int get epochMs => utc.millisecondsSinceEpoch;

  int get epochSeconds => epochMs ~/ 1000;
}
