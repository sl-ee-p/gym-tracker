/// A weekly reminder: which weekdays, and at what time of day.
///
/// Stored as two columns on user_profiles — the days comma-joined (the same
/// precedent as Exercise.muscleGroups), the time as minutes after midnight —
/// with null days meaning "off". An empty set of days is also off; toggling
/// every chip off and toggling the switch off end in the same place.
class ReminderSchedule {
  const ReminderSchedule({required this.days, required this.minutesOfDay});

  /// ISO weekdays, 1 = Monday … 7 = Sunday, matching [DateTime.weekday].
  final Set<int> days;

  /// Minutes after midnight, 0–1439.
  final int minutesOfDay;

  bool get isEnabled => days.isNotEmpty;

  int get hour => minutesOfDay ~/ 60;
  int get minute => minutesOfDay % 60;

  /// Unknown or malformed entries are dropped rather than failing the whole
  /// value, so one bad digit can't switch a reminder off.
  factory ReminderSchedule.parse(String? days, int minutesOfDay) {
    final parsed = <int>{
      for (final part in (days ?? '').split(','))
        if (int.tryParse(part.trim()) case final day?)
          if (day >= DateTime.monday && day <= DateTime.sunday) day,
    };
    return ReminderSchedule(days: parsed, minutesOfDay: minutesOfDay);
  }

  /// The stored form of [days], or null when there are none.
  String? encodeDays() {
    if (days.isEmpty) return null;
    return (days.toList()..sort()).join(',');
  }

  /// The next local date-time on or after [now] that falls on [weekday] at
  /// this schedule's time. Built from calendar fields, not by adding hours,
  /// so a DST change in between doesn't shift the time of day.
  DateTime nextOccurrence(DateTime now, int weekday) {
    var daysAhead = (weekday - now.weekday) % 7;
    var candidate =
        DateTime(now.year, now.month, now.day + daysAhead, hour, minute);
    if (!candidate.isAfter(now)) {
      daysAhead += 7;
      candidate =
          DateTime(now.year, now.month, now.day + daysAhead, hour, minute);
    }
    return candidate;
  }
}

/// "18:00" for 1080. 24-hour, like every other time this app prints.
String formatMinutesOfDay(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';
