import 'package:chronos/controller.dart';
import 'package:chronos/data/entity/time_reference.dart';
import 'package:chronos/data/entity/true_time.dart';
import 'package:chronos/domain/calcs.dart';
import 'package:chronos/domain/time_integrity_checks.dart';

/// Top-level facade for the Chronos time synchronization engine.
class Chronos {
  Chronos._internal();

  /// Singleton instance of [Chronos].
  static final Chronos instance = Chronos._internal();

  final ChronosController _controller = ChronosController(
    Calcs(),
    TimeIntegrityChecks(),
  );

  /// Returns the current active network time reference anchor, if initialized.
  TimeReference? get reference => _controller.ref;

  /// Whether the network reference anchor has been synchronized.
  bool get isSynced => _controller.ref != null;

  /// Synchronizes the local hardware tick baseline against a trusted network timestamp.
  ///
  /// [networkDateTime] - The UTC timestamp retrieved from a trusted NTP or API server.
  /// [networkLatencyMs] - Optional network round-trip delay to offset latency drift.
  Future<void> sync({
    required DateTime networkDateTime,
    int? networkLatencyMs,
  }) async {
    await _controller.sync(
      networkDateTime: networkDateTime,
      networkLatencyMs: networkLatencyMs,
    );
  }

  /// Calculates current true UTC time using monotonic hardware ticks
  /// and evaluates time integrity confidence.
  ///
  /// Throws a [StateError] if [sync] has not been called prior.
  Future<TrueTime> now() async {
    return await _controller.getTrueTime();
  }
}
