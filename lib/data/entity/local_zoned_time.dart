import 'package:chronos/data/entity/utc_offset.dart';
import 'package:flutter/foundation.dart' show immutable;

import 'package:chronos/data/entity/confidence.dart';
import 'package:chronos/data/entity/instant.dart';

/// The [instant] seen in the device's current OS timezone. The instant is
/// still the server-anchored true time; only the presentation follows the OS.
///
/// It is a snapshot: the zone is read from the OS when it is built, so it is
/// the one entity that changes if the user changes the device timezone.
@immutable
class LocalZonedTime {
  final Instant instant;

  /// The instant as a local [DateTime] (fields in the OS timezone).
  final DateTime dateTime;

  const LocalZonedTime._(this.instant, this.dateTime);

  factory LocalZonedTime.fromInstant(Instant instant) =>
      LocalZonedTime._(instant, instant.utc.toLocal());

  DateTime get utc => instant.utc;
  int get epochMs => instant.epochMs;
  int get epochSeconds => instant.epochSeconds;
  Confidence get confidence => instant.confidence;

  /// Device offset at this instant (DST-aware).
  Duration get offset => dateTime.timeZoneOffset;

  /// OS abbreviation (e.g. `-03`). Dart does not expose the IANA id.
  String get timeZoneName => dateTime.timeZoneName;

  /// e.g. `2026-10-09T18:05:31.411065-03:00`.
  String toIso8601String() => isoWithOffset(dateTime, offset);
}
