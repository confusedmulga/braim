import 'package:flutter_test/flutter_test.dart';

import 'package:braim/services/calendar_days.dart';

/// Calendar-day steps land on midnights and count whole days. (The test host
/// may have no daylight saving; these pin the arithmetic the app relies on in
/// zones that do.)
void main() {
  test('stepping lands on midnight across months and years', () {
    expect(addDays(DateTime(2026, 12, 30), 3), DateTime(2027, 1, 2));
    expect(addDays(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
    expect(addDays(DateTime(2028, 3, 1), -1), DateTime(2028, 2, 29));
    expect(addDays(DateTime(2026, 10, 12, 15, 30), 0), DateTime(2026, 10, 12));
  });

  test('days between counts calendar days, whatever the hour', () {
    expect(daysBetween(DateTime(2026, 3, 7), DateTime(2026, 3, 9)), 2);
    expect(daysBetween(DateTime(2026, 3, 9), DateTime(2026, 3, 7)), -2);
    expect(daysBetween(DateTime(2026, 3, 8, 23), DateTime(2026, 3, 9, 1)), 1);
    expect(daysBetween(DateTime(2026, 1, 1), DateTime(2027, 1, 1)), 365);
  });

  test('the Monday of a week', () {
    expect(mondayOf(DateTime(2026, 10, 13)), DateTime(2026, 10, 12));
    expect(mondayOf(DateTime(2026, 10, 12)), DateTime(2026, 10, 12));
    expect(mondayOf(DateTime(2026, 11, 1)), DateTime(2026, 10, 26));
  });

  test('a week strip across the autumn clock change keeps its weekdays', () {
    final monday = DateTime(2026, 10, 12);
    for (var week = 0; week < 8; week++) {
      for (var i = 0; i < 7; i++) {
        final day = addDays(monday, week * 7 + i);
        expect(day.weekday, i + 1);
        expect(day.hour, 0);
      }
    }
  });
}
