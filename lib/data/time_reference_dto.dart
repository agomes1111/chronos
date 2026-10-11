import 'dart:convert';

import 'package:chronos/data/entity/time_reference.dart';

class TimeReferenceDto {
  static Map<String, dynamic> toJSON(TimeReference timeRef) => {
    'hw_uptime_ms': timeRef.hardwareUptimeMs,
    'network_date_time': timeRef.networkDateTime.toIso8601String(),
    'network_latency': timeRef.networkLatency,
    'server_utc_offset': timeRef.serverUtcOffset?.inMilliseconds,
    'server_utc_offset_name': timeRef.serverUtcOffsetZoneName,
  };

  static String toCache(TimeReference timeRef) => jsonEncode(toJSON(timeRef));

  static TimeReference fromCache(String cacheJsonString) {
    final j = jsonDecode(cacheJsonString);
    return TimeReference(
      hardwareUptimeMs: j['hw_uptime_ms'],
      networkDateTime: DateTime.parse(j['network_date_time']),
      networkLatency: j['network_latency'],
      serverUtcOffset: j['server_utc_offset'] != null
          ? Duration(milliseconds: j['server_utc_offset'] as int)
          : null,
      serverUtcOffsetZoneName: j['server_utc_offset_name'],
    );
  }
}
