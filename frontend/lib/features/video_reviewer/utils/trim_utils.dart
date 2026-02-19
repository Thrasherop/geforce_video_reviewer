import 'package:flutter/material.dart';

RangeValues clampTrimRange(RangeValues values, double durationSeconds) {
  final double safeMax = (durationSeconds.isFinite && durationSeconds > 0)
      ? durationSeconds
      : 0;
  final double start = values.start.clamp(0, safeMax).toDouble();
  final double end = values.end.clamp(start, safeMax).toDouble();
  return RangeValues(start, end);
}

Duration defaultStartPositionForDuration(
  double durationSeconds,
  double startPositionPercent,
) {
  if (!durationSeconds.isFinite || durationSeconds <= 0) {
    return Duration.zero;
  }
  final double percent = startPositionPercent.clamp(0, 100).toDouble();
  final int targetMs = ((durationSeconds * percent) / 100 * 1000).round();
  return Duration(milliseconds: targetMs);
}
