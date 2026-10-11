import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:chronos/controller.dart';
import 'package:chronos/data/entity/instant.dart';
import 'package:chronos/data/entity/local_zoned_time.dart';
import 'package:chronos/data/entity/remote_zoned_time.dart';
import 'package:chronos/data/entity/time_reference.dart';
import 'package:chronos/domain/calcs.dart';
import 'package:chronos/domain/time_integrity_checks.dart';

/// Top-level facade for the Chronos time synchronization engine.
///
/// Sync once against the server, then read the calculated "now" as one of
/// three views of the same server-anchored instant:
///  - [now]: [Instant], independent of any zone (TOTP, expiry, time gates).
///  - [nowRemoteZoned]: [RemoteZonedTime], in the server's zone.
///  - [nowLocalZoned]: [LocalZonedTime], in the device's OS timezone.
class Chronos {
  Chronos._internal()
    : _controller = ChronosController(Calcs(), TimeIntegrityChecks());

  @visibleForTesting
  Chronos.withController(this._controller);

  /// Singleton instance of [Chronos].
  static final Chronos instance = Chronos._internal();

  final ChronosController _controller;

  /// Returns the current active network time reference anchor, if initialized.
  TimeReference? get reference => _controller.ref;

  /// Whether the network reference anchor has been synchronized.
  bool get isSynced => _controller.ref != null;

  /// Synchronizes the local hardware tick baseline against a trusted network
  /// timestamp.
  ///
  /// [networkDateTime] - The real server instant (it is normalized to UTC).
  /// It must already be a true instant: if your API returns a wall-clock
  /// string without an offset plus a zone name, use [syncFromString] instead.
  /// [serverUtcOffset] - Optional server UTC offset at that instant. Needed
  /// only for [nowRemoteZoned].
  /// [networkLatencyMs] - Optional network round-trip delay to offset latency
  /// drift.
  Future<void> sync({
    required DateTime networkDateTime,
    Duration? serverUtcOffset,
    int? networkLatencyMs,
  }) async {
    await _controller.sync(
      networkDateTime: networkDateTime,
      serverUtcOffset: serverUtcOffset,
      networkLatencyMs: networkLatencyMs,
    );
  }

  /// Synchronizes from the strings the API returns.
  ///
  /// [date] - e.g. `2026-10-09 18:05:31.411065` (wall clock), or a string
  /// that already carries `Z` or an offset like `-03:00`.
  /// [timezone] - Required only when [date] has no offset: an IANA name
  /// (`America/Sao_Paulo`) or an offset (`-03:00`).
  /// [networkLatencyMs] - Optional network round-trip delay.
  ///
  /// Throws (leaving the current reference untouched) a [FormatException] for
  /// a malformed date, an [ArgumentError] when the date has no offset and no
  /// [timezone] was given, and an error for an unknown zone name.
  Future<void> syncFromString({
    required String date,
    String? timezone,
    int? networkLatencyMs,
  }) async {
    await _controller.syncFromString(
      date: date,
      timezone: timezone,
      networkLatencyMs: networkLatencyMs,
    );
  }

  /// Calculates the current true time (server anchor + monotonic hardware
  /// ticks elapsed since the sync) and evaluates time integrity confidence.
  /// The result is independent of any zone and of the device clock.
  ///
  /// Throws a [StateError] if no sync has been done.
  Future<Instant> now() async {
    return await _controller.getInstant();
  }

  /// The same calculated now, seen in the server's zone.
  ///
  /// Throws a [StateError] if no sync has been done, or if the sync did not
  /// provide the server offset (the remote zone cannot be evaluated).
  Future<RemoteZonedTime> nowRemoteZoned() async {
    return await _controller.getRemoteZonedTime();
  }

  /// The same calculated now, seen in the device's current OS timezone.
  ///
  /// Throws a [StateError] if no sync has been done.
  Future<LocalZonedTime> nowLocalZoned() async {
    return await _controller.getLocalZonedTime();
  }

  Future<bool> isBetween({
    String? firstDateTimeString,
    String? lastDateTimeString,
    DateTime? first,
    DateTime? last,
  }) async => await _controller.isBetween(
    firstDateTimeString: firstDateTimeString,
    lastDateTimeString: lastDateTimeString,
    first: first,
    last: last,
  );

  Future<bool> isBefore({
    String? firstDateTimeString,
    String? lastDateTimeString,
    DateTime? first,
    DateTime? last,
  }) async => await _controller.isBefore(
    firstDateTimeString: firstDateTimeString,
    lastDateTimeString: lastDateTimeString,
    first: first,
    last: last,
  );

  Future<bool> isAfter({
    String? firstDateTimeString,
    String? lastDateTimeString,
    DateTime? first,
    DateTime? last,
  }) async => await _controller.isAfter(
    firstDateTimeString: firstDateTimeString,
    lastDateTimeString: lastDateTimeString,
    first: first,
    last: last,
  );
}
