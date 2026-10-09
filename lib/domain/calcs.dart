class Calcs {
  Duration getElapsedTime({required int initial, required int last}) {
    final int elapsed = last - initial;
    return Duration(milliseconds: elapsed.toInt());
  }

  DateTime evaluateTrueTime({
    required DateTime ref,
    required Duration elapsed,
    required int networkLatencyMs,
  }) => ref.add(elapsed).add(Duration(milliseconds: networkLatencyMs));
}
