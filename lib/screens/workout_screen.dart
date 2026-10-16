import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../dialogs/edit_set_dialog.dart';
import '../models/exercise.dart';
import '../models/exercise_set.dart';
import '../providers/workout_provider.dart';
import '../providers/exercise_provider.dart';
import '../providers/progress_provider.dart';
import '../providers/user_provider.dart';
import '../providers/rest_timer_controller.dart';
import '../services/backup_service.dart';
import '../services/home_widget_service.dart';
import '../theme/app_theme.dart';
import 'templates_screen.dart';

import '../widgets/exercise_sets_card.dart';
import '../widgets/set_input_form.dart';
import '../widgets/rest_timer_widget.dart';
import '../widgets/exercise_picker_sheet.dart';
import '../widgets/workout_header_clock.dart';
import '../widgets/app_overflow_menu.dart';
import '../widgets/warmup_sheet.dart';

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  /// Whether the rest-timer sheet is open — nothing more. The countdown lives
  /// in RestTimerController, so this no longer says anything about whether a
  /// timer is running. Kept per-instance rather than in the controller
  /// because two WorkoutScreens can be mounted at once (the nav tab and a
  /// pushed route); a shared flag would render the overlay on both.
  bool _showRestTimer = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // The name moved up here when the in-body header gave its place to
        // the clock. It still matters — a workout started from a template
        // carries that template's name — so it is shown rather than dropped.
        title: Consumer<WorkoutProvider>(
          builder: (context, workoutProvider, child) => Text(
            workoutProvider.activeWorkout?.name ?? 'Workout',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        actions: [
          Consumer<WorkoutProvider>(
            builder: (context, workoutProvider, child) {
              if (workoutProvider.hasActiveWorkout) {
                return AppOverflowMenu(
                  tooltip: 'Workout options',
                  items: [
                    AppMenuItem(
                      label: 'Complete Workout',
                      icon: Icons.check_circle_outline,
                      onSelected: _completeWorkout,
                    ),
                    AppMenuItem(
                      label: 'Cancel Workout',
                      icon: Icons.cancel_outlined,
                      isDestructive: true,
                      onSelected: _cancelWorkout,
                    ),
                  ],
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Consumer<WorkoutProvider>(
        builder: (context, workoutProvider, child) {
          if (!workoutProvider.hasActiveWorkout) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.fitness_center,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Active Workout',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start a new workout to begin tracking your exercises',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () async {
                      await workoutProvider.startWorkout(
                        workoutName: 'My Workout',
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Start Workout'),
                  ),
                  const SizedBox(height: 12),
                  // A second, always-visible way into templates — the
                  // Dashboard's Quick Actions card is user-hideable, and this
                  // is the one screen where starting from a template belongs.
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const TemplatesScreen()),
                      );
                    },
                    icon: const Icon(Icons.playlist_add_check),
                    label: const Text('Start from Template'),
                  ),
                ],
              ),
            );
          }

          final currentWorkoutExercises = workoutProvider.getCurrentWorkoutExercises();
          // Standalone exercises as their own single-item row, grouped
          // exercises (supersets/circuits) as one contiguous multi-item row.
          final groupedRows = workoutProvider.groupedWorkoutRows();

          // Resolve which exercise the set-input form targets. Fall back to the
          // first exercise when nothing is selected (or the selection was
          // removed), so there is always exactly one active input form.
          final int? selectedExerciseId = currentWorkoutExercises
                  .contains(workoutProvider.selectedExerciseId)
              ? workoutProvider.selectedExerciseId
              : (currentWorkoutExercises.isNotEmpty
                  ? currentWorkoutExercises.first
                  : null);

          return Stack(
            children: [
              Column(
                children: [
                  // Workout Header
                  Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // The header's one number, and the whole title now
                        // that the workout name has moved to the AppBar. It
                        // shows elapsed workout time, or the rest countdown
                        // while a timer is running — mid-rest that is the
                        // number you actually want. It watches the timer
                        // internally, so this Consumer subtree is not
                        // rebuilt every second.
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: WorkoutHeaderClock(
                              workoutStartTime: workoutProvider.workoutStartTime,
                              onOpenTimer: _openRestTimer,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: IconButton.filledTonal(
                            onPressed: _showAddExerciseDialog,
                            tooltip: 'Add exercise',
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.add, size: 18),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: IconButton.filledTonal(
                            onPressed: _showAddSupersetDialog,
                            tooltip: 'Add superset',
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.link, size: 18),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.fitness_center,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${currentWorkoutExercises.length} exercises',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(width: 16),
                        Icon(
                          Icons.repeat,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${workoutProvider.currentSets.length} sets',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Exercise List
              Expanded(
                child: currentWorkoutExercises.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_circle_outline,
                              size: 48,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Add your first exercise',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap the + button to get started',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _showAddExerciseDialog,
                              icon: const Icon(Icons.add),
                              label: const Text('Add First Exercise'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: groupedRows.length,
                        itemBuilder: (context, index) {
                          final row = groupedRows[index];

                          if (row.length == 1) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: _buildExerciseEntry(
                                context,
                                workoutProvider,
                                row.first,
                                selectedExerciseId,
                              ),
                            );
                          }

                          // A superset/circuit: rendered as one bordered
                          // block with its members contiguous and closer
                          // together than the gap between unrelated
                          // exercises, so the group reads as a single unit.
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: Container(
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
                                    padding: const EdgeInsets.only(left: 4, bottom: 8),
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
                                  for (var i = 0; i < row.length; i++)
                                    Padding(
                                      padding: EdgeInsets.only(
                                          bottom: i == row.length - 1 ? 0 : 8),
                                      child: _buildExerciseEntry(
                                        context,
                                        workoutProvider,
                                        row[i],
                                        selectedExerciseId,
                                        groupPosition: i + 1,
                                        groupSize: row.length,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          // Rest Timer Overlay
          if (_showRestTimer)
            Positioned.fill(
              child: Container(
                color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.5),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: SingleChildScrollView(
                        child: RestTimerWidget(
                          onDismiss: () {
                            setState(() {
                              _showRestTimer = false;
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
        },
      ),
      // Bottom-left rather than the default endFloat: at the bottom right the
      // extended FAB sat directly over the Add Set button and the last set
      // row, which is exactly where the thumb is during a workout.
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      // A nested Consumer, not a watch at the top of build: the timer notifies
      // once a second, and the body above is a ListView of exercise cards
      // that must not rebuild at that rate.
      floatingActionButton: Consumer2<WorkoutProvider, RestTimerController>(
        builder: (context, workoutProvider, restTimer, child) {
          // Hidden while a timer is active: the header pill is then both the
          // status display and the way back into the sheet, and two competing
          // affordances would disagree about state.
          if (!workoutProvider.hasActiveWorkout ||
              _showRestTimer ||
              restTimer.isActive) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            onPressed: _openRestTimer,
            icon: const Icon(Icons.timer_outlined),
            label: const Text('Rest Timer'),
          );
        },
      ),
    );
  }


  void _openRestTimer() {
    // The weight/reps fields are usually still focused when this fires — from
    // the FAB, from the "Start Rest Timer" SnackBar action after logging a
    // set, or from the header pill — and the keyboard would otherwise sit on
    // top of the timer. FocusManager rather than FocusScope.of(context)
    // because the SnackBar action fires from a different subtree.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _showRestTimer = true;
    });
  }

  Future<void> _editSet(Exercise exercise, ExerciseSet set) async {
    final edited =
        await showEditSetDialog(context, exercise: exercise, set: set);
    if (edited == null || !mounted) return;
    try {
      await context.read<WorkoutProvider>().updateSet(edited);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the set: $e')),
      );
    }
  }

  /// Logs a warm-up ramp for [exercise], worked out from its last working set
  /// in this workout (or a weight the user types).
  Future<void> _addWarmups(Exercise exercise) async {
    final workoutProvider = context.read<WorkoutProvider>();
    final lastWorking = workoutProvider
        .getSetsForExercise(exercise.id!)
        .where((set) => !set.isWarmup && set.weight != null)
        .lastOrNull;

    final sets = await showWarmupSheet(
      context,
      exercise: exercise,
      initialWorkingWeightKg: lastWorking?.weight,
    );
    if (sets == null || !mounted) return;

    try {
      for (final set in sets) {
        await workoutProvider.addSet(
          exerciseId: exercise.id!,
          weight: set.weightKg,
          reps: set.reps,
          isWarmup: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not log the warm-ups: $e')),
      );
    }
  }

  Future<void> _completeWorkout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Workout'),
        content: const Text('Are you sure you want to complete this workout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final progressProvider = context.read<ProgressProvider>();
    final userProvider = context.read<UserProvider>();
    await context.read<WorkoutProvider>().completeWorkout();

    // The dashboard stays mounted underneath a pushed WorkoutScreen, so
    // nothing remounts to refresh the heatmap, goal ring or achievements when
    // this pops. Refresh them here instead — a finished workout is exactly
    // when the "3 of 4 this week" number should move.
    await progressProvider.loadHeatmapData();

    // The one moment the heatmap's data actually changes, so it is also the
    // only moment the home-screen widget needs pushing. Reuses the state
    // loadHeatmapData just fetched rather than re-querying.
    unawaited(HomeWidgetService.refresh(
      workoutDays: progressProvider.workoutDates.toSet(),
      workoutsThisWeek: progressProvider.workoutsThisWeek,
      weeklyGoal: userProvider.weeklyWorkoutGoal,
      themeMode: userProvider.themeMode,
      accentLight: userProvider.accentColorLight,
      accentDark: userProvider.accentColorDark,
      highlightLight: userProvider.highlightColorLight,
      highlightDark: userProvider.highlightColorDark,
    ));

    await _runAutoBackup(userProvider);
  }

  /// Writes the rolling backup after a workout is completed.
  ///
  /// Runs here rather than inside completeWorkout so it is off the critical
  /// path — a slow MediaStore write can no longer stall finishing a workout —
  /// and so the user's setting can be honoured and the result recorded.
  /// Failures surface once, quietly: a backup problem is worth knowing about,
  /// but not worth blocking on.
  Future<void> _runAutoBackup(UserProvider userProvider) async {
    if (!userProvider.autoBackupEnabled) return;

    final outcome = await BackupService.run();
    if (!mounted) return;

    if (outcome.succeeded) {
      await userProvider.recordBackupAt(DateTime.now());
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Automatic backup failed — your workout is saved.'),
        action: SnackBarAction(
          label: 'Details',
          onPressed: () {
            if (!mounted) return;
            showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Backup failed'),
                content: SelectableText(outcome.error ?? 'Unknown error'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _cancelWorkout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Workout'),
        content: const Text('Are you sure you want to cancel this workout? All progress will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep Workout'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Cancel Workout'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<WorkoutProvider>().cancelWorkout();
    }
  }

  Future<void> _showAddExerciseDialog() async {
    final workoutProvider = context.read<WorkoutProvider>();
    final currentExerciseIds = workoutProvider.getCurrentWorkoutExercises().toSet();

    final selectedExercise = await showExercisePickerSheet(
      context,
      title: 'Add Exercise',
      excludeExerciseIds: currentExerciseIds,
      allowCreateNew: true,
    );

    if (selectedExercise != null && mounted) {
      await workoutProvider.addExerciseToWorkout(selectedExercise.id!);
      workoutProvider.selectExercise(selectedExercise.id!);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${selectedExercise.name} added to workout'),
          backgroundColor: context.semanticColors.success,
        ),
      );
    }
  }

  /// The "Add superset" header action: picks 2+ new exercises and adds them
  /// to the workout already grouped together.
  Future<void> _showAddSupersetDialog() async {
    final workoutProvider = context.read<WorkoutProvider>();
    final currentExerciseIds = workoutProvider.getCurrentWorkoutExercises().toSet();

    final selected = await showMultiExercisePickerSheet(
      context,
      title: 'Add Superset',
      excludeExerciseIds: currentExerciseIds,
      allowCreateNew: true,
    );

    if (selected == null || selected.length < 2 || !mounted) return;

    final exerciseIds = selected.map((exercise) => exercise.id!).toList();
    await workoutProvider.groupExercises(exerciseIds);
    workoutProvider.selectExercise(exerciseIds.first);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${selected.length} exercises added as a superset'),
        backgroundColor: context.semanticColors.success,
      ),
    );
  }

  /// "Group with…" from an existing card's overflow menu: picks other
  /// exercises already in this workout to join [exerciseId]'s group,
  /// creating one if it doesn't already have one.
  Future<void> _groupWithAnother(int exerciseId) async {
    final workoutProvider = context.read<WorkoutProvider>();
    final otherExerciseIds = workoutProvider.getCurrentWorkoutExercises().toSet()
      ..remove(exerciseId);

    final selected = await showMultiExercisePickerSheet(
      context,
      title: 'Group with…',
      restrictToIds: otherExerciseIds,
      minSelection: 1,
    );

    if (selected == null || selected.isEmpty || !mounted) return;

    final existingGroup = workoutProvider.groupMembersFor(exerciseId) ?? [exerciseId];
    final newMemberIds = selected
        .map((exercise) => exercise.id!)
        .where((id) => !existingGroup.contains(id));
    final combinedGroup = [...existingGroup, ...newMemberIds];

    await workoutProvider.groupExercises(combinedGroup);
  }

  /// One exercise's card, plus its set-input form when it is the selected
  /// exercise. Shared by both the standalone and the grouped/superset
  /// rendering in the exercise list, differing only in the group badge
  /// ([groupPosition]/[groupSize]) passed through to [ExerciseSetsCard].
  Widget _buildExerciseEntry(
    BuildContext context,
    WorkoutProvider workoutProvider,
    int exerciseId,
    int? selectedExerciseId, {
    int? groupPosition,
    int? groupSize,
  }) {
    final isSelected = exerciseId == selectedExerciseId;
    return Consumer<ExerciseProvider>(
      builder: (context, exerciseProvider, child) {
        final exercise = exerciseProvider.getExerciseById(exerciseId);
        if (exercise == null) return const SizedBox.shrink();

        final sets = workoutProvider.getSetsForExercise(exerciseId);

        return Column(
          children: [
            // Exercise Sets Card — tap to choose which exercise the input
            // form below targets.
            ExerciseSetsCard(
              exercise: exercise,
              sets: sets,
              isActiveWorkout: true,
              isSelected: isSelected,
              groupPosition: groupPosition,
              groupSize: groupSize,
              onTap: () => workoutProvider.selectExercise(exerciseId),
              onEditSet: (set) => _editSet(exercise, set),
              onDeleteSet: (set) async {
                await workoutProvider.deleteSet(set.id!);
              },
              onRemoveExercise: () =>
                  workoutProvider.removeExerciseFromWorkout(exerciseId),
              onGroupWith: () => _groupWithAnother(exerciseId),
              onGenerateWarmups: () => _addWarmups(exercise),
              onUngroup: groupSize != null
                  ? () => workoutProvider.ungroupExercise(exerciseId)
                  : null,
            ),

            // Set Input Form — only for the selected exercise, so there is
            // a single form.
            if (isSelected) ...[
              const SizedBox(height: 16),
              SetInputForm(
                key: ValueKey('set-input-$exerciseId'),
                exercise: exercise,
                onSetAdded: (weight, reps, duration, notes, isWarmup,
                    partialReps, rpe) async {
                  // The record flag is persisted on the set itself, so
                  // there is nothing to hold onto here — the provider's
                  // notifyListeners repaints the badge.
                  await workoutProvider.addSet(
                    exerciseId: exerciseId,
                    weight: weight,
                    reps: reps,
                    duration: duration,
                    isWarmup: isWarmup,
                    notes: notes,
                    partialReps: partialReps,
                    rpe: rpe,
                  );
                  // Logging the next set is the clearest possible "yes, I
                  // saw that the rest ended". No-op in any other phase.
                  if (!context.mounted) return;
                  context.read<RestTimerController>().acknowledgeCompletion();
                },
                onRestTimerRequested: _openRestTimer,
                isLastInGroup: workoutProvider.isLastInGroup(exerciseId),
                onQuickRestRequested: () => context
                    .read<RestTimerController>()
                    .start(RestTimerController.quickRestDuration),
              ),
            ],
          ],
        );
      },
    );
  }
}