import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/exercise.dart';
import '../models/exercise_set.dart';
import '../providers/user_provider.dart';
import '../utils/app_spacing.dart';
import '../utils/weight_format.dart';
import '../widgets/rpe_picker_sheet.dart';

/// Edits a logged set. Resolves to the edited copy, or null on cancel.
///
/// The copy keeps [set]'s id, workout, exercise, set number and timestamp —
/// editing what was lifted must not move the set in history or change which
/// sets it is compared against for records. The caller saves it (see
/// WorkoutProvider.updateSet, which re-resolves the record flag).
Future<ExerciseSet?> showEditSetDialog(
  BuildContext context, {
  required Exercise exercise,
  required ExerciseSet set,
}) {
  return showDialog<ExerciseSet>(
    context: context,
    builder: (_) => _EditSetDialog(exercise: exercise, set: set),
  );
}

class _EditSetDialog extends StatefulWidget {
  const _EditSetDialog({required this.exercise, required this.set});

  final Exercise exercise;
  final ExerciseSet set;

  @override
  State<_EditSetDialog> createState() => _EditSetDialogState();
}

class _EditSetDialogState extends State<_EditSetDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _weightController;
  late final TextEditingController _repsController;
  late final TextEditingController _partialRepsController;
  late final TextEditingController _minutesController;
  late final TextEditingController _secondsController;
  late final TextEditingController _notesController;
  late bool _isWarmup;
  double? _rpe;

  @override
  void initState() {
    super.initState();
    final set = widget.set;
    final unit = context.read<UserProvider>().weightUnit;
    _weightController = TextEditingController(
      text: set.weight == null ? '' : formatWeightValue(set.weight!, unit: unit),
    );
    _repsController = TextEditingController(text: set.reps?.toString() ?? '');
    _partialRepsController = TextEditingController(
      text: set.hasPartialReps ? set.partialReps.toString() : '',
    );
    _minutesController = TextEditingController(
      text: set.duration == null ? '' : '${set.duration!.inMinutes}',
    );
    _secondsController = TextEditingController(
      text: set.duration == null ? '' : '${set.duration!.inSeconds % 60}',
    );
    _notesController = TextEditingController(text: set.notes ?? '');
    _isWarmup = set.isWarmup;
    _rpe = set.rpe;
  }

  @override
  void dispose() {
    _weightController.dispose();
    _repsController.dispose();
    _partialRepsController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final unit = userProvider.weightUnit;
    final exercise = widget.exercise;
    // Shown when switched on, or when this set already carries a value —
    // turning a setting off must never strand data the user can't edit.
    final showPartials = exercise.isRepsBased &&
        (userProvider.partialRepsEnabled || widget.set.hasPartialReps);
    final showRpe = userProvider.rpeEnabled || widget.set.rpe != null;

    return AlertDialog(
      title: Text('Edit set ${widget.set.setNumber}'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (exercise.isWeightBased) ...[
                TextFormField(
                  controller: _weightController,
                  decoration: InputDecoration(
                    labelText: 'Weight',
                    suffixText: unit,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: const [DecimalWeightInputFormatter()],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Required';
                    }
                    final kg = parseWeightToKg(value, unit: unit);
                    return kg == null || kg <= 0 ? 'Invalid' : null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (exercise.isRepsBased) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _repsController,
                        decoration: const InputDecoration(
                          labelText: 'Reps',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          final reps = int.tryParse(value ?? '');
                          return reps == null || reps <= 0 ? 'Invalid' : null;
                        },
                      ),
                    ),
                    if (showPartials) ...[
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: TextFormField(
                          controller: _partialRepsController,
                          decoration: const InputDecoration(
                            labelText: 'Partials',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (exercise.isTimeBased) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _minutesController,
                        decoration: const InputDecoration(
                          labelText: 'Minutes',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextFormField(
                        controller: _secondsController,
                        decoration: const InputDecoration(
                          labelText: 'Seconds',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          final seconds = int.tryParse(value ?? '');
                          return seconds != null && seconds >= 60
                              ? 'Max 59'
                              : null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  FilterChip(
                    label: const Text('Warm-up'),
                    selected: _isWarmup,
                    onSelected: (value) => setState(() => _isWarmup = value),
                  ),
                  if (showRpe)
                    ActionChip(
                      avatar: const Icon(Icons.speed, size: 18),
                      label: Text(
                          _rpe == null ? 'RPE' : 'RPE ${formatRpe(_rpe!)}'),
                      onPressed: () async {
                        final choice =
                            await showRpePicker(context, current: _rpe);
                        if (choice != null && mounted) {
                          setState(() => _rpe = choice.rpe);
                        }
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => _save(unit),
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save(String unit) {
    if (!_formKey.currentState!.validate()) return;
    final exercise = widget.exercise;

    final minutes = int.tryParse(_minutesController.text) ?? 0;
    final seconds = int.tryParse(_secondsController.text) ?? 0;
    final hasDuration = minutes > 0 || seconds > 0;
    final partials = int.tryParse(_partialRepsController.text);
    final notes = _notesController.text.trim();

    // Built whole rather than via copyWith, so a field emptied in the dialog
    // really becomes null instead of silently keeping its old value.
    final edited = ExerciseSet(
      id: widget.set.id,
      workoutSessionId: widget.set.workoutSessionId,
      exerciseId: widget.set.exerciseId,
      setNumber: widget.set.setNumber,
      timestamp: widget.set.timestamp,
      weight: exercise.isWeightBased
          ? parseWeightToKg(_weightController.text, unit: unit)
          : widget.set.weight,
      reps: exercise.isRepsBased
          ? int.tryParse(_repsController.text)
          : widget.set.reps,
      partialReps: partials != null && partials > 0 ? partials : null,
      duration: exercise.isTimeBased
          ? (hasDuration ? Duration(minutes: minutes, seconds: seconds) : null)
          : widget.set.duration,
      notes: notes.isEmpty ? null : notes,
      isWarmup: _isWarmup,
      rpe: _rpe,
      // Re-resolved by WorkoutProvider.updateSet.
      isPersonalRecord: widget.set.isPersonalRecord,
    );
    Navigator.of(context).pop(edited);
  }
}
