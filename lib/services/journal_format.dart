import 'package:intl/intl.dart';

/// "July 11th, 2026" — the journal's human date, with the ordinal suffix the
/// plain intl patterns can't produce.
String formatJournalDate(DateTime day) {
  final month = DateFormat('MMMM').format(day);
  return '$month ${day.day}${ordinalSuffix(day.day)}, ${day.year}';
}

String ordinalSuffix(int day) {
  if (day >= 11 && day <= 13) return 'th';
  switch (day % 10) {
    case 1:
      return 'st';
    case 2:
      return 'nd';
    case 3:
      return 'rd';
    default:
      return 'th';
  }
}
