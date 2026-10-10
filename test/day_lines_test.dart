import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:braim/services/day_lines.dart';
import 'package:braim/widgets/feed_greeting.dart';

void main() {
  final saturday = DateTime(2026, 10, 10);

  List<String> everyLine() => [
        ...kDateLines,
        ...kWeekdayLines.values.expand((l) => l),
        ...kDayOfYearLines.values.expand((l) => l),
      ];

  test('tokens fill from the date', () {
    expect(fillDayTokens('{day}, {date} {month} {year}', saturday),
        'Saturday, 10 October 2026');
    expect(fillDayTokens('The {dateOrd} of {month}', saturday),
        'The 10th of October');
    expect(fillDayTokens('{date}/{monthNum}', DateTime(2026, 3, 7)), '7/3');
    expect(fillDayTokens('{daysLeft} days left in {year}', saturday),
        '82 days left in 2026');
  });

  test('days left counts calendar days, leap years included', () {
    String left(DateTime d) => fillDayTokens('{daysLeft}', d);
    expect(left(DateTime(2026, 12, 31)), '0');
    expect(left(DateTime(2026, 1, 1)), '364');
    expect(left(DateTime(2028, 1, 1)), '365');
    // The day the clocks change doesn't lose one.
    expect(left(DateTime(2026, 3, 29, 23)), '277');
  });

  test('ordinals', () {
    expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 31, 101, 111, 112].map(ordinal),
        ['1st', '2nd', '3rd', '4th', '11th', '12th', '13th', '21st', '22nd',
         '23rd', '31st', '101st', '111th', '112th']);
  });

  test('every line fills completely, every day of a year', () {
    for (var d = DateTime(2026, 1, 1);
        d.year == 2026;
        d = DateTime(d.year, d.month, d.day + 1)) {
      for (final line in everyLine()) {
        expect(fillDayTokens(line, d), isNot(contains('{')), reason: line);
      }
    }
  });

  test("today's line comes from the pool, filled in", () {
    final pool = dayLinePool(saturday);
    expect(pool, isNotEmpty);
    expect(everyLine(), containsAll(pool));
    final filled = {for (final l in everyLine()) fillDayTokens(l, saturday)};
    for (var seed = 0; seed < 20; seed++) {
      expect(filled, contains(pickDayLine(saturday, random: Random(seed))));
    }
  });

  test('the journal greeting holds for the day and moves on at midnight', () {
    final morning = pickJournalGreeting(now: DateTime(2026, 10, 10, 8));
    expect(pickJournalGreeting(now: DateTime(2026, 10, 10, 23, 59)), morning);
    final next = pickJournalGreeting(now: DateTime(2026, 10, 11, 0, 1));
    final sunday = {
      for (final l in everyLine()) fillDayTokens(l, DateTime(2026, 10, 11))
    };
    expect(sunday, contains(next));
  });
}
