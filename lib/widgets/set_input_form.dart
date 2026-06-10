import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/exercise.dart';

class SetInputForm extends StatefulWidget {
  final Exercise exercise;
  final Function(double? weight, int? reps, Duration? duration, String? notes) onSetAdded;
  final double? previousWeight;
  final int? previousReps;
  final Duration? previousDuration;
  final Function([int? restTime])? onRestTimerRequested;

  const SetInputForm({
    super.key,
    required this.exercise,
    required this.onSetAdded,
    this.previousWeight,
    this.previousReps,
    this.previousDuration,
    this.onRestTimerRequested,
  });

  @override
  State<SetInputForm> createState() => _SetInputFormState();
}

class _SetInputFormState extends State<SetInputForm> {
  final _formKey = GlobalKey<FormState>();
  final _weightController = TextEditingController();
  final _repsController = TextEditingController();
  final _durationMinutesController = TextEditingController();
  final _durationSecondsController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    
    // Pre-fill with previous values if available
    if (widget.previousWeight != null) {
      _weightController.text = widget.previousWeight.toString();
    }
    if (widget.previousReps != null) {
      _repsController.text = widget.previousReps.toString();
    }
    if (widget.previousDuration != null) {
      final duration = widget.previousDuration!;
      _durationMinutesController.text = duration.inMinutes.toString();
      _durationSecondsController.text = (duration.inSeconds % 60).toString();
    }
  }

  @override
  void dispose() {
    _weightController.dispose();
    _repsController.dispose();
    _durationMinutesController.dispose();
    _durationSecondsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Set',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  // Weight Input
                  if (widget.exercise.isWeightBased) ...[
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _weightController,
                        decoration: const InputDecoration(
                          labelText: 'Weight',
                          suffixText: 'kg',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                        ],
                        validator: widget.exercise.isWeightBased 
                            ? (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Required';
                                }
                                final weight = double.tryParse(value);
                                if (weight == null || weight <= 0) {
                                  return 'Invalid';
                                }
                                return null;
                              }
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],

                  // Reps Input
                  if (widget.exercise.isRepsBased) ...[
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _repsController,
                        decoration: const InputDecoration(
                          labelText: 'Reps',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: widget.exercise.isRepsBased
                            ? (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Required';
                                }
                                final reps = int.tryParse(value);
                                if (reps == null || reps <= 0) {
                                  return 'Invalid';
                                }
                                return null;
                              }
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ],
              ),

              // Duration Input
              if (widget.exercise.isTimeBased) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _durationMinutesController,
                        decoration: const InputDecoration(
                          labelText: 'Minutes',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(':'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _durationSecondsController,
                        decoration: const InputDecoration(
                          labelText: 'Seconds',
                          border: OutlineInputBorder(),
                          isDense: true,
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

              // Notes Input
              const SizedBox(height: 12),
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

              const SizedBox(height: 16),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _clearForm,
                      child: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _submitSet,
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

  void _clearForm() {
    _weightController.clear();
    _repsController.clear();
    _durationMinutesController.clear();
    _durationSecondsController.clear();
    _notesController.clear();
  }

  void _submitSet() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Parse values
    double? weight;
    int? reps;
    Duration? duration;
    String? notes;

    if (widget.exercise.isWeightBased && _weightController.text.isNotEmpty) {
      weight = double.tryParse(_weightController.text);
    }

    if (widget.exercise.isRepsBased && _repsController.text.isNotEmpty) {
      reps = int.tryParse(_repsController.text);
    }

    if (widget.exercise.isTimeBased) {
      final minutes = int.tryParse(_durationMinutesController.text) ?? 0;
      final seconds = int.tryParse(_durationSecondsController.text) ?? 0;
      if (minutes > 0 || seconds > 0) {
        duration = Duration(minutes: minutes, seconds: seconds);
      }
    }

    if (_notesController.text.trim().isNotEmpty) {
      notes = _notesController.text.trim();
    }

    // Validate that required fields have values
    if (widget.exercise.isWeightBased && weight == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter weight')),
      );
      return;
    }

    if (widget.exercise.isRepsBased && reps == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter reps')),
      );
      return;
    }

    // All validations passed, submit the set
    widget.onSetAdded(weight, reps, duration, notes);

    // Clear form after successful submission
    _clearForm();

    // Show success feedback with rest timer option
    if (widget.onRestTimerRequested != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Set added successfully!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Start Rest Timer',
            textColor: Colors.white,
            onPressed: () => widget.onRestTimerRequested?.call(),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set added successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }
}