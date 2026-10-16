import 'dart:math' as math;

import '../models/exercise.dart';

/// Framework-agnostic, typo-tolerant search over a list of [Exercise].
///
/// Combines whole-string and per-word (token) matching, each with an
/// exact/substring pass and a bounded-fuzzy (Levenshtein) fallback, into a
/// single ranked list. Every match "tier" occupies its own 1000-point score
/// band, so — regardless of any tie-breaking bonus within a tier — a match
/// in a higher tier always outranks every match in a lower tier. In
/// particular: any match that is 100% substring-based always outranks any
/// match that needed a fuzzy (typo-tolerant) step for even one word, and
/// any match against the exercise's name always outranks a match that only
/// worked against its muscle groups.
///
/// No Flutter/BuildContext dependency — pure Dart, independently testable.
class ExerciseSearch {
  const ExerciseSearch._();

  // ---- Public API -------------------------------------------------------

  /// Returns [exercises] filtered to those matching [query], ranked most
  /// relevant first. A blank [query] returns every exercise, alphabetical
  /// by name (i.e. "no filter").
  ///
  /// Matching runs primarily against [Exercise.name]. When
  /// [includeMuscleGroups] is true (the default) and an exercise has no
  /// name-based match, its [Exercise.muscleGroups] are checked as a lower
  /// priority fallback, so e.g. searching "bicep" can still surface
  /// "Hammer Curls" beneath direct name matches like "Bicep Curls".
  static List<Exercise> search(
    String query,
    List<Exercise> exercises, {
    bool includeMuscleGroups = true,
  }) {
    final trimmed = query.trim();
    final queryTokens = _tokenize(trimmed);

    if (trimmed.isEmpty || queryTokens.isEmpty) {
      final all = List<Exercise>.from(exercises);
      all.sort(_byNameThenId);
      return all;
    }

    final normalizedQuery = trimmed.toLowerCase();
    final scored = <MapEntry<Exercise, int>>[];
    for (final exercise in exercises) {
      final matchScore = _score(
        normalizedQuery: normalizedQuery,
        queryTokens: queryTokens,
        exercise: exercise,
        includeMuscleGroups: includeMuscleGroups,
      );
      if (matchScore != null) {
        scored.add(MapEntry(exercise, matchScore));
      }
    }

    scored.sort((a, b) {
      final byScore = b.value.compareTo(a.value);
      if (byScore != 0) return byScore;
      return _byNameThenId(a.key, b.key);
    });

    return scored.map((entry) => entry.key).toList();
  }

  /// The relevance score for [exercise] against [query], or `null` if it
  /// does not match at all. Exposed mainly so tests can assert individual
  /// match/no-match and relative-ranking decisions without inspecting list
  /// order; [search] uses this internally.
  static int? score(
    String query,
    Exercise exercise, {
    bool includeMuscleGroups = true,
  }) {
    final trimmed = query.trim();
    return _score(
      normalizedQuery: trimmed.toLowerCase(),
      queryTokens: _tokenize(trimmed),
      exercise: exercise,
      includeMuscleGroups: includeMuscleGroups,
    );
  }

  // ---- Scoring tiers ------------------------------------------------
  // Each tier occupies a disjoint 1000-point band, highest first.

  static const int _tierExact = 4000; // normalized name == query
  static const int _tierSubstringWhole = 3000; // query is a substring of the name
  static const int _tierTokensSubstring = 2000; // every query word is a substring of a name word (any order)
  static const int _tierTokensFuzzy = 1000; // as above, but >=1 word needed a fuzzy match
  static const int _tierMuscleGroupFallback = 0; // as above two tiers, matched via muscleGroups instead of name

  static int? _score({
    required String normalizedQuery,
    required List<String> queryTokens,
    required Exercise exercise,
    required bool includeMuscleGroups,
  }) {
    final normalizedName = exercise.name.trim().toLowerCase();

    if (normalizedName == normalizedQuery) {
      return _tierExact;
    }

    final nameIndex = normalizedName.indexOf(normalizedQuery);
    if (nameIndex != -1) {
      // Reward matches at the start of the name (prefix matches feel most
      // relevant) and tighter matches (query covers more of the name).
      final positionBonus = nameIndex == 0 ? 50 : 0;
      final coverageBonus =
          (normalizedQuery.length / normalizedName.length * 40).round();
      return _tierSubstringWhole + positionBonus + coverageBonus;
    }

    final nameMatch = _matchTokens(queryTokens, _tokenize(exercise.name));
    if (nameMatch != null) {
      final base = nameMatch.usedFuzzy ? _tierTokensFuzzy : _tierTokensSubstring;
      final bonus = math.max(0, 100 - nameMatch.totalEditDistance * 10);
      return base + bonus;
    }

    if (includeMuscleGroups && exercise.muscleGroups.isNotEmpty) {
      final muscleTokens = _tokenize(exercise.muscleGroups.join(' '));
      final muscleMatch = _matchTokens(queryTokens, muscleTokens);
      if (muscleMatch != null) {
        final bonus = math.max(0, 100 - muscleMatch.totalEditDistance * 10);
        return _tierMuscleGroupFallback + bonus;
      }
    }

    return null;
  }

  /// Requires every token in [queryTokens] to match at least one token in
  /// [candidateTokens] (substring in either direction, or — failing that —
  /// within the length-scaled fuzzy threshold). Returns `null` if any
  /// single query token matches nothing at all.
  static _TokenMatchResult? _matchTokens(
    List<String> queryTokens,
    List<String> candidateTokens,
  ) {
    if (candidateTokens.isEmpty) return null;

    var usedFuzzy = false;
    var totalEditDistance = 0;

    for (final queryToken in queryTokens) {
      var matched = false;
      var bestDistance = 0;

      // Substring check, either direction — handles both a short query
      // token inside a longer candidate word ("bicep" in "biceps") and a
      // longer query token containing a shorter candidate word.
      for (final candidateToken in candidateTokens) {
        if (candidateToken.contains(queryToken) ||
            queryToken.contains(candidateToken)) {
          matched = true;
          bestDistance = 0;
          break;
        }
      }

      if (!matched) {
        final maxDistance = _maxEditDistanceFor(queryToken.length);
        if (maxDistance > 0) {
          var bestFuzzyDistance = maxDistance + 1; // sentinel: "too far"
          for (final candidateToken in candidateTokens) {
            // Cheap pre-check before paying for the full DP table.
            if ((candidateToken.length - queryToken.length).abs() >
                maxDistance) {
              continue;
            }
            final distance = levenshteinDistance(queryToken, candidateToken);
            if (distance < bestFuzzyDistance) {
              bestFuzzyDistance = distance;
            }
          }
          if (bestFuzzyDistance <= maxDistance) {
            matched = true;
            bestDistance = bestFuzzyDistance;
            usedFuzzy = true;
          }
        }
      }

      if (!matched) return null;
      totalEditDistance += bestDistance;
    }

    return _TokenMatchResult(usedFuzzy: usedFuzzy, totalEditDistance: totalEditDistance);
  }

  /// Typo tolerance scales with word length: 1-3 chars require an
  /// exact/substring match (fuzzing a short word produces more noise than
  /// signal), 4-7 chars tolerate 1 edit (the dominant real-world typo
  /// shape), 8+ chars tolerate 2 edits (long/specific words rarely collide
  /// with an unrelated word within 2 edits).
  static int _maxEditDistanceFor(int tokenLength) {
    if (tokenLength <= 3) return 0;
    if (tokenLength <= 7) return 1;
    return 2;
  }

  static List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.isNotEmpty)
        .toList();
  }

  static int _byNameThenId(Exercise a, Exercise b) {
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (byName != 0) return byName;
    return (a.id ?? 0).compareTo(b.id ?? 0);
  }

  // ---- Levenshtein distance ----------------------------------------

  /// Classic Levenshtein edit distance (single-character insert, delete or
  /// substitute) between [a] and [b]. O(|a| * |b|) time, O(min(|a|, |b|))
  /// space via two rolling rows. Case-sensitive and does no normalization —
  /// callers ([_matchTokens]) pass already-lowercased, tokenized strings.
  static int levenshteinDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final String shorter = a.length <= b.length ? a : b;
    final String longer = a.length <= b.length ? b : a;

    var previousRow = List<int>.generate(shorter.length + 1, (i) => i);
    var currentRow = List<int>.filled(shorter.length + 1, 0);

    for (var i = 1; i <= longer.length; i++) {
      currentRow[0] = i;
      final longerUnit = longer.codeUnitAt(i - 1);

      for (var j = 1; j <= shorter.length; j++) {
        final cost = longerUnit == shorter.codeUnitAt(j - 1) ? 0 : 1;
        final deletion = previousRow[j] + 1;
        final insertion = currentRow[j - 1] + 1;
        final substitution = previousRow[j - 1] + cost;
        currentRow[j] = math.min(deletion, math.min(insertion, substitution));
      }

      final swap = previousRow;
      previousRow = currentRow;
      currentRow = swap;
    }

    return previousRow[shorter.length];
  }
}

class _TokenMatchResult {
  final bool usedFuzzy;
  final int totalEditDistance;
  const _TokenMatchResult({required this.usedFuzzy, required this.totalEditDistance});
}
