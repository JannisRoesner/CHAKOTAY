import 'package:intl/intl.dart';

/// Datum eines Gottesdienstes. CHAPEL speichert Kalendertage als
/// Mitternacht UTC – deshalb wird das UTC-Datum angezeigt, damit der Tag in
/// keiner Zeitzone verrutscht.
DateTime serviceDay(DateTime date) {
  final utc = date.toUtc();
  return DateTime(utc.year, utc.month, utc.day);
}

String formatServiceDate(DateTime date) =>
    DateFormat('EEEE, d. MMMM y', 'de').format(serviceDay(date));

String formatShortDate(DateTime date) =>
    DateFormat('d. MMM y', 'de').format(serviceDay(date));

String formatMonthShort(DateTime date) => DateFormat(
  'MMM',
  'de',
).format(serviceDay(date)).replaceAll('.', '').toUpperCase();

String formatDateTime(DateTime date) =>
    DateFormat('d. MMM y, HH:mm', 'de').format(date.toLocal());

String formatBytes(int bytes) {
  const units = ['Bytes', 'KB', 'MB', 'GB'];
  if (bytes < 1024) return '$bytes Bytes';
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 ? 0 : 1;
  return '${NumberFormat.decimalPatternDigits(locale: 'de', decimalDigits: digits).format(value)} ${units[unit]}';
}

/// `m:ss` bzw. `h:mm:ss`.
String formatDuration(Duration? d) {
  if (d == null) return '–:––';
  final total = d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// „92 %“ (CHAPEL: `formatPlaybackRate`).
String formatRate(double rate) => '${(rate * 100).round()} %';

String stepCountLabel(int n) => n == 1 ? '1 Schritt' : '$n Schritte';
