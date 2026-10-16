// The duplicate-name rule. `exercises.name` has no UNIQUE constraint and
// cannot gain one without risking existing installs, so this predicate is the
// enforcement — which makes it worth pinning.

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/models/exercise.dart';
import 'package:gym_app/providers/exercise_provider.dart';

void main() {
  final library = [
    Exercise(id: 1, name: 'Bench Press', categoryId: 1),
    Exercise(id: 2, name: 'Squat', categoryId: 2),
  ];

  Exercise? find(String name, {int? excludingId}) =>
      ExerciseProvider.findDuplicateName(library, name, excludingId: excludingId);

  group('normalizeName', () {
    test('trims and lower-cases', () {
      expect(Exercise.normalizeName('  Bench Press  '), 'bench press');
    });
  });

  group('findDuplicateName', () {
    test('returns null for a free name', () {
      expect(find('Overhead Press'), isNull);
    });

    test('matches an exact name', () {
      expect(find('Bench Press')?.id, 1);
    });

    test('matches regardless of case', () {
      expect(find('bench press')?.id, 1);
      expect(find('BENCH PRESS')?.id, 1);
    });

    test('matches despite surrounding whitespace', () {
      expect(find('  Bench Press ')?.id, 1);
    });

    test('does not match a different name that merely contains it', () {
      expect(find('Close-grip Bench Press'), isNull);
    });

    test('lets an exercise keep its own name while being edited', () {
      expect(find('Bench Press', excludingId: 1), isNull);
    });

    test('still blocks renaming one exercise onto another', () {
      expect(find('Squat', excludingId: 1)?.id, 2);
    });
  });

  group('DuplicateExerciseNameException', () {
    test('reads as a sentence, since it is shown to the user verbatim', () {
      expect(
        const DuplicateExerciseNameException('Bench Press').toString(),
        'An exercise named "Bench Press" already exists.',
      );
    });
  });
}
