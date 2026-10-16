/// Something worth telling the user about, shown under the heatmap.
///
/// This replaces the streak counter. A streak rewards not missing a day, which
/// for strength training is the wrong target — rest days are part of the
/// programme — and it punishes a single missed session by resetting to zero,
/// which is demotivating exactly when motivation is already low. Achievements
/// are additive: they only ever accumulate.
class Achievement {
  const Achievement({
    required this.kind,
    required this.title,
    this.detail = '',
    required this.date,
    this.weightKg,
    this.reps,
  });

  final AchievementKind kind;

  /// The headline, e.g. an exercise name or "100 workouts".
  final String title;

  /// Supporting text for a milestone, e.g. "logged since you started".
  ///
  /// Empty for personal records: those carry [weightKg] and [reps] instead,
  /// and the widget formats them in the user's display unit. Pre-formatting
  /// the record here is what once produced "100 × 8 kg" — the unit tacked on
  /// after the reps, and the kg number never converted for lbs users.
  final String detail;

  final DateTime date;

  /// The record set's weight, always kg. Only set for personal records.
  final double? weightKg;

  /// The record set's reps. Only set for personal records.
  final int? reps;
}

enum AchievementKind {
  /// A set no earlier set matched on both weight and reps — see
  /// `findRepRecords` in utils/personal_records.dart.
  personalRecord,

  /// A round total of completed workouts.
  milestone,
}
