import 'package:flutter_body_atlas/flutter_body_atlas.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/utils/muscle_region_mapping.dart';

/// Asserts the muscle mapping against the artwork the package actually ships.
///
/// Deliberately a separate file with no `testWidgets` in it: loading a package
/// asset from `setUpAll` deadlocks once a widget test has run in the same
/// file, because the binding's platform-message pump is no longer being
/// serviced outside a test body.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Guards the editorial front/back rule in muscle_region_mapping.dart against
  // the real artwork: it claims certain groups are only worth viewing from
  // behind, which is only true while those muscles really are absent from the
  // front layer.
  group('the artwork backs up the posterior-view rule', () {
    late String frontSvg;
    late String backSvg;

    setUpAll(() async {
      frontSvg = await AtlasAsset.musclesFront.loadSvg();
      backSvg = await AtlasAsset.musclesBack.loadSvg();
    });

    bool inFront(String id) => frontSvg.contains('id="$id"');
    bool inBack(String id) => backSvg.contains('id="$id"');

    test('rear delts are drawn only on the back layer', () {
      for (final muscle in musclesForMuscleGroup('Rear Delts')) {
        expect(inFront(muscle.id), isFalse, reason: muscle.id);
        expect(inBack(muscle.id), isTrue, reason: muscle.id);
      }
    });

    test('the bulk of the glutes is on the back layer', () {
      final glutes = musclesForMuscleGroup('Glutes');
      final onBack = glutes.where((m) => inBack(m.id)).length;
      final onFront = glutes.where((m) => inFront(m.id)).length;
      expect(onBack, greaterThan(onFront));
    });

    test('chest is drawn only on the front layer', () {
      for (final muscle in musclesForMuscleGroup('Chest')) {
        expect(inFront(muscle.id), isTrue, reason: muscle.id);
        expect(inBack(muscle.id), isFalse, reason: muscle.id);
      }
    });

    test('there really is no erector spinae to map "lower back" onto', () {
      for (final needle in const [
        'erector',
        'spinae',
        'thoracolumbar',
        'quadratus_lumborum',
      ]) {
        expect(frontSvg.contains(needle), isFalse, reason: needle);
        expect(backSvg.contains(needle), isFalse, reason: needle);
      }
    });
  });
}
