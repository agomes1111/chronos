import 'package:chronos/controller.dart';
import 'package:chronos/data/entity/confidence.dart';
import 'package:chronos/data/entity/true_time.dart';
import 'package:chronos/domain/calcs.dart';
import 'package:chronos/domain/time_integrity_checks.dart';
import 'package:flutter/widgets.dart';

void main() async {
  // Ensure Flutter engine bindings are initialized for MethodChannel calls
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Instantiate domain dependencies and controller
  final calcs = Calcs();
  final integrityChecks = TimeIntegrityChecks();
  final chronos = ChronosController(calcs, integrityChecks);

  print('--- Chronos / Chronify Time Sync Initialization ---');

  // 2. Perform Network Time Synchronization
  // Anchor trusted UTC time (e.g., fetched from your API/NTP) against hardware uptime
  final DateTime serverUtcTime = DateTime.utc(2026, 10, 8, 12, 0, 0);
  const int estimatedLatencyMs = 42;

  await chronos.sync(
    networkDateTime: serverUtcTime,
    networkLatencyMs: estimatedLatencyMs,
  );

  print('Synced baseline: ${chronos.ref?.networkDateTime} UTC');
  print('Hardware Uptime mark: ${chronos.ref?.hardwareUptimeMs} ms\n');

  // Simulate app running for 5 seconds...
  await Future.delayed(const Duration(seconds: 2));

  // 3. Retrieve True Time & Validate Integrity
  try {
    final TrueTime trueTime = await chronos.getTrueTime();

    print('Calculated True UTC: ${trueTime.time}');
    print('Confidence Tier: ${trueTime.confidence.runtimeType}');
    print('Tampered Flag: ${trueTime.confidence.timeIntegrity.tampered}');
    print('Integrity Reason: ${trueTime.confidence.timeIntegrity.reason}\n');

    // 4. Pattern Match Confidence to Enforcement Business Rules
    switch (trueTime.confidence) {
      case HighConfidence():
      case MediumConfidence():
        print('✅ ACCESS GRANTED: High/Medium integrity verified.');
        _generateTotpPasscode(trueTime.time);

      case LowConfidence():
        print('⚠️ WARNING: Low integrity (reboot/reset detected).');
        _promptNetworkResync();

      case LowestConfidence():
        print('🚫 SECURITY ALERT: Device clock tampered or manipulated.');
        _lockSensitiveFeatures();
    }
  } catch (e) {
    print('Error calculating true time: $e');
  }
}

void _generateTotpPasscode(DateTime trustedUtc) {
  print('Generating TOTP code for timestamp: $trustedUtc');
}

void _promptNetworkResync() {
  print('Action: Prompting user for network re-synchronization.');
}

void _lockSensitiveFeatures() {
  print('Action: Locking TOTP wallet and invalidating local cache.');
}
