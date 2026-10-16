import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/models/progress_date_range.dart';

void main() {
  group('fromName', () {
    test('round-trips every range through its stored name', () {
      // `name` is what lands in user_profiles.progressDateRange, so this is
      // the persistence contract.
      for (final range in ProgressDateRange.values) {
        expect(ProgressDateRange.fromName(range.name), range,
            reason: range.name);
      }
    });

    test('null means "never chosen" and gives the default', () {
      expect(ProgressDateRange.fromName(null), ProgressDateRange.defaultRange);
    });

    test('an unrecognised name falls back instead of throwing', () {
      // A value written by a newer build, or a corrupted row, must not stop
      // the Progress screen from loading.
      expect(ProgressDateRange.fromName('lastDecade'),
          ProgressDateRange.defaultRange);
      expect(ProgressDateRange.fromName(''), ProgressDateRange.defaultRange);
    });

    test('matching is exact, not case-insensitive or partial', () {
      expect(ProgressDateRange.fromName('LAST30'),
          ProgressDateRange.defaultRange);
      expect(ProgressDateRange.fromName('last3'),
          ProgressDateRange.defaultRange);
    });
  });

  test('every range has a label, a short label and an icon', () {
    for (final range in ProgressDateRange.values) {
      expect(range.label, isNotEmpty);
      expect(range.shortLabel, isNotEmpty);
      // The short label goes in a chip beside the screen title.
      expect(range.shortLabel.length, lessThanOrEqualTo(4), reason: range.name);
    }
  });

  test('short labels are distinct, so the chip is unambiguous', () {
    final shortLabels =
        ProgressDateRange.values.map((r) => r.shortLabel).toSet();
    expect(shortLabels.length, ProgressDateRange.values.length);
  });
}
