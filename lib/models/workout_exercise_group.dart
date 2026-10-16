/// Records that [exerciseId] is grouped (as a superset/circuit) with the
/// other exercises sharing its [groupId], within one workout session.
///
/// [groupId] is simply the `exerciseId` of the group's first ("anchor")
/// member — no separate id-generation scheme is needed. [groupOrder] is the
/// position of this exercise within the group (0-based), which is what
/// [isLastInGroup]-style rest-timer logic uses to decide whether a "Quick
/// Rest" or the normal rest timer applies after a set.
class WorkoutExerciseGroup {
  int? id;
  int workoutSessionId;
  int exerciseId;
  int groupId;
  int groupOrder;

  WorkoutExerciseGroup({
    this.id,
    required this.workoutSessionId,
    required this.exerciseId,
    required this.groupId,
    required this.groupOrder,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'workoutSessionId': workoutSessionId,
      'exerciseId': exerciseId,
      'groupId': groupId,
      'groupOrder': groupOrder,
    };
  }

  factory WorkoutExerciseGroup.fromMap(Map<String, dynamic> map) {
    return WorkoutExerciseGroup(
      id: map['id']?.toInt(),
      workoutSessionId: map['workoutSessionId']?.toInt() ?? 0,
      exerciseId: map['exerciseId']?.toInt() ?? 0,
      groupId: map['groupId']?.toInt() ?? 0,
      groupOrder: map['groupOrder']?.toInt() ?? 0,
    );
  }

  WorkoutExerciseGroup copyWith({
    int? id,
    int? workoutSessionId,
    int? exerciseId,
    int? groupId,
    int? groupOrder,
  }) {
    return WorkoutExerciseGroup(
      id: id ?? this.id,
      workoutSessionId: workoutSessionId ?? this.workoutSessionId,
      exerciseId: exerciseId ?? this.exerciseId,
      groupId: groupId ?? this.groupId,
      groupOrder: groupOrder ?? this.groupOrder,
    );
  }
}
