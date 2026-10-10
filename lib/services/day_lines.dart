import 'dart:math';

/// The Journal's greeting: today's date, told a different way each day.
///
/// Lines carry tokens filled from the date ([fillDayTokens]): `{day}` Saturday,
/// `{date}` 10, `{dateOrd}` 10th, `{month}` October, `{monthNum}` 10,
/// `{year}` 2026, `{daysLeft}` the days left in the year after today.

/// Lines for any day.
const List<String> kDateLines = [
  '{day}, {date} {month}. Make it count, or at least make it a paragraph.',
  '{month} {date}. One of 365, apparently.',
  "It's {day}. Time is a social construct, but your list isn't.",
  "{date} {month} {year}. You'll want to remember this one. Or not.",
  '{daysLeft} days left in {year}. No pressure.',
  '{day}, whatever that means to you today.',
  '{month} {date}: a date future you will have to look up.',
  'Today is {day}. Nobody asked, here it is.',
  "{date}/{monthNum}. A number you'll forget by Tuesday.",
  '{day}. The calendar insists.',
  "The {dateOrd} of {month}. Let's see what it becomes.",
  'This {day} will never happen again. Dramatic, still true.',
  '{day}, {date} {month}. Write it down before it turns into tomorrow.',
  '{day} has been assigned to you. No refunds.',
  '{month} {date}, {year}: a day that existed.',
  '{day} again? They keep coming.',
  "Today's date: {date} {month}. Today's plan: unclear. Fill in below.",
  '{day}, {date} {month}. Past tense by tonight.',
  '{day} is a day like any other. Document it anyway.',
  '{date}/{monthNum}/{year}. Mood: pending.',
  "It's {day}. Past-you made plans. Present-you has opinions.",
  'Someday {month} {date} will be "that one day". Pick which one.',
  'Timestamp: {day}, {date} {month}. Contents: TBD.',
  'A fresh {day}, lightly used.',
  "The date changed. You didn't have to do anything.",
  '{dateOrd} of {month}. Statistically unremarkable. Write it up anyway.',
  '{day}. Free of charge, mildly overpriced in effort.',
  'Same planet, new date: {date} {month}.',
  '{month} {date} showed up whether you were ready or not.',
  "{day}'s a blank page with a header already on it.",
];

/// Lines for one weekday only, by [DateTime.weekday].
const Map<int, List<String>> kWeekdayLines = {
  DateTime.monday: [
    'Monday. The least favorite sentence in the calendar.',
    'New week, same you, slightly worse sleep.',
  ],
  DateTime.tuesday: [
    'Tuesday. Nobody has a feeling about Tuesday.',
    "Monday's problems, now with momentum.",
  ],
  DateTime.wednesday: [
    'Wednesday. Halfway, allegedly.',
    'Peak middle. Nothing to see, plenty to do.',
  ],
  DateTime.thursday: [
    "Thursday. Friday's understudy.",
    'One more day of pretending to be consistent.',
  ],
  DateTime.friday: [
    'Friday. Productivity optional after 4.',
    "The week's almost over. Log the evidence.",
  ],
  DateTime.saturday: [
    'Saturday. Weekend rules apply, mostly.',
    'Tasks optional, journal encouraged.',
  ],
  DateTime.sunday: [
    'Sunday. Tomorrow is already loitering.',
    'Last day of the week, first day of dread. Write through it.',
  ],
};

/// Lines for one date of the year only, keyed `month/day`.
const Map<String, List<String>> kDayOfYearLines = {
  '10/10': [
    '10/10. The calendar peaked early.',
    '{date}/{monthNum}: a perfect score, no further comment.',
  ],
};

const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
  'Sunday', //
];
const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December', //
];

/// 1st, 2nd, 3rd, 4th … 11th, 12th, 13th … 21st, 22nd, 23rd … 31st.
String ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

/// [line] with its date tokens filled in for [day].
String fillDayTokens(String line, DateTime day) {
  // Calendar days, not hours: a daylight-saving change can't shave one off.
  final daysLeft = DateTime.utc(day.year, 12, 31)
      .difference(DateTime.utc(day.year, day.month, day.day))
      .inDays;
  return line
      .replaceAll('{day}', _weekdays[day.weekday - 1])
      .replaceAll('{dateOrd}', ordinal(day.day))
      .replaceAll('{date}', '${day.day}')
      .replaceAll('{monthNum}', '${day.month}')
      .replaceAll('{month}', _months[day.month - 1])
      .replaceAll('{year}', '${day.year}')
      .replaceAll('{daysLeft}', '$daysLeft');
}

/// The lines today's greeting may be drawn from.
List<String> dayLinePool(DateTime day) {
  // TODO(human): decide how the three kinds of line share a day — the date
  // lines (any day), kWeekdayLines[day.weekday] and the one-date lines in
  // kDayOfYearLines['${day.month}/${day.day}'].
  return kDateLines;
}

/// Today's greeting: one line from [dayLinePool], its tokens filled in.
String pickDayLine(DateTime day, {Random? random}) {
  final pool = dayLinePool(day);
  return fillDayTokens(pool[(random ?? Random()).nextInt(pool.length)], day);
}
