import 'package:flutter/material.dart';
import 'package:flutter_body_atlas/flutter_body_atlas.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/utils/muscle_region_mapping.dart';
import 'package:gym_app/widgets/muscle_diagram.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

BodyAtlasView<MuscleInfo> _atlas(WidgetTester tester) =>
    tester.widget<BodyAtlasView<MuscleInfo>>(
      find.byType(BodyAtlasView<MuscleInfo>),
    );

/// The colour the diagram assigned to [muscle], via the flattened path-id map
/// the widget actually hands to the SVG mapper.
Color? _colorOf(BodyAtlasView<MuscleInfo> atlas, Muscle muscle) {
  final info = MuscleCatalog.byMuscle[muscle];
  return info == null ? null : atlas.colorMapping?[info];
}

void main() {
  group('MuscleDiagram', () {
    testWidgets('renders a front/back toggle and starts on the given view',
        (tester) async {
      await tester.pumpWidget(
        _host(MuscleDiagram(activeMuscles: musclesForMuscleGroup('Chest'))),
      );

      expect(find.text('Front'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
      expect(_atlas(tester).view, AtlasAsset.musclesFront);
    });

    testWidgets('honours initialView', (tester) async {
      await tester.pumpWidget(
        _host(MuscleDiagram(
          activeMuscles: musclesForMuscleGroup('Glutes'),
          initialView: AtlasAsset.musclesBack,
        )),
      );

      expect(_atlas(tester).view, AtlasAsset.musclesBack);
    });

    testWidgets('the toggle switches the rendered layer', (tester) async {
      await tester.pumpWidget(
        _host(MuscleDiagram(activeMuscles: musclesForMuscleGroup('Chest'))),
      );

      await tester.tap(find.text('Back'));
      await tester.pump();
      expect(_atlas(tester).view, AtlasAsset.musclesBack);

      await tester.tap(find.text('Front'));
      await tester.pump();
      expect(_atlas(tester).view, AtlasAsset.musclesFront);
    });

    testWidgets('highlights active muscles and neutralises the rest',
        (tester) async {
      await tester.pumpWidget(
        _host(MuscleDiagram(activeMuscles: musclesForMuscleGroup('Chest'))),
      );

      final atlas = _atlas(tester);
      final context = tester.element(find.byType(MuscleDiagram));
      final colorScheme = Theme.of(context).colorScheme;

      // Active: the app's dedicated highlight token.
      expect(
        _colorOf(atlas, Muscle.pectoralisMajorLeft),
        colorScheme.secondary,
      );
      expect(
        _colorOf(atlas, Muscle.pectoralisMajorRight),
        colorScheme.secondary,
      );

      // Inactive muscles are recoloured too, not left at the artwork's own
      // flat grey — that's what makes the figure legible in dark mode.
      final quadColor = _colorOf(atlas, Muscle.rectusFemorisLeft);
      expect(quadColor, isNotNull);
      expect(quadColor, isNot(colorScheme.secondary));

      // Every muscle in the catalog gets a colour, so no path falls back to
      // the asset's hard-coded #BDBDBD.
      expect(atlas.colorMapping, hasLength(MuscleCatalog.all.length));
    });

    // The subtle one. `Muscle.externalObliqueLeft/Right` are aggregates over
    // eight digitation paths each, and the catalog ALSO lists those
    // digitations individually. BodyAtlasView flattens colorMapping to
    // {pathId: colour}, so if the digitations were classified on their own
    // (inactive) they would overwrite the aggregate's highlight and obliques
    // would never light up. Deciding by path id is what prevents that.
    testWidgets('an active aggregate also highlights its digitations',
        (tester) async {
      await tester.pumpWidget(
        _host(MuscleDiagram(activeMuscles: musclesForMuscleGroup('Obliques'))),
      );

      final atlas = _atlas(tester);
      final context = tester.element(find.byType(MuscleDiagram));
      final highlight = Theme.of(context).colorScheme.secondary;

      expect(_colorOf(atlas, Muscle.externalObliqueLeft), highlight);
      expect(_colorOf(atlas, Muscle.externalObliqueRight), highlight);

      for (final digitation in [
        Muscle.externalOblique1Left,
        Muscle.externalOblique4Left,
        Muscle.externalOblique8Left,
        Muscle.externalOblique1Right,
        Muscle.externalOblique8Right,
      ]) {
        expect(
          _colorOf(atlas, digitation),
          highlight,
          reason: '$digitation should inherit the aggregate highlight',
        );
      }

      // ...and an unrelated trunk muscle stays neutral.
      expect(
        _colorOf(atlas, Muscle.rectusAbdominis1),
        isNot(highlight),
      );
    });

    testWidgets('an empty muscle set renders a fully neutral figure',
        (tester) async {
      await tester.pumpWidget(
        _host(const MuscleDiagram(activeMuscles: <Muscle>{})),
      );

      final atlas = _atlas(tester);
      final context = tester.element(find.byType(MuscleDiagram));
      final highlight = Theme.of(context).colorScheme.secondary;

      expect(atlas.colorMapping, isNotEmpty);
      expect(
        atlas.colorMapping!.values.any((color) => color == highlight),
        isFalse,
      );
    });

    testWidgets('an unmapped muscle-group string does not throw',
        (tester) async {
      await tester.pumpWidget(
        _host(MuscleDiagram(
          activeMuscles: musclesForMuscleGroup('Wingspan Stabilizers'),
        )),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(BodyAtlasView<MuscleInfo>), findsOneWidget);
    });

    // One theme per pump: comparing two pumpWidget calls in a single test
    // reads back the first tree's colours, so each brightness gets its own.
    for (final (name, themeData) in [
      ('light', ThemeData.light()),
      ('dark', ThemeData.dark()),
    ]) {
      testWidgets('neutral tracks onSurface in the $name theme',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: themeData,
            home: Scaffold(
              body: SingleChildScrollView(
                child: MuscleDiagram(
                  activeMuscles: musclesForMuscleGroup('Chest'),
                ),
              ),
            ),
          ),
        );

        final colorScheme = themeData.colorScheme;
        final atlas = _atlas(tester);

        expect(
          _colorOf(atlas, Muscle.rectusFemorisLeft),
          colorScheme.onSurface.withValues(alpha: 0.25),
        );
        expect(
          _colorOf(atlas, Muscle.pectoralisMajorLeft),
          colorScheme.secondary,
        );
      });
    }

  });
}
