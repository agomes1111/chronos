# Chronos ⏳

<!-- [![pub package](https://img.shields.io/pub/v/chronos.svg)](https://pub.dev/packages/chronos) -->
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Chronos** is a Flutter and Dart package that delivers tamper-proof, server-anchored time (`TrueTime`).

It pairs a trusted network time anchor with the platform's monotonic hardware clock (`SystemClock.elapsedRealtime()` on Android, `ProcessInfo.systemUptime` on iOS). Your app is insulated from wall-clock manipulation (the user editing the time in Settings), from timezone changes (the user traveling or switching zones), and from app restarts. Hardware reboots are detected and reported as lower confidence.

---

## Features 🚀

- 🔒 **Tamper-proof true time:** the current instant is the server anchor plus the hardware uptime elapsed since the sync. `DateTime.now()` is never read.
- 🌍 **Immune to OS clock and timezone changes:** only the anchor and the uptime delta count.
- 🧭 **Three views of the same instant:** zone-independent `Instant`, `RemoteZonedTime` (server zone) and `LocalZonedTime` (device zone). They always agree.
- 🧾 **Sync straight from your API strings:** `syncFromString` parses `date` + `timezone` (IANA name or offset) exactly as the server returns them.
- 💾 **Persistent reference:** the anchor is cached on every sync and restored on the next app start, so closing the app does not lose it.
- 🛡️ **Integrity validation:** every read carries a `Confidence` tier (`HighConfidence`, `MediumConfidence`, `LowConfidence`, `LowestConfidence`).
- 🔄 **Reboot detection:** an uptime regression (power-off, restart) lowers the confidence until the app syncs again.
- ⏱️ **Interval helpers:** `isBefore`, `isBetween`, `isAfter` and `evaluateInterval` for time-gated features.
- 🔑 **Built for security-sensitive work:** TOTP, dynamic QR tickets, expiry checks and offline time gates.

---

## Architecture 📐

- **Trusted network time (API/NTP)** ──( sync )──> **TimeReference anchor** ──( cache )──> restored on next start
- **Current monotonic hardware tick** ──( elapsed )──> **True time calculation** ──> **Instant**
- **Integrity engine** ──> **Confidence tiers**
- **Instant** ──> `RemoteZonedTime` (server zone) / `LocalZonedTime` (device zone)

---

## Installation 📦

Chronos is not on pub.dev yet. Add it from Git in your `pubspec.yaml`:

```yaml
dependencies:
  chronos:
    git:
      url: https://github.com/agomes1111/chronos
```

<!-- Once published:

```bash
flutter pub add chronos
```
-->

---

## Getting Started 🏁

### 1. Initialize and restore the cached reference

Call `ensureInitialized` once at startup. If a reference was saved by a previous run, it is restored and `isSynced` is `true` right away.

```dart
import 'package:chronos/chronos.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Chronos.instance.ensureInitialized();

  if (!Chronos.instance.isSynced) {
    // First run (or no valid cache): sync with your server.
  }

  runApp(const MyApp());
}
```

### 2. Synchronize with the server

**Option A: from the strings your API returns (recommended).**

```dart
// API response: { "date": "2026-10-09 18:05:31.411065", "timezone": "America/Sao_Paulo" }
await Chronos.instance.syncFromString(
  date: '2026-10-09 18:05:31.411065',
  timezone: 'America/Sao_Paulo',
  networkLatencyMs: 45,
);
```

Accepted shapes for `date` and `timezone`:

| `date` | `timezone` | Result |
| --- | --- | --- |
| `2026-10-09 18:05:31.411065` (wall clock, no offset) | `America/Sao_Paulo` or `-03:00` | Wall clock resolved in that zone |
| `2026-10-09T21:05:31.411065Z` | not needed | UTC, server offset `0` |
| `2026-10-09T18:05:31.411065-03:00` | not needed | Offset taken from the string |

Errors (the current reference is left untouched):

- `FormatException`: malformed date.
- `ArgumentError`: the date has no offset and no `timezone` was given.
- An error for an unknown zone name.

**Option B: from an instant you already trust (for example NTP).**

```dart
await Chronos.instance.sync(
  networkDateTime: DateTime.utc(2026, 10, 8, 12, 0, 0),
  serverUtcOffset: const Duration(hours: -3), // optional
  networkLatencyMs: 45,                       // optional
);
```

`networkDateTime` must already be a true instant. If your API returns a wall clock plus a zone name, use `syncFromString`. `serverUtcOffset` is only needed for `nowRemoteZoned()`.

Every successful sync is persisted to the cache. A failed sync never overwrites it.

### 3. Read the time

```dart
final Instant instant = await Chronos.instance.now();
final RemoteZonedTime remote = await Chronos.instance.nowRemoteZoned();
final LocalZonedTime local = await Chronos.instance.nowLocalZoned();
```

| Method | Returns | Use it for |
| --- | --- | --- |
| `now()` | `Instant` (UTC, zone independent) | TOTP, expiry, time gates |
| `nowRemoteZoned()` | `RemoteZonedTime` (server zone) | Showing the server's wall clock |
| `nowLocalZoned()` | `LocalZonedTime` (device OS zone) | Showing the user's local time |

All three come from the same calculation, so `utc`, `epochMs` and `confidence` are identical across them.

Errors:

- All three throw `StateError` if no sync has been done.
- `nowRemoteZoned()` also throws `StateError` if the sync did not provide a server offset. `now()` and `nowLocalZoned()` still work in that case.

### 4. Enforce confidence rules

```dart
Future<void> evaluateAccessControl() async {
  try {
    final Instant instant = await Chronos.instance.now();

    print('Calculated true UTC: ${instant.utc}');
    print('Tampered flag: ${instant.confidence.timeIntegrity.tampered}');

    switch (instant.confidence) {
      case HighConfidence():
      case MediumConfidence():
        // Safe to generate TOTP codes or render time-critical passes
        _grantAccess(instant);

      case LowConfidence():
        // Hardware reboot detected: sync with the server again
        _promptNetworkResync();

      case LowestConfidence():
        // Clock rollback / tampering detected: restrict features
        _lockSensitiveFeatures();
    }
  } on StateError catch (e) {
    print('Chronos is not synchronized: ${e.message}');
  }
}
```

---

## Use cases 🧩

### TOTP

Use the epoch seconds of the `Instant`. The counter is the same whatever zone is shown and whatever the device clock says.

```dart
final instant = await Chronos.instance.now();
final int counter = instant.epochSeconds ~/ 30; // RFC 6238, 30 s step
```

### Time-gated features and intervals

Pass the interval boundaries as strings in the server's zone. This needs a reference created with `syncFromString` and a `timezone`.

```dart
final open = await Chronos.instance.isBetween(
  firstDateTimeString: '2026-10-09 16:05:31.411065',
  lastDateTimeString: '2026-10-09 21:05:31.411065',
);

final notYet = await Chronos.instance.isBefore(
  firstDateTimeString: '2026-10-09 16:05:31.411065',
  lastDateTimeString: '2026-10-09 21:05:31.411065',
);

final over = await Chronos.instance.isAfter(
  firstDateTimeString: '2026-10-09 16:05:31.411065',
  lastDateTimeString: '2026-10-09 21:05:31.411065',
);
```

`isBefore` means the current server time is before the first boundary, and `isAfter` means it is past the last one. `evaluateInterval` returns the same result as an integer constant. You can also pass `DateTime first` and `last` instead of strings.

### Showing the time to the user

```dart
final remote = await Chronos.instance.nowRemoteZoned();
print(remote.toIso8601String()); // 2026-10-09T18:05:36.411065-03:00
```

---

## Cache 💾

- Each `sync` and `syncFromString` saves the reference (anchor, uptime at sync, latency, server offset and zone name) through `CacheService`.
- `ensureInitialized()` loads it back. The restored reference keeps counting from the original sync as long as the device has not rebooted.
- If the device rebooted while the app was closed, the first read after the restart returns `LowConfidence` until you sync again.
- If the cached value cannot be parsed, Chronos starts unsynced instead of crashing. Sync again to recover.
- `ensureInitialized()` must be awaited before the first read. A reference restored from the cache is replaced as soon as you sync.

---

## Integrity & Confidence States 🛡️

| Confidence Tier | Underlying Integrity | Status | Action |
| --- | --- | --- | --- |
| **`HighConfidence`** | `Trusted` | Exact match / verified delta | Allow all operations (e.g., TOTP generation). |
| **`MediumConfidence`** | `UpRight` | Sub-threshold delta / rapid check | Allow operations; schedule background sync. |
| **`LowConfidence`** | `Inconsistent` | Uptime regression / reboot detected | Prompt network re-sync. |
| **`LowestConfidence`** | `Tampered` | Clock manipulation or anomaly | Lock sensitive time-gated features. |

---

## Running Unit Tests 🧪

The suites cover the native uptime channel (`chronos/uptime`), sequential uptime deltas, sync from API strings, device clock and timezone tampering, intervals, and the cache (stored, restored, reboot after restore, corrupt data).

```bash
flutter test
```

Tests mock only the edges: the uptime `MethodChannel` and `CacheService` (with `mocktail`). The controller and calculations run for real.

---

## License 📄

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.