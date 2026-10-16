/// Calendar-day arithmetic that survives daylight saving time.
///
/// This codebase has a documented history of day-boundary bugs: differencing
/// two local [DateTime]s with `Duration.inDays` looks right and is wrong twice
/// a year. Even normalising both sides to local midnight first isn't safe —
/// on a DST-transition day two consecutive local midnights are 23 or 25 real
/// hours apart, so `inDays` truncates to 0 or 1 when it should be 1, and
/// "Today" starts rendering as "Yesterday".
///
/// The fix: map each date to a UTC-anchored integer day number and do all
/// arithmetic on integers.
library;

/// Days since the Unix epoch for [date]'s *calendar day*, read in local time.
///
/// The UTC anchoring is deliberate: it makes the result a plain integer that
/// can be compared and subtracted with no timezone left in it. The date's own
/// time-of-day and offset are discarded, which is exactly what "which day was
/// this?" means.
int epochDay(DateTime date) {
  final utcMidnight = DateTime.utc(date.year, date.month, date.day);
  return utcMidnight.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
}

/// Whole calendar days from [from] to [to] — positive when [to] is later.
/// `daysBetween(yesterday, today) == 1` on every day of the year, DST
/// transitions included.
int daysBetween(DateTime from, DateTime to) => epochDay(to) - epochDay(from);

/// Whether [a] and [b] fall on the same calendar day.
bool isSameDay(DateTime a, DateTime b) => epochDay(a) == epochDay(b);

/// The date [days] calendar days after [date], at local midnight.
///
/// Use instead of `date.add(Duration(days: n))`, which adds 24 real hours and
/// so drifts an hour off midnight across a DST boundary — enough for an
/// equality check against a midnight-anchored key to start failing.
DateTime addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

/// Local midnight at the start of [date]'s calendar day.
DateTime startOfDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);

/// Local midnight on the Monday of [date]'s week. Monday-based to match how
/// the weekly workout goal is counted and how `DateTime.weekday` numbers days
/// (Monday == 1).
DateTime startOfWeek(DateTime date) =>
    addDays(startOfDay(date), -(date.weekday - DateTime.monday));
