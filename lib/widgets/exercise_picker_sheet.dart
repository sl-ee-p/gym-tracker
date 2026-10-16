import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../dialogs/exercise_form_dialog.dart';
import '../models/exercise.dart';
import '../providers/exercise_provider.dart';
import '../utils/exercise_search.dart';

/// Opens a modal bottom sheet that lets the user search for and pick an
/// [Exercise] from the catalog (typo-tolerant, via [ExerciseSearch]).
/// Returns the picked exercise, or `null` if dismissed without a selection.
Future<Exercise?> showExercisePickerSheet(
  BuildContext context, {
  String title = 'Select Exercise',
  Set<int> excludeExerciseIds = const {},
  bool allowCreateNew = false,
}) {
  return showModalBottomSheet<Exercise>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ExercisePickerSheet(
      title: title,
      excludeExerciseIds: excludeExerciseIds,
      allowCreateNew: allowCreateNew,
    ),
  );
}

/// Opens the same sheet as [showExercisePickerSheet], but in multi-select
/// mode: rows toggle a checkbox instead of immediately popping, and a
/// bottom button returns every exercise checked so far (disabled below
/// [minSelection] selections). Returns the picked exercises, or `null` if
/// dismissed without confirming a selection.
///
/// Used for building a superset/circuit: [restrictToIds], when given,
/// limits the list to those ids — e.g. "group with an exercise already in
/// this workout/template" only ever offers exercises already in it.
Future<List<Exercise>?> showMultiExercisePickerSheet(
  BuildContext context, {
  String title = 'Select Exercises',
  Set<int> excludeExerciseIds = const {},
  Set<int>? restrictToIds,
  Set<int> preselectedIds = const {},
  int minSelection = 2,
  bool allowCreateNew = false,
}) {
  return showModalBottomSheet<List<Exercise>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ExercisePickerSheet(
      title: title,
      excludeExerciseIds: excludeExerciseIds,
      allowCreateNew: allowCreateNew,
      multiSelect: true,
      restrictToIds: restrictToIds,
      preselectedIds: preselectedIds,
      minSelection: minSelection,
    ),
  );
}

/// Search-and-pick content for [showExercisePickerSheet]. A standalone
/// widget (not an inline closure) so it's independently reusable —
/// e.g. from the add-to-workout flow and the progress-screen exercise
/// picker, which previously each had their own copy of this logic.
class ExercisePickerSheet extends StatefulWidget {
  final String title;
  final Set<int> excludeExerciseIds;

  /// Whether to offer "create a new exercise" when nothing matches the
  /// search. Off by default: a freshly created exercise has no logged
  /// history, so offering this from a progress-viewing picker would just
  /// dead-end at an empty-data screen.
  final bool allowCreateNew;

  /// Opt-in multi-select: rows toggle a checkbox instead of immediately
  /// popping, and a bottom button returns every checked exercise. Off by
  /// default, which keeps every existing single-select call site's
  /// behavior/contract exactly unchanged.
  final bool multiSelect;

  /// In [multiSelect] mode, the minimum number of selections the bottom
  /// button requires before it enables. Ignored otherwise.
  final int minSelection;

  /// When set, the list is filtered down to only these ids — e.g. "group
  /// with an exercise already in this workout/template" only ever offers
  /// exercises already in it, rather than the whole catalog.
  final Set<int>? restrictToIds;

  /// In [multiSelect] mode, ids checked before the user touches anything.
  final Set<int> preselectedIds;

  const ExercisePickerSheet({
    super.key,
    this.title = 'Select Exercise',
    this.excludeExerciseIds = const {},
    this.allowCreateNew = false,
    this.multiSelect = false,
    this.minSelection = 2,
    this.restrictToIds,
    this.preselectedIds = const {},
  });

  @override
  State<ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<ExercisePickerSheet> {
  String _searchQuery = '';

  /// A `Set` literal is a `LinkedHashSet`, so iteration order matches the
  /// order exercises were checked — which is what decides a new group's
  /// member order (and therefore its anchor/id) once this is returned.
  late final Set<int> _selectedIds = {...widget.preselectedIds};

  void _toggleSelected(Exercise exercise) {
    if (exercise.id == null) return;
    setState(() {
      if (!_selectedIds.remove(exercise.id)) {
        _selectedIds.add(exercise.id!);
      }
    });
  }

  void _confirmSelection() {
    final byId = <int, Exercise>{
      for (final exercise in context.read<ExerciseProvider>().exercises)
        if (exercise.id != null) exercise.id!: exercise,
    };
    final selected = [
      for (final id in _selectedIds)
        if (byId.containsKey(id)) byId[id]!,
    ];
    Navigator.of(context).pop(selected);
  }

  /// In single-select mode, immediately returns [exercise] as the pick — the
  /// original behavior. In multi-select mode, adds it to the current
  /// selection instead of popping, so picking can continue: a freshly
  /// created exercise still needs to be checked (or more exercises added)
  /// before the bottom button is used.
  void _resolveCreatedOrFound(Exercise exercise) {
    if (widget.multiSelect) {
      if (exercise.id != null) {
        setState(() => _selectedIds.add(exercise.id!));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${exercise.name}" added to selection.')),
        );
      }
    } else {
      Navigator.of(context).pop(exercise);
    }
  }

  Future<void> _createExerciseFromSearch() async {
    final requestedName = _searchQuery.trim();

    // "Create X" is offered whenever the search finds nothing — including
    // when the only match was filtered out by [excludeExerciseIds], i.e. the
    // exercise is already in this workout or template. Opening the form there
    // would dead-end on a name the duplicate check refuses to accept, so
    // resolve it here instead. Checked before any await, so `context` is safe.
    final existing = requestedName.isEmpty
        ? null
        : context.read<ExerciseProvider>().findByName(requestedName);
    if (existing != null) {
      if (existing.id != null &&
          !widget.excludeExerciseIds.contains(existing.id)) {
        _resolveCreatedOrFound(existing);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${existing.name}" is already added.')),
        );
      }
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ExerciseFormDialog(
        initialName: requestedName.isEmpty ? null : requestedName,
      ),
    );

    if (result != true || !mounted) return;

    if (requestedName.isNotEmpty) {
      final updated = context
          .read<ExerciseProvider>()
          .exercises
          .where((exercise) =>
              exercise.id != null &&
              !widget.excludeExerciseIds.contains(exercise.id))
          .toList();

      final createdMatch = updated
          .where((exercise) =>
              Exercise.normalizeName(exercise.name) ==
              Exercise.normalizeName(requestedName))
          .toList()
        ..sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));

      if (createdMatch.isNotEmpty) {
        if (mounted) _resolveCreatedOrFound(createdMatch.first);
        return;
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exercise created. Tap it below to add it.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ExerciseProvider>(
      builder: (context, exerciseProvider, child) {
        final restrictToIds = widget.restrictToIds;
        final available = exerciseProvider.exercises
            .where((exercise) =>
                exercise.id != null &&
                !widget.excludeExerciseIds.contains(exercise.id) &&
                (restrictToIds == null || restrictToIds.contains(exercise.id)))
            .toList();

        final results = ExerciseProvider.sortFavoritesFirst(
            ExerciseSearch.search(_searchQuery, available));
        final canCreateNamed = _searchQuery.trim().isNotEmpty;

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Search exercises',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: widget.allowCreateNew
                          ? IconButton(
                              onPressed: _createExerciseFromSearch,
                              tooltip: canCreateNamed
                                  ? 'Create "${_searchQuery.trim()}"'
                                  : 'Create new exercise',
                              icon: const Icon(Icons.add_circle_outline),
                            )
                          : null,
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                  if (widget.allowCreateNew) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _createExerciseFromSearch,
                        icon: const Icon(Icons.add),
                        label: Text(canCreateNamed
                            ? 'Create "${_searchQuery.trim()}"'
                            : 'Create new exercise'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Expanded(
                    child: available.isEmpty
                        ? _PickerEmptyState(
                            message: 'No exercises available yet',
                            actionLabel: 'Create first exercise',
                            onAction:
                                widget.allowCreateNew ? _createExerciseFromSearch : null,
                          )
                        : results.isEmpty
                            ? _PickerEmptyState(
                                message: 'No exercises match your search',
                                actionLabel: canCreateNamed
                                    ? 'Create "${_searchQuery.trim()}"'
                                    : 'Create new exercise',
                                onAction: widget.allowCreateNew
                                    ? _createExerciseFromSearch
                                    : null,
                              )
                            : ListView.separated(
                                itemCount: results.length,
                                separatorBuilder: (_, _) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final exercise = results[index];
                                  final isSelected =
                                      widget.multiSelect && _selectedIds.contains(exercise.id);
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: widget.multiSelect
                                        ? Checkbox(
                                            value: isSelected,
                                            onChanged: (_) => _toggleSelected(exercise),
                                          )
                                        : const CircleAvatar(
                                            child: Icon(Icons.fitness_center, size: 18),
                                          ),
                                    title: Text(exercise.name),
                                    subtitle: exercise.muscleGroups.isNotEmpty
                                        ? Text(
                                            exercise.muscleGroups.take(2).join(' • '),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          )
                                        : null,
                                    trailing: widget.multiSelect
                                        ? IconButton(
                                            icon: Icon(
                                              exercise.isFavorite
                                                  ? Icons.star
                                                  : Icons.star_border,
                                              color: exercise.isFavorite
                                                  ? Colors.amber
                                                  : Theme.of(context).colorScheme.outline,
                                            ),
                                            tooltip: exercise.isFavorite
                                                ? 'Remove from favorites'
                                                : 'Add to favorites',
                                            onPressed: () => context
                                                .read<ExerciseProvider>()
                                                .setFavorite(
                                                    exercise.id!, !exercise.isFavorite),
                                          )
                                        : Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: Icon(
                                                  exercise.isFavorite
                                                      ? Icons.star
                                                      : Icons.star_border,
                                                  color: exercise.isFavorite
                                                      ? Colors.amber
                                                      : Theme.of(context).colorScheme.outline,
                                                ),
                                                tooltip: exercise.isFavorite
                                                    ? 'Remove from favorites'
                                                    : 'Add to favorites',
                                                onPressed: () => context
                                                    .read<ExerciseProvider>()
                                                    .setFavorite(
                                                        exercise.id!, !exercise.isFavorite),
                                              ),
                                              const Icon(Icons.chevron_right),
                                            ],
                                          ),
                                    onTap: widget.multiSelect
                                        ? () => _toggleSelected(exercise)
                                        : () => Navigator.of(context).pop(exercise),
                                  );
                                },
                              ),
                  ),
                  if (widget.multiSelect) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _selectedIds.length >= widget.minSelection
                            ? _confirmSelection
                            : null,
                        child: Text(
                          _selectedIds.length >= widget.minSelection
                              ? 'Add ${_selectedIds.length} Exercise${_selectedIds.length == 1 ? '' : 's'}'
                              : 'Select at least ${widget.minSelection}',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PickerEmptyState extends StatelessWidget {
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  const _PickerEmptyState({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          if (onAction != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add),
              label: Text(actionLabel),
            ),
          ],
        ],
      ),
    );
  }
}
