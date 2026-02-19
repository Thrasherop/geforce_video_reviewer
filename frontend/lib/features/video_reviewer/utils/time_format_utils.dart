String formatSeconds(double seconds) {
  final int totalMs = (seconds * 1000).round();
  final int hours = totalMs ~/ 3600000;
  final int minutes = (totalMs % 3600000) ~/ 60000;
  final int secs = (totalMs % 60000) ~/ 1000;
  final int millis = totalMs % 1000;
  final String hh = hours.toString().padLeft(2, '0');
  final String mm = minutes.toString().padLeft(2, '0');
  final String ss = secs.toString().padLeft(2, '0');
  final String mmm = millis.toString().padLeft(3, '0');
  return '$hh:$mm:$ss.$mmm';
}
