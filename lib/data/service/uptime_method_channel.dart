import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service responsible for invoking platform-native channels to retrieve
/// monotonic hardware uptime in milliseconds.
class UptimeMethodChannel {
  UptimeMethodChannel._internal();

  /// Singleton instance of [UptimeMethodChannel].
  static final UptimeMethodChannel instance = UptimeMethodChannel._internal();

  static const MethodChannel _channel = MethodChannel('chronify/uptime');

  /// Fetches the native monotonic uptime in milliseconds.
  ///
  /// Uses `SystemClock.elapsedRealtime()` on Android and
  /// `ProcessInfo.processInfo.systemUptime` on iOS.
  /// Returns `0` if invocation fails or platform is unsupported.
  Future<int> getUptimeMs() async {
    try {
      final dynamic rawUptime = await _channel.invokeMethod('getUptimeMs');

      if (rawUptime is int) {
        return rawUptime;
      } else if (rawUptime is double) {
        return rawUptime.toInt();
      }

      return 0;
    } on PlatformException catch (e) {
      debugPrint('Chronos: Failed to retrieve native uptime - ${e.message}');
      return 0;
    } on MissingPluginException {
      debugPrint(
        'Chronos: MethodChannel "chronify/uptime" not implemented on this platform.',
      );
      return 0;
    } catch (e) {
      debugPrint('Chronos: Unexpected error reading uptime - $e');
      return 0;
    }
  }
}
