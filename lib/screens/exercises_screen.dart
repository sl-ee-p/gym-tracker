import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/exercise_provider.dart';
import '../dialogs/exercise_form_dialog.dart';
import '../widgets/app_overflow_menu.dart';
import 'exercise_details_screen.dart';
import 'muscle_map_screen.dart';

class ExercisesScreen extends StatefulWidget {
  const ExercisesScreen({super.key});

  @override
  State<ExercisesScreen> createState() => _ExercisesScreenState();
}

class _ExercisesScreenState extends State<ExercisesScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercises'),
        actions: [
          IconButton(
            icon: const Icon(Icons.accessibility_new),
            tooltip: 'Muscle map',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MuscleMapScreen()),
              );
            },
          ),
        ],
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
                      controller: _searchController,
                      onChanged: exerciseProvider.setSearchQuery,
                      decoration: InputDecoration(
                        hintText: 'Search exercises...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: exerciseProvider.searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  exerciseProvider.setSearchQuery('');
                                },
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
                            backgroundColor: Color(category.colorValue).withValues(alpha: 0.1),
                            selectedColor: Color(category.colorValue).withValues(alpha: 0.3),
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
                    FilledButton(
                      onPressed: () {
                        _searchController.clear();
                        exerciseProvider.clearFilters();
                      },
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
                        ? Color(category.colorValue).withValues(alpha: 0.2)
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          exercise.isFavorite ? Icons.star : Icons.star_border,
                          color: exercise.isFavorite
                              ? Colors.amber
                              : Theme.of(context).colorScheme.outline,
                        ),
                        tooltip: exercise.isFavorite ? 'Remove from favorites' : 'Add to favorites',
                        onPressed: () => context
                            .read<ExerciseProvider>()
                            .setFavorite(exercise.id!, !exercise.isFavorite),
                      ),
                      AppOverflowMenu(
                        tooltip: 'Exercise options',
                        items: [
                          AppMenuItem(
                            label: 'Edit',
                            icon: Icons.edit,
                            onSelected: () => _editExercise(exercise.id!),
                          ),
                          AppMenuItem(
                            label: 'Delete',
                            icon: Icons.delete,
                            isDestructive: true,
                            onSelected: () => _deleteExercise(exercise.id!),
                          ),
                        ],
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
    // The id, not the row: ExerciseDetailsScreen re-reads it from the provider
    // on every build so an edit made there repaints its own muscle diagram.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExerciseDetailsScreen(exerciseId: exerciseId),
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
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
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