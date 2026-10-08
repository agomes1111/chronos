import 'package:chronos/data/entity/confidence.dart';

class TrueTime {
  final DateTime time;
  final Confidence confidence;

  TrueTime({required this.time, required this.confidence});
}
