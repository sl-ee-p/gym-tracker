class Exercise {
  int? id;
  String name;
  int categoryId;
  String? instructions;
  List<String> muscleGroups;
  bool isWeightBased;
  bool isTimeBased;
  bool isRepsBased;
  bool isFavorite;

  /// Whether the plate calculator is offered for this exercise. Only true for
  /// movements actually loaded with plates on a bar — offering it on a machine
  /// or dumbbell exercise is noise.
  bool usesPlateCalculator;

  /// Weight of the empty bar, in kg. Null means "use the profile's
  /// defaultBarWeightKg" — an Olympic bar is 20 kg, but an EZ bar is ~7.5 kg
  /// and a trap bar ~25 kg, so this is per-exercise rather than global.
  double? barWeightKg;

  Exercise({
    this.id,
    required this.name,
    required this.categoryId,
    this.instructions,
    this.muscleGroups = const [],
    this.isWeightBased = true,
    this.isTimeBased = false,
    this.isRepsBased = true,
    this.isFavorite = false,
    this.usesPlateCalculator = false,
    this.barWeightKg,
  });

  /// The comparison key for "is this name already taken": trimmed and
  /// lower-cased. One shared rule so the form validator, the provider guard
  /// and ExercisePickerSheet's post-create lookup can't drift apart.
  ///
  /// Dart's Unicode-aware `toLowerCase`, deliberately — SQL's `NOCASE`
  /// collation folds ASCII only, so a database constraint could not implement
  /// the rule the UI states.
  static String normalizeName(String name) => name.trim().toLowerCase();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'categoryId': categoryId,
      'instructions': instructions,
      'muscleGroups': muscleGroups.join(','),
      'isWeightBased': isWeightBased ? 1 : 0,
      'isTimeBased': isTimeBased ? 1 : 0,
      'isRepsBased': isRepsBased ? 1 : 0,
      'isFavorite': isFavorite ? 1 : 0,
      'usesPlateCalculator': usesPlateCalculator ? 1 : 0,
      'barWeightKg': barWeightKg,
    };
  }

  factory Exercise.fromMap(Map<String, dynamic> map) {
    return Exercise(
      id: map['id']?.toInt(),
      name: map['name'] ?? '',
      categoryId: map['categoryId']?.toInt() ?? 1,
      instructions: map['instructions'],
      muscleGroups: map['muscleGroups'] != null
          ? (map['muscleGroups'] as String).split(',').where((s) => s.isNotEmpty).toList()
          : [],
      isWeightBased: map['isWeightBased'] == 1,
      isTimeBased: map['isTimeBased'] == 1,
      isRepsBased: map['isRepsBased'] == 1,
      isFavorite: map['isFavorite'] == 1,
      usesPlateCalculator: map['usesPlateCalculator'] == 1,
      barWeightKg: map['barWeightKg']?.toDouble(),
    );
  }

  Exercise copyWith({
    int? id,
    String? name,
    int? categoryId,
    String? instructions,
    List<String>? muscleGroups,
    bool? isWeightBased,
    bool? isTimeBased,
    bool? isRepsBased,
    bool? isFavorite,
    bool? usesPlateCalculator,
    double? barWeightKg,
    // A plain `copyWith(barWeightKg: null)` can't clear the field —
    // `null ?? this.barWeightKg` keeps the old value — so reverting an
    // exercise to the global default bar has to be asked for explicitly.
    bool clearBarWeight = false,
  }) {
    return Exercise(
      id: id ?? this.id,
      name: name ?? this.name,
      categoryId: categoryId ?? this.categoryId,
      instructions: instructions ?? this.instructions,
      muscleGroups: muscleGroups ?? this.muscleGroups,
      isWeightBased: isWeightBased ?? this.isWeightBased,
      isTimeBased: isTimeBased ?? this.isTimeBased,
      isRepsBased: isRepsBased ?? this.isRepsBased,
      isFavorite: isFavorite ?? this.isFavorite,
      usesPlateCalculator: usesPlateCalculator ?? this.usesPlateCalculator,
      barWeightKg: clearBarWeight ? null : (barWeightKg ?? this.barWeightKg),
    );
  }
  
  /// The seeded movements that are loaded with plates on a bar, and so get
  /// [usesPlateCalculator] on by default.
  ///
  /// Read by two places that must never disagree: [getDefaultExercises] below
  /// (fresh installs) and DatabaseHelper's v4 migration (existing installs).
  /// Everything else defaults to off and is flagged by hand in the exercise
  /// editor — a name-matching heuristic can't tell a barbell row from a
  /// machine row, so it only claims the cases it is sure about.
  static const Set<String> barbellExerciseNames = {
    'Bench Press',
    'Incline Bench Press',
    'Overhead Press',
    'Deadlift',
    'Bent-over Row',
    'T-Bar Row',
    'Squat',
    'Romanian Deadlift',
    'Close-grip Bench Press',
    'Thrusters',
    'Clean and Press',
  };

  // Default exercises for initial setup
  static List<Exercise> getDefaultExercises() {
    final exercises = [
      // Push exercises (categoryId: 1)
      Exercise(name: 'Bench Press', categoryId: 1, muscleGroups: ['Chest', 'Triceps', 'Shoulders']),
      Exercise(name: 'Incline Bench Press', categoryId: 1, muscleGroups: ['Chest', 'Triceps', 'Shoulders']),
      Exercise(name: 'Dumbbell Press', categoryId: 1, muscleGroups: ['Chest', 'Triceps', 'Shoulders']),
      Exercise(name: 'Overhead Press', categoryId: 1, muscleGroups: ['Shoulders', 'Triceps']),
      Exercise(name: 'Dips', categoryId: 1, muscleGroups: ['Triceps', 'Chest']),
      Exercise(name: 'Push-ups', categoryId: 1, muscleGroups: ['Chest', 'Triceps', 'Shoulders']),
      
      // Pull exercises (categoryId: 2)
      Exercise(name: 'Deadlift', categoryId: 2, muscleGroups: ['Back', 'Hamstrings', 'Glutes']),
      Exercise(name: 'Pull-ups', categoryId: 2, muscleGroups: ['Back', 'Biceps']),
      Exercise(name: 'Lat Pulldown', categoryId: 2, muscleGroups: ['Back', 'Biceps']),
      Exercise(name: 'Bent-over Row', categoryId: 2, muscleGroups: ['Back', 'Biceps']),
      Exercise(name: 'T-Bar Row', categoryId: 2, muscleGroups: ['Back']),
      Exercise(name: 'Face Pulls', categoryId: 2, muscleGroups: ['Rear Delts', 'Back']),
      
      // Leg exercises (categoryId: 3)
      Exercise(name: 'Squat', categoryId: 3, muscleGroups: ['Quadriceps', 'Glutes']),
      Exercise(name: 'Romanian Deadlift', categoryId: 3, muscleGroups: ['Hamstrings', 'Glutes']),
      Exercise(name: 'Leg Press', categoryId: 3, muscleGroups: ['Quadriceps', 'Glutes']),
      Exercise(name: 'Leg Curl', categoryId: 3, muscleGroups: ['Hamstrings']),
      Exercise(name: 'Leg Extension', categoryId: 3, muscleGroups: ['Quadriceps']),
      Exercise(name: 'Calf Raises', categoryId: 3, muscleGroups: ['Calves']),
      Exercise(name: 'Bulgarian Split Squat', categoryId: 3, muscleGroups: ['Quadriceps', 'Glutes']),
      
      // Arm exercises (categoryId: 4)
      Exercise(name: 'Bicep Curls', categoryId: 4, muscleGroups: ['Biceps']),
      Exercise(name: 'Hammer Curls', categoryId: 4, muscleGroups: ['Biceps', 'Forearms']),
      Exercise(name: 'Tricep Extensions', categoryId: 4, muscleGroups: ['Triceps']),
      Exercise(name: 'Close-grip Bench Press', categoryId: 4, muscleGroups: ['Triceps']),
      Exercise(name: 'Preacher Curls', categoryId: 4, muscleGroups: ['Biceps']),
      
      // Core exercises (categoryId: 5)
      Exercise(name: 'Planks', categoryId: 5, muscleGroups: ['Core'], isWeightBased: false, isTimeBased: true, isRepsBased: false),
      Exercise(name: 'Crunches', categoryId: 5, muscleGroups: ['Abs'], isWeightBased: false),
      Exercise(name: 'Russian Twists', categoryId: 5, muscleGroups: ['Obliques']),
      Exercise(name: 'Hanging Leg Raises', categoryId: 5, muscleGroups: ['Abs']),
      
      // Full Body exercises (categoryId: 6)
      Exercise(name: 'Burpees', categoryId: 6, muscleGroups: ['Full Body'], isWeightBased: false),
      Exercise(name: 'Thrusters', categoryId: 6, muscleGroups: ['Full Body']),
      Exercise(name: 'Clean and Press', categoryId: 6, muscleGroups: ['Full Body']),
    ];
    for (final exercise in exercises) {
      if (barbellExerciseNames.contains(exercise.name)) {
        exercise.usesPlateCalculator = true;
      }
    }
    return exercises;
  }
}
/// Thrown when adding or renaming an exercise would collide with one that
/// already exists.
///
/// The check lives in the app layer rather than a `UNIQUE` constraint on
/// `exercises.name` (which `exercise_categories.name` does have). Nothing has
/// ever stopped duplicates, so existing installs may already hold some, and
/// `CREATE UNIQUE INDEX` against a table that violates it throws inside
/// sqflite's upgrade transaction — rolling back the whole migration and
/// leaving the user on the "Failed to initialize app" screen with a Retry
/// that can never succeed. Silently renaming or deleting a user's exercises
/// to make room for the index would be worse still.
class DuplicateExerciseNameException implements Exception {
  final String name;
  const DuplicateExerciseNameException(this.name);

  @override
  String toString() => 'An exercise named "$name" already exists.';
}
