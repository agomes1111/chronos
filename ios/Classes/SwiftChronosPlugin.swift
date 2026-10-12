import Flutter
import UIKit

public class SwiftChronosPlugin: NSObject, FlutterPlugin {

    private static let channelName = "chronos/uptime" // must match the Dart side
    private static let errSystemUptimeFailed = "SYSTEM_UPTIME_FAILED"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = SwiftChronosPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getUptimeMs":
            // Monotonic, keeps counting while the device sleeps (like Android's
            // elapsedRealtime) and resets on reboot. Returns 0 on failure.
            let nanos = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)

            guard nanos != 0 else {
                result(FlutterError(
                    code: SwiftChronosPlugin.errSystemUptimeFailed,
                    message: "Monotonic clock read failed.",
                    details: nil
                ))
                return
            }

            result(Int64(nanos / 1_000_000))

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}