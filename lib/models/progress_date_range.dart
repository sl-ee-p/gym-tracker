import 'package:flutter/material.dart';

import '../providers/progress_provider.dart';

/// The date ranges the Progress screen can be filtered to.
///
/// An enum rather than the loose `'last30'`/`'all'` strings the range menu
/// used to pass around, so the screen can show *which* range is active — it
/// couldn't before, and a silently-applied 90-day window made an exercise last
/// trained four months ago look like it had no data at all.
///
/// Lives in models rather than beside the screen because the choice is
/// persisted (`user_profiles.progressDateRange`) and applied at startup by
/// ProgressProvider, before any screen exists.
enum ProgressDateRange {
  last30('Last 30 Days', '30d', Icons.calendar_view_week),
  last90('Last 90 Days', '90d', Icons.calendar_view_month),
  last6months('Last 6 Months', '6m', Icons.calendar_month),
  lastyear('Last Year', '1y', Icons.calendar_today),
  all('All Time', 'All', Icons.all_inclusive);

  const ProgressDateRange(this.label, this.shortLabel, this.icon);

  final String label;

  /// Short form for the AppBar chip, where the full label doesn't fit.
  final String shortLabel;

  final IconData icon;

  /// The default when nothing has been saved yet.
  static const defaultRange = ProgressDateRange.last90;

  /// Resolves a persisted [name], falling back to [defaultRange] for null or
  /// anything unrecognised — a stale value from another version must not stop
  /// the Progress screen loading.
  static ProgressDateRange fromName(String? name) {
    if (name == null) return defaultRange;
    for (final range in ProgressDateRange.values) {
      if (range.name == name) return range;
    }
    return defaultRange;
  }

  void applyTo(ProgressProvider provider) {
    switch (this) {
      case ProgressDateRange.last30:
        provider.setLast30Days();
      case ProgressDateRange.last90:
        provider.setLast90Days();
      case ProgressDateRange.last6months:
        provider.setLast6Months();
      case ProgressDateRange.lastyear:
        provider.setLastYear();
      case ProgressDateRange.all:
        provider.clearDateRange();
    }
  }
}
