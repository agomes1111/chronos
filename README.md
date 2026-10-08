<!-- ## Hardware uptime milliseconds integrity check
                              ┌─────────────────────────────────────────┐
                              │ Calculate elapsed = current - initial   │
                              └────────────────────┬────────────────────┘
                                                   │
                                            Is elapsed < 0?
                                                   │
                         ┌─────────────────────────┴─────────────────────────┐
                         │ YES                                               │ NO
                         ▼                                                   ▼
         【 1. Negative Delta Check 】                             Is elapsed >= threshold?
         • Return `Inconsistent`                                             │
         • Reason: Power-off / reboot detected             ┌─────────────────┴─────────────────┐
                                                           │ YES                               │ NO
                                                           ▼                                   ▼
                                           【 2. Trusted Range 】               【 3. Immediate / Fast Call 】
                                           • Return `Trusted`                   • Return `UpRight`
                                           • `elapsed >= 1000 ms`               • `0 <= elapsed < 1000 ms`

Here is the complete, clean Markdown text for `README.md` formatted without any nesting or rendering issues:

```markdown -->
# Chronos ⏳

<!-- [![pub package](https://img.shields.io/pub/v/chronos.svg)](https://pub.dev/packages/chronos) -->
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Chronos**  is a zero-third-party-dependency Flutter and Dart package designed to deliver tamper-proof UTC time calculations (`TrueTime`). 

By pairing trusted network time anchors with native platform monotonic hardware clocks (`SystemClock.elapsedRealtime()` on Android and `ProcessInfo.systemUptime` on iOS), Chronos insulates your application from wall-clock manipulations (such as users manually changing device time in Settings) and detects hardware reboots or resets.

---

## Features 🚀

- 🔒 **Tamper-Proof True Time:** Calculates current UTC using hardware tick deltas, bypassing `DateTime.now()` wall-clock manipulation.
- ⚡ **Native Monotonic Hardware Uptime:** Direct `MethodChannel` integrations with Android's `SystemClock.elapsedRealtime()` and iOS's `ProcessInfo.systemUptime`.
- 🛡️ **Heuristic Integrity Validation:** Evaluates time state changes into explicit `Confidence` tiers (`HighConfidence`, `MediumConfidence`, `LowConfidence`, `LowestConfidence`).
- 🔄 **Reboot & Cold-Boot Detection:** Flags negative uptime regressions caused by device power-offs or restarts.
- 🔑 **Ideal for Security-Sensitive Tasks:** Built specifically for gating time-based passcodes (TOTP), dynamic QR tickets, and offline time checks.

---

## Architecture 📐

- **Trusted Network Time (API/NTP)** ──( sync )──> **TimeReference Anchor**
- **Current Monotonic Hardware Tick** ──( elapsed )──> **TrueTime Calculation**
- **AccuracyValidation Engine** ──> **Confidence Tiers** (`HighConfidence` vs `LowConfidence` / `LowestConfidence`)

---

<!-- ## Installation 📦

Add `chronos` to your `pubspec.yaml`:

```yaml
dependencies:
  chronos: ^1.0.0

```

Or run:

```bash
flutter pub add chronos

``` -->

<!-- --- -->

## Getting Started 🏁

### 1. Synchronize Network Time Baseline

Anchor a trusted server UTC timestamp during app startup or after fetching an API response:

```dart
import 'package:chronos/chronos.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Fetch trusted UTC time from your API or NTP server
  final DateTime serverUtc = DateTime.utc(2026, 10, 8, 12, 0, 0);
  const int estimatedLatencyMs = 45;

  // 2. Sync Chronos engine
  await Chronos.instance.sync(
    networkDateTime: serverUtc,
    networkLatencyMs: estimatedLatencyMs,
  );

  runApp(const MyApp());
}

```

### 2. Retrieve TrueTime and Enforce Confidence Rules

Request `TrueTime` anywhere in your application and pattern match on the confidence result:

```dart
import 'package:chronos/chronos.dart';

Future<void> evaluateAccessControl() async {
  try {
    final TrueTime trueTime = await Chronos.instance.now();

    print('Calculated True UTC: ${trueTime.time}');
    print('Tampered Flag: ${trueTime.confidence.timeIntegrity.tampered}');

    switch (trueTime.confidence) {
      case HighConfidence():
      case MediumConfidence():
        // Safe to generate TOTP codes or render time-critical passes
        _grantAccess(trueTime.time);

      case LowConfidence():
        // Hardware reboot detected; prompt network re-synchronization
        _promptNetworkResync();

      case LowestConfidence():
        // Explicit clock rollback / tampering detected; restrict features
        _lockSensitiveFeatures();
    }
  } on StateError catch (e) {
    print('Chronos is not synchronized: ${e.message}');
  }
}

```

---

## Integrity & Confidence States 🛡️

| Confidence Tier | Underlying Integrity | Status | Action |
| --- | --- | --- | --- |
| **`HighConfidence`** | `Trusted` | Exact match / verified delta | Allow all operations (e.g., TOTP generation). |
| **`MediumConfidence`** | `UpRight` | Sub-threshold delta / rapid check | Allow operations; schedule background sync. |
| **`LowConfidence`** | `Inconsistent` | Uptime regression / reboot detected | Prompt background/foreground network re-sync. |
| **`LowestConfidence`** | `Tampered` | Clock manipulation or anomaly | Lock sensitive time-gated features. |

---

## Running Unit Tests 🧪

Chronos includes comprehensive unit test suites covering hardware channel mocking, sequential uptime deltas, and wall-clock tampering heuristics:

```bash
flutter test

```

---

## License 📄

This project is licensed under the MIT License - see the [LICENSE](https://www.google.com/search?q=LICENSE) file for details.