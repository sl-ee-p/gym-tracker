import 'package:flutter/material.dart';
import 'package:flutter_body_atlas/flutter_body_atlas.dart';

/// An anatomical front/back muscle chart with [activeMuscles] highlighted.
///
/// Owns its own view toggle, and is shared unmodified between the standalone
/// Muscle Map screen and the exercise details screen so the two can't drift
/// apart visually.
///
/// Sizes itself: a [MainAxisSize.min] column whose figure is bounded by an
/// [AspectRatio], so it drops into a scroll view without needing an [Expanded]
/// from the caller. [BodyAtlasView] is `SizedBox.expand` internally and would
/// otherwise have no bounded height to work with.
///
/// Deliberately binary — worked / not worked, with no per-muscle intensity —
/// matching [WorkoutHeatmap]'s reasoning: `muscleGroups` records only *which*
/// muscles an exercise involves, never how much, so a gradient would be
/// invented precision.
class MuscleDiagram extends StatefulWidget {
  final Set<Muscle> activeMuscles;

  /// Which view to open on. Callers with an [Exercise] in hand should pass
  /// `preferredViewForExercise(exercise)` so a posterior-only movement does
  /// not open on a blank front view.
  final AtlasAsset initialView;

  const MuscleDiagram({
    super.key,
    required this.activeMuscles,
    this.initialView = AtlasAsset.musclesFront,
  });

  @override
  State<MuscleDiagram> createState() => _MuscleDiagramState();
}

class _MuscleDiagramState extends State<MuscleDiagram> {
  late AtlasAsset _view = widget.initialView;

  @override
  void didUpdateWidget(MuscleDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow the caller's preference when it changes — picking a different
    // exercise in the standalone screen should be able to flip to the back
    // view — but never fight a toggle the user has since pressed.
    if (widget.initialView != oldWidget.initialView) {
      _view = widget.initialView;
    }
  }

  /// Both layers are ~0.52 wide-to-tall (587x1137 front, 596x1133 back). One
  /// shared ratio rather than each layer's own, so the figure doesn't resize
  /// by a few pixels when the view is toggled; `fit: contain` inside
  /// [BodyAtlasView] letterboxes the difference rather than cropping.
  static const double _figureAspectRatio = 587 / 1137;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // The artwork ships as flat greys (#BDBDBD), which is legible on a light
    // background and muddy on a dark one. Every muscle is therefore recoloured
    // rather than only the active ones: a translucent onSurface is the one
    // neutral guaranteed to read as a figure against `surface` in both themes,
    // which no fixed grey and no container token can promise.
    final neutral = colorScheme.onSurface.withValues(alpha: 0.25);
    final highlight = colorScheme.secondary;

    // Resolved to SVG path ids before comparing, not to Muscle values.
    //
    // The two external-oblique entries are aggregates that fan out to eight
    // digitation paths each, and the catalog *also* lists those digitations
    // individually. Deciding per-Muscle would mark the aggregate active and
    // each digitation inactive, and since the widget flattens the map to
    // `{pathId: color}` the later neutral entries would overwrite the
    // aggregate's highlight — obliques would silently never light up.
    final activeParts = <String>{
      for (final muscle in widget.activeMuscles) ...muscle.parts,
    };

    final colorMapping = <MuscleInfo, Color?>{
      for (final info in MuscleCatalog.all)
        info: info.muscle.parts.any(activeParts.contains) ? highlight : neutral,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<AtlasAsset>(
          segments: const [
            ButtonSegment(
              value: AtlasAsset.musclesFront,
              label: Text('Front'),
              icon: Icon(Icons.accessibility_new),
            ),
            ButtonSegment(
              value: AtlasAsset.musclesBack,
              label: Text('Back'),
              icon: Icon(Icons.accessibility),
            ),
          ],
          selected: {_view},
          onSelectionChanged: (selection) =>
              setState(() => _view = selection.first),
        ),
        const SizedBox(height: 16),
        AspectRatio(
          aspectRatio: _figureAspectRatio,
          child: BodyAtlasView<MuscleInfo>(
            view: _view,
            resolver: const MuscleResolver(),
            colorMapping: colorMapping,
          ),
        ),
      ],
    );
  }
}
