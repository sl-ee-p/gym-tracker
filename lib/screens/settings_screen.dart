import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../providers/exercise_provider.dart';
import '../providers/progress_provider.dart';
import '../providers/user_provider.dart';
import '../providers/workout_provider.dart';
import '../services/database_helper.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _isEditingName = false;
  bool _isDataActionInProgress = false;

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
                  
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.info),
                    title: const Text('App Version'),
                    subtitle: const Text('1.0.0'),
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
                  
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.upload_file),
                    title: const Text('Export Data'),
                    subtitle: const Text('Export your workout data'),
                    trailing: TextButton(
                      onPressed: _isDataActionInProgress ? null : _exportData,
                      child: const Text('Export'),
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

  Future<void> _exportData() async {
    if (_isDataActionInProgress) return;

    setState(() {
      _isDataActionInProgress = true;
    });

    try {
      final exportJson = await DatabaseHelper().exportAllTablesAsJson();
      final appDirectory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final exportFile = File(
        '${appDirectory.path}${Platform.pathSeparator}gym_tracker_export_$timestamp.json',
      );

      await exportFile.writeAsString(exportJson);

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export Completed'),
          content: SelectableText(
            'Exported all app tables to:\n${exportFile.path}',
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
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
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
      await Future.wait([
        context.read<UserProvider>().initialize(),
        context.read<ExerciseProvider>().initialize(),
        context.read<WorkoutProvider>().initialize(),
        context.read<ProgressProvider>().initialize(),
      ]);

      if (!mounted) return;
      _nameController.text = context.read<UserProvider>().userName;
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