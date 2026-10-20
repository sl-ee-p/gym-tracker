import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/exercise_category.dart';
import '../providers/exercise_provider.dart';
import '../utils/app_spacing.dart';
import '../widgets/app_overflow_menu.dart';
import '../widgets/hex_color_picker.dart';
import '../widgets/system_nav_bar_spacer.dart';

/// Add, rename, recolour and delete exercise categories.
///
/// The data layer has supported all of this since the beginning
/// (ExerciseRepository's category CRUD, ExerciseProvider's wrappers) — there
/// was simply no screen wired to it, so the six seeded categories were
/// effectively fixed.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const SystemNavBarSpacer(),
      appBar: AppBar(title: const Text('Exercise Categories')),
      body: Consumer<ExerciseProvider>(
        builder: (context, exerciseProvider, child) {
          final categories = exerciseProvider.categories;
          if (categories.isEmpty) {
            return const _EmptyCategories();
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: categories.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final category = categories[index];
              final exerciseCount = exerciseProvider.exercises
                  .where((exercise) => exercise.categoryId == category.id)
                  .length;

              return ListTile(
                leading: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: category.color,
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(category.name),
                subtitle: Text(
                  [
                    if (category.description != null &&
                        category.description!.trim().isNotEmpty)
                      category.description!.trim(),
                    '$exerciseCount exercise${exerciseCount == 1 ? '' : 's'}',
                  ].join(' · '),
                ),
                trailing: AppOverflowMenu(
                  tooltip: 'Category options',
                  items: [
                    AppMenuItem(
                      label: 'Edit',
                      icon: Icons.edit,
                      onSelected: () => _editCategory(context, category),
                    ),
                    AppMenuItem(
                      label: 'Delete',
                      icon: Icons.delete,
                      isDestructive: true,
                      // Never let the last category go: Exercise.categoryId is
                      // a required non-null column, so there has to be
                      // somewhere for a new exercise to live.
                      enabled: categories.length > 1,
                      onSelected: () => _deleteCategory(context, category),
                    ),
                  ],
                ),
                onTap: () => _editCategory(context, category),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editCategory(context, null),
        icon: const Icon(Icons.add),
        label: const Text('New Category'),
      ),
    );
  }

  Future<void> _editCategory(
    BuildContext context,
    ExerciseCategory? category,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<ExerciseCategory>(
      context: context,
      builder: (context) => _CategoryFormDialog(category: category),
    );
    if (result == null || !context.mounted) return;

    final exerciseProvider = context.read<ExerciseProvider>();
    try {
      if (category == null) {
        await exerciseProvider.addCategory(result);
      } else {
        await exerciseProvider.updateCategory(result);
      }
    } catch (e) {
      // The name column is UNIQUE, so this is nearly always a duplicate.
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.toString().contains('UNIQUE')
                ? 'A category named "${result.name}" already exists.'
                : 'Could not save the category: $e',
          ),
        ),
      );
    }
  }

  Future<void> _deleteCategory(
    BuildContext context,
    ExerciseCategory category,
  ) async {
    if (category.id == null) return;
    final exerciseProvider = context.read<ExerciseProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final count = await exerciseProvider.countExercisesInCategory(category.id!);
    if (!context.mounted) return;

    // A category still holding exercises can't just be deleted — the FK isn't
    // enforced, so those exercises would keep pointing at a category that no
    // longer exists, and deleting them instead would take their entire logged
    // history with them. Offer to move them somewhere else.
    int? reassignTo;
    if (count > 0) {
      reassignTo = await _pickReassignTarget(context, category, count);
      if (reassignTo == null || !context.mounted) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Category'),
          content: Text('Delete "${category.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      if (reassignTo != null) {
        await exerciseProvider.reassignExercises(category.id!, reassignTo);
      }
      await exerciseProvider.deleteCategory(category.id!);
      messenger.showSnackBar(
        SnackBar(content: Text('Deleted "${category.name}"')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not delete the category: $e')),
      );
    }
  }

  /// Asks which category [count] exercises should move to before
  /// [category] is deleted. Returns the target id, or null if cancelled.
  Future<int?> _pickReassignTarget(
    BuildContext context,
    ExerciseCategory category,
    int count,
  ) {
    final others = context
        .read<ExerciseProvider>()
        .categories
        .where((other) => other.id != null && other.id != category.id)
        .toList();

    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${category.name}"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$count exercise${count == 1 ? '' : 's'} still '
              '${count == 1 ? 'uses' : 'use'} this category. '
              'Move ${count == 1 ? 'it' : 'them'} to:',
            ),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final other in others)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: other.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        title: Text(other.name),
                        onTap: () => Navigator.of(context).pop(other.id),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _EmptyCategories extends StatelessWidget {
  const _EmptyCategories();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.category_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No categories', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Add one to start grouping your exercises.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Add/edit form. Pops the built [ExerciseCategory] — persisting is the
/// caller's job, so the dialog stays free of provider and error handling.
class _CategoryFormDialog extends StatefulWidget {
  const _CategoryFormDialog({this.category});

  final ExerciseCategory? category;

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late Color _color;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
    _descriptionController =
        TextEditingController(text: widget.category?.description ?? '');
    _color = widget.category?.color ?? const Color(0xFF0B6E77);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickColor() async {
    final picked = await showHexColorPicker(
      context,
      title: 'Category colour',
      initialColor: _color,
    );
    if (picked != null && mounted) setState(() => _color = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final description = _descriptionController.text.trim();
    Navigator.of(context).pop(
      (widget.category ?? ExerciseCategory(name: '')).copyWith(
        name: _nameController.text.trim(),
        description: description.isEmpty ? null : description,
        colorValue: _color.toARGB32(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.category == null ? 'New Category' : 'Edit Category'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name *',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Enter a name'
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'e.g. Chest, Shoulders, Triceps',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            InkWell(
              onTap: _pickColor,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Colour',
                  border: OutlineInputBorder(),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: _color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(formatHexColor(_color)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
