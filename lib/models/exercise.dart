class Exercise {
  int? id;
  String name;
  int categoryId;
  String? instructions;
  List<String> muscleGroups;
  bool isWeightBased;
  bool isTimeBased;
  bool isRepsBased;
  
  Exercise({
    this.id,
    required this.name,
    required this.categoryId,
    this.instructions,
    this.muscleGroups = const [],
    this.isWeightBased = true,
    this.isTimeBased = false,
    this.isRepsBased = true,
  });
  
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
    );
  }
  
  // Default exercises for initial setup
  static List<Exercise> getDefaultExercises() {
    return [
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
  }
}