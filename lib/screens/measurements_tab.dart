import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/body_measurement.dart';
import '../providers/user_provider.dart';
import '../services/measurement_repository.dart';
import '../utils/app_spacing.dart';
import '../utils/length_format.dart';
import '../utils/weight_format.dart';
import '../widgets/app_overflow_menu.dart';
import '../widgets/chart_axis.dart';

/// Body measurements: the latest value of each type, with the change since
/// the entry before it, plus a per-type history. Lives next to body weight
/// on the Weight tab.
///
/// Talks to [MeasurementRepository] directly, as the weight half of the tab
/// does with WeightRepository — nothing else in the app reads measurements,
/// so there is no shared state worth a provider.
class MeasurementsTab extends StatefulWidget {
  const MeasurementsTab({super.key});

  @override
  State<MeasurementsTab> createState() => _MeasurementsTabState();
}

class _MeasurementsTabState extends State<MeasurementsTab> {
  final MeasurementRepository _repository = MeasurementRepository();
  Map<MeasurementType, List<BodyMeasurement>> _latest = const {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final latest = await _repository.getLatestPerType();
      if (!mounted) return;
      setState(() {
        _latest = latest;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading measurements: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading measurements: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lengthUnit = lengthUnitFor(context.watch<UserProvider>().weightUnit);
    final theme = Theme.of(context);

    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        FilledButton.icon(
          onPressed: () => _logMeasurements(lengthUnit),
          icon: const Icon(Icons.add),
          label: const Text('Log measurements'),
        ),
        const SizedBox(height: AppSpacing.lg),
        Card(
          child: Column(
            children: [
              for (final type in MeasurementType.values)
                _MeasurementRow(
                  type: type,
                  entries: _latest[type] ?? const [],
                  lengthUnit: lengthUnit,
                  onTap: () => _openHistory(type),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Lengths follow your weight unit: cm with kg, inches with lbs.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// One dialog for a whole session: every type as an optional field, so a
  /// monthly check-in is one screen, and logging just a waist still works.
  Future<void> _logMeasurements(String lengthUnit) async {
    final entries = await showDialog<List<BodyMeasurement>>(
      context: context,
      builder: (_) => _LogMeasurementsDialog(lengthUnit: lengthUnit),
    );
    if (entries == null || entries.isEmpty || !mounted) return;

    try {
      for (final entry in entries) {
        await _repository.insertMeasurement(entry);
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(entries.length == 1
              ? 'Measurement saved'
              : '${entries.length} measurements saved'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving measurements: $e')),
      );
    }
  }

  Future<void> _openHistory(MeasurementType type) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MeasurementHistorySheet(
        type: type,
        repository: _repository,
      ),
    );
    // Entries may have been edited or deleted from the sheet.
    await _load();
  }
}

/// Formats a stored value for [type]: a length in [lengthUnit], or a
/// percentage for body fat.
String _formatValue(MeasurementType type, double value, String lengthUnit) =>
    type.isLength
        ? formatLength(value, lengthUnit: lengthUnit)
        : '${formatDecimal(value)}%';

String _formatDate(DateTime date) => '${date.day}/${date.month}/${date.year}';

class _MeasurementRow extends StatelessWidget {
  const _MeasurementRow({
    required this.type,
    required this.entries,
    required this.lengthUnit,
    required this.onTap,
  });

  final MeasurementType type;

  /// Newest first, at most two.
  final List<BodyMeasurement> entries;
  final String lengthUnit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final latest = entries.isEmpty ? null : entries.first;
    final previous = entries.length > 1 ? entries[1] : null;

    String? change;
    if (latest != null && previous != null) {
      final delta = latest.value - previous.value;
      final shown = type.isLength ? cmToUnit(delta.abs(), lengthUnit) : delta.abs();
      final suffix = type.isLength ? ' $lengthUnit' : '%';
      change = delta == 0
          ? 'no change'
          : '${delta > 0 ? '+' : '−'}${formatDecimal(shown)}$suffix';
    }

    return ListTile(
      title: Text(type.label),
      subtitle: Text(
        latest == null ? 'No entries yet' : _formatDate(latest.date),
        style: muted,
      ),
      trailing: latest == null
          ? const Icon(Icons.chevron_right)
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatValue(type, latest.value, lengthUnit),
                  style: theme.textTheme.titleSmall,
                ),
                if (change != null) Text(change, style: muted),
              ],
            ),
      onTap: onTap,
    );
  }
}

class _LogMeasurementsDialog extends StatefulWidget {
  const _LogMeasurementsDialog({required this.lengthUnit});

  final String lengthUnit;

  @override
  State<_LogMeasurementsDialog> createState() => _LogMeasurementsDialogState();
}

class _LogMeasurementsDialogState extends State<_LogMeasurementsDialog> {
  final Map<MeasurementType, TextEditingController> _controllers = {
    for (final type in MeasurementType.values) type: TextEditingController(),
  };
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Log measurements'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(_formatDate(_date)),
              subtitle: const Text('Fill in any you measured'),
              onTap: _pickDate,
            ),
            for (final type in MeasurementType.values)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: TextField(
                  controller: _controllers[type],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: const [DecimalWeightInputFormatter()],
                  decoration: InputDecoration(
                    labelText: type.label,
                    suffixText: type.isLength ? widget.lengthUnit : '%',
                    border: const OutlineInputBorder(),
                    isDense: true,
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
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    // Keep the time of day, so two check-ins on one day still sort.
    final now = DateTime.now();
    setState(() => _date = DateTime(
        picked.year, picked.month, picked.day, now.hour, now.minute));
  }

  void _save() {
    final entries = <BodyMeasurement>[];
    for (final type in MeasurementType.values) {
      final text = _controllers[type]!.text;
      final value = type.isLength
          ? parseLengthToCm(text, lengthUnit: widget.lengthUnit)
          : double.tryParse(text.trim().replaceAll(',', '.'));
      if (value == null || value <= 0) continue;
      entries.add(BodyMeasurement(type: type, value: value, date: _date));
    }
    Navigator.of(context).pop(entries);
  }
}

class _MeasurementHistorySheet extends StatefulWidget {
  const _MeasurementHistorySheet({
    required this.type,
    required this.repository,
  });

  final MeasurementType type;
  final MeasurementRepository repository;

  @override
  State<_MeasurementHistorySheet> createState() =>
      _MeasurementHistorySheetState();
}

class _MeasurementHistorySheetState extends State<_MeasurementHistorySheet> {
  List<BodyMeasurement> _entries = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await widget.repository.getEntries(widget.type);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading ${widget.type.key} history: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lengthUnit = lengthUnitFor(context.watch<UserProvider>().weightUnit);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        if (_isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          children: [
            Text(widget.type.label, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            if (_entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Text(
                  'No entries yet. Use "Log measurements" to add one.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (_entries.length >= 2) ...[
              SizedBox(height: 200, child: _buildChart(context, lengthUnit)),
              const SizedBox(height: AppSpacing.lg),
            ],
            // Newest first to read, while the chart runs oldest to newest.
            for (final entry in _entries.reversed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_formatValue(widget.type, entry.value, lengthUnit)),
                subtitle: Text(
                  entry.notes == null || entry.notes!.isEmpty
                      ? _formatDate(entry.date)
                      : '${_formatDate(entry.date)} · ${entry.notes}',
                ),
                trailing: AppOverflowMenu(
                  tooltip: 'Entry options',
                  items: [
                    AppMenuItem(
                      label: 'Edit',
                      icon: Icons.edit,
                      onSelected: () => _edit(entry, lengthUnit),
                    ),
                    AppMenuItem(
                      label: 'Delete',
                      icon: Icons.delete,
                      isDestructive: true,
                      onSelected: () => _delete(entry),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildChart(BuildContext context, String lengthUnit) {
    final colorScheme = Theme.of(context).colorScheme;
    double display(double value) =>
        widget.type.isLength ? cmToUnit(value, lengthUnit) : value;
    final spots = [
      for (var i = 0; i < _entries.length; i++)
        FlSpot(i.toDouble(), display(_entries[i].value)),
    ];
    final axis = computeNiceAxis(spots.map((s) => s.y).toList());

    return LineChart(
      LineChartData(
        minY: axis.minY,
        maxY: axis.maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: axis.interval,
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: axis.interval,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(axis.interval < 1 ? 1 : 0),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            // Straight segments: a spline would invent values between
            // measurements that were never taken.
            isCurved: false,
            color: colorScheme.secondary,
            barWidth: 3,
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BodyMeasurement entry, String lengthUnit) async {
    final isLength = widget.type.isLength;
    final valueController = TextEditingController(
      text: formatDecimal(isLength ? cmToUnit(entry.value, lengthUnit) : entry.value),
    );
    final notesController = TextEditingController(text: entry.notes ?? '');

    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit ${widget.type.label.toLowerCase()}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: valueController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: const [DecimalWeightInputFormatter()],
              decoration: InputDecoration(
                labelText: widget.type.label,
                suffixText: isLength ? lengthUnit : '%',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
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

    final text = valueController.text;
    final notes = notesController.text.trim();
    valueController.dispose();
    notesController.dispose();
    if (save != true || !mounted) return;

    final value = isLength
        ? parseLengthToCm(text, lengthUnit: lengthUnit)
        : double.tryParse(text.trim().replaceAll(',', '.'));
    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid value')),
      );
      return;
    }

    try {
      await widget.repository.updateMeasurement(BodyMeasurement(
        id: entry.id,
        type: entry.type,
        value: value,
        date: entry.date,
        notes: notes.isEmpty ? null : notes,
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating entry: $e')),
      );
    }
  }

  Future<void> _delete(BodyMeasurement entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete entry'),
        content: Text(
            'Delete the ${widget.type.label.toLowerCase()} entry from '
            '${_formatDate(entry.date)}?'),
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
    if (confirmed != true || !mounted) return;

    try {
      await widget.repository.deleteMeasurement(entry.id!);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting entry: $e')),
      );
    }
  }
}
