import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Result of parsing a server date: the real instant (UTC) and the server's
/// UTC offset at that instant.
class ParsedServerTime {
  final DateTime utc;
  final Duration offset;

  const ParsedServerTime({required this.utc, required this.offset});
}

/// Parses the strings the API returns (a `date` plus optional zone info) into
/// a UTC instant + offset, without ever touching the device OS timezone.
///
/// What decides the case is whether the date string carries an offset (not
/// the presence of a `T`):
///  1. `...Z`                        -> UTC, offset zero.
///  2. `...-03:00` / `-0300` / `-03` -> instant from the string, offset kept.
///  3. no offset (wall clock)        -> the `timezone` string gives the offset:
///     an IANA name (`America/Sao_Paulo`, needs the tz database) or an
///     offset (`-03:00`, `+0530`, e.g. PHP `timezone_type` 1).
class ServerTimeParser {
  ServerTimeParser._();

  static bool _initialized = false;

  /// Loads the tz database once. Only needed for IANA zone names.
  static void ensureInitialized() {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    _initialized = true;
  }

  // Requires a time part before the offset, so a date-only string ending in
  // "-09" is not mistaken for an offset.
  static final RegExp _offsetPattern = RegExp(
    r'\d{2}:\d{2}(?::\d{2}(?:[.,]\d+)?)?\s*'
    r'(?:(?<utc>Z)|(?<sign>[+-])(?<hh>\d{2})(?::?(?<mm>\d{2}))?)$',
    caseSensitive: false,
  );

  // A zone string that is only an offset, e.g. "-03:00", "+0530", "+03".
  static final RegExp _offsetOnlyPattern = RegExp(
    r'^(?<sign>[+-])(?<hh>\d{2})(?::?(?<mm>\d{2}))?$',
  );

  static Duration _offsetFrom(RegExpMatch match) {
    final minutes =
        int.parse(match.namedGroup('hh')!) * 60 +
        int.parse(match.namedGroup('mm') ?? '0');

    return Duration(
      minutes: match.namedGroup('sign') == '-' ? -minutes : minutes,
    );
  }

  /// [timezone] is required only when [date] has no offset.
  ///
  /// Throws [FormatException] for a malformed date, [ArgumentError] when the
  /// date has no offset and no [timezone] was given, and
  /// `LocationNotFoundException` for an unknown zone name.
  static ParsedServerTime parse({required String date, String? timezone}) {
    final value = date.trim();
    final match = _offsetPattern.firstMatch(value);

    // Cases 1 and 2: Dart already applies the offset found in the string.
    if (match != null) {
      final utc = DateTime.parse(value).toUtc();

      return ParsedServerTime(
        utc: utc,
        offset: match.namedGroup('utc') != null
            ? Duration.zero
            : _offsetFrom(match),
      );
    }

    // Case 3: wall-clock fields in the server's zone.
    if (timezone == null) {
      throw ArgumentError('timezone_required_when_date_has_no_offset');
    }

    // Appending `Z` makes Dart read the fields as UTC (OS-independent).
    final wall = DateTime.parse('${value.replaceFirst(' ', 'T')}Z');

    // 3a: the zone is just an offset -> instant = wall clock - offset.
    final zoneOffset = _offsetOnlyPattern.firstMatch(timezone.trim());
    if (zoneOffset != null) {
      final offset = _offsetFrom(zoneOffset);

      return ParsedServerTime(utc: wall.subtract(offset), offset: offset);
    }

    // 3b: IANA name -> the tz database resolves the offset (DST-aware).
    ensureInitialized();

    final zoned = tz.TZDateTime(
      tz.getLocation(timezone),
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
      wall.second,
      wall.millisecond,
      wall.microsecond,
    );

    return ParsedServerTime(
      // Plain UTC DateTime (not a TZDateTime) for simple equality.
      utc: DateTime.fromMicrosecondsSinceEpoch(
        zoned.microsecondsSinceEpoch,
        isUtc: true,
      ),
      offset: zoned.timeZoneOffset,
    );
  }
}
