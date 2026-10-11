import 'package:chronos/data/entity/utc_offset.dart';
import 'package:flutter/foundation.dart' show immutable;

import 'package:chronos/data/entity/confidence.dart';
import 'package:chronos/data/entity/instant.dart';

/// The [instant] seen in the server's zone, using the server UTC offset
/// captured at sync. Based on server time + server zone, never on the device
/// clock or OS timezone.
///
/// It only exists when the server offset is known: the controller throws
/// instead of building one when it could not be evaluated.
///
/// Use [instant] (or the delegating getters) for logic and [wallClock] /
/// [toIso8601String] for presentation.
@immutable
class RemoteZonedTime {
  final Instant instant;

  /// Server UTC offset captured at sync.
  final Duration offset;

  const RemoteZonedTime({required this.instant, required this.offset});

  DateTime get utc => instant.utc;
  int get epochMs => instant.epochMs;
  int get epochSeconds => instant.epochSeconds;
  Confidence get confidence => instant.confidence;

  /// Wall-clock fields at [offset] (e.g. 18:05:31 for 21:05:31Z at -03:00).
  /// The `isUtc` flag is true only because Dart cannot hold an arbitrary
  /// offset: this is NOT an instant, use [instant] for comparisons.
  DateTime get wallClock => instant.utc.add(offset);

  /// e.g. `2026-10-09T18:05:31.411065-03:00`.
  String toIso8601String() => isoWithOffset(wallClock, offset);
}
