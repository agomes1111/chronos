class TimeReference {
  /// Hardware Uptime Milliseconds
  /// - Set when network date time is stored
  /// - Used to calculate `deltaElapsed` = hardwareUptimeMs - currentUptimeMS(fetched at consult time)
  /// - Then the product of `networkDateTime` + deltaElapsed` will be currentTime
  final int hardwareUptimeMs;

  /// Network dateTime
  /// - Set when network date time is fetched
  final DateTime networkDateTime;

  /// Network [latency] when `networkDateTime` is set
  final int? networkLatency;

  new({
    required this.hardwareUptimeMs,
    required this.networkDateTime,
    this.networkLatency,
  });
}
