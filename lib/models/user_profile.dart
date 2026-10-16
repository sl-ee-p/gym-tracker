class UserProfile {
  int? id;
  String name;
  DateTime createdDate;
  double? currentWeight;
  String weightUnit; // 'kg' or 'lbs'
  String themeMode; // 'light', 'dark', or 'system'

  /// Fallback bar weight in kg for exercises that don't set their own
  /// [Exercise.barWeightKg]. 20 kg is a standard Olympic bar.
  double defaultBarWeightKg;

  /// Custom theme colors as ARGB ints, one pair per brightness. Null means
  /// "use the built-in palette", which is what Reset restores — so the
  /// defaults live in AppTheme, not duplicated here.
  int? accentColorLight;
  int? accentColorDark;
  int? highlightColorLight;
  int? highlightColorDark;

  /// Target workouts per week, shown as a progress ring on the heatmap card.
  int weeklyWorkoutGoal;

  /// Ordered, comma-joined keys of the visible dashboard blocks
  /// (e.g. 'workout,welcome,heatmap'). Absent keys are hidden. Null means
  /// "default order, everything visible". Comma-joined to match the existing
  /// precedent of Exercise.muscleGroups and WorkoutTemplate.exerciseIds.
  String? homeLayout;

  /// Whether a backup is written to Downloads after each completed workout.
  bool autoBackupEnabled;

  /// When the last automatic backup succeeded, so Settings can show it.
  DateTime? lastBackupAt;

  /// The Progress screen's selected date range, by enum name. Persisted
  /// because it is a viewing preference, not a per-visit choice — it used to
  /// snap back to 90 days on every visit to the tab.
  String? progressDateRange;

  /// The exercise the Progress screen's Exercise tab last showed. Persisted
  /// for the same reason as [progressDateRange]: switching nav tabs remounts
  /// that screen, so a local field reset the selection on every visit. Null
  /// means "no choice yet" — the tab then falls back to the most recently
  /// trained exercise.
  int? lastProgressExerciseId;

  /// The rest duration the user last started a timer with, in seconds. Null
  /// means "never started one", and the picker opens on its 90 s default.
  int? restTimerSeconds;

  /// Whether the set form offers a "Partials" field. Only gates the input:
  /// partials already logged are always shown.
  bool partialRepsEnabled;

  /// Whether the set form offers an RPE picker. Same input-only gating.
  bool rpeEnabled;

  /// Goal body weight in kg. Null means no goal.
  double? targetWeight;

  /// Body weight in kg when [targetWeight] was set — the 0% end of the
  /// progress bar. Null when there was no weight logged at the time.
  double? targetWeightStart;

  /// Weekdays (ISO, 1 = Monday) for the workout reminder, comma-joined —
  /// see ReminderSchedule. Null means the reminder is off.
  String? workoutReminderDays;

  /// Time of day for the workout reminder, minutes after midnight.
  int workoutReminderMinutes;

  /// Weekdays for the weigh-in reminder, as [workoutReminderDays].
  String? weighInReminderDays;

  /// Time of day for the weigh-in reminder, minutes after midnight.
  int weighInReminderMinutes;

  UserProfile({
    this.id,
    required this.name,
    required this.createdDate,
    this.currentWeight,
    this.weightUnit = 'kg',
    this.themeMode = 'system',
    this.defaultBarWeightKg = 20.0,
    this.accentColorLight,
    this.accentColorDark,
    this.highlightColorLight,
    this.highlightColorDark,
    this.weeklyWorkoutGoal = 3,
    this.homeLayout,
    this.autoBackupEnabled = true,
    this.lastBackupAt,
    this.progressDateRange,
    this.lastProgressExerciseId,
    this.restTimerSeconds,
    this.partialRepsEnabled = false,
    this.rpeEnabled = false,
    this.targetWeight,
    this.targetWeightStart,
    this.workoutReminderDays,
    this.workoutReminderMinutes = 18 * 60,
    this.weighInReminderDays,
    this.weighInReminderMinutes = 7 * 60 + 30,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'createdDate': createdDate.toIso8601String(),
      'currentWeight': currentWeight,
      'weightUnit': weightUnit,
      'themeMode': themeMode,
      'defaultBarWeightKg': defaultBarWeightKg,
      'accentColorLight': accentColorLight,
      'accentColorDark': accentColorDark,
      'highlightColorLight': highlightColorLight,
      'highlightColorDark': highlightColorDark,
      'weeklyWorkoutGoal': weeklyWorkoutGoal,
      'homeLayout': homeLayout,
      'autoBackupEnabled': autoBackupEnabled ? 1 : 0,
      'lastBackupAt': lastBackupAt?.toIso8601String(),
      'progressDateRange': progressDateRange,
      'lastProgressExerciseId': lastProgressExerciseId,
      'restTimerSeconds': restTimerSeconds,
      'partialRepsEnabled': partialRepsEnabled ? 1 : 0,
      'rpeEnabled': rpeEnabled ? 1 : 0,
      'targetWeight': targetWeight,
      'targetWeightStart': targetWeightStart,
      'workoutReminderDays': workoutReminderDays,
      'workoutReminderMinutes': workoutReminderMinutes,
      'weighInReminderDays': weighInReminderDays,
      'weighInReminderMinutes': weighInReminderMinutes,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id']?.toInt(),
      name: map['name'] ?? '',
      createdDate: DateTime.parse(map['createdDate']),
      currentWeight: map['currentWeight']?.toDouble(),
      weightUnit: map['weightUnit'] ?? 'kg',
      themeMode: map['themeMode'] ?? 'system',
      defaultBarWeightKg: map['defaultBarWeightKg']?.toDouble() ?? 20.0,
      accentColorLight: map['accentColorLight']?.toInt(),
      accentColorDark: map['accentColorDark']?.toInt(),
      highlightColorLight: map['highlightColorLight']?.toInt(),
      highlightColorDark: map['highlightColorDark']?.toInt(),
      weeklyWorkoutGoal: map['weeklyWorkoutGoal']?.toInt() ?? 3,
      homeLayout: map['homeLayout'],
      // Defaults to on: rows written before v4 have the column's DEFAULT 1.
      autoBackupEnabled: map['autoBackupEnabled'] != 0,
      lastBackupAt: map['lastBackupAt'] != null
          ? DateTime.parse(map['lastBackupAt'])
          : null,
      progressDateRange: map['progressDateRange'],
      lastProgressExerciseId: map['lastProgressExerciseId']?.toInt(),
      restTimerSeconds: map['restTimerSeconds']?.toInt(),
      partialRepsEnabled: map['partialRepsEnabled'] == 1,
      rpeEnabled: map['rpeEnabled'] == 1,
      targetWeight: map['targetWeight']?.toDouble(),
      targetWeightStart: map['targetWeightStart']?.toDouble(),
      workoutReminderDays: map['workoutReminderDays'],
      workoutReminderMinutes: map['workoutReminderMinutes']?.toInt() ?? 18 * 60,
      weighInReminderDays: map['weighInReminderDays'],
      weighInReminderMinutes:
          map['weighInReminderMinutes']?.toInt() ?? 7 * 60 + 30,
    );
  }

  /// Note the `clear*` flags. A plain `copyWith(currentWeight: null)` cannot
  /// clear a nullable field — `null ?? this.currentWeight` just keeps the old
  /// value — so clearing has to be asked for explicitly.
  UserProfile copyWith({
    int? id,
    String? name,
    DateTime? createdDate,
    double? currentWeight,
    String? weightUnit,
    String? themeMode,
    double? defaultBarWeightKg,
    int? accentColorLight,
    int? accentColorDark,
    int? highlightColorLight,
    int? highlightColorDark,
    int? weeklyWorkoutGoal,
    String? homeLayout,
    bool? autoBackupEnabled,
    DateTime? lastBackupAt,
    String? progressDateRange,
    int? lastProgressExerciseId,
    int? restTimerSeconds,
    bool? partialRepsEnabled,
    bool? rpeEnabled,
    double? targetWeight,
    double? targetWeightStart,
    String? workoutReminderDays,
    int? workoutReminderMinutes,
    String? weighInReminderDays,
    int? weighInReminderMinutes,
    bool clearCurrentWeight = false,
    bool clearThemeColors = false,
    bool clearHomeLayout = false,
    bool clearLastProgressExercise = false,
    bool clearTargetWeight = false,
    bool clearTargetWeightStart = false,
    bool clearWorkoutReminder = false,
    bool clearWeighInReminder = false,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      createdDate: createdDate ?? this.createdDate,
      currentWeight:
          clearCurrentWeight ? null : (currentWeight ?? this.currentWeight),
      weightUnit: weightUnit ?? this.weightUnit,
      themeMode: themeMode ?? this.themeMode,
      defaultBarWeightKg: defaultBarWeightKg ?? this.defaultBarWeightKg,
      accentColorLight:
          clearThemeColors ? null : (accentColorLight ?? this.accentColorLight),
      accentColorDark:
          clearThemeColors ? null : (accentColorDark ?? this.accentColorDark),
      highlightColorLight: clearThemeColors
          ? null
          : (highlightColorLight ?? this.highlightColorLight),
      highlightColorDark: clearThemeColors
          ? null
          : (highlightColorDark ?? this.highlightColorDark),
      weeklyWorkoutGoal: weeklyWorkoutGoal ?? this.weeklyWorkoutGoal,
      homeLayout: clearHomeLayout ? null : (homeLayout ?? this.homeLayout),
      autoBackupEnabled: autoBackupEnabled ?? this.autoBackupEnabled,
      lastBackupAt: lastBackupAt ?? this.lastBackupAt,
      progressDateRange: progressDateRange ?? this.progressDateRange,
      // Clearable: the saved exercise can be deleted from the library, and
      // there has to be a way to forget an id that no longer resolves.
      lastProgressExerciseId: clearLastProgressExercise
          ? null
          : (lastProgressExerciseId ?? this.lastProgressExerciseId),
      restTimerSeconds: restTimerSeconds ?? this.restTimerSeconds,
      partialRepsEnabled: partialRepsEnabled ?? this.partialRepsEnabled,
      rpeEnabled: rpeEnabled ?? this.rpeEnabled,
      // Clearing the goal clears its starting point too: a start without a
      // target means nothing.
      targetWeight:
          clearTargetWeight ? null : (targetWeight ?? this.targetWeight),
      targetWeightStart: clearTargetWeight || clearTargetWeightStart
          ? null
          : (targetWeightStart ?? this.targetWeightStart),
      workoutReminderDays: clearWorkoutReminder
          ? null
          : (workoutReminderDays ?? this.workoutReminderDays),
      workoutReminderMinutes:
          workoutReminderMinutes ?? this.workoutReminderMinutes,
      weighInReminderDays: clearWeighInReminder
          ? null
          : (weighInReminderDays ?? this.weighInReminderDays),
      weighInReminderMinutes:
          weighInReminderMinutes ?? this.weighInReminderMinutes,
    );
  }
}
