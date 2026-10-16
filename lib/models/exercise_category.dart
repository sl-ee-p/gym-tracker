import 'package:flutter/material.dart';

class ExerciseCategory {
  int? id;
  String name;
  String? description;
  int colorValue; // Store color as int for database
  
  ExerciseCategory({
    this.id,
    required this.name,
    this.description,
    this.colorValue = 0xFF2196F3, // Default blue
  });
  
  Color get color => Color(colorValue);
  
  set color(Color newColor) {
    colorValue = newColor.toARGB32();
  }
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'colorValue': colorValue,
    };
  }
  
  factory ExerciseCategory.fromMap(Map<String, dynamic> map) {
    return ExerciseCategory(
      id: map['id']?.toInt(),
      name: map['name'] ?? '',
      description: map['description'],
      colorValue: map['colorValue'] ?? 0xFF2196F3,
    );
  }
  
  ExerciseCategory copyWith({
    int? id,
    String? name,
    String? description,
    int? colorValue,
  }) {
    return ExerciseCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      colorValue: colorValue ?? this.colorValue,
    );
  }
  
  // Predefined categories for initial setup
  static List<ExerciseCategory> getDefaultCategories() {
    return [
      ExerciseCategory(name: 'Push', description: 'Chest, Shoulders, Triceps', colorValue: 0xFFE57373),
      ExerciseCategory(name: 'Pull', description: 'Back, Biceps', colorValue: 0xFF64B5F6),
      ExerciseCategory(name: 'Legs', description: 'Quadriceps, Hamstrings, Glutes, Calves', colorValue: 0xFF81C784),
      ExerciseCategory(name: 'Arms', description: 'Biceps, Triceps, Forearms', colorValue: 0xFFFFB74D),
      ExerciseCategory(name: 'Core', description: 'Abs, Obliques', colorValue: 0xFFBA68C8),
      ExerciseCategory(name: 'Full Body', description: 'Compound movements', colorValue: 0xFF9575CD),
    ];
  }
}