import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../utils/app_spacing.dart';
import '../utils/plate_calculator.dart';
import '../utils/weight_format.dart';

/// Opens a modal plate-loading calculator.
///
/// [initialTargetWeightKg] and the returned value are both kilograms — the
/// app's storage unit. Everything shown inside the sheet is converted to
/// UserProvider.weightUnit, and there is deliberately no unit switcher here:
/// if the app is set to kg it's kg, if it's set to lbs it's lbs. A local
/// override was just one more thing to get out of sync with the rest of the
/// screen.
///
/// [barWeightKg] is the empty bar for this exercise. Editable inside the sheet
/// for a one-off (a different bar today), which does not change the exercise's
/// saved value.
Future<double?> showPlateCalculatorSheet(
  BuildContext context, {
  double? initialTargetWeightKg,
  required double barWeightKg,
}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => PlateCalculatorSheet(
      initialTargetWeightKg: initialTargetWeightKg,
      barWeightKg: barWeightKg,
    ),
  );
}

class PlateCalculatorSheet extends StatefulWidget {
  final double? initialTargetWeightKg;
  final double barWeightKg;

  const PlateCalculatorSheet({
    super.key,
    this.initialTargetWeightKg,
    required this.barWeightKg,
  });

  @override
  State<PlateCalculatorSheet> createState() => _PlateCalculatorSheetState();
}

class _PlateCalculatorSheetState extends State<PlateCalculatorSheet> {
  late final String _unit;
  late final TextEditingController _weightController;
  late final TextEditingController _barController;

  @override
  void initState() {
    super.initState();
    _unit = context.read<UserProvider>().weightUnit;

    _weightController = TextEditingController(
      text: widget.initialTargetWeightKg != null
          ? formatWeightValue(widget.initialTargetWeightKg!, unit: _unit)
          : '',
    );
    _barController = TextEditingController(
      text: formatWeightValue(widget.barWeightKg, unit: _unit),
    );
  }

  @override
  void dispose() {
    _weightController.dispose();
    _barController.dispose();
    super.dispose();
  }

  /// Parses a field's text as a number in the display unit. Values inside this
  /// sheet stay in display units throughout — the plate sizes are defined per
  /// unit too — and only the final result is converted back to kg.
  double? _read(TextEditingController controller) {
    final text = controller.text.trim().replaceAll(',', '.');
    return text.isEmpty ? null : double.tryParse(text);
  }

  void _useWeight(double achievedInDisplayUnit) {
    Navigator.of(context).pop(unitToKg(achievedInDisplayUnit, _unit));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetWeight = _read(_weightController);
    // Fall back to the exercise's bar if the field is mid-edit or empty, so
    // the breakdown never silently computes against a 0 kg bar.
    final barWeight = _read(_barController) ??
        kgToUnit(widget.barWeightKg, _unit);
    final plates = PlateDefaults.platesFor(_unit);
    final breakdown = targetWeight != null && targetWeight > 0
        ? PlateCalculator.calculate(
            targetWeight: targetWeight,
            barWeight: barWeight,
            availablePlates: plates)
        : null;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.sm,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Plate Calculator', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _weightController,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: const [DecimalWeightInputFormatter()],
                    decoration: InputDecoration(
                      labelText: 'Target weight',
                      suffixText: _unit,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _barController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: const [DecimalWeightInputFormatter()],
                    decoration: InputDecoration(
                      labelText: 'Bar',
                      suffixText: _unit,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Per side', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            if (breakdown == null)
              Text(
                'Enter a target weight',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else if (breakdown.platesPerSide.isEmpty)
              Text(
                'No plates needed',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: breakdown.platesPerSide
                    .map((entry) => Chip(
                        label: Text(
                            '${entry.value} × ${formatDecimal(entry.key)}$_unit')))
                    .toList(),
              ),
            if (breakdown != null && !breakdown.isExact) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Closest achievable: '
                '${formatDecimal(breakdown.achievedWeight)} $_unit '
                '(${formatDecimal(breakdown.remainder)} $_unit short)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: breakdown != null
                    ? () => _useWeight(breakdown.achievedWeight)
                    : null,
                child: const Text('Use this weight'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
