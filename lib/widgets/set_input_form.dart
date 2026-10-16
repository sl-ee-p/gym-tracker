import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/exercise.dart';
import '../models/exercise_set.dart';
import '../providers/user_provider.dart';
import '../utils/app_spacing.dart';
import '../utils/weight_format.dart';
import 'plate_calculator_sheet.dart';
import 'rpe_picker_sheet.dart';

class SetInputForm extends StatefulWidget {
  final Exercise exercise;

  /// [weight] is kilograms — this form converts out of the display unit
  /// before calling back, so callers never have to think about units.
  /// [partialReps] and [rpe] are null unless their Settings switch is on and
  /// the user filled them in.
  final Function(double? weight, int? reps, Duration? duration, String? notes,
      bool isWarmup, int? partialReps, double? rpe) onSetAdded;

  final VoidCallback? onRestTimerRequested;

  /// Whether this exercise is standalone or the last member (by
  /// groupOrder) of its superset/circuit group — i.e. whether the normal
  /// rest timer applies after a set. Defaults to `true` so every existing
  /// caller (which never passes this) keeps today's exact SnackBar/action.
  final bool isLastInGroup;

  /// Offered instead of [onRestTimerRequested] when [isLastInGroup] is
  /// `false`: starts the shortened "Quick Rest" rather than opening the
  /// full rest-timer picker.
  final VoidCallback? onQuickRestRequested;

  const SetInputForm({
    super.key,
    required this.exercise,
    required this.onSetAdded,
    this.onRestTimerRequested,
    this.isLastInGroup = true,
    this.onQuickRestRequested,
  });

  @override
  State<SetInputForm> createState() => _SetInputFormState();
}

class _SetInputFormState extends State<SetInputForm> {
  final _formKey = GlobalKey<FormState>();
  final _weightController = TextEditingController();
  final _repsController = TextEditingController();
  final _partialRepsController = TextEditingController();
  final _durationMinutesController = TextEditingController();
  final _durationSecondsController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isWarmup = false;
  double? _rpe;

  // Deliberately no pre-filling of the controllers here.
  //
  // This form used to copy the previous set's weight and reps into the fields
  // in initState. Because WorkoutScreen keys it per exercise, re-selecting an
  // exercise remounts the State and the old numbers reappeared — so the panel
  // was never reliably empty, and it was far too easy to log a set you hadn't
  // actually re-entered. The previous sets stay visible in the exercise's
  // sets card.

  @override
  void dispose() {
    _weightController.dispose();
    _repsController.dispose();
    _partialRepsController.dispose();
    _durationMinutesController.dispose();
    _durationSecondsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final unit = userProvider.weightUnit;
    final showPartials =
        userProvider.partialRepsEnabled && widget.exercise.isRepsBased;
    // Weight gets the wider share when a third field joins the row: it
    // carries the unit suffix and the plate-calculator button.
    final weightFlex = showPartials ? 3 : 2;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Add Set',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  // In the header, not the field row: the row already holds
                  // up to three inputs, and a chip is one tap either way.
                  if (userProvider.rpeEnabled) ...[
                    ActionChip(
                      label: Text(
                          _rpe == null ? 'RPE' : 'RPE ${formatRpe(_rpe!)}'),
                      avatar: const Icon(Icons.speed, size: 18),
                      onPressed: _pickRpe,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  FilterChip(
                    label: const Text('Warm-up'),
                    selected: _isWarmup,
                    onSelected: (value) => setState(() => _isWarmup = value),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // crossAxisAlignment.start, plus the reserved error line every
              // field below carries, is what keeps these two inputs aligned.
              // With the Row's default centre alignment, a "Required" under
              // one field grew that column and shoved its neighbour half a
              // line down the moment you submitted an incomplete set.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.exercise.isWeightBased)
                    Expanded(
                      flex: weightFlex,
                      child: TextFormField(
                        controller: _weightController,
                        decoration: _denseDecoration(
                          label: 'Weight',
                          suffixText: unit,
                          // Only offered for movements actually loaded with
                          // plates on a bar — see Exercise.usesPlateCalculator.
                          suffixIcon: widget.exercise.usesPlateCalculator
                              ? IconButton(
                                  icon: const Icon(Icons.calculate_outlined,
                                      size: 20),
                                  tooltip: 'Plate calculator',
                                  onPressed: () => _openPlateCalculator(unit),
                                )
                              : null,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: const [DecimalWeightInputFormatter()],
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Required';
                          }
                          final weight = parseWeightToKg(value, unit: unit);
                          if (weight == null || weight <= 0) return 'Invalid';
                          return null;
                        },
                      ),
                    ),
                  if (widget.exercise.isWeightBased &&
                      widget.exercise.isRepsBased)
                    const SizedBox(width: AppSpacing.md),
                  if (widget.exercise.isRepsBased)
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _repsController,
                        decoration: _denseDecoration(
                          label: 'Reps',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Required';
                          }
                          final reps = int.tryParse(value);
                          if (reps == null || reps <= 0) return 'Invalid';
                          return null;
                        },
                      ),
                    ),
                  if (showPartials) ...[
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _partialRepsController,
                        // Optional, so no validator: empty or 0 is "none".
                        decoration: _denseDecoration(label: 'Partials'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                  ],
                ],
              ),

              if (widget.exercise.isTimeBased) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _durationMinutesController,
                        decoration: _denseDecoration(
                          label: 'Minutes',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        // Reads both fields: a duration is required, but it
                        // can come from either box. Replaces a SnackBar that
                        // fired after submit, well away from the field.
                        validator: (_) => _hasDuration() ? null : 'Required',
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Text(':',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextFormField(
                        controller: _durationSecondsController,
                        decoration: _denseDecoration(
                          label: 'Seconds',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          if (value != null && value.isNotEmpty) {
                            final seconds = int.tryParse(value);
                            if (seconds != null && seconds >= 60) {
                              return 'Max 59';
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 2,
                textInputAction: TextInputAction.done,
              ),

              const SizedBox(height: AppSpacing.lg),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _clearForm,
                      child: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => _submitSet(unit),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Set'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Every numeric field shares this decoration so they stay the same height.
  ///
  /// `helperText: ' '` is load-bearing: it permanently reserves the line the
  /// error message will occupy, so showing or clearing a validation error
  /// doesn't resize the field or nudge anything beside it.
  InputDecoration _denseDecoration({
    required String label,
    String? suffixText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      suffixText: suffixText,
      suffixIcon: suffixIcon,
      border: const OutlineInputBorder(),
      isDense: true,
      helperText: ' ',
    );
  }

  bool _hasDuration() {
    final minutes = int.tryParse(_durationMinutesController.text) ?? 0;
    final seconds = int.tryParse(_durationSecondsController.text) ?? 0;
    return minutes > 0 || seconds > 0;
  }

  Future<void> _openPlateCalculator(String unit) async {
    final barWeightKg =
        context.read<UserProvider>().barWeightFor(widget.exercise);
    final resultKg = await showPlateCalculatorSheet(
      context,
      initialTargetWeightKg: parseWeightToKg(_weightController.text, unit: unit),
      barWeightKg: barWeightKg,
    );
    if (resultKg == null || !mounted) return;
    setState(() {
      _weightController.text = formatWeightValue(resultKg, unit: unit);
    });
  }

  Future<void> _pickRpe() async {
    final choice = await showRpePicker(context, current: _rpe);
    if (choice == null || !mounted) return;
    setState(() => _rpe = choice.rpe);
  }

  void _clearForm() {
    _weightController.clear();
    _repsController.clear();
    _partialRepsController.clear();
    _durationMinutesController.clear();
    _durationSecondsController.clear();
    _notesController.clear();
    setState(() {
      _isWarmup = false;
      _rpe = null;
    });
    // Drop any validation errors along with the text, so an emptied form
    // doesn't sit there still showing "Required".
    _formKey.currentState?.reset();
  }

  void _submitSet(String unit) {
    if (!_formKey.currentState!.validate()) return;

    // The field holds the display unit; storage is always kg.
    final weight = widget.exercise.isWeightBased
        ? parseWeightToKg(_weightController.text, unit: unit)
        : null;

    final reps = widget.exercise.isRepsBased
        ? int.tryParse(_repsController.text)
        : null;

    Duration? duration;
    if (widget.exercise.isTimeBased) {
      final minutes = int.tryParse(_durationMinutesController.text) ?? 0;
      final seconds = int.tryParse(_durationSecondsController.text) ?? 0;
      if (minutes > 0 || seconds > 0) {
        duration = Duration(minutes: minutes, seconds: seconds);
      }
    }

    final notesText = _notesController.text.trim();
    final notes = notesText.isEmpty ? null : notesText;

    // Read the settings again rather than trusting the controller: a value
    // typed before the switch was turned off must not be logged.
    final userProvider = context.read<UserProvider>();
    final typedPartials = int.tryParse(_partialRepsController.text);
    final partialReps = userProvider.partialRepsEnabled &&
            widget.exercise.isRepsBased &&
            typedPartials != null &&
            typedPartials > 0
        ? typedPartials
        : null;
    final rpe = userProvider.rpeEnabled ? _rpe : null;

    widget.onSetAdded(
        weight, reps, duration, notes, _isWarmup, partialReps, rpe);
    _clearForm();

    // Show success feedback with rest timer option. Deliberately no color
    // override — this uses the theme's default inverseSurface SnackBar
    // styling; the new row's own settle-in animation (ExerciseSetsCard) is
    // the visible "this landed" signal, not the SnackBar's color.
    final onRestTimerRequested = widget.onRestTimerRequested;
    final onQuickRestRequested = widget.onQuickRestRequested;
    if (!widget.isLastInGroup) {
      // Mid-superset/circuit: the next exercise is up immediately, so this
      // never opens the full rest-timer picker — only the shortened Quick
      // Rest action (or, if the caller didn't wire that, nothing at all).
      if (onQuickRestRequested != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Set added — on to the next exercise'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Quick Rest (20s)',
              onPressed: onQuickRestRequested,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Set added successfully!'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } else if (onRestTimerRequested != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Set added successfully!'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Start Rest Timer',
            onPressed: onRestTimerRequested,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set added successfully!'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }
}
