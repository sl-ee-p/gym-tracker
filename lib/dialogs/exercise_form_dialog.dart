import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/exercise.dart';
import '../providers/exercise_provider.dart';
import '../providers/user_provider.dart';
import '../theme/app_theme.dart';
import '../utils/weight_format.dart';

class ExerciseFormDialog extends StatefulWidget {
  final Exercise? exercise; // null for add, non-null for edit
  final String? initialName;
  
  const ExerciseFormDialog({super.key, this.exercise, this.initialName});

  @override
  State<ExerciseFormDialog> createState() => _ExerciseFormDialogState();
}

class _ExerciseFormDialogState extends State<ExerciseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _instructionsController = TextEditingController();
  final _muscleGroupsController = TextEditingController();
  final _barWeightController = TextEditingController();

  int? _selectedCategoryId;
  bool _isWeightBased = true;
  bool _isTimeBased = false;
  bool _isRepsBased = true;
  bool _usesPlateCalculator = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    
    if (widget.exercise != null) {
      // Edit Mode
      _nameController.text = widget.exercise!.name;
      _instructionsController.text = widget.exercise!.instructions ?? '';
      _muscleGroupsController.text = widget.exercise!.muscleGroups.join(', ');
      _selectedCategoryId = widget.exercise!.categoryId;
      _isWeightBased = widget.exercise!.isWeightBased;
      _isTimeBased = widget.exercise!.isTimeBased;
      _isRepsBased = widget.exercise!.isRepsBased;
      _usesPlateCalculator = widget.exercise!.usesPlateCalculator;
      // Shown in the display unit; converted back to kg on save.
      final barWeightKg = widget.exercise!.barWeightKg;
      if (barWeightKg != null) {
        _barWeightController.text = formatWeightValue(
          barWeightKg,
          unit: context.read<UserProvider>().weightUnit,
        );
      }
    } else if (widget.initialName != null && widget.initialName!.trim().isNotEmpty) {
      _nameController.text = widget.initialName!.trim();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _instructionsController.dispose();
    _muscleGroupsController.dispose();
    _barWeightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ExerciseProvider>(
      builder: (context, exerciseProvider, child) {
        final categories = exerciseProvider.categories;
        
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            width: double.maxFinite,
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              // So a duplicate name is called out while typing rather than
              // only after tapping Save.
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Text(
                          widget.exercise == null ? 'Add Exercise' : 'Edit Exercise',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Exercise Name
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Exercise Name *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.fitness_center),
                      ),
                      validator: (value) {
                        final name = value?.trim() ?? '';
                        if (name.isEmpty) {
                          return 'Please enter an exercise name';
                        }
                        // excludingId is null when adding, and the exercise's
                        // own id when editing — so renaming an exercise to
                        // the name it already has still validates.
                        final clash = exerciseProvider.findByName(
                          name,
                          excludingId: widget.exercise?.id,
                        );
                        if (clash != null) {
                          return '"${clash.name}" already exists';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Category Selection
                    DropdownButtonFormField<int>(
                      value: _selectedCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'Category *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.category),
                      ),
                      items: categories.map((category) {
                        return DropdownMenuItem<int>(
                          value: category.id,
                          child: Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: category.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(category.name),
                            ],
                          ),
                        );
                      }).toList(),
                      validator: (value) {
                        if (value == null) {
                          return 'Please select a category';
                        }
                        return null;
                      },
                      onChanged: (value) {
                        setState(() {
                          _selectedCategoryId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Instructions/Notes
                    TextFormField(
                      controller: _instructionsController,
                      decoration: const InputDecoration(
                        labelText: 'Instructions/Notes',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.notes),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 3,
                      textInputAction: TextInputAction.newline,
                    ),
                    const SizedBox(height: 16),

                    // Muscle Groups
                    TextFormField(
                      controller: _muscleGroupsController,
                      decoration: const InputDecoration(
                        labelText: 'Muscle Groups (comma separated)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.accessibility_new),
                        hintText: 'e.g., chest, triceps, shoulders',
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Exercise Type Switches
                    Text(
                      'Exercise Type',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    
                    SwitchListTile(
                      title: const Text('Weight-based'),
                      subtitle: const Text('Track weight lifted'),
                      value: _isWeightBased,
                      onChanged: (value) {
                        setState(() {
                          _isWeightBased = value;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                    ),
                    
                    SwitchListTile(
                      title: const Text('Time-based'),
                      subtitle: const Text('Track duration'),
                      value: _isTimeBased,
                      onChanged: (value) {
                        setState(() {
                          _isTimeBased = value;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                    ),
                    
                    SwitchListTile(
                      title: const Text('Reps-based'),
                      subtitle: const Text('Track repetitions'),
                      value: _isRepsBased,
                      onChanged: (value) {
                        setState(() {
                          _isRepsBased = value;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                    ),

                    // Only meaningful for a weight-based exercise, and only
                    // worth offering on movements actually loaded with plates
                    // — on a machine or a dumbbell press the calculator is
                    // just an extra icon in the weight field.
                    if (_isWeightBased) ...[
                      SwitchListTile(
                        title: const Text('Loaded with plates'),
                        subtitle: const Text('Show the plate calculator'),
                        value: _usesPlateCalculator,
                        onChanged: (value) {
                          setState(() {
                            _usesPlateCalculator = value;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (_usesPlateCalculator) ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _barWeightController,
                          decoration: InputDecoration(
                            labelText: 'Bar weight',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.straighten),
                            suffixText: context.watch<UserProvider>().weightUnit,
                            helperText: 'Leave empty to use the default bar',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: const [DecimalWeightInputFormatter()],
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return null; // empty means "use the default"
                            }
                            final unit = context.read<UserProvider>().weightUnit;
                            final parsed = parseWeightToKg(value, unit: unit);
                            if (parsed == null || parsed <= 0) {
                              return 'Enter a positive weight, or leave empty';
                            }
                            return null;
                          },
                        ),
                      ],
                    ],

                    const SizedBox(height: 24),

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isLoading ? null : () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FilledButton(
                            onPressed: _isLoading ? null : _saveExercise,
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(widget.exercise == null ? 'Add Exercise' : 'Save Changes'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveExercise() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_isWeightBased && !_isTimeBased && !_isRepsBased) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enable at least one of Weight-based, Time-based or Reps-based'),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final exerciseProvider = context.read<ExerciseProvider>();
      final unit = context.read<UserProvider>().weightUnit;

      // Turning off "loaded with plates" also drops any saved bar weight,
      // so re-enabling it later starts from the global default rather than a
      // stale number the user can no longer see.
      final usesPlates = _isWeightBased && _usesPlateCalculator;
      final barWeightKg = usesPlates
          ? parseWeightToKg(_barWeightController.text, unit: unit)
          : null;

      // Parse muscle groups
      final muscleGroups = _muscleGroupsController.text
          .split(',')
          .map((group) => group.trim())
          .where((group) => group.isNotEmpty)
          .toList();

      if (widget.exercise == null) {
        // Add new exercise
        final newExercise = Exercise(
          name: _nameController.text.trim(),
          categoryId: _selectedCategoryId!,
          instructions: _instructionsController.text.trim().isNotEmpty
              ? _instructionsController.text.trim()
              : null,
          muscleGroups: muscleGroups,
          isWeightBased: _isWeightBased,
          isTimeBased: _isTimeBased,
          isRepsBased: _isRepsBased,
          usesPlateCalculator: usesPlates,
          barWeightKg: barWeightKg,
        );
        
        await exerciseProvider.addExercise(newExercise);
      } else {
        // Update existing exercise
        final updatedExercise = widget.exercise!.copyWith(
          name: _nameController.text.trim(),
          categoryId: _selectedCategoryId,
          instructions: _instructionsController.text.trim().isNotEmpty
              ? _instructionsController.text.trim()
              : null,
          muscleGroups: muscleGroups,
          isWeightBased: _isWeightBased,
          isTimeBased: _isTimeBased,
          isRepsBased: _isRepsBased,
          usesPlateCalculator: usesPlates,
          barWeightKg: barWeightKg,
          clearBarWeight: barWeightKg == null,
        );
        
        await exerciseProvider.updateExercise(updatedExercise);
      }

      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate success
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.exercise == null 
                  ? 'Exercise added successfully' 
                  : 'Exercise updated successfully',
            ),
            backgroundColor: context.semanticColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            // DuplicateExerciseNameException already reads as a sentence; an
            // "Error:" prefix would only make it worse.
            content: Text(e is DuplicateExerciseNameException
                ? e.toString()
                : 'Error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}