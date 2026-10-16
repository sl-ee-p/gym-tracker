import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/exercise.dart';
import '../models/exercise_set.dart';
import '../models/workout_session.dart';
import '../utils/weight_format.dart';
import 'exercise_repository.dart';
import 'workout_repository.dart';

/// Builds the printable workout-history report.
///
/// Uses only the PDF standard fonts (Helvetica) rather than embedding a
/// typeface, which keeps the generated file small and adds no font assets.
/// The trade-off is Latin-1 coverage only, so any character outside it is
/// stripped by [_ascii] instead of rendering as a blank box.
class PdfReportService {
  const PdfReportService._();

  static final _workoutRepository = WorkoutRepository();
  static final _exerciseRepository = ExerciseRepository();

  /// Generates the report for the most recent [limit] completed workouts.
  static Future<Uint8List> buildWorkoutHistoryReport({
    required String weightUnit,
    int limit = 100,
  }) async {
    final workouts = await _workoutRepository.getAllWorkouts(limit: limit);
    final completed = workouts.where((w) => w.isCompleted).toList();
    final exercises = await _exerciseRepository.getAllExercises();
    final exercisesById = {
      for (final exercise in exercises)
        if (exercise.id != null) exercise.id!: exercise,
    };

    // One batched query rather than one per workout: this report can cover a
    // hundred sessions, and the N+1 pattern the history screen uses is already
    // a known performance concern.
    final workoutIds = [
      for (final workout in completed)
        if (workout.id != null) workout.id!,
    ];
    final allSets = await _workoutRepository.getSetsByWorkouts(workoutIds);
    final setsByWorkout = <int, List<ExerciseSet>>{};
    for (final set in allSets) {
      setsByWorkout.putIfAbsent(set.workoutSessionId, () => []).add(set);
    }

    final document = pw.Document(
      title: 'Gym Tracker — workout history',
      author: 'Gym Tracker',
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : pw.Container(
                alignment: pw.Alignment.centerRight,
                margin: const pw.EdgeInsets.only(bottom: 12),
                child: pw.Text('Workout history',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          _title(completed),
          pw.SizedBox(height: 16),
          _summaryTable(completed, setsByWorkout, weightUnit),
          pw.SizedBox(height: 24),
          if (completed.isEmpty)
            pw.Text('No completed workouts yet.',
                style: const pw.TextStyle(fontSize: 11))
          else
            for (final workout in completed)
              _workoutSection(
                workout,
                setsByWorkout[workout.id] ?? const [],
                exercisesById,
                weightUnit,
              ),
        ],
      ),
    );

    return document.save();
  }

  static pw.Widget _title(List<WorkoutSession> workouts) {
    final generated = DateTime.now();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Workout history',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(
          'Generated ${_date(generated)} · ${workouts.length} workout'
          '${workouts.length == 1 ? '' : 's'}',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      ],
    );
  }

  static pw.Widget _summaryTable(
    List<WorkoutSession> workouts,
    Map<int, List<ExerciseSet>> setsByWorkout,
    String weightUnit,
  ) {
    var totalSets = 0;
    var totalVolumeKg = 0.0;
    var totalMinutes = 0;
    for (final workout in workouts) {
      final sets = setsByWorkout[workout.id] ?? const [];
      totalSets += sets.length;
      for (final set in sets) {
        // Warm-ups are excluded from volume everywhere else in the app; the
        // report has to agree or the numbers won't reconcile.
        if (set.isWarmup) continue;
        totalVolumeKg += set.volume ?? 0;
      }
      totalMinutes += workout.duration?.inMinutes ?? 0;
    }

    return pw.Row(
      children: [
        _statBox('Workouts', '${workouts.length}'),
        _statBox('Sets', '$totalSets'),
        _statBox('Volume', formatWeight(totalVolumeKg, unit: weightUnit)),
        _statBox('Time', '${(totalMinutes / 60).floor()}h ${totalMinutes % 60}m'),
      ],
    );
  }

  static pw.Widget _statBox(String label, String value) {
    return pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.only(right: 8),
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(_ascii(label),
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            pw.SizedBox(height: 2),
            pw.Text(_ascii(value),
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  static pw.Widget _workoutSection(
    WorkoutSession workout,
    List<ExerciseSet> sets,
    Map<int, Exercise> exercisesById,
    String weightUnit,
  ) {
    final byExercise = <int, List<ExerciseSet>>{};
    for (final set in sets) {
      byExercise.putIfAbsent(set.exerciseId, () => []).add(set);
    }

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 18),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Text(
                  _ascii(workout.name ?? 'Workout'),
                  style: pw.TextStyle(
                      fontSize: 13, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.Text(
                _date(workout.date),
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ],
          ),
          if (workout.duration != null)
            pw.Text(
              '${workout.duration!.inMinutes} min',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          pw.SizedBox(height: 6),
          if (byExercise.isEmpty)
            pw.Text('No sets logged.',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600))
          else
            pw.TableHelper.fromTextArray(
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerStyle: pw.TextStyle(
                  fontSize: 9, fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(1.4),
                3: const pw.FlexColumnWidth(1),
                4: const pw.FlexColumnWidth(1.2),
              },
              headers: ['Exercise', 'Set', 'Weight', 'Reps', 'Note'],
              data: [
                for (final entry in byExercise.entries)
                  for (var i = 0; i < entry.value.length; i++)
                    _setRow(
                      exerciseName: i == 0
                          ? (exercisesById[entry.key]?.name ??
                              '(deleted exercise)')
                          : '',
                      set: entry.value[i],
                      weightUnit: weightUnit,
                    ),
              ],
            ),
          if (workout.notes != null && workout.notes!.trim().isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              _ascii(workout.notes!.trim()),
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ],
        ],
      ),
    );
  }

  static List<String> _setRow({
    required String exerciseName,
    required ExerciseSet set,
    required String weightUnit,
  }) {
    final markers = [
      if (set.isWarmup) 'warm-up',
      if (set.isPersonalRecord) 'PR',
      if (set.rpe != null) 'RPE ${formatRpe(set.rpe!)}',
    ];
    return [
      _ascii(exerciseName),
      set.isWarmup ? 'W' : '${set.setNumber}',
      set.weight != null
          ? _ascii(formatWeight(set.weight!, unit: weightUnit))
          : (set.duration != null ? set.formattedDuration : '-'),
      set.reps == null
          ? '-'
          : (set.hasPartialReps
              ? '${set.reps} +${set.partialReps}'
              : '${set.reps}'),
      _ascii([
        ...markers,
        if (set.notes != null && set.notes!.trim().isNotEmpty) set.notes!.trim(),
      ].join(' · ')),
    ];
  }

  static String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  /// Drops characters the built-in Helvetica can't encode.
  ///
  /// The PDF standard fonts are Latin-1 only. Without this, an exercise name
  /// or note containing anything outside that range throws during save, so a
  /// single emoji in a note would fail the whole export.
  static String _ascii(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (rune >= 0x20 && rune <= 0xFF) {
        buffer.writeCharCode(rune);
      } else if (rune == 0x2022 || rune == 0xB7) {
        buffer.write('-');
      }
    }
    return buffer.toString();
  }
}
