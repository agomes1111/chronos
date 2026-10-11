/// Formats an offset as `±hh:mm` (e.g. `-03:00`, `+05:30`).
String formatUtcOffset(Duration offset) {
  final totalMinutes = offset.inMinutes;
  final sign = totalMinutes < 0 ? '-' : '+';
  final abs = totalMinutes.abs();
  final hh = (abs ~/ 60).toString().padLeft(2, '0');
  final mm = (abs % 60).toString().padLeft(2, '0');

  return '$sign$hh:$mm';
}

/// ISO-8601 string made of [fields] (wall-clock fields) plus [offset],
/// e.g. `2026-10-09T18:05:31.411065-03:00`. A trailing `Z` on [fields] is
/// dropped, since the offset replaces it.
String isoWithOffset(DateTime fields, Duration offset) {
  final iso = fields.toIso8601String();
  final base = iso.endsWith('Z') ? iso.substring(0, iso.length - 1) : iso;

  return '$base${formatUtcOffset(offset)}';
}
