import 'package:flutter/material.dart';

import '../models/exercise_set.dart';
import '../utils/app_spacing.dart';

/// Every selectable RPE: 6 to 10 in half steps. Below 6 is a warm-up by any
/// practical definition, and the scale tops out at 10.
const List<double> rpeValues = [6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10];

/// Asks for a set's RPE. Resolves to null when dismissed (keep the current
/// value), or to a record whose `rpe` is the choice — null there meaning
/// "cleared". The record is what tells "cleared" apart from "dismissed".
Future<({double? rpe})?> showRpePicker(
  BuildContext context, {
  double? current,
}) {
  return showModalBottomSheet<({double? rpe})>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Effort (RPE)', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '10 = nothing left · 9 = one more rep · 8 = two more',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final value in rpeValues)
                    ChoiceChip(
                      label: Text(formatRpe(value)),
                      selected: current == value,
                      onSelected: (_) =>
                          Navigator.of(context).pop((rpe: value)),
                    ),
                ],
              ),
              if (current != null) ...[
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop((rpe: null)),
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear'),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
