import 'package:flutter/foundation.dart';

@immutable
sealed class TimeIntegrity {
  final bool tampered;
  final String? reason;

  const TimeIntegrity({required this.tampered, this.reason});
}

abstract class Tampered extends TimeIntegrity {
  const Tampered({super.tampered = true, required super.reason});
}

class Inconsistent extends Tampered {
  const Inconsistent({super.reason = 'inconsistent'});
}

class UpRight extends TimeIntegrity {
  const UpRight({super.tampered = false, super.reason = 'upright'});
}

class Trusted extends TimeIntegrity {
  const Trusted({super.tampered = false, super.reason = 'accurate'});
}
