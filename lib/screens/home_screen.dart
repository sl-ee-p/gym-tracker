import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/home_block.dart';
import '../providers/user_provider.dart';
import '../providers/workout_provider.dart';
import 'customize_home_screen.dart';
import 'workout_screen.dart';
import 'exercises_screen.dart';
import 'progress_screen.dart';
import 'weight_tracking_screen.dart';
import 'settings_screen.dart';
import 'workout_detail_screen.dart';
import 'templates_screen.dart';
import '../widgets/workout_elapsed_clock.dart';
import '../widgets/workout_heatmap_card.dart';
import '../widgets/weight_goal_card.dart';
import '../utils/app_date.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const DashboardTab(),
    const WorkoutScreen(),
    const ExercisesScreen(),
    const ProgressScreen(),
    const WeightTrackingScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  /// Android's back button used to close the app from any tab, because
  /// switching tabs pushes nothing onto the Navigator — there was never
  /// anything for the system pop to consume. Back now steps to Home first, and
  /// only leaves the app from Home, which is what every other Android app with
  /// a bottom nav does.
  ///
  /// `canPop: false` means "we intend to handle this ourselves": Flutter then
  /// calls [onPopInvokedWithResult] with `didPop == false` instead of popping.
  /// Pushed routes (Settings, Templates, workout detail) sit above this and
  /// still pop normally.
  void _handleSystemBack(bool didPop, Object? result) {
    if (didPop) return;
    setState(() => _selectedIndex = 0);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: _handleSystemBack,
      child: Scaffold(
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: KeyedSubtree(
            key: ValueKey(_selectedIndex),
            child: _screens[_selectedIndex],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onItemTapped,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.fitness_center_outlined),
              selectedIcon: Icon(Icons.fitness_center),
              label: 'Workout',
            ),
            NavigationDestination(
              icon: Icon(Icons.list_outlined),
              selectedIcon: Icon(Icons.list),
              label: 'Exercises',
            ),
            NavigationDestination(
              icon: Icon(Icons.trending_up_outlined),
              selectedIcon: Icon(Icons.trending_up),
              label: 'Progress',
            ),
            NavigationDestination(
              icon: Icon(Icons.monitor_weight_outlined),
              selectedIcon: Icon(Icons.monitor_weight),
              label: 'Weight',
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    // watch, not read: reordering or hiding a block in the customise screen
    // has to repaint this immediately.
    final userProvider = context.watch<UserProvider>();
    final blocks = HomeLayoutCodec.parse(userProvider.homeLayout)
        .visible
        // No goal, no card — dropped here rather than rendered empty, so it
        // doesn't leave a gap between its neighbours.
        .where((block) =>
            block != HomeBlock.weightGoal || userProvider.targetWeight != null)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('PlateLog'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Customise home',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CustomizeHomeScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: blocks.isEmpty
          ? const _AllBlocksHidden()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final block in blocks) ...[
                    _blockFor(context, block),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _blockFor(BuildContext context, HomeBlock block) {
    switch (block) {
      case HomeBlock.welcome:
        return _welcomeBlock(context);
      case HomeBlock.workout:
        return _workoutBlock(context);
      case HomeBlock.quickActions:
        return _quickActionsBlock(context);
      case HomeBlock.heatmap:
        return _heatmapBlock(context);
      case HomeBlock.recent:
        return _recentBlock(context);
      case HomeBlock.weightGoal:
        return const WeightGoalCard(showWhenEmpty: false);
    }
  }

  Widget _welcomeBlock(BuildContext context) {
    return Consumer<UserProvider>(
      builder: (context, userProvider, child) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(
                    Icons.person,
                    size: 30,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome back, ${userProvider.userName}!',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      if (userProvider.currentWeight != null)
                        Text(
                          'Current weight: ${userProvider.formatWeight(userProvider.currentWeight!)}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _workoutBlock(BuildContext context) {
    return Consumer<WorkoutProvider>(
      builder: (context, workoutProvider, child) {
        if (workoutProvider.hasActiveWorkout) {
          return Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.play_circle,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Active Workout',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    workoutProvider.activeWorkout?.name ?? 'Workout in Progress',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (workoutProvider.workoutStartTime != null)
                    ElapsedTime(
                      startTime: workoutProvider.workoutStartTime,
                      builder: (context, elapsed) => Text(
                        'Duration: ${_formatDuration(elapsed)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const WorkoutScreen()),
                        );
                      },
                      child: const Text('Continue Workout'),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ready to work out?',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Start a new workout session to track your progress.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      await workoutProvider.startWorkout();
                      if (context.mounted) {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const WorkoutScreen()),
                        );
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Start Workout'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _quickActionsBlock(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _QuickActionCard(
              title: 'Log Weight',
              icon: Icons.monitor_weight,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WeightTrackingScreen()),
                );
              },
            ),
            _QuickActionCard(
              title: 'View Progress',
              icon: Icons.trending_up,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProgressScreen()),
                );
              },
            ),
            _QuickActionCard(
              title: 'Browse Exercises',
              icon: Icons.list,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ExercisesScreen()),
                );
              },
            ),
            _QuickActionCard(
              title: 'Settings',
              icon: Icons.settings,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
            _QuickActionCard(
              title: 'Templates',
              icon: Icons.playlist_add_check,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TemplatesScreen()),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _heatmapBlock(BuildContext context) {
    return const WorkoutHeatmapCard();
  }

  Widget _recentBlock(BuildContext context) {
    return Consumer<WorkoutProvider>(
      builder: (context, workoutProvider, child) {
        final recentWorkouts = workoutProvider.workoutHistory
            .where((workout) => workout.isCompleted)
            .take(3)
            .toList();
        if (recentWorkouts.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Workouts',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ...recentWorkouts.map((workout) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.fitness_center),
                ),
                title: Text(workout.name ?? 'Workout'),
                subtitle: Text(_formatDate(workout.date)),
                trailing: workout.duration != null 
                    ? Text(workout.formattedDuration)
                    : null,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WorkoutDetailScreen(workout: workout),
                  ),
                ),
              ),
            )),
          ],
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }
  
  String _formatDate(DateTime date) {
    // daysBetween, not today.difference(entryDate).inDays: two local
    // midnights are 23 or 25 hours apart across a DST transition, so the
    // truncating division silently reported "Yesterday" for today.
    final difference = daysBetween(date, DateTime.now());

    if (difference == 0) {
      return 'Today';
    } else if (difference == 1) {
      return 'Yesterday';
    } else if (difference < 7) {
      return '$difference days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

class _QuickActionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
/// Shown when every dashboard block has been hidden. The customise screen
/// warns about this, but there still has to be a way back from it.
class _AllBlocksHidden extends StatelessWidget {
  const _AllBlocksHidden();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.dashboard_customize_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Your home screen is empty',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Every section is hidden. Turn some back on to see them here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CustomizeHomeScreen()),
              ),
              icon: const Icon(Icons.tune),
              label: const Text('Customise home'),
            ),
          ],
        ),
      ),
    );
  }
}
