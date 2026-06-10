import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/exercise_provider.dart';
import '../dialogs/exercise_form_dialog.dart';

class ExercisesScreen extends StatefulWidget {
  const ExercisesScreen({super.key});

  @override
  State<ExercisesScreen> createState() => _ExercisesScreenState();
}

class _ExercisesScreenState extends State<ExercisesScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercises'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(120),
          child: Column(
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Consumer<ExerciseProvider>(
                  builder: (context, exerciseProvider, child) {
                    return TextField(
                      onChanged: exerciseProvider.setSearchQuery,
                      decoration: InputDecoration(
                        hintText: 'Search exercises...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: exerciseProvider.searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () => exerciseProvider.setSearchQuery(''),
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              
              // Category Filter
              SizedBox(
                height: 40,
                child: Consumer<ExerciseProvider>(
                  builder: (context, exerciseProvider, child) {
                    return ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: exerciseProvider.categories.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: const Text('All'),
                              selected: exerciseProvider.selectedCategoryId == null,
                              onSelected: (selected) {
                                if (selected) {
                                  exerciseProvider.setSelectedCategory(null);
                                }
                              },
                            ),
                          );
                        }
                        
                        final category = exerciseProvider.categories[index - 1];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(category.name),
                            selected: exerciseProvider.selectedCategoryId == category.id,
                            onSelected: (selected) {
                              exerciseProvider.setSelectedCategory(
                                selected ? category.id : null,
                              );
                            },
                            backgroundColor: Color(category.colorValue).withOpacity(0.1),
                            selectedColor: Color(category.colorValue).withOpacity(0.3),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
      body: Consumer<ExerciseProvider>(
        builder: (context, exerciseProvider, child) {
          if (exerciseProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final exercises = exerciseProvider.filteredExercises;
          
          if (exercises.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No exercises found',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    exerciseProvider.searchQuery.isNotEmpty 
                        ? 'Try adjusting your search or filters'
                        : 'Add your first exercise to get started',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (exerciseProvider.searchQuery.isNotEmpty || 
                      exerciseProvider.selectedCategoryId != null) ...[
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => exerciseProvider.clearFilters(),
                      child: const Text('Clear Filters'),
                    ),
                  ],
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: exercises.length,
            itemBuilder: (context, index) {
              final exercise = exercises[index];
              final category = exerciseProvider.getCategoryById(exercise.categoryId);
              
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: category != null 
                        ? Color(category.colorValue).withOpacity(0.2)
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.fitness_center,
                      color: category != null 
                          ? Color(category.colorValue)
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  title: Text(exercise.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (category != null) Text(category.name),
                      if (exercise.muscleGroups.isNotEmpty)
                        Text(
                          exercise.muscleGroups.join(', '),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') {
                        _editExercise(exercise.id!);
                      } else if (value == 'delete') {
                        _deleteExercise(exercise.id!);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                  onTap: () => _viewExerciseDetails(exercise.id!),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addExercise,
        icon: const Icon(Icons.add),
        label: const Text('Add Exercise'),
      ),
    );
  }

  void _viewExerciseDetails(int exerciseId) {
    final exerciseProvider = context.read<ExerciseProvider>();
    final exercise = exerciseProvider.getExerciseById(exerciseId);
    
    if (exercise == null) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(exercise.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (exercise.instructions != null) ...[
                const Text('Instructions:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(exercise.instructions!),
                const SizedBox(height: 16),
              ],
              if (exercise.muscleGroups.isNotEmpty) ...[
                const Text('Muscle Groups:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(exercise.muscleGroups.join(', ')),
                const SizedBox(height: 16),
              ],
              const Text('Exercise Type:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (exercise.isWeightBased) 
                    Chip(label: Text('Weight-based'), backgroundColor: Colors.blue.withOpacity(0.2)),
                  if (exercise.isRepsBased)
                    Chip(label: Text('Reps-based'), backgroundColor: Colors.green.withOpacity(0.2)),
                  if (exercise.isTimeBased)
                    Chip(label: Text('Time-based'), backgroundColor: Colors.orange.withOpacity(0.2)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _editExercise(exerciseId);
            },
            child: const Text('Edit'),
          ),
        ],
      ),
    );
  }

  void _editExercise(int exerciseId) async {
    final exerciseProvider = context.read<ExerciseProvider>();
    final exercise = exerciseProvider.getExerciseById(exerciseId);
    
    if (exercise == null) return;
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ExerciseFormDialog(exercise: exercise),
    );
    
    if (result == true) {
      // Exercise was successfully updated, refresh the UI
      setState(() {});
    }
  }

  void _deleteExercise(int exerciseId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Exercise'),
        content: const Text('Are you sure you want to delete this exercise? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<ExerciseProvider>().deleteExercise(exerciseId);
    }
  }

  void _addExercise() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const ExerciseFormDialog(),
    );
    
    if (result == true) {
      // Exercise was successfully added, refresh the UI
      setState(() {});
    }
  }
}