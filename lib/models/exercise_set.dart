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
    );
  }
  
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
  }) {
    return ExerciseSet(
      id: id ?? this.id,
      workoutSessionId: workoutSessionId ?? this.workoutSessionId,
      exerciseId: exerciseId ?? this.exerciseId,
      setNumber: setNumber ?? this.setNumber,
      weight: weight ?? this.weight,
      reps: reps ?? this.reps,
      duration: duration ?? this.duration,
      notes: notes ?? this.notes,
      timestamp: timestamp ?? this.timestamp,
    );
  }
  
  // Calculate volume (weight × reps)
  double? get volume {
    if (weight != null && reps != null) {
      return weight! * reps!;
    }
    return null;
  }
  
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
      parts.add('$reps reps');
    }
    
    if (duration != null) {
      parts.add(formattedDuration);
    }
    
    return parts.isEmpty ? 'Set $setNumber' : parts.join(' × ');
  }
}