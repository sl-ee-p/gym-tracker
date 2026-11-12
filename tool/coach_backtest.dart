// Replays a PlateLog backup through the coach and compares each suggestion
// with what was actually lifted next.
//
//   dart run tool/coach_backtest.dart <backup.json> <report.md> [from] [to]
//
// from/to are ISO dates bounding the scored sessions (default: the last 92
// days of the backup). Older sessions are used as history only. Write the
// report outside the repository: it contains personal training data.
import 'dart:convert';
import 'dart:io';

import 'package:gym_app/coach/coach_models.dart';
import 'package:gym_app/coach/progression_engine.dart';

class _Exercise {
  _Exercise(this.name, this.equipment);
  final String name;
  final CoachEquipment equipment;
  final List<CoachExposure> exposures = [];
}

enum _Decision { up, hold, down }

class _Row {
  _Row({
    required this.exercise,
    required this.date,
    required this.prev,
    required this.report,
    required this.actual,
    required this.step,
  });
  final String exercise;
  final DateTime date;
  final CoachSet prev;
  final CoachReport report;
  final CoachSet actual;
  final double step;

  CoachSuggestion get s => report.suggestion!;
  _Decision _decide(double w) => w > prev.weightKg + 0.01
      ? _Decision.up
      : w < prev.weightKg - 0.01
      ? _Decision.down
      : _Decision.hold;
  _Decision get suggested => _decide(s.weightKg);
  _Decision get actualDecision => _decide(actual.weightKg);
  bool get decisionAgrees => suggested == actualDecision;
  bool get weightExact => (s.weightKg - actual.weightKg).abs() < 0.01;
  bool get weightWithinStep =>
      (s.weightKg - actual.weightKg).abs() <= step + 0.01;
  bool get repsOk =>
      actual.reps >= s.repsMin - 1 && actual.reps <= s.repsMax + 1;
}

class _Variant {
  const _Variant(this.name, this.config);
  final String name;
  final CoachConfig config;
}

const _variants = [
  _Variant('default', CoachConfig()),
  _Variant('2nd set slack 2', CoachConfig(secondSetSlack: 2)),
  _Variant('2nd set slack 0', CoachConfig(secondSetSlack: 0)),
  _Variant('range p50', CoachConfig(rangePercentile: 0.5)),
  _Variant('range p90', CoachConfig(rangePercentile: 0.9)),
  _Variant('stall after 5', CoachConfig(stallExposures: 5)),
  _Variant('stall blocks 28 days', CoachConfig(stallDays: 28)),
  _Variant(
    'stall blocks 28 days, min 4',
    CoachConfig(stallDays: 28, stallExposures: 4),
  ),
  _Variant('big step 10%', CoachConfig(bigStepFraction: 0.10)),
  _Variant('big step off', CoachConfig(bigStepFraction: 1)),
];

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'usage: dart run tool/coach_backtest.dart <backup.json> <report.md> [from] [to]',
    );
    exit(64);
  }
  final backup = jsonDecode(File(args[0]).readAsStringSync()) as Map;
  final tables = backup['tables'] as Map;
  final profile = (tables['user_profiles'] as List).cast<Map>().firstOrNull;
  final defaultBar = (profile?['defaultBarWeightKg'] as num?)?.toDouble() ?? 20;

  final exercises = <int, _Exercise>{};
  for (final e in (tables['exercises'] as List).cast<Map>()) {
    final weighted =
        e['isWeightBased'] == 1 &&
        e['isRepsBased'] == 1 &&
        e['isTimeBased'] != 1;
    if (!weighted) continue;
    exercises[e['id'] as int] = _Exercise(
      e['name'] as String,
      e['usesPlateCalculator'] == 1
          ? CoachEquipment.plates(
              barWeightKg: (e['barWeightKg'] as num?)?.toDouble() ?? defaultBar,
            )
          : const CoachEquipment.stack(),
    );
  }
  final sessions = <int, DateTime>{
    for (final w in (tables['workout_sessions'] as List).cast<Map>())
      if (w['isCompleted'] == 1) w['id'] as int: DateTime.parse(w['date']),
  };

  // Group working sets by (exercise, session), in logged order.
  final grouped = <int, Map<int, List<Map>>>{};
  final sets = (tables['exercise_sets'] as List).cast<Map>()
    ..sort((a, b) => (a['timestamp'] as String).compareTo(b['timestamp']));
  for (final s in sets) {
    final ex = s['exerciseId'] as int, ws = s['workoutSessionId'] as int;
    if (!exercises.containsKey(ex) || !sessions.containsKey(ws)) continue;
    if (s['isWarmup'] == 1) continue;
    grouped.putIfAbsent(ex, () => {}).putIfAbsent(ws, () => []).add(s);
  }
  DateTime last = DateTime(1970);
  for (final MapEntry(key: ex, value: bySession) in grouped.entries) {
    for (final MapEntry(key: ws, value: list) in bySession.entries) {
      final date = sessions[ws]!;
      if (date.isAfter(last)) last = date;
      exercises[ex]!.exposures.add(
        CoachExposure(
          date: date,
          sets: [
            for (final s in list)
              CoachSet(
                weightKg: (s['weight'] as num?)?.toDouble() ?? 0,
                reps: (s['reps'] as int?) ?? 0,
              ),
          ],
        ),
      );
    }
  }
  for (final e in exercises.values) {
    e.exposures.sort((a, b) => a.date.compareTo(b.date));
  }

  final to = args.length > 3 ? DateTime.parse(args[3]) : last;
  final from = args.length > 2
      ? DateTime.parse(args[2])
      : DateTime(to.year, to.month, to.day).subtract(const Duration(days: 92));

  List<_Row> run(CoachConfig config) {
    final engine = ProgressionEngine(config);
    final rows = <_Row>[];
    for (final e in exercises.values) {
      for (var i = 1; i < e.exposures.length; i++) {
        final x = e.exposures[i];
        if (x.date.isBefore(from) ||
            x.date.isAfter(to.add(const Duration(days: 1)))) {
          continue;
        }
        final before = engine.analyze(
          e.exposures.sublist(0, i),
          now: x.date,
          unit: 'kg',
          equipment: e.equipment,
        );
        final after = engine.analyze(
          e.exposures.sublist(0, i + 1),
          now: x.date,
          unit: 'kg',
          equipment: e.equipment,
        );
        if (before.suggestion == null || after.lastTopSet == null) continue;
        rows.add(
          _Row(
            exercise: e.name,
            date: x.date,
            prev: before.lastTopSet!,
            report: before,
            actual: after.lastTopSet!,
            step: before.step,
          ),
        );
      }
    }
    rows.sort((a, b) => a.date.compareTo(b.date));
    return rows;
  }

  String pct(int n, int d) => d == 0 ? '-' : '${(100 * n / d).round()}%';
  String day(DateTime d) => d.toIso8601String().substring(0, 10);
  String w(double kg) => kg == kg.roundToDouble()
      ? kg.toStringAsFixed(0)
      : '$kg'.replaceAll(RegExp(r'0+$'), '');
  String sug(CoachSuggestion s) =>
      '${s.action.name} ${w(s.weight)}×${s.repsMin == s.repsMax ? s.repsMin : '${s.repsMin}–${s.repsMax}'}'
      '${s.secondSetReps == null ? '' : ', 2nd ×${s.secondSetReps}'}';

  final out = StringBuffer()
    ..writeln('# Coach backtest')
    ..writeln()
    ..writeln('Backup: `${args[0]}` (exported ${backup['exportedAt']}).')
    ..writeln(
      'Scored sessions: ${day(from)} to ${day(to)}; earlier sessions are history only.',
    )
    ..writeln()
    ..writeln('## Variants')
    ..writeln()
    ..writeln(
      '| Variant | Sessions | Decision agrees | Weight exact | Weight ±1 step | Reps in target ±1 | Stall/deload calls (sessions) |',
    )
    ..writeln('|---|---|---|---|---|---|---|');
  for (final v in _variants) {
    final rows = run(v.config);
    final scored = rows
        .where((r) => r.report.status != CoachStatus.baseline)
        .toList();
    final sameWeight = scored.where((r) => r.weightExact).toList();
    out.writeln(
      '| ${v.name} | ${scored.length} '
      '| ${pct(scored.where((r) => r.decisionAgrees).length, scored.length)} '
      '| ${pct(sameWeight.length, scored.length)} '
      '| ${pct(scored.where((r) => r.weightWithinStep).length, scored.length)} '
      '| ${pct(sameWeight.where((r) => r.repsOk).length, sameWeight.length)} '
      '| ${scored.where((r) => r.report.deload != null).length} '
      '(${_episodes(scored)} episodes) |',
    );
  }

  final rows = run(const CoachConfig());
  final scored = rows
      .where((r) => r.report.status != CoachStatus.baseline)
      .toList();

  // Confusion matrix of decisions.
  out
    ..writeln()
    ..writeln('## Default rules: suggested vs actual decision')
    ..writeln()
    ..writeln('| Suggested \\ actual | up | hold | down |')
    ..writeln('|---|---|---|---|');
  for (final sd in _Decision.values) {
    out.write('| ${sd.name} ');
    for (final ad in _Decision.values) {
      out.write(
        '| ${scored.where((r) => r.suggested == sd && r.actualDecision == ad).length} ',
      );
    }
    out.writeln('|');
  }

  out
    ..writeln()
    ..writeln('## Default rules: by deciding rule')
    ..writeln()
    ..writeln(
      '| Rule | Sessions | Actual up | Actual hold | Actual down | Went up and still hit the range |',
    )
    ..writeln('|---|---|---|---|---|---|');
  final byRule = <String, List<_Row>>{};
  for (final r in scored) {
    final code = r.s.reasons
        .lastWhere(
          (x) => x.code != CoachReasonCode.welcomeBack,
          orElse: () => r.s.reasons.last,
        )
        .code
        .name;
    byRule.putIfAbsent(code, () => []).add(r);
  }
  for (final MapEntry(key: code, value: rs) in byRule.entries) {
    int n(_Decision d) => rs.where((r) => r.actualDecision == d).length;
    final ups = rs.where((r) => r.actualDecision == _Decision.up);
    out.writeln(
      '| $code | ${rs.length} '
      '| ${n(_Decision.up)} | ${n(_Decision.hold)} | ${n(_Decision.down)} '
      '| ${pct(ups.where((r) => r.actual.reps >= r.report.range.lo).length, ups.length)} |',
    );
  }

  out
    ..writeln()
    ..writeln('## Per exercise')
    ..writeln()
    ..writeln(
      '| Exercise | Sessions | Range | Step | Decision agrees | Weight exact |',
    )
    ..writeln('|---|---|---|---|---|---|');
  final byEx = <String, List<_Row>>{};
  for (final r in scored) {
    byEx.putIfAbsent(r.exercise, () => []).add(r);
  }
  final names = byEx.keys.toList()
    ..sort((a, b) => byEx[b]!.length.compareTo(byEx[a]!.length));
  for (final n in names) {
    final rs = byEx[n]!;
    out.writeln(
      '| $n | ${rs.length} | ${rs.last.report.range} | ${w(rs.last.step)} '
      '| ${pct(rs.where((r) => r.decisionAgrees).length, rs.length)} '
      '| ${pct(rs.where((r) => r.weightExact).length, rs.length)} |',
    );
  }

  out
    ..writeln()
    ..writeln('## Stall and deload calls (with the next two sessions)')
    ..writeln();
  final calls = scored.where((r) => r.report.deload != null).toList();
  if (calls.isEmpty) out.writeln('None.');
  for (final r in calls) {
    final d = r.report.deload!;
    final next = rows
        .where((x) => x.exercise == r.exercise && !x.date.isBefore(r.date))
        .take(2)
        .map((x) => '${day(x.date)} ${w(x.actual.weightKg)}×${x.actual.reps}')
        .join('; ');
    out.writeln(
      '- ${day(r.date)} **${r.exercise}**: ${d.trigger.code.name}'
      '${d.trigger.sessions != null ? ' (${d.trigger.sessions} sessions)' : ''}'
      '${d.trigger.percent != null ? ' (${(d.trigger.percent! * 100).toStringAsFixed(1)}%)' : ''}'
      ' → deload ${w(d.weight)}×${d.reps} for ${d.sessions}. Last top ${w(r.prev.weightKg)}×${r.prev.reps}. Actually: $next',
    );
  }

  out
    ..writeln()
    ..writeln('## Disagreements (default rules)')
    ..writeln()
    ..writeln(
      '| Date | Exercise | Last top set | Suggested | Actual top set | Reasons |',
    )
    ..writeln('|---|---|---|---|---|---|');
  for (final r in scored.where(
    (r) => !r.decisionAgrees || !r.weightWithinStep,
  )) {
    out.writeln(
      '| ${day(r.date)} | ${r.exercise} | ${w(r.prev.weightKg)}×${r.prev.reps} '
      '| ${sug(r.s)} | ${w(r.actual.weightKg)}×${r.actual.reps} '
      '| ${r.s.reasons.map((x) => x.code.name).join(', ')} |',
    );
  }

  File(args[1])
    ..createSync(recursive: true)
    ..writeAsStringSync(out.toString());
  stdout.writeln('Wrote ${args[1]} (${scored.length} scored sessions).');
}

/// Consecutive sessions of one exercise that carry a deload call count as a
/// single episode: the banner just stays up while it is ignored.
int _episodes(List<_Row> rows) {
  final byEx = <String, List<_Row>>{};
  for (final r in rows) {
    byEx.putIfAbsent(r.exercise, () => []).add(r);
  }
  var n = 0;
  for (final list in byEx.values) {
    var inCall = false;
    for (final r in list) {
      final call = r.report.deload != null;
      if (call && !inCall) n++;
      inCall = call;
    }
  }
  return n;
}
