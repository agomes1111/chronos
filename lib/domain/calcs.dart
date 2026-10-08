class Calcs {
  Duration getElapsedTime({required int inital, required int last}) {
    final int elapsed = inital - last;
    return Duration(milliseconds: elapsed);
  }
}
