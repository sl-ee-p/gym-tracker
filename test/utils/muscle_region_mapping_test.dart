import 'package:flutter/material.dart';
import 'package:flutter_body_atlas/flutter_body_atlas.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/models/exercise.dart';
import 'package:gym_app/utils/muscle_region_mapping.dart';

Exercise _exercise(List<String> muscleGroups) =>
    Exercise(name: 'Test', categoryId: 1, muscleGroups: muscleGroups);

void main() {
  group('normalizeMuscleGroup', () {
    test('trims, lower-cases and collapses internal whitespace', () {
      expect(normalizeMuscleGroup('  Chest '), 'chest');
      expect(normalizeMuscleGroup('TRICEPS'), 'triceps');
      expect(normalizeMuscleGroup('Rear   Delts'), 'rear delts');
      expect(normalizeMuscleGroup('\tFull\nBody '), 'full body');
    });
  });

  group('the seeded vocabulary', () {
    // The guard that matters: getDefaultExercises() is the only place in the
    // app with a fixed muscle-group vocabulary, so every string it uses must
    // be drawable. Adding a seeded exercise with a new muscle name fails here
    // rather than silently rendering a blank body.
    test('every muscle group in getDefaultExercises() maps to some muscle', () {
      final unmapped = <String>{};
      for (final exercise in Exercise.getDefaultExercises()) {
        for (final group in exercise.muscleGroups) {
          if (musclesForMuscleGroup(group).isEmpty) unmapped.add(group);
        }
      }
      expect(unmapped, isEmpty, reason: 'undrawable seeded muscle groups');
    });

    test('covers exactly the 15 known strings', () {
      final seeded = <String>{
        for (final exercise in Exercise.getDefaultExercises())
          ...exercise.muscleGroups,
      };
      expect(seeded, hasLength(15));
      expect(seeded.every(isKnownMuscleGroup), isTrue);
    });
  });

  group('musclesForMuscleGroup', () {
    test('maps a simple group to both sides', () {
      expect(musclesForMuscleGroup('Chest'), {
        Muscle.pectoralisMajorLeft,
        Muscle.pectoralisMajorRight,
      });
    });

    test('Rear Delts is narrower than Shoulders', () {
      final rearDelts = musclesForMuscleGroup('Rear Delts');
      final shoulders = musclesForMuscleGroup('Shoulders');

      expect(rearDelts, {
        Muscle.posteriorDeltoidLeft,
        Muscle.posteriorDeltoidRight,
      });
      // Shoulders must be a strict superset: anterior + lateral + posterior.
      expect(shoulders, containsAll(rearDelts));
      expect(shoulders.length, greaterThan(rearDelts.length));
      expect(shoulders, contains(Muscle.anteriorDeltoidLeft));
      expect(shoulders, contains(Muscle.lateralDeltoidLeft));
    });

    test('Core is the union of Abs and Obliques', () {
      expect(
        musclesForMuscleGroup('Core'),
        musclesForMuscleGroup('Abs').union(musclesForMuscleGroup('Obliques')),
      );
    });

    test('Obliques uses the aggregate ids, not the digitations', () {
      final obliques = musclesForMuscleGroup('Obliques');
      expect(obliques, {
        Muscle.externalObliqueLeft,
        Muscle.externalObliqueRight,
      });
      // The aggregate has to actually fan out, otherwise nothing paints.
      expect(Muscle.externalObliqueLeft.parts, hasLength(8));
      expect(
        Muscle.externalObliqueLeft.parts,
        contains('external_oblique_1_l'),
      );
    });

    test('Full Body covers every muscle in the artwork', () {
      expect(musclesForMuscleGroup('Full Body'), Muscle.values.toSet());
    });

    test('synonyms resolve to the same set as the canonical string', () {
      expect(musclesForMuscleGroup('quads'), musclesForMuscleGroup('Quadriceps'));
      expect(musclesForMuscleGroup('abdominals'), musclesForMuscleGroup('Abs'));
      expect(musclesForMuscleGroup('delts'), musclesForMuscleGroup('Shoulders'));
      expect(musclesForMuscleGroup('lats'), {
        Muscle.latissimusDorsiLeft,
        Muscle.latissimusDorsiRight,
      });
    });

    test('an unrecognised string highlights nothing and is not "known"', () {
      expect(musclesForMuscleGroup('Wingspan Stabilizers'), isEmpty);
      expect(isKnownMuscleGroup('Wingspan Stabilizers'), isFalse);
      expect(musclesForMuscleGroup(''), isEmpty);
      expect(musclesForMuscleGroup('   '), isEmpty);
    });

    // The artwork has no erector spinae, so "lower back" is recognised as a
    // real muscle name that simply cannot be drawn. It must not be quietly
    // redirected to the lats.
    test('lower back is known but undrawable', () {
      expect(isKnownMuscleGroup('Lower Back'), isTrue);
      expect(musclesForMuscleGroup('Lower Back'), isEmpty);
      expect(musclesForMuscleGroup('lower back'),
          isNot(contains(Muscle.latissimusDorsiLeft)));
    });
  });

  group('musclesForExercise', () {
    test('unions across muscle groups', () {
      final exercise = _exercise(['Chest', 'Triceps']);
      expect(
        musclesForExercise(exercise),
        musclesForMuscleGroup('Chest').union(musclesForMuscleGroup('Triceps')),
      );
    });

    test('a partial match highlights only the recognised part', () {
      final exercise = _exercise(['Chest', 'Wingspan Stabilizers']);
      expect(musclesForExercise(exercise), musclesForMuscleGroup('Chest'));
    });

    test('survives untrimmed values, as Exercise.fromMap produces', () {
      // fromMap splits the stored column on ',' without trimming, so a row
      // written with ', ' separators arrives with leading spaces.
      final exercise = _exercise([' chest ', ' TRICEPS']);
      expect(
        musclesForExercise(exercise),
        musclesForMuscleGroup('Chest').union(musclesForMuscleGroup('Triceps')),
      );
    });

    test('no muscle groups means no highlights', () {
      expect(musclesForExercise(_exercise(const [])), isEmpty);
    });
  });

  group('undrawableMuscleGroups', () {
    test('reports unrecognised groups in entry order, trimmed', () {
      final exercise = _exercise(['Chest', ' Wingspan Stabilizers ', 'Abs']);
      expect(undrawableMuscleGroups(exercise), ['Wingspan Stabilizers']);
    });

    test('de-duplicates by normalized key', () {
      final exercise = _exercise(['Foo', 'foo', ' FOO ']);
      expect(undrawableMuscleGroups(exercise), ['Foo']);
    });

    test('includes known-but-undrawable groups', () {
      expect(undrawableMuscleGroups(_exercise(['Lower Back'])), ['Lower Back']);
    });

    test('is empty when everything maps', () {
      expect(undrawableMuscleGroups(_exercise(['Chest', 'Abs'])), isEmpty);
    });

    test('skips blank entries rather than reporting them', () {
      expect(undrawableMuscleGroups(_exercise(['Chest', '  '])), isEmpty);
    });
  });

  group('preferredViewForExercise', () {
    AtlasAsset viewFor(List<String> groups) =>
        preferredViewForExercise(_exercise(groups));

    test('opens on the back when every group is posterior', () {
      expect(viewFor(['Back', 'Hamstrings', 'Glutes']), AtlasAsset.musclesBack);
      expect(viewFor(['Rear Delts', 'Back']), AtlasAsset.musclesBack);
      expect(viewFor(['Hamstrings']), AtlasAsset.musclesBack);
      expect(viewFor(['Calves']), AtlasAsset.musclesBack);
    });

    test('opens on the front when anything anterior is involved', () {
      expect(viewFor(['Chest', 'Triceps', 'Shoulders']),
          AtlasAsset.musclesFront);
      expect(viewFor(['Quadriceps', 'Glutes']), AtlasAsset.musclesFront);
      expect(viewFor(['Back', 'Biceps']), AtlasAsset.musclesFront);
      expect(viewFor(['Abs']), AtlasAsset.musclesFront);
      expect(viewFor(['Full Body']), AtlasAsset.musclesFront);
    });

    test('ignores undrawable groups instead of counting them as anterior', () {
      expect(viewFor(['Hamstrings', 'Lower Back']), AtlasAsset.musclesBack);
      expect(
        viewFor(['Glutes', 'Wingspan Stabilizers']),
        AtlasAsset.musclesBack,
      );
    });

    test('falls back to the front with nothing drawable', () {
      expect(viewFor(const []), AtlasAsset.musclesFront);
      expect(viewFor(['Wingspan Stabilizers']), AtlasAsset.musclesFront);
      expect(viewFor(['Lower Back']), AtlasAsset.musclesFront);
    });

    // The named seeded exercises are the ones a user is most likely to open
    // first, so pin the view each of them lands on.
    test('picks the informative view for the seeded catalog', () {
      final bySeededName = {
        for (final exercise in Exercise.getDefaultExercises())
          exercise.name: preferredViewForExercise(exercise),
      };

      expect(bySeededName['Bench Press'], AtlasAsset.musclesFront);
      expect(bySeededName['Squat'], AtlasAsset.musclesFront);
      expect(bySeededName['Bicep Curls'], AtlasAsset.musclesFront);
      expect(bySeededName['Crunches'], AtlasAsset.musclesFront);
      expect(bySeededName['Face Pulls'], AtlasAsset.musclesBack);
      expect(bySeededName['Deadlift'], AtlasAsset.musclesBack);
      expect(bySeededName['Romanian Deadlift'], AtlasAsset.musclesBack);
      expect(bySeededName['Leg Curl'], AtlasAsset.musclesBack);
      expect(bySeededName['Calf Raises'], AtlasAsset.musclesBack);
      expect(bySeededName['T-Bar Row'], AtlasAsset.musclesBack);
    });
  });

  group('atlasColorMapping', () {
    const color = Color(0xFF00FF00);

    test('produces one entry per muscle, using catalog instances', () {
      final mapping = atlasColorMapping(musclesForMuscleGroup('Chest'), color);

      expect(mapping, hasLength(2));
      expect(mapping.values, everyElement(color));
      // Identity matters: BodyAtlasView keys its map by identity, so these
      // must be the catalog's own const MuscleInfo objects.
      expect(
        mapping.keys,
        containsAll([
          MuscleCatalog.byMuscle[Muscle.pectoralisMajorLeft],
          MuscleCatalog.byMuscle[Muscle.pectoralisMajorRight],
        ]),
      );
    });

    test('an empty muscle set produces an empty mapping', () {
      expect(atlasColorMapping(const <Muscle>{}, color), isEmpty);
    });

    // If the package ever ships an enum value with no catalog entry,
    // atlasColorMapping would silently drop it and "Full Body" would be
    // quietly incomplete. Assert the two stay in sync.
    test('every muscle the artwork defines has a catalog entry', () {
      final missing = Muscle.values
          .where((m) => MuscleCatalog.byMuscle[m] == null)
          .toList();
      expect(missing, isEmpty);
      expect(
        atlasColorMapping(musclesForMuscleGroup('Full Body'), color),
        hasLength(Muscle.values.length),
      );
    });
  });
}
