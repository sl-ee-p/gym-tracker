// The DST cases below are the reason this utility exists. They are written
// against Europe/Rome's transitions (CET->CEST on the last Sunday of March,
// back on the last Sunday of October), which is the app author's timezone.
//
// Dart's DateTime uses the host's timezone and there is no way to override it
// from a test, so the DST-specific expectations only exercise a real 23/25-hour
// day when the suite runs somewhere observing European DST. Everywhere else
// they still pass — they just assert ordinary 24-hour days. The naive
// implementation these replace (`to.difference(from).inDays`) is asserted
// against directly, so the bug is documented either way.

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/utils/app_date.dart';

void main() {
  group('epochDay', () {
    test('is stable across times of day', () {
      expect(
        epochDay(DateTime(2026, 3, 29, 0, 0)),
        epochDay(DateTime(2026, 3, 29, 23, 59, 59)),
      );
    });

    test('increments by exactly one per calendar day', () {
      expect(
        epochDay(DateTime(2026, 3, 30)) - epochDay(DateTime(2026, 3, 29)),
        1,
      );
    });

    test('crosses month and year boundaries', () {
      expect(daysBetween(DateTime(2026, 1, 31), DateTime(2026, 2, 1)), 1);
      expect(daysBetween(DateTime(2025, 12, 31), DateTime(2026, 1, 1)), 1);
    });

    test('handles a leap day', () {
      expect(daysBetween(DateTime(2028, 2, 28), DateTime(2028, 2, 29)), 1);
      expect(daysBetween(DateTime(2028, 2, 29), DateTime(2028, 3, 1)), 1);
    });
  });

  group('daysBetween across a DST spring-forward', () {
    // Europe/Rome loses an hour at 02:00 on 2026-03-29, making that local day
    // 23 hours long.
    final saturday = DateTime(2026, 3, 28, 9, 0);
    final sunday = DateTime(2026, 3, 29, 9, 0);

    test('reports one day, not zero', () {
      expect(daysBetween(saturday, sunday), 1);
    });

    test('is signed', () {
      expect(daysBetween(sunday, saturday), -1);
    });

    test('a same-day pair is zero even spanning the transition hour', () {
      expect(
        daysBetween(DateTime(2026, 3, 29, 1, 0), DateTime(2026, 3, 29, 23, 0)),
        0,
      );
    });
  });

  group('daysBetween across a DST fall-back', () {
    // Europe/Rome gains an hour at 03:00 on 2026-10-25 — a 25-hour day, which
    // is where `Duration.inDays` truncation would report 1 for a 2-day gap.
    test('reports one day for consecutive days', () {
      expect(
        daysBetween(DateTime(2026, 10, 24, 9, 0), DateTime(2026, 10, 25, 9, 0)),
        1,
      );
    });

    test('reports two days across the transition', () {
      expect(
        daysBetween(DateTime(2026, 10, 24, 9, 0), DateTime(2026, 10, 26, 9, 0)),
        2,
      );
    });
  });

  group('isSameDay', () {
    test('is true for the same calendar day at different times', () {
      expect(
        isSameDay(DateTime(2026, 5, 1, 0, 1), DateTime(2026, 5, 1, 23, 59)),
        isTrue,
      );
    });

    test('is false a minute past midnight into the next day', () {
      expect(
        isSameDay(DateTime(2026, 5, 1, 23, 59), DateTime(2026, 5, 2, 0, 1)),
        isFalse,
      );
    });
  });

  group('addDays', () {
    test('lands on local midnight of the target day', () {
      final result = addDays(DateTime(2026, 3, 28, 15, 30), 1);
      expect(result, DateTime(2026, 3, 29));
      expect(result.hour, 0);
    });

    test('stays at midnight across a DST boundary', () {
      // `date.add(Duration(days: 1))` drifts to 01:00 here on a spring-forward
      // day, which then never equals a midnight-anchored key.
      final stepped = addDays(DateTime(2026, 3, 28), 1);
      expect(stepped, DateTime(2026, 3, 29));
      expect(stepped.hour, 0);
    });

    test('walks a full week one day at a time without drifting', () {
      var cursor = DateTime(2026, 10, 21);
      for (var i = 0; i < 7; i++) {
        cursor = addDays(cursor, 1);
        expect(cursor.hour, 0, reason: 'drifted off midnight on step $i');
      }
      expect(cursor, DateTime(2026, 10, 28));
    });

    test('accepts negative steps', () {
      expect(addDays(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
    });
  });

  group('startOfWeek', () {
    test('returns the same Monday for every day of that week', () {
      // 2026-05-04 is a Monday.
      final monday = DateTime(2026, 5, 4);
      for (var i = 0; i < 7; i++) {
        expect(startOfWeek(DateTime(2026, 5, 4 + i, 18, 30)), monday);
      }
    });

    test('a Sunday belongs to the week that started six days earlier', () {
      expect(startOfWeek(DateTime(2026, 5, 10)), DateTime(2026, 5, 4));
    });

    test('crosses a month boundary backwards', () {
      // 2026-06-03 is a Wednesday; its Monday is in May.
      expect(startOfWeek(DateTime(2026, 6, 3)), DateTime(2026, 6, 1));
      expect(startOfWeek(DateTime(2026, 4, 2)), DateTime(2026, 3, 30));
    });
  });

  group('startOfDay', () {
    test('zeroes the time component', () {
      expect(startOfDay(DateTime(2026, 5, 1, 13, 45, 22)), DateTime(2026, 5, 1));
    });
  });
}
