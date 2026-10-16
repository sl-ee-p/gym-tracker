/// The personal-record rule, and the rep-max table built on the same data.
///
/// A set is a record ("New best") when no earlier set of the exercise matched
/// it on *both* weight and reps. So a heavier single counts, and so does
/// 100 kg × 10 after 100 kg × 5 — the old rule ("heavier than every earlier
/// set") never credited doing more reps with the same weight. Warm-ups and
/// sets missing weight or reps are the caller's to filter out; they never
/// count.
///
/// An exercise's very first set is not a record: there is nothing to beat.
library;

/// One set as the record rule sees it.
typedef RecordCandidate = ({int id, double weight, int reps});

/// The ids in [orderedSets] (oldest first) that were records when logged.
///
/// Tracks the Pareto frontier of earlier sets — the ones no other earlier set
/// beats on both weight and reps. A new set is matched by some earlier set
/// exactly when it is matched by a frontier member, so this checks the
/// frontier (a handful of points) rather than all of history.
Set<int> findRepRecords(Iterable<RecordCandidate> orderedSets) {
  final recordIds = <int>{};
  var frontier = <(double, int)>[];
  for (final set in orderedSets) {
    final matched =
        frontier.any((p) => p.$1 >= set.weight && p.$2 >= set.reps);
    if (matched) continue;
    if (frontier.isNotEmpty) recordIds.add(set.id);
    frontier = [
      for (final p in frontier)
        if (!(set.weight >= p.$1 && set.reps >= p.$2)) p,
      (set.weight, set.reps),
    ];
  }
  return recordIds;
}

/// The rep counts the rep-max table shows.
const List<int> repMaxTargets = [1, 3, 5, 8, 10, 12];

/// The heaviest weight lifted for at least [reps] reps, and when.
class RepMax {
  const RepMax({required this.reps, required this.weightKg, required this.date});

  final int reps;
  final double weightKg;
  final DateTime date;
}

/// One row of the rep-max table per target in [targets] that has data, in
/// target order. "At least N reps", not "exactly N": a 100 kg × 6 set proves
/// you can do 100 kg for 5, so it sets the 5-rep max too.
///
/// Ties on weight keep the earliest date — when the max was first reached.
List<RepMax> computeRepMaxes(
  Iterable<({double weight, int reps, DateTime date})> sets, {
  List<int> targets = repMaxTargets,
}) {
  final result = <RepMax>[];
  for (final target in targets) {
    ({double weight, int reps, DateTime date})? best;
    for (final set in sets) {
      if (set.reps < target) continue;
      if (best == null ||
          set.weight > best.weight ||
          (set.weight == best.weight && set.date.isBefore(best.date))) {
        best = set;
      }
    }
    if (best != null) {
      result.add(RepMax(reps: target, weightKg: best.weight, date: best.date));
    }
  }
  return result;
}
