class ExerciseSet {
  int? id;
  int workoutSessionId;
  int exerciseId;
  int setNumber;
  double? weight;
  int? reps;
  Duration? duration;
  String? notes;
  DateTime timestamp;
  bool isWarmup;

  /// True when no earlier non-warmup set of the same exercise matched this
  /// one on both weight and reps at the moment it was logged — see
  /// utils/personal_records.dart. Persisted rather than derived so the
  /// "New best" badge survives leaving and re-entering the workout, and so
  /// history keeps showing the sets that *were* records at the time even after
  /// they are beaten.
  bool isPersonalRecord;

  /// Extra partial-range reps done after [reps] full ones, e.g. the "+3" in
  /// "8 +3". Deliberately a separate column rather than folded into [reps]:
  /// every volume, 1RM, rep-range and record calculation reads [reps] only,
  /// so partials are recorded without inflating any of them. Null means none.
  int? partialReps;

  /// Rate of perceived exertion, 6–10 in 0.5 steps. Null means not rated.
  double? rpe;

  ExerciseSet({
    this.id,
    required this.workoutSessionId,
    required this.exerciseId,
    required this.setNumber,
    this.weight,
    this.reps,
    this.duration,
    this.notes,
    required this.timestamp,
    this.isWarmup = false,
    this.isPersonalRecord = false,
    this.partialReps,
    this.rpe,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'workoutSessionId': workoutSessionId,
      'exerciseId': exerciseId,
      'setNumber': setNumber,
      'weight': weight,
      'reps': reps,
      'duration': duration?.inSeconds,
      'notes': notes,
      'timestamp': timestamp.toIso8601String(),
      'isWarmup': isWarmup ? 1 : 0,
      'isPersonalRecord': isPersonalRecord ? 1 : 0,
      'partialReps': partialReps,
      'rpe': rpe,
    };
  }

  factory ExerciseSet.fromMap(Map<String, dynamic> map) {
    return ExerciseSet(
      id: map['id']?.toInt(),
      workoutSessionId: map['workoutSessionId']?.toInt() ?? 0,
      exerciseId: map['exerciseId']?.toInt() ?? 0,
      setNumber: map['setNumber']?.toInt() ?? 1,
      weight: map['weight']?.toDouble(),
      reps: map['reps']?.toInt(),
      duration: map['duration'] != null ? Duration(seconds: map['duration']) : null,
      notes: map['notes'],
      timestamp: DateTime.parse(map['timestamp']),
      isWarmup: map['isWarmup'] == 1,
      isPersonalRecord: map['isPersonalRecord'] == 1,
      partialReps: map['partialReps']?.toInt(),
      rpe: map['rpe']?.toDouble(),
    );
  }

  /// The `clear*` flags exist because `copyWith(rpe: null)` can't clear a
  /// nullable field — `null ?? this.rpe` just keeps the old value.
  ExerciseSet copyWith({
    int? id,
    int? workoutSessionId,
    int? exerciseId,
    int? setNumber,
    double? weight,
    int? reps,
    Duration? duration,
    String? notes,
    DateTime? timestamp,
    bool? isWarmup,
    bool? isPersonalRecord,
    int? partialReps,
    double? rpe,
    bool clearNotes = false,
    bool clearPartialReps = false,
    bool clearRpe = false,
  }) {
    return ExerciseSet(
      id: id ?? this.id,
      workoutSessionId: workoutSessionId ?? this.workoutSessionId,
      exerciseId: exerciseId ?? this.exerciseId,
      setNumber: setNumber ?? this.setNumber,
      weight: weight ?? this.weight,
      reps: reps ?? this.reps,
      duration: duration ?? this.duration,
      notes: clearNotes ? null : (notes ?? this.notes),
      timestamp: timestamp ?? this.timestamp,
      isWarmup: isWarmup ?? this.isWarmup,
      isPersonalRecord: isPersonalRecord ?? this.isPersonalRecord,
      partialReps: clearPartialReps ? null : (partialReps ?? this.partialReps),
      rpe: clearRpe ? null : (rpe ?? this.rpe),
    );
  }

  // Calculate volume (weight × reps). Full reps only — partials never count.
  double? get volume {
    if (weight != null && reps != null) {
      return weight! * reps!;
    }
    return null;
  }

  /// True when there are partial reps worth showing.
  bool get hasPartialReps => partialReps != null && partialReps! > 0;

  String get formattedDuration {
    if (duration == null) return '--';
    final minutes = duration!.inMinutes;
    final seconds = duration!.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String getDisplayText({required String weightUnit}) {
    List<String> parts = [];

    if (weight != null) {
      parts.add('$weight $weightUnit');
    }

    if (reps != null) {
      parts.add(hasPartialReps ? '$reps +$partialReps reps' : '$reps reps');
    }

    if (duration != null) {
      parts.add(formattedDuration);
    }

    final text = parts.isEmpty ? 'Set $setNumber' : parts.join(' × ');
    return rpe == null ? text : '$text @${formatRpe(rpe!)}';
  }
}

/// "8" for 8.0, "8.5" for 8.5 — RPE only ever moves in half steps.
String formatRpe(double rpe) =>
    rpe == rpe.roundToDouble() ? rpe.toStringAsFixed(0) : rpe.toStringAsFixed(1);
