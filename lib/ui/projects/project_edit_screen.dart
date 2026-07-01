import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/project_repository.dart';
import '../app_database_provider.dart';
import '../labels.dart';

/// Create (when [project] is null) or edit a single project.
class ProjectEditScreen extends StatefulWidget {
  const ProjectEditScreen({super.key, this.project});

  final Project? project;

  bool get isEditing => project != null;

  @override
  State<ProjectEditScreen> createState() => _ProjectEditScreenState();
}

class _ProjectEditScreenState extends State<ProjectEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _tags;
  late ProjectStatus _status;
  late Priority _priority;
  DateTime? _startDate;
  DateTime? _targetDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.project;
    _title = TextEditingController(text: p?.title ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _tags = TextEditingController(text: p?.tags.join(', ') ?? '');
    _status = p?.status ?? ProjectStatus.planning;
    _priority = p?.priority ?? Priority.medium;
    _startDate = p?.startDate;
    _targetDate = p?.targetDate;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _tags.dispose();
    super.dispose();
  }

  List<String> _parseTags() => _tags.text
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _startDate : _targetDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => isStart ? _startDate = picked : _targetDate = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = ProjectRepository(AppDatabaseProvider.of(context));
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      final tags = _parseTags();
      if (widget.isEditing) {
        await repo.update(
          widget.project!.id,
          ProjectsCompanion(
            title: Value(_title.text.trim()),
            description: Value(_description.text.trim()),
            status: Value(_status),
            priority: Value(_priority),
            startDate: Value(_startDate),
            targetDate: Value(_targetDate),
            tags: Value(tags),
          ),
        );
      } else {
        await repo.create(
          ProjectsCompanion.insert(
            title: _title.text.trim(),
            description: Value(_description.text.trim()),
            status: Value(_status),
            priority: Value(_priority),
            startDate: Value(_startDate),
            targetDate: Value(_targetDate),
            tags: Value(tags),
          ),
        );
      }
      navigator.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit project' : 'New project'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              autofocus: !widget.isEditing,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _description,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ProjectStatus>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: [
                for (final s in ProjectStatus.values)
                  DropdownMenuItem(value: s, child: Text(enumLabel(s))),
              ],
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Priority>(
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: [
                for (final p in Priority.values)
                  DropdownMenuItem(value: p, child: Text(enumLabel(p))),
              ],
              onChanged: (v) => setState(() => _priority = v ?? _priority),
            ),
            const SizedBox(height: 8),
            _DateField(
              label: 'Start date',
              value: _startDate,
              onPick: () => _pickDate(isStart: true),
              onClear: () => setState(() => _startDate = null),
            ),
            _DateField(
              label: 'Target date',
              value: _targetDate,
              onPick: () => _pickDate(isStart: false),
              onClear: () => setState(() => _targetDate = null),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _tags,
              decoration: const InputDecoration(
                labelText: 'Tags',
                helperText: 'Comma-separated, e.g. AID2, GFP, Yarrowia',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text('$label: ${formatDate(value)}')),
          if (value != null)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear',
              onPressed: onClear,
            ),
          TextButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.event),
            label: const Text('Pick'),
          ),
        ],
      ),
    );
  }
}
