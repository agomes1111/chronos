import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service responsible for invoking platform-native channels to retrieve
/// monotonic hardware uptime in milliseconds.
class UptimeMethodChannel {
  UptimeMethodChannel._internal();

  /// Singleton instance of [UptimeMethodChannel].
  static final UptimeMethodChannel instance = UptimeMethodChannel._internal();

  static const MethodChannel _channel = MethodChannel('chronos/uptime');

  /// Fetches native monotonic uptime in milliseconds.
  ///
  /// Returns `0` if invocation fails, platform is unsupported, or native code throws.
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
      // Handles native FlutterError thrown from Swift/Kotlin
      switch (e.code) {
        case 'SYSTEM_UPTIME_FAILED':
          debugPrint(
            'Chronify [iOS Error]: Kernel uptime failed - ${e.message}',
          );
          break;
        case 'INVALID_METHOD':
          debugPrint('Chronify: Invalid method call - ${e.message}');
          break;
        default:
          debugPrint('Chronify: PlatformException [${e.code}] -${e.message}');
      }
      return 0;
    } on MissingPluginException {
      // Handles un-implemented platforms (e.g., running unit tests without channel mocks)
      debugPrint(
        'Chronify: MethodChannel "chronify/uptime" not implemented on this platform.',
      );
      return 0;
    } catch (e) {
      debugPrint('Chronify: Unexpected error reading uptime - $e');
      return 0;
    }
  }
}
