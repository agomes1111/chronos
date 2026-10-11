import 'package:chronos/data/final.dart';
import 'package:chronos/data/server_time_parser.dart';

class IntervalHelper {
  static int evaluateInterval({
    required DateTime reference,
    required DateTime first,
    required DateTime last,
  }) {
    assert(reference.isUtc);
    assert(first.isUtc);
    assert(last.isUtc);

    final bool isBefore = reference.isBefore(first);
    final bool isAfter = reference.isAfter(last);
    final bool isBetween = !isBefore && !isAfter;

    print('[INTERVAL-HELPER] :: ref:$reference i:$first  x l: $last');
    print('[INTERVAL-HELPER] :: between:$isBetween i:$isBefore  x l: $isAfter');

    if (isBetween) {
      return INTERVAL_BETWEEN;
    } else if (isBefore) {
      return INTERVAL_BEFORE;
    } else {
      return INTERVAL_AFTER;
    }
  }

  static Future<int> evaluateIntervalString({
    required DateTime reference,
    required String first,
    required String last,
    required String zoneName,
  }) async {
    assert(reference.isUtc);

    final _first = ServerTimeParser.parse(date: first, timezone: zoneName);
    final _last = ServerTimeParser.parse(date: last, timezone: zoneName);

    return await evaluateInterval(
      reference: reference,
      first: _first.utc,
      last: _last.utc,
    );

    // final bool isBefore = reference.isBefore(_first.utc);
    // final bool isAfter = reference.isBefore(_last.utc);
    // final bool isBetween = !isBefore && !isAfter;

    // if (isBetween) {
    //   return INTERVAL_BETWEEN;
    // } else if (isBefore) {
    //   return INTERVAL_BEFORE;
    // } else {
    //   return INTERVAL_AFTER;
    // }
  }
}
