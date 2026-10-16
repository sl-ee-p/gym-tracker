import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/progress_provider.dart';
import '../providers/user_provider.dart';
import '../services/weight_repository.dart';
import '../models/weight_entry.dart';
import '../widgets/app_overflow_menu.dart';
import '../utils/app_date.dart';
import '../utils/weight_format.dart';
import 'measurements_tab.dart';

class WeightTrackingScreen extends StatefulWidget {
  const WeightTrackingScreen({super.key});

  @override
  State<WeightTrackingScreen> createState() => _WeightTrackingScreenState();
}

class _WeightTrackingScreenState extends State<WeightTrackingScreen> {
  final WeightRepository _weightRepository = WeightRepository();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  
  List<WeightEntry> _weightEntries = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadWeightEntries();
  }

  @override
  void dispose() {
    _weightController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadWeightEntries() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final entries = await _weightRepository.getAllWeightEntries(limit: 50);
      if (!mounted) return;
      setState(() {
        _weightEntries = entries;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading weight entries: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Body Tracking'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Weight'),
              Tab(text: 'Measurements'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildWeightTab(context),
            const MeasurementsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildWeightTab(BuildContext context) {
    return Column(
        children: [
          // Add Weight Section
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Log Your Weight',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Consumer<UserProvider>(
                    builder: (context, userProvider, child) {
                      return Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _weightController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: const [DecimalWeightInputFormatter()],
                              decoration: InputDecoration(
                                labelText: 'Weight',
                                suffixText: userProvider.weightUnit,
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.monitor_weight),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          FilledButton(
                            onPressed: () => _addWeightEntry(),
                            child: const Text('Add'),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.note),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),

          // Weight History
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _weightEntries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.monitor_weight,
                              size: 64,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No Weight Entries',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Add your first weight entry above',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Weight History',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _weightEntries.length,
                              itemBuilder: (context, index) {
                                final entry = _weightEntries[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: Consumer<UserProvider>(
                                    builder: (context, userProvider, child) {
                                      return ListTile(
                                        isThreeLine:
                                            entry.notes != null && entry.notes!.isNotEmpty,
                                        leading: CircleAvatar(
                                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                          child: Icon(
                                            Icons.monitor_weight,
                                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                        title: Text(
                                          formatWeight(entry.weight,
                                              unit: userProvider.weightUnit),
                                          style: Theme.of(context).textTheme.titleMedium,
                                        ),
                                        subtitle: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(_formatDate(entry.date)),
                                            if (entry.notes != null && entry.notes!.isNotEmpty)
                                              Text(
                                                entry.notes!,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                          ],
                                        ),
                                        trailing: AppOverflowMenu(
                                          tooltip: 'Entry options',
                                          items: [
                                            AppMenuItem(
                                              label: 'Edit',
                                              icon: Icons.edit,
                                              onSelected: () =>
                                                  _editWeightEntry(entry),
                                            ),
                                            AppMenuItem(
                                              label: 'Delete',
                                              icon: Icons.delete,
                                              isDestructive: true,
                                              onSelected: () =>
                                                  _deleteWeightEntry(entry),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
          ),
        ],
    );
  }

  Future<void> _addWeightEntry() async {
    if (_weightController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a weight value')),
      );
      return;
    }

    final userProvider = context.read<UserProvider>();
    // The field holds the display unit; storage is always kg.
    final weightInKg = parseWeightToKg(
      _weightController.text,
      unit: userProvider.weightUnit,
    );
    if (weightInKg == null || weightInKg <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid weight')),
      );
      return;
    }

    try {
      final entry = WeightEntry(
        weight: weightInKg,
        date: DateTime.now(),
        notes: _notesController.text.trim().isEmpty 
            ? null 
            : _notesController.text.trim(),
      );

      await _weightRepository.insertWeightEntry(entry);
      await userProvider.updateCurrentWeight(weightInKg);
      await _refreshProgressData();

      if (!mounted) return;

      // Clear inputs
      _weightController.clear();
      _notesController.clear();

      // Reload entries
      await _loadWeightEntries();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Weight entry added successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding weight entry: $e')),
        );
      }
    }
  }

  Future<void> _editWeightEntry(WeightEntry entry) async {
    final userProvider = context.read<UserProvider>();
    final editWeightController = TextEditingController(
      text: formatWeightValue(entry.weight, unit: userProvider.weightUnit),
    );
    final editNotesController = TextEditingController(text: entry.notes ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Weight Entry'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: editWeightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: const [DecimalWeightInputFormatter()],
              decoration: InputDecoration(
                labelText: 'Weight',
                suffixText: userProvider.weightUnit,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: editNotesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
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
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      editWeightController.dispose();
      editNotesController.dispose();
      return;
    }

    final weightInKg = parseWeightToKg(
      editWeightController.text,
      unit: userProvider.weightUnit,
    );
    if (weightInKg == null || weightInKg <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid weight')),
        );
      }
      editWeightController.dispose();
      editNotesController.dispose();
      return;
    }

    final updatedEntry = WeightEntry(
      id: entry.id,
      weight: weightInKg,
      date: entry.date,
      notes: editNotesController.text.trim().isEmpty
          ? null
          : editNotesController.text.trim(),
    );

    try {
      await _weightRepository.updateWeightEntry(updatedEntry);
      await _syncCurrentWeight();
      await _refreshProgressData();
      await _loadWeightEntries();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Weight entry updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating entry: $e')),
        );
      }
    } finally {
      editWeightController.dispose();
      editNotesController.dispose();
    }
  }

  Future<void> _deleteWeightEntry(WeightEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Weight Entry'),
        content: const Text('Are you sure you want to delete this weight entry?'),
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
      try {
        await _weightRepository.deleteWeightEntry(entry.id!);
        await _syncCurrentWeight();
        await _refreshProgressData();
        await _loadWeightEntries();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Weight entry deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting entry: $e')),
          );
        }
      }
    }
  }

  Future<void> _syncCurrentWeight() async {
    final latestEntry = await _weightRepository.getLatestWeightEntry();
    if (!mounted) return;

    final userProvider = context.read<UserProvider>();
    if (latestEntry == null) {
      await userProvider.clearCurrentWeight();
      return;
    }

    await userProvider.updateCurrentWeight(latestEntry.weight);
  }

  Future<void> _refreshProgressData() async {
    if (!mounted) return;
    final progressProvider = context.read<ProgressProvider>();
    await Future.wait([
      progressProvider.loadWeightProgress(),
      progressProvider.loadWeightStatistics(),
    ]);
  }

  String _formatDate(DateTime date) {
    // daysBetween, not today.difference(entryDate).inDays: two local
    // midnights are 23 or 25 hours apart across a DST transition, so the
    // truncating division silently reported "Yesterday" for today.
    final difference = daysBetween(date, DateTime.now());

    if (difference == 0) {
      return 'Today at ${_formatTime(date)}';
    } else if (difference == 1) {
      return 'Yesterday at ${_formatTime(date)}';
    } else if (difference < 7) {
      return '$difference days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}