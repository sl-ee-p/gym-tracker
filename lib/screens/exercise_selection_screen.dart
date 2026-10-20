import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/exercise.dart';
import '../providers/exercise_provider.dart';
import '../widgets/system_nav_bar_spacer.dart';

class ExerciseSelectionScreen extends StatefulWidget {
  final List<int> excludeExerciseIds; // Exercises already in workout
  
  const ExerciseSelectionScreen({
    super.key,
    this.excludeExerciseIds = const [],
  });

  @override
  State<ExerciseSelectionScreen> createState() => _ExerciseSelectionScreenState();
}

class _ExerciseSelectionScreenState extends State<ExerciseSelectionScreen> {
  final TextEditingController _searchController = TextEditingController();
  int? _selectedCategoryId;
  List<Exercise> _filteredExercises = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterExercises);
    
    // Initial filter
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _filterExercises();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterExercises() {
    final exerciseProvider = context.read<ExerciseProvider>();
    final allExercises = exerciseProvider.exercises;
    final searchQuery = _searchController.text.toLowerCase();

    setState(() {
      _filteredExercises = allExercises.where((exercise) {
        // Exclude exercises already in workout
        if (widget.excludeExerciseIds.contains(exercise.id)) {
          return false;
        }

        // Filter by category
        if (_selectedCategoryId != null && exercise.categoryId != _selectedCategoryId) {
          return false;
        }

        // Filter by search query
        if (searchQuery.isNotEmpty) {
          final matchesName = exercise.name.toLowerCase().contains(searchQuery);
          final matchesMuscleGroups = exercise.muscleGroups
              .any((group) => group.toLowerCase().contains(searchQuery));
          
          return matchesName || matchesMuscleGroups;
        }

        return true;
      }).toList();

      // Sort exercises alphabetically
      _filteredExercises.sort((a, b) => a.name.compareTo(b.name));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const SystemNavBarSpacer(),
      appBar: AppBar(
        title: const Text('Select Exercise'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(120),
          child: Column(
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search exercises...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
              
              // Category Filter
              Consumer<ExerciseProvider>(
                builder: (context, exerciseProvider, child) {
                  final categories = exerciseProvider.categories;
                  
                  return SizedBox(
                    height: 50,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: categories.length + 1, // +1 for "All" option
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          // "All" filter chip
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: const Text('All'),
                              selected: _selectedCategoryId == null,
                              onSelected: (selected) {
                                setState(() {
                                  _selectedCategoryId = null;
                                });
                                _filterExercises();
                              },
                            ),
                          );
                        }
                        
                        final category = categories[index - 1];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(category.name),
                            selected: _selectedCategoryId == category.id,
                            onSelected: (selected) {
                              setState(() {
                                _selectedCategoryId = selected ? category.id : null;
                              });
                              _filterExercises();
                            },
                            avatar: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: category.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      body: Consumer<ExerciseProvider>(
        builder: (context, exerciseProvider, child) {
          if (exerciseProvider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (_filteredExercises.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.excludeExerciseIds.isNotEmpty
                        ? 'No more exercises available'
                        : 'No exercises found',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.excludeExerciseIds.isNotEmpty
                        ? 'All exercises are already in your workout'
                        : 'Try adjusting your search or filters',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _filteredExercises.length,
            itemBuilder: (context, index) {
              final exercise = _filteredExercises[index];
              final category = exerciseProvider.categories
                  .where((cat) => cat.id == exercise.categoryId)
                  .firstOrNull;

              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: Text(
                    exercise.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (category != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: category.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(category.name),
                          ],
                        ),
                      ],
                      if (exercise.muscleGroups.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          exercise.muscleGroups.join(', '),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
                          ),
                        ),
                      ],
                      if (exercise.instructions != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          exercise.instructions!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Exercise type indicators
                      if (exercise.isWeightBased)
                        _buildTypeChip(Icons.fitness_center, 'Weight', context),
                      if (exercise.isRepsBased)
                        _buildTypeChip(Icons.repeat, 'Reps', context),
                      if (exercise.isTimeBased)
                        _buildTypeChip(Icons.timer, 'Time', context),
                      const SizedBox(width: 8),
                      const Icon(Icons.add_circle_outline),
                    ],
                  ),
                  onTap: () => _selectExercise(exercise),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTypeChip(IconData icon, String label, BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSecondaryContainer,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  void _selectExercise(Exercise exercise) {
    Navigator.pop(context, exercise);
  }
}