import Flutter
import UIKit

public class SwiftChronosPlugin: NSObject, FlutterPlugin {
    
    // Error Codes
    private static let errInvalidMethod = "INVALID_METHOD"
    private static let errSystemUptimeFailed = "SYSTEM_UPTIME_FAILED"
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "chronify/uptime",
            binaryMessenger: registrar.messenger()
        )
        let instance = SwiftChronosPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getUptimeMs":
            // Dispatch off main thread to prevent UI thread blocking
            DispatchQueue.global(qos: .userInitiated).async {
                let uptimeSeconds = ProcessInfo.processInfo.systemUptime
                
                // Guard against invalid/negative values from kernel
                guard uptimeSeconds >= 0 else {
                    DispatchQueue.main.async {
                        result(FlutterError(
                            code: SwiftChronosPlugin.errSystemUptimeFailed,
                            message: "System uptime returned a negative value.",
                            details: nil
                        ))
                    }
                    return
                }
                
                // Convert seconds (Double) to milliseconds (Int64) safely
                let uptimeMsDouble = uptimeSeconds * 1000.0
                
                // Check against Int64 bounds before casting
                if uptimeMsDouble <= Double(Int64.max) {
                    let uptimeMs = Int64(uptimeMsDouble)
                    DispatchQueue.main.async {
                        result(uptimeMs)
                    }
                } else {
                    DispatchQueue.main.async {
                        result(FlutterError(
                            code: SwiftChronosPlugin.errSystemUptimeFailed,
                            message: "System uptime value overflowed Int64 representation.",
                            details: nil
                        ))
                    }
                }
            }
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}