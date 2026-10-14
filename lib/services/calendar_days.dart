/// Calendar-day arithmetic on local dates.
///
/// `date.add(Duration(days: n))` adds n × 24 hours. Across a daylight-saving
/// change that lands on 23:00 the day before or 01:00, not midnight: the date
/// no longer equals the midnight it should, can name the wrong day, and a
/// difference in whole days comes out one short. These step and count by the
/// calendar instead.
library;

/// [d] moved by [n] calendar days (negative for earlier), at midnight.
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Whole calendar days from [from] to [to]; negative when [to] is earlier.
int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

/// The Monday on or before [d], at midnight.
DateTime mondayOf(DateTime d) => addDays(d, 1 - d.weekday);
