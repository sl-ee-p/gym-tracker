import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/exercise_provider.dart';
import '../providers/workout_provider.dart';
import '../widgets/app_overflow_menu.dart';
import '../widgets/exercise_picker_sheet.dart';

class TemplateEditorScreen extends StatefulWidget {
  const TemplateEditorScreen({super.key});

  @override
  State<TemplateEditorScreen> createState() => _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends State<TemplateEditorScreen> {
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  int? _categoryId;
  final List<int> _exerciseIds = [];
  bool _isSaving = false;

  /// exerciseId -> the anchor exerciseId of its superset/circuit group.
  /// Absent means standalone. Mirrors WorkoutProvider's in-memory group
  /// maps, but with no persisted groupOrder — a template's group member
  /// order is simply its members' relative order within [_exerciseIds].
  final Map<int, int> _exerciseGroupIds = {};

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _addExercise() async {
    final selected = await showExercisePickerSheet(
      context,
      title: 'Add Exercise to Template',
      excludeExerciseIds: _exerciseIds.toSet(),
      allowCreateNew: true,
    );

    if (selected?.id != null && mounted) {
      setState(() => _exerciseIds.add(selected!.id!));
    }
  }

  /// Picks 2+ new exercises and adds them to the template already grouped
  /// together, mirroring WorkoutScreen's "Add Superset" action.
  Future<void> _addSuperset() async {
    final selected = await showMultiExercisePickerSheet(
      context,
      title: 'Add Superset to Template',
      excludeExerciseIds: _exerciseIds.toSet(),
      allowCreateNew: true,
    );

    if (selected == null || selected.length < 2 || !mounted) return;

    final ids = selected.map((exercise) => exercise.id!).toList();
    final anchor = ids.first;
    setState(() {
      for (final id in ids) {
        _exerciseIds.add(id);
        _exerciseGroupIds[id] = anchor;
      }
    });
  }

  /// "Group with…": picks other exercises already in the template to join
  /// [exerciseId]'s group, creating one (anchored on [exerciseId]) if it
  /// doesn't already have one.
  Future<void> _groupWithAnother(int exerciseId) async {
    final otherIds = _exerciseIds.toSet()..remove(exerciseId);

    final selected = await showMultiExercisePickerSheet(
      context,
      title: 'Group with…',
      restrictToIds: otherIds,
      minSelection: 1,
    );

    if (selected == null || selected.isEmpty || !mounted) return;

    setState(() {
      final anchor = _exerciseGroupIds[exerciseId] ?? exerciseId;
      _exerciseGroupIds[exerciseId] = anchor;
      for (final exercise in selected) {
        _exerciseGroupIds[exercise.id!] = anchor;
      }
      _makeGroupContiguous(anchor);
    });
  }

  /// Dissolves [exerciseId]'s group membership. A group left with exactly
  /// one remaining member is ungrouped too — a "superset of one" isn't
  /// meaningful.
  void _ungroup(int exerciseId) {
    setState(() {
      final anchor = _exerciseGroupIds.remove(exerciseId);
      if (anchor == null) return;
      final remaining =
          _exerciseIds.where((id) => _exerciseGroupIds[id] == anchor).toList();
      if (remaining.length == 1) {
        _exerciseGroupIds.remove(remaining.single);
      }
    });
  }

  /// Removes [exerciseId] from the template entirely. If it was the anchor
  /// of a group that still has 2+ other members, the group is re-anchored
  /// to its new first member so no row is left pointing at an exercise id
  /// that no longer exists in the template.
  void _removeExercise(int exerciseId) {
    setState(() {
      final anchor = _exerciseGroupIds[exerciseId];
      _exerciseIds.remove(exerciseId);
      _exerciseGroupIds.remove(exerciseId);

      if (anchor == null) return;
      final remaining =
          _exerciseIds.where((id) => _exerciseGroupIds[id] == anchor).toList();
      if (remaining.length == 1) {
        _exerciseGroupIds.remove(remaining.single);
      } else if (remaining.length >= 2 && anchor == exerciseId) {
        final newAnchor = remaining.first;
        for (final id in remaining) {
          _exerciseGroupIds[id] = newAnchor;
        }
      }
    });
  }

  /// Re-splices [_exerciseIds] so every member sharing [anchor] becomes
  /// contiguous, at the position of whichever member currently sits
  /// earliest — mirroring WorkoutProvider's identically-named helper.
  void _makeGroupContiguous(int anchor) {
    final members =
        _exerciseIds.where((id) => _exerciseGroupIds[id] == anchor).toList();
    if (members.length < 2) return;

    final insertAt = members.map(_exerciseIds.indexOf).reduce((a, b) => a < b ? a : b);
    _exerciseIds.removeWhere(members.contains);
    _exerciseIds.insertAll(insertAt, members);
  }

  /// The member list (in template order) of [exerciseId]'s group, or
  /// `null` if it is standalone.
  List<int>? _groupMembersFor(int exerciseId) {
    final anchor = _exerciseGroupIds[exerciseId];
    if (anchor == null) return null;
    return _exerciseIds.where((id) => _exerciseGroupIds[id] == anchor).toList();
  }

  /// Partitions [_exerciseIds] into display rows, the same shape
  /// WorkoutProvider.groupedWorkoutRows produces for the live workout
  /// screen.
  List<List<int>> _groupedRows() {
    final rows = <List<int>>[];
    final emitted = <int>{};
    for (final id in _exerciseIds) {
      final anchor = _exerciseGroupIds[id];
      if (anchor == null) {
        rows.add([id]);
        continue;
      }
      if (!emitted.add(anchor)) continue;
      rows.add(_groupMembersFor(id) ?? [id]);
    }
    return rows;
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a template name')),
      );
      return;
    }
    if (_exerciseIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one exercise')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final exerciseGroupIds = [
        for (final id in _exerciseIds) _exerciseGroupIds[id],
      ];
      await context.read<WorkoutProvider>().createTemplate(
            name: name,
            categoryId: _categoryId,
            notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
            exerciseIds: _exerciseIds,
            exerciseGroupIds: exerciseGroupIds,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save template: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Template'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Template Name',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          Consumer<ExerciseProvider>(
            builder: (context, exerciseProvider, child) {
              return DropdownButtonFormField<int?>(
                value: _categoryId,
                decoration: const InputDecoration(
                  labelText: 'Category (optional)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('None')),
                  ...exerciseProvider.categories.map(
                    (category) => DropdownMenuItem<int?>(
                      value: category.id,
                      child: Text(category.name),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _categoryId = value),
              );
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Exercises',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: _addExercise,
                icon: const Icon(Icons.add),
                label: const Text('Add Exercise'),
              ),
              TextButton.icon(
                onPressed: _addSuperset,
                icon: const Icon(Icons.link),
                label: const Text('Add Superset'),
              ),
            ],
          ),
          if (_exerciseIds.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No exercises added yet',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            )
          else
            Consumer<ExerciseProvider>(
              builder: (context, exerciseProvider, child) {
                final rows = _groupedRows();
                return Column(
                  children: [
                    for (final row in rows)
                      if (row.length == 1)
                        _buildExerciseRow(exerciseProvider, row.first)
                      else
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: Theme.of(context).colorScheme.secondary,
                                width: 3,
                              ),
                            ),
                            borderRadius: BorderRadius.circular(12),
                            color: Theme.of(context)
                                .colorScheme
                                .secondaryContainer
                                .withValues(alpha: 0.2),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 4, bottom: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.link,
                                      size: 16,
                                      color: Theme.of(context).colorScheme.secondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Superset',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: Theme.of(context).colorScheme.secondary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              for (final exerciseId in row)
                                _buildExerciseRow(
                                  exerciseProvider,
                                  exerciseId,
                                  groupSize: row.length,
                                ),
                            ],
                          ),
                        ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  /// One exercise's row, shared by the standalone and grouped rendering.
  /// [groupSize] non-null (only for a grouped exercise) offers "Remove from
  /// superset" alongside the always-available "Group with…".
  Widget _buildExerciseRow(
    ExerciseProvider exerciseProvider,
    int exerciseId, {
    int? groupSize,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          exerciseProvider.getExerciseById(exerciseId)?.name ?? 'Unknown Exercise',
        ),
        trailing: AppOverflowMenu(
          tooltip: 'Exercise options',
          items: [
            AppMenuItem(
              label: 'Group with…',
              icon: Icons.link,
              onSelected: () => _groupWithAnother(exerciseId),
            ),
            if (groupSize != null)
              AppMenuItem(
                label: 'Remove from superset',
                icon: Icons.link_off,
                isDestructive: true,
                onSelected: () => _ungroup(exerciseId),
              ),
            AppMenuItem(
              label: 'Remove from template',
              icon: Icons.close,
              isDestructive: true,
              onSelected: () => _removeExercise(exerciseId),
            ),
          ],
        ),
      ),
    );
  }
}
