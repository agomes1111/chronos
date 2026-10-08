import 'package:chronos/data/entity/time_integrity.dart';
import 'package:flutter/foundation.dart';

@immutable
sealed class Confidence {
  final TimeIntegrity timeIntegrity;

  const Confidence({required this.timeIntegrity});
}

class HighConfidence extends Confidence {
  const HighConfidence({required super.timeIntegrity});
}

class MediumConfidence extends Confidence {
  const MediumConfidence({required super.timeIntegrity});
}

class LowConfidence extends Confidence {
  const LowConfidence({required super.timeIntegrity});
}

class LowestConfidence extends Confidence {
  const LowestConfidence({required super.timeIntegrity});
}
