import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/models/reminder_schedule.dart';

void main() {
  group('parse / encode', () {
    test('round-trips, sorted', () {
      final schedule = ReminderSchedule.parse('5,1,3', 1080);

      expect(schedule.days, {1, 3, 5});
      expect(schedule.encodeDays(), '1,3,5');
      expect(schedule.hour, 18);
      expect(schedule.minute, 0);
    });

    test('null or empty days mean off', () {
      expect(ReminderSchedule.parse(null, 1080).isEnabled, isFalse);
      expect(ReminderSchedule.parse('', 1080).isEnabled, isFalse);
      expect(
          const ReminderSchedule(days: {}, minutesOfDay: 0).encodeDays(), isNull);
    });

    test('drops malformed and out-of-range entries', () {
      expect(ReminderSchedule.parse('1, x,9,0,7', 0).days, {1, 7});
    });
  });

  group('nextOccurrence', () {
    // Wednesday 23 September 2026, 10:00.
    final wednesdayMorning = DateTime(2026, 9, 23, 10);
    const sixPm = ReminderSchedule(days: {3}, minutesOfDay: 18 * 60);

    test('later the same day when the time is still ahead', () {
      expect(sixPm.nextOccurrence(wednesdayMorning, DateTime.wednesday),
          DateTime(2026, 9, 23, 18));
    });

    test('a week later when the time has passed today', () {
      final evening = DateTime(2026, 9, 23, 19);
      expect(sixPm.nextOccurrence(evening, DateTime.wednesday),
          DateTime(2026, 9, 30, 18));
    });

    test('the coming weekday otherwise, across a month end', () {
      expect(sixPm.nextOccurrence(wednesdayMorning, DateTime.monday),
          DateTime(2026, 9, 28, 18));
      expect(sixPm.nextOccurrence(DateTime(2026, 9, 30, 20), DateTime.friday),
          DateTime(2026, 10, 2, 18));
    });
  });

  test('formatMinutesOfDay pads to HH:MM', () {
    expect(formatMinutesOfDay(450), '07:30');
    expect(formatMinutesOfDay(1080), '18:00');
  });
}
