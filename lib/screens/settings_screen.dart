import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../dialogs/target_weight_dialog.dart';
import '../models/reminder_schedule.dart';
import '../providers/exercise_provider.dart';
import '../providers/progress_provider.dart';
import '../providers/user_provider.dart';
import '../providers/workout_provider.dart';
import '../services/backup_service.dart';
import '../services/database_helper.dart';
import '../services/export_service.dart';
import '../services/pdf_report_service.dart';
import '../services/home_widget_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_date.dart';
import '../utils/app_spacing.dart';
import '../utils/weight_format.dart';
import '../widgets/app_overflow_menu.dart';
import '../widgets/hex_color_picker.dart';
import 'categories_screen.dart';

/// What an export writes. [label] is the menu entry; [extension] and
/// [description] feed the filename and the completion dialog.
enum _ExportFormat {
  json('Everything (JSON)', 'json',
      'every table, the format to keep for a full backup'),
  csvSets('Sets (CSV)', 'csv', 'one row per logged set'),
  csvWorkouts('Workouts (CSV)', 'csv', 'one row per completed workout'),
  csvWeight('Body weight (CSV)', 'csv', 'one row per weight entry'),
  csvMeasurements('Measurements (CSV)', 'csv', 'one row per body measurement'),
  pdf('Workout report (PDF)', 'pdf', 'a printable history of your workouts');

  const _ExportFormat(this.label, this.extension, this.description);

  final String label;
  final String extension;
  final String description;

  /// Distinguishes the CSVs from each other on disk — they used to be a
  /// single "csv" export, so the bare timestamped name is no longer enough.
  String get fileSuffix => switch (this) {
        _ExportFormat.json => 'export',
        _ExportFormat.csvSets => 'sets',
        _ExportFormat.csvWorkouts => 'workouts',
        _ExportFormat.csvWeight => 'weight',
        _ExportFormat.csvMeasurements => 'measurements',
        _ExportFormat.pdf => 'report',
      };
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _isEditingName = false;
  bool _isDataActionInProgress = false;

  /// Resolved once. Whether the launcher can take an "add widget" request
  /// doesn't change while this screen is open.
  final Future<bool> _pinSupported = HomeWidgetService.isPinSupported();

  @override
  void initState() {
    super.initState();
    final userProvider = context.read<UserProvider>();
    _nameController.text = userProvider.userName;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // User Profile Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Profile',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  
                  // User Name
                  Row(
                    children: [
                      const Icon(Icons.person),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _isEditingName
                            ? TextField(
                                controller: _nameController,
                                decoration: const InputDecoration(
                                  labelText: 'Name',
                                  border: OutlineInputBorder(),
                                ),
                                autofocus: true,
                                onSubmitted: (_) => _saveName(),
                              )
                            : Consumer<UserProvider>(
                                builder: (context, userProvider, child) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Name',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      Text(
                                        userProvider.userName,
                                        style: Theme.of(context).textTheme.bodyLarge,
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),
                      IconButton(
                        icon: Icon(_isEditingName ? Icons.check : Icons.edit),
                        onPressed: _isEditingName ? _saveName : _editName,
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Current Weight
                  Consumer<UserProvider>(
                    builder: (context, userProvider, child) {
                      return Row(
                        children: [
                          const Icon(Icons.monitor_weight),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Current Weight',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  userProvider.currentWeight != null
                                      ? userProvider.formatWeight(userProvider.currentWeight!)
                                      : 'Not set',
                                  style: Theme.of(context).textTheme.bodyLarge,
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
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Unit Preferences
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Units',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  
                  Consumer<UserProvider>(
                    builder: (context, userProvider, child) {
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.straighten),
                        title: const Text('Weight Unit'),
                        subtitle: Text(userProvider.weightUnit.toUpperCase()),
                        trailing: DropdownButton<String>(
                          value: userProvider.weightUnit,
                          items: const [
                            DropdownMenuItem(value: 'kg', child: Text('Kilograms (kg)')),
                            DropdownMenuItem(value: 'lbs', child: Text('Pounds (lbs)')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              userProvider.updateWeightUnit(value);
                            }
                          },
                        ),
                      );
                    },
                  ),

                  Consumer<UserProvider>(
                    builder: (context, userProvider, child) {
                      final unit = userProvider.weightUnit;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.fitness_center),
                        title: const Text('Default bar weight'),
                        subtitle: const Text(
                          'Used by the plate calculator for exercises that '
                          "don't set their own",
                        ),
                        trailing: Text(
                          formatWeight(userProvider.defaultBarWeightKg,
                              unit: unit),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        onTap: () => _editDefaultBarWeight(userProvider),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Training goal
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Goals',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Consumer<UserProvider>(
                    builder: (context, userProvider, child) {
                      final goal = userProvider.weeklyWorkoutGoal;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.flag_outlined),
                            title: const Text('Weekly workout goal'),
                            subtitle: const Text(
                              'Drives the progress ring on the home screen',
                            ),
                            trailing: Text(
                              '$goal / week',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          // A slider rather than a text field: the useful
                          // range is small and bounded, and 1-7 covers every
                          // realistic training split.
                          Slider(
                            value: goal.clamp(1, 7).toDouble(),
                            min: 1,
                            max: 7,
                            divisions: 6,
                            label: '$goal',
                            onChanged: (value) => userProvider
                                .updateWeeklyWorkoutGoal(value.round()),
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.monitor_weight_outlined),
                            title: const Text('Target body weight'),
                            subtitle: const Text(
                              'Tracked on the Body Weight tab and the home '
                              'screen',
                            ),
                            trailing: Text(
                              userProvider.targetWeight == null
                                  ? 'Not set'
                                  : userProvider
                                      .formatWeight(userProvider.targetWeight!),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            onTap: () => showTargetWeightDialog(context),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Workout logging options
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Workout',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  // These only switch the extra inputs on or off. Anything
                  // already logged keeps showing either way.
                  Consumer<UserProvider>(
                    builder: (context, userProvider, child) {
                      return Column(
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: const Icon(Icons.add_circle_outline),
                            title: const Text('Track partial reps'),
                            subtitle: const Text(
                              'Shown on the set; not counted in volume, 1RM '
                              'or records',
                            ),
                            value: userProvider.partialRepsEnabled,
                            onChanged: userProvider.updatePartialRepsEnabled,
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: const Icon(Icons.speed),
                            title: const Text('Track effort (RPE)'),
                            subtitle: const Text('Rate each set 6–10'),
                            value: userProvider.rpeEnabled,
                            onChanged: userProvider.updateRpeEnabled,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Reminders
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reminders',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Consumer<UserProvider>(
                    builder: (context, userProvider, child) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ReminderSetting(
                            icon: Icons.fitness_center,
                            title: 'Workout reminder',
                            schedule: userProvider.workoutReminder,
                            defaultDays: const {1, 3, 5},
                            onChanged: userProvider.updateWorkoutReminder,
                          ),
                          const Divider(height: 24),
                          _ReminderSetting(
                            icon: Icons.monitor_weight_outlined,
                            title: 'Weigh-in reminder',
                            schedule: userProvider.weighInReminder,
                            defaultDays: const {1},
                            onChanged: userProvider.updateWeighInReminder,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Exercise library management
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Exercise Library',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Consumer<ExerciseProvider>(
                    builder: (context, exerciseProvider, child) {
                      final count = exerciseProvider.categories.length;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.category),
                        title: const Text('Categories'),
                        subtitle: Text(
                          '$count categor${count == 1 ? 'y' : 'ies'} · '
                          'add, rename, recolour or remove',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const CategoriesScreen(),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Appearance
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Appearance',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),

                  Consumer<UserProvider>(
                    builder: (context, userProvider, child) {
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.brightness_6),
                        title: const Text('Theme'),
                        subtitle: SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.light,
                              label: Text('Light'),
                              icon: Icon(Icons.light_mode),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              label: Text('Dark'),
                              icon: Icon(Icons.dark_mode),
                            ),
                            ButtonSegment(
                              value: ThemeMode.system,
                              label: Text('System'),
                              icon: Icon(Icons.brightness_auto),
                            ),
                          ],
                          selected: {userProvider.themeMode},
                          onSelectionChanged: (selection) {
                            userProvider.updateThemeMode(selection.first);
                          },
                        ),
                      );
                    },
                  ),

                  const Divider(height: 24),

                  Consumer<UserProvider>(
                    builder: (context, userProvider, child) {
                      final hasCustomColors =
                          userProvider.accentColorLight != null ||
                              userProvider.accentColorDark != null ||
                              userProvider.highlightColorLight != null ||
                              userProvider.highlightColorDark != null;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Colours',
                                  style:
                                      Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              if (hasCustomColors)
                                TextButton(
                                  onPressed: userProvider.resetThemeColors,
                                  child: const Text('Reset'),
                                ),
                            ],
                          ),
                          Text(
                            'The accent seeds the whole palette; the highlight '
                            'is the secondary colour. Light and dark are set '
                            'separately.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                          const SizedBox(height: 8),
                          _ColorSettingTile(
                            label: 'Accent · Light',
                            value: userProvider.accentColorLight,
                            fallback: AppTheme.defaultAccent,
                            onPicked: (color) => userProvider
                                .updateThemeColors(accentLight: color.toARGB32()),
                          ),
                          _ColorSettingTile(
                            label: 'Highlight · Light',
                            value: userProvider.highlightColorLight,
                            fallback: AppTheme.defaultHighlightLight,
                            onPicked: (color) => userProvider
                                .updateThemeColors(highlightLight: color.toARGB32()),
                          ),
                          _ColorSettingTile(
                            label: 'Accent · Dark',
                            value: userProvider.accentColorDark,
                            fallback: AppTheme.defaultAccent,
                            onPicked: (color) => userProvider
                                .updateThemeColors(accentDark: color.toARGB32()),
                          ),
                          _ColorSettingTile(
                            label: 'Highlight · Dark',
                            value: userProvider.highlightColorDark,
                            fallback: AppTheme.defaultHighlightDark,
                            onPicked: (color) => userProvider
                                .updateThemeColors(highlightDark: color.toARGB32()),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // App Information
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.info),
                    title: Text('App Version'),
                    subtitle: Text('1.0.0'),
                  ),
                  
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.storage),
                    title: const Text('Data Storage'),
                    subtitle: const Text('Local SQLite Database'),
                    trailing: TextButton(
                      onPressed: _showDataInfo,
                      child: const Text('Info'),
                    ),
                  ),

                  // Only rendered where the launcher can actually take a pin
                  // request — Android 8+, and not every launcher supports it.
                  // Elsewhere the widget is still addable by long-pressing the
                  // home screen, so there is nothing to explain here.
                  FutureBuilder<bool>(
                    // The future is held in a field, not created here: this
                    // builder runs on every settings rebuild and would
                    // otherwise fire a fresh platform call each time.
                    future: _pinSupported,
                    builder: (context, snapshot) {
                      if (snapshot.data != true) return const SizedBox.shrink();
                      return const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.widgets_outlined),
                        title: Text('Home screen widget'),
                        subtitle: Text(
                          'Add your weekly goal and 12-week grid to the '
                          'home screen',
                        ),
                        trailing: TextButton(
                          onPressed: HomeWidgetService.requestPin,
                          child: Text('Add'),
                        ),
                      );
                    },
                  ),

                  // Required, not decorative: the muscle-map artwork is
                  // CC BY 4.0, whose terms oblige the app to credit its
                  // author. See the flutter_body_atlas entry in pubspec.yaml.
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.accessibility_new),
                    title: Text('Muscle map artwork'),
                    subtitle: Text(
                      'Anatomical illustrations by Ryan Graves, licensed '
                      'under CC BY 4.0',
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Data Management
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Data Management',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  
                  Consumer<UserProvider>(
                    builder: (context, userProvider, child) {
                      final lastBackup = userProvider.lastBackupAt;
                      return SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.backup_outlined),
                        title: const Text('Automatic backup'),
                        subtitle: Text(
                          userProvider.autoBackupEnabled
                              ? (lastBackup == null
                                  ? 'After each workout, to Downloads/GymTracker'
                                  : 'Last backup: ${_formatBackupTime(lastBackup)}')
                              : 'Off — only manual exports are written',
                        ),
                        value: userProvider.autoBackupEnabled,
                        onChanged: userProvider.updateAutoBackupEnabled,
                      );
                    },
                  ),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.upload_file),
                    title: const Text('Export Data'),
                    subtitle: const Text('Export your workout data'),
                    trailing: AppOverflowMenu(
                      enabled: !_isDataActionInProgress,
                      items: [
                        for (final format in _ExportFormat.values)
                          AppMenuItem(
                            label: format.label,
                            icon: switch (format) {
                              _ExportFormat.json => Icons.data_object,
                              _ExportFormat.pdf => Icons.picture_as_pdf_outlined,
                              _ => Icons.table_chart_outlined,
                            },
                            onSelected: () => _exportData(format),
                          ),
                      ],
                      child: const Text('Export'),
                    ),
                  ),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.settings_backup_restore),
                    title: const Text('Restore from backup'),
                    subtitle: const Text(
                      'Replace all data with an "Everything (JSON)" export',
                    ),
                    trailing: TextButton(
                      onPressed:
                          _isDataActionInProgress ? null : _restoreFromBackup,
                      child: const Text('Restore'),
                    ),
                  ),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.delete_forever,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      'Clear All Data',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    subtitle: const Text('Permanently delete all workout data'),
                    trailing: TextButton(
                      onPressed: _isDataActionInProgress ? null : _clearAllData,
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      child: const Text('Clear'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _editName() {
    setState(() {
      _isEditingName = true;
    });
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      await context.read<UserProvider>().updateUserName(name);
    }
    setState(() {
      _isEditingName = false;
    });
  }

  void _showDataInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Data Storage Info'),
        content: const Text(
          'Your workout data is stored locally on your device using SQLite. '
          'This means your data is private and doesn\'t require an internet connection. '
          'However, it\'s recommended to export your data regularly as a backup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// "Today at 18:04" / "Yesterday at 18:04" / "12/3/2026 at 18:04".
  String _formatBackupTime(DateTime time) {
    final days = daysBetween(time, DateTime.now());
    final clock =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    if (days == 0) return 'Today at $clock';
    if (days == 1) return 'Yesterday at $clock';
    return '${time.day}/${time.month}/${time.year} at $clock';
  }

  /// Prompts for the fallback bar weight used by the plate calculator when an
  /// exercise doesn't define its own. Entered and shown in the display unit;
  /// stored as kg like every other weight.
  Future<void> _editDefaultBarWeight(UserProvider userProvider) async {
    final unit = userProvider.weightUnit;
    final controller = TextEditingController(
      text: formatWeightValue(userProvider.defaultBarWeightKg, unit: unit),
    );

    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Default bar weight'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: const [DecimalWeightInputFormatter()],
          decoration: InputDecoration(
            labelText: 'Bar weight',
            suffixText: unit,
            helperText: 'An Olympic bar is 20 kg / 45 lbs',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final kg = parseWeightToKg(controller.text, unit: unit);
              Navigator.of(context).pop(kg != null && kg > 0 ? kg : null);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (result != null) await userProvider.updateDefaultBarWeight(result);
  }

  Future<void> _exportData(_ExportFormat format) async {
    if (_isDataActionInProgress) return;

    setState(() {
      _isDataActionInProgress = true;
    });

    try {
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;

      final databaseHelper = DatabaseHelper();
      final fileName =
          'gym_tracker_${format.fileSuffix}_$timestamp.${format.extension}';

      // The PDF is bytes rather than text, so it takes the other
      // ExportService entry point; everything else is a string.
      final String exportLocationDescription;
      if (format == _ExportFormat.pdf) {
        final bytes = await PdfReportService.buildWorkoutHistoryReport(
          weightUnit: context.read<UserProvider>().weightUnit,
        );
        exportLocationDescription = await ExportService.exportBytesToDownloads(
          fileName: fileName,
          bytes: bytes,
        );
      } else {
        final content = switch (format) {
          _ExportFormat.json => await databaseHelper.exportAllTablesAsJson(),
          _ExportFormat.csvSets => await databaseHelper.exportAllSetsAsCsv(),
          _ExportFormat.csvWorkouts =>
            await databaseHelper.exportWorkoutsAsCsv(),
          _ExportFormat.csvWeight =>
            await databaseHelper.exportWeightEntriesAsCsv(),
          _ExportFormat.csvMeasurements =>
            await databaseHelper.exportMeasurementsAsCsv(),
          _ExportFormat.pdf => '', // unreachable, handled above
        };
        exportLocationDescription = await ExportService.exportToDownloads(
          fileName: fileName,
          content: content,
        );
      }

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export Completed'),
          content: SelectableText(
            'Exported ${format.description} to:\n$exportLocationDescription',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDataActionInProgress = false;
        });
      }
    }
  }

  /// Reloads every provider after the database was replaced wholesale (Clear
  /// or Restore), in the same order startup uses: UserProvider first, since
  /// ProgressProvider needs its saved date range. Then re-applies what lives
  /// outside the app — scheduled reminders and the home-screen widget.
  Future<void> _reloadAllData() async {
    final userProvider = context.read<UserProvider>();
    final exerciseProvider = context.read<ExerciseProvider>();
    final workoutProvider = context.read<WorkoutProvider>();
    final progressProvider = context.read<ProgressProvider>();

    await userProvider.initialize();
    await Future.wait([
      exerciseProvider.initialize(),
      workoutProvider.initialize(),
      progressProvider.initialize(
        savedDateRange: userProvider.progressDateRange,
      ),
    ]);

    unawaited(userProvider.syncReminders());
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

    if (mounted) _nameController.text = userProvider.userName;
  }

  /// Replaces all data with a picked JSON backup — after confirming what it
  /// holds, and only once a safety copy of the current data is written.
  Future<void> _restoreFromBackup() async {
    if (_isDataActionInProgress) return;

    final ({Map<String, dynamic> backup, BackupSummary summary}) picked;
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Choose a Gym Tracker backup',
        // Any, not custom ['json']: several Android file providers label a
        // .json in Downloads as a generic binary and grey it out. The
        // contents are validated below instead.
        type: FileType.any,
      );
      if (file == null) return;
      picked = BackupService.readBackup(utf8.decode(await file.readAsBytes()));
    } on FormatException catch (e) {
      if (!mounted) return;
      await _showRestoreError(e.message);
      return;
    } catch (e) {
      if (!mounted) return;
      await _showRestoreError('Could not read the file: $e');
      return;
    }
    if (!mounted) return;

    final summary = picked.summary;
    final exportedAt = summary.exportedAt;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore from backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (exportedAt != null)
              Text('Backup from ${_formatBackupTime(exportedAt)}.'),
            const SizedBox(height: 8),
            Text(
              '${summary.workouts} workouts · ${summary.sets} sets · '
              '${summary.weightEntries} weight entries'
              '${summary.measurements > 0 ? ' · ${summary.measurements} measurements' : ''}',
            ),
            const SizedBox(height: 12),
            const Text(
              'This replaces everything currently in the app, settings '
              'included. A copy of your current data is saved to '
              'Downloads/GymTracker first.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDataActionInProgress = true);
    try {
      final String safetyCopy;
      try {
        safetyCopy = await BackupService.writeSafetyCopy();
      } catch (e) {
        if (!mounted) return;
        await _showRestoreError(
            'Could not save a copy of your current data, so nothing was '
            'restored: $e');
        return;
      }

      await BackupService.restore(picked.backup);
      if (!mounted) return;
      await _reloadAllData();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup restored. Previous data saved to $safetyCopy'),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await _showRestoreError(
          'The restore failed and your data was left as it was: $e');
    } finally {
      if (mounted) setState(() => _isDataActionInProgress = false);
    }
  }

  Future<void> _showRestoreError(String message) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore failed'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text(
          'Are you sure you want to delete all your workout data? '
          'This action cannot be undone.',
        ),
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
            child: const Text('Clear All Data'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isDataActionInProgress = true;
    });

    try {
      await DatabaseHelper().clearAllData(reseedDefaults: true);

      if (!mounted) return;
      await _reloadAllData();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All data cleared successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to clear data: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDataActionInProgress = false;
        });
      }
    }
  }
}
/// One weekly reminder: an on/off switch, the weekdays it fires on, and the
/// time. Every change saves immediately and reschedules — see
/// UserProvider.updateWorkoutReminder.
class _ReminderSetting extends StatelessWidget {
  const _ReminderSetting({
    required this.icon,
    required this.title,
    required this.schedule,
    required this.defaultDays,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final ReminderSchedule schedule;

  /// The days a freshly switched-on reminder starts with, so the switch
  /// alone does something useful.
  final Set<int> defaultDays;
  final Future<void> Function(ReminderSchedule) onChanged;

  static const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final enabled = schedule.isEnabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(icon),
          title: Text(title),
          subtitle: Text(enabled
              ? '${_describeDays(schedule.days)} at '
                  '${formatMinutesOfDay(schedule.minutesOfDay)}'
              : 'Off'),
          value: enabled,
          onChanged: (on) => onChanged(ReminderSchedule(
            days: on ? defaultDays : const {},
            minutesOfDay: schedule.minutesOfDay,
          )),
        ),
        if (enabled) ...[
          Wrap(
            spacing: 4,
            children: [
              for (var day = DateTime.monday; day <= DateTime.sunday; day++)
                FilterChip(
                  label: Text(_dayLetters[day - 1]),
                  showCheckmark: false,
                  selected: schedule.days.contains(day),
                  onSelected: (selected) {
                    final days = Set<int>.from(schedule.days);
                    selected ? days.add(day) : days.remove(day);
                    onChanged(ReminderSchedule(
                        days: days, minutesOfDay: schedule.minutesOfDay));
                  },
                ),
            ],
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: const Text('Time'),
            trailing: Text(
              formatMinutesOfDay(schedule.minutesOfDay),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime:
                    TimeOfDay(hour: schedule.hour, minute: schedule.minute),
              );
              if (picked == null) return;
              await onChanged(ReminderSchedule(
                days: schedule.days,
                minutesOfDay: picked.hour * 60 + picked.minute,
              ));
            },
          ),
        ],
      ],
    );
  }

  static String _describeDays(Set<int> days) {
    if (days.length == 7) return 'Every day';
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return (days.toList()..sort()).map((d) => names[d - 1]).join(', ');
  }
}

/// One row of the colour settings: a swatch, the current hex, and a tap target
/// that opens the hex picker. Shows the built-in [fallback] greyed out when
/// [value] is null, so "not customised" is visibly different from "customised
/// to the same colour".
class _ColorSettingTile extends StatelessWidget {
  const _ColorSettingTile({
    required this.label,
    required this.value,
    required this.fallback,
    required this.onPicked,
  });

  final String label;
  final int? value;
  final Color fallback;
  final ValueChanged<Color> onPicked;

  @override
  Widget build(BuildContext context) {
    final color = value != null ? Color(value!) : fallback;
    final isDefault = value == null;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      title: Text(label),
      subtitle: Text(
        isDefault ? '${formatHexColor(color)} · default' : formatHexColor(color),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final picked = await showHexColorPicker(
          context,
          title: label,
          initialColor: color,
        );
        if (picked != null) onPicked(picked);
      },
    );
  }
}
