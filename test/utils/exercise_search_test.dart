import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/models/exercise.dart';
import 'package:gym_app/utils/exercise_search.dart';

void main() {
  group('ExerciseSearch.levenshteinDistance', () {
    test('classic kitten/sitting example is 3', () {
      expect(ExerciseSearch.levenshteinDistance('kitten', 'sitting'), 3);
    });

    test('identical strings have distance 0', () {
      expect(ExerciseSearch.levenshteinDistance('squat', 'squat'), 0);
    });

    test('single substitution has distance 1', () {
      expect(ExerciseSearch.levenshteinDistance('curl', 'curk'), 1);
    });
  });

  group('ExerciseSearch.search', () {
    final exercises = [
      Exercise(id: 1, name: 'Bicep Curls', categoryId: 4, muscleGroups: ['Biceps']),
      Exercise(id: 2, name: 'Hammer Curls', categoryId: 4, muscleGroups: ['Biceps', 'Forearms']),
      Exercise(id: 3, name: 'Bench Press', categoryId: 1, muscleGroups: ['Chest', 'Triceps']),
      Exercise(id: 4, name: 'Incline Bench Press', categoryId: 1, muscleGroups: ['Chest']),
      Exercise(id: 5, name: 'Squat', categoryId: 3, muscleGroups: ['Quadriceps']),
    ];

    test('blank query returns everything, alphabetically', () {
      final result = ExerciseSearch.search('', exercises);
      expect(result.length, exercises.length);
      expect(result.first.name, 'Bench Press');
      expect(result.last.name, 'Squat');
    });

    test('short (<=3 char) queries require exact substring, not fuzz', () {
      // "sqt" is not a contiguous substring of "Squat" and is too short to
      // fuzz-match.
      expect(ExerciseSearch.search('sqt', exercises), isEmpty);
    });

    test('4-7 char single-letter typo still matches', () {
      expect(
        ExerciseSearch.search('squai', exercises).map((e) => e.name),
        contains('Squat'),
      );
    });

    test('exact name match ranks first', () {
      expect(ExerciseSearch.search('bench press', exercises).first.name, 'Bench Press');
    });

    test('substring match finds partial names', () {
      final result = ExerciseSearch.search('press', exercises).map((e) => e.name).toList();
      expect(result, containsAll(['Bench Press', 'Incline Bench Press']));
    });

    test('reordered multi-word query matches via per-token search', () {
      expect(
        ExerciseSearch.search('curl bicep', exercises).map((e) => e.name),
        contains('Bicep Curls'),
      );
    });

    test('name matches rank above muscle-group-only matches', () {
      final result = ExerciseSearch.search('bicep', exercises).map((e) => e.name).toList();
      expect(result, contains('Bicep Curls'));
      expect(result, contains('Hammer Curls'));
      expect(result.indexOf('Bicep Curls'), lessThan(result.indexOf('Hammer Curls')));
    });

    test('no match returns empty list', () {
      expect(ExerciseSearch.search('xyznonexistent', exercises), isEmpty);
    });

    test('includeMuscleGroups: false excludes muscle-group-only matches', () {
      final result = ExerciseSearch.search(
        'forearms',
        exercises,
        includeMuscleGroups: false,
      );
      expect(result, isEmpty);
    });
  });
}
