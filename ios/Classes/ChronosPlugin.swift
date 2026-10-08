import Flutter
import UIKit

public class ChronosPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "chronify/uptime", binaryMessenger: registrar.messenger())
    let instance = ChronosPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "getUptimeMs" {
      let uptimeMs = Int64(ProcessInfo.processInfo.systemUptime * 1000)
      result(uptimeMs)
    } else {
      result(FlutterMethodNotImplemented)
    }
  }
}