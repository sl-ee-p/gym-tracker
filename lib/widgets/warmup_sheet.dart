import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/exercise.dart';
import '../providers/user_provider.dart';
import '../utils/app_spacing.dart';
import '../utils/warmup_generator.dart';
import '../utils/weight_format.dart';

/// Works out a warm-up ramp for a working weight and previews it. Resolves
/// to the sets to log — weights in kg — or null if dismissed.
///
/// [initialWorkingWeightKg] pre-fills the field, typically the last working
/// set of the exercise.
Future<List<({double weightKg, int reps})>?> showWarmupSheet(
  BuildContext context, {
  required Exercise exercise,
  double? initialWorkingWeightKg,
}) {
  return showModalBottomSheet<List<({double weightKg, int reps})>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _WarmupSheet(
      exercise: exercise,
      initialWorkingWeightKg: initialWorkingWeightKg,
    ),
  );
}

class _WarmupSheet extends StatefulWidget {
  const _WarmupSheet({required this.exercise, this.initialWorkingWeightKg});

  final Exercise exercise;
  final double? initialWorkingWeightKg;

  @override
  State<_WarmupSheet> createState() => _WarmupSheetState();
}

class _WarmupSheetState extends State<_WarmupSheet> {
  late final TextEditingController _controller;
  late final String _unit;

  @override
  void initState() {
    super.initState();
    _unit = context.read<UserProvider>().weightUnit;
    final initial = widget.initialWorkingWeightKg;
    _controller = TextEditingController(
      text: initial == null ? '' : formatWeightValue(initial, unit: _unit),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The ramp in the display unit, or empty for a missing/invalid weight.
  List<WarmupSet> _ramp() {
    final kg = parseWeightToKg(_controller.text, unit: _unit);
    if (kg == null || kg <= 0) return const [];
    final barKg = context.read<UserProvider>().barWeightFor(widget.exercise);
    return generateWarmups(
      workingWeight: kgToUnit(kg, _unit),
      barWeight: kgToUnit(barKg, _unit),
      unit: _unit,
      usesPlates: widget.exercise.usesPlateCalculator,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ramp = _ramp();

    return Padding(
      // Lift above the keyboard (the field is the first thing focused), or
      // above the navigation bar when the keyboard is closed (edge-to-edge).
      padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg +
              math.max(MediaQuery.viewInsetsOf(context).bottom, MediaQuery.paddingOf(context).bottom)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Warm-up sets', style: theme.textTheme.titleMedium),
          Text(
            widget.exercise.usesPlateCalculator
                ? 'Rounded down to what your plates can load'
                : 'Rounded down to the nearest ${_unit == 'lbs' ? '5 lbs' : '2.5 kg'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            autofocus: widget.initialWorkingWeightKg == null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [DecimalWeightInputFormatter()],
            decoration: InputDecoration(
              labelText: 'Working weight',
              suffixText: _unit,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          if (ramp.isEmpty)
            Text(
              'Enter a working weight above the bar to see the ramp.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final (index, set) in ramp.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  child: Text('W${index + 1}',
                      style: theme.textTheme.labelSmall),
                ),
                title: Text('${formatDecimal(set.weight)} $_unit × ${set.reps}'),
              ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: ramp.isEmpty
                  ? null
                  : () => Navigator.of(context).pop([
                        for (final set in ramp)
                          (weightKg: unitToKg(set.weight, _unit), reps: set.reps),
                      ]),
              icon: const Icon(Icons.whatshot_outlined),
              label: Text(ramp.isEmpty
                  ? 'Log warm-ups'
                  : 'Log ${ramp.length} warm-up set${ramp.length == 1 ? '' : 's'}'),
            ),
          ),
        ],
      ),
    );
  }
}
