import 'package:chronos/data/entity/confidence.dart';
import 'package:chronos/data/entity/instant.dart'; // <- adjust paths
import 'package:chronos/data/entity/local_zoned_time.dart';
import 'package:chronos/data/entity/remote_zoned_time.dart';
import 'package:chronos/data/entity/time_integrity.dart';
import 'package:chronos/data/entity/time_reference.dart';
import 'package:chronos/data/final.dart';
import 'package:chronos/data/server_time_parser.dart';
import 'package:chronos/data/service/cache_service.dart';
import 'package:chronos/data/service/uptime_method_channel.dart';
import 'package:chronos/data/time_reference_dto.dart';
import 'package:chronos/domain/calcs.dart';
import 'package:chronos/domain/interval_helper.dart';
import 'package:chronos/domain/time_integrity_checks.dart';

class ChronosController {
  final Calcs calcs;
  final TimeIntegrityChecks integrityChecks;
  final CacheService cacheService;

  ChronosController(this.calcs, this.integrityChecks, this.cacheService);

  TimeReference? ref;

  Future<int> get uptime async =>
      await UptimeMethodChannel.instance.getUptimeMs();

  Future<void> ensureInitialized() async {
    await cacheService.ensureInitialized();
    final c = await cacheService.getString(TIME_REF_CACHE_KEY);

    if (c != null) {
      try {
        ref = TimeReferenceDto.fromCache(c);
      } catch (_) {
        ref = null; // corrupt cache: start unsynced and wait for a sync
      }
    }
  }

  /// [networkDateTime] is the real server instant and [serverUtcOffset] the
  /// server's offset at that instant, both from `ServerTimeParser.parse`.
  /// The offset is only needed for [getRemoteZonedTime].
  Future<void> sync({
    required DateTime networkDateTime,
    Duration? serverUtcOffset,
    int? networkLatencyMs,
  }) async {
    ref = TimeReference(
      hardwareUptimeMs: await uptime,
      networkDateTime: networkDateTime.toUtc(),
      networkLatency: networkLatencyMs,
      serverUtcOffset: serverUtcOffset,
    );

    cacheService.storeString(
      k: TIME_REF_CACHE_KEY,
      v: TimeReferenceDto.toCache(ref!),
    );
  }

  /// Syncs from the strings the API returns: a [date] (with or without an
  /// offset) and, when the date has none, the [timezone] (IANA name or
  /// offset). See `ServerTimeParser.parse` for the accepted shapes.
  ///
  /// Throws (and leaves the current reference untouched) when the strings
  /// cannot be parsed.
  Future<void> syncFromString({
    required String date,
    String? timezone,
    int? networkLatencyMs,
  }) async {
    // Read the uptime BEFORE parsing: parsing (the first call also loads the
    // tz database) must not shift the anchor.
    final int uptimeAtSync = await uptime;

    final ParsedServerTime parsed = ServerTimeParser.parse(
      date: date,
      timezone: timezone,
    );

    ref = TimeReference(
      hardwareUptimeMs: uptimeAtSync,
      networkDateTime: parsed.utc,
      networkLatency: networkLatencyMs,
      serverUtcOffset: parsed.offset,
      serverUtcOffsetZoneName: timezone,
    );

    cacheService.storeString(
      k: TIME_REF_CACHE_KEY,
      v: TimeReferenceDto.toCache(ref!),
    );
  }

  /// Calculated "now": server anchor + hardware uptime elapsed since the
  /// sync + network latency. Independent of any zone. Use this one for TOTP,
  /// expiry and any time-gated logic.
  Future<Instant> getInstant() async => _compute(_requireRef());

  /// The same calculated now, seen in the server's zone. Throws [StateError]
  /// when the sync did not provide the server offset (not evaluable).
  Future<RemoteZonedTime> getRemoteZonedTime() async {
    final reference = _requireRef();
    final offset = reference.serverUtcOffset;
    if (offset == null) {
      throw StateError('server_utc_offset_was_not_provided_on_sync');
    }

    return RemoteZonedTime(instant: await _compute(reference), offset: offset);
  }

  /// The same calculated now, seen in the device's current OS timezone.
  Future<LocalZonedTime> getLocalZonedTime() async =>
      LocalZonedTime.fromInstant(await getInstant());

  Future<int> evaluateInterval({
    String? firstDateTimeString,
    String? lastDateTimeString,
    DateTime? first,
    DateTime? last,
  }) async {
    assert(ref != null);
    if (first != null && last != null) {
      assert(ref?.serverUtcOffsetZoneName != null);
      return await IntervalHelper.evaluateInterval(
        reference: (await getInstant()).utc,
        first: first,
        last: last,
      );
    } else if (firstDateTimeString != null && lastDateTimeString != null) {
      assert(ref?.serverUtcOffsetZoneName != null);
      return await IntervalHelper.evaluateIntervalString(
        reference: (await getInstant()).utc,
        first: firstDateTimeString,
        last: lastDateTimeString,
        zoneName: ref!.serverUtcOffsetZoneName!,
      );
    } else {
      throw StateError('must_provide_at_least_one_set_of_dates');
    }
  }

  Future<bool> isBetween({
    String? firstDateTimeString,
    String? lastDateTimeString,
    DateTime? first,
    DateTime? last,
  }) async {
    assert(ref != null);
    if (first != null && last != null) {
      assert(ref?.serverUtcOffsetZoneName != null);
      return (await IntervalHelper.evaluateInterval(
            reference: (await getInstant()).utc,
            first: first,
            last: last,
          ) ==
          INTERVAL_BETWEEN);
    } else if (firstDateTimeString != null && lastDateTimeString != null) {
      assert(ref?.serverUtcOffsetZoneName != null);
      return (await IntervalHelper.evaluateIntervalString(
            reference: (await getInstant()).utc,
            first: firstDateTimeString,
            last: lastDateTimeString,
            zoneName: ref!.serverUtcOffsetZoneName!,
          ) ==
          INTERVAL_BETWEEN);
    } else {
      throw StateError('must_provide_at_least_one_set_of_dates');
    }
  }

  Future<bool> isBefore({
    String? firstDateTimeString,
    String? lastDateTimeString,
    DateTime? first,
    DateTime? last,
  }) async {
    assert(ref != null);
    if (first != null && last != null) {
      assert(ref?.serverUtcOffsetZoneName != null);
      return (await IntervalHelper.evaluateInterval(
            reference: (await getInstant()).utc,
            first: first,
            last: last,
          ) ==
          INTERVAL_BEFORE);
    } else if (firstDateTimeString != null && lastDateTimeString != null) {
      assert(ref?.serverUtcOffsetZoneName != null);
      return (await IntervalHelper.evaluateIntervalString(
            reference: (await getInstant()).utc,
            first: firstDateTimeString,
            last: lastDateTimeString,
            zoneName: ref!.serverUtcOffsetZoneName!,
          ) ==
          INTERVAL_BEFORE);
    } else {
      throw StateError('must_provide_at_least_one_set_of_dates');
    }
  }

  Future<bool> isAfter({
    String? firstDateTimeString,
    String? lastDateTimeString,
    DateTime? first,
    DateTime? last,
  }) async {
    assert(ref != null);
    if (first != null && last != null) {
      assert(ref?.serverUtcOffsetZoneName != null);
      return (await IntervalHelper.evaluateInterval(
            reference: (await getInstant()).utc,
            first: first,
            last: last,
          ) ==
          INTERVAL_AFTER);
    } else if (firstDateTimeString != null && lastDateTimeString != null) {
      assert(ref?.serverUtcOffsetZoneName != null);
      return (await IntervalHelper.evaluateIntervalString(
            reference: (await getInstant()).utc,
            first: firstDateTimeString,
            last: lastDateTimeString,
            zoneName: ref!.serverUtcOffsetZoneName!,
          ) ==
          INTERVAL_AFTER);
    } else {
      throw StateError('must_provide_at_least_one_set_of_dates');
    }
  }

  TimeReference _requireRef() {
    final reference = ref;
    if (reference == null) {
      throw StateError('network_time_reference_has_not_been_initialized');
    }
    return reference;
  }

  /// The single place where elapsed time is calculated. All three entities
  /// are built from the [Instant] it returns, so they always agree.
  Future<Instant> _compute(TimeReference reference) async {
    final int currentUptime = await uptime;

    final Duration elapsed = calcs.getElapsedTime(
      initial: reference.hardwareUptimeMs,
      last: currentUptime,
    );

    final DateTime calculatedNow = calcs.evaluateTrueTime(
      ref: reference.networkDateTime,
      elapsed: elapsed,
      networkLatencyMs: reference.networkLatency ?? 0,
    );

    final TimeIntegrity integrity = integrityChecks
        .evaluateUptimeDeltaThreshold(
          initalUptimeMs: reference.hardwareUptimeMs,
          currentUptimeMs: currentUptime,
        );

    final Confidence confidence = switch (integrity) {
      Inconsistent() => LowConfidence(timeIntegrity: integrity),
      Tampered() => LowestConfidence(timeIntegrity: integrity),
      UpRight() => MediumConfidence(timeIntegrity: integrity),
      Trusted() => HighConfidence(timeIntegrity: integrity),
    };

    return Instant(
      utc: calculatedNow.toUtc(),
      hwUptimeMsAtSync: reference.hardwareUptimeMs,
      hwUptimeMsNow: currentUptime,
      confidence: confidence,
    );
  }
}
