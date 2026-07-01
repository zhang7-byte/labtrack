import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/experiment_repository.dart';
import '../../data/project_repository.dart';
import '../../data/strain_repository.dart';
import '../app_database_provider.dart';
import '../labels.dart';
import '../search_picker.dart';

/// Create (when [experiment] is null) or edit an experiment. [defaultProjectId]
/// preselects the parent project when adding from a project's detail screen.
class ExperimentEditScreen extends StatefulWidget {
  const ExperimentEditScreen({super.key, this.experiment, this.defaultProjectId});

  final Experiment? experiment;
  final String? defaultProjectId;

  bool get isEditing => experiment != null;

  @override
  State<ExperimentEditScreen> createState() => _ExperimentEditScreenState();
}

class _ExperimentEditScreenState extends State<ExperimentEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _hypothesis;
  late final TextEditingController _protocolRef;
  late final TextEditingController _resultsNotes;
  late final TextEditingController _conclusion;
  late final TextEditingController _furtherPlan;
  late final TextEditingController _dataLinks;
  final List<TextEditingController> _steps = [];
  final Set<String> _selectedStrainIds = {};
  late ExperimentStatus _status;
  DateTime? _date;
  String? _projectId;
  List<Project>? _projects;
  List<Strain>? _strains;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.experiment;
    _title = TextEditingController(text: e?.title ?? '');
    _hypothesis = TextEditingController(text: e?.hypothesis ?? '');
    _protocolRef = TextEditingController(text: e?.protocolRef ?? '');
    _resultsNotes = TextEditingController(text: e?.resultsNotes ?? '');
    _conclusion = TextEditingController(text: e?.conclusion ?? '');
    _furtherPlan = TextEditingController(text: e?.furtherPlan ?? '');
    for (final s in e?.methodologySteps ?? const <String>[]) {
      _steps.add(TextEditingController(text: s));
    }
    _dataLinks = TextEditingController(text: e?.dataLinks.join(', ') ?? '');
    _selectedStrainIds.addAll(e?.strainIds ?? const []);
    _status = e?.status ?? ExperimentStatus.planned;
    _date = e?.date;
    _projectId = e?.projectId ?? widget.defaultProjectId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_projects == null) _load();
  }

  Future<void> _load() async {
    final db = AppDatabaseProvider.of(context);
    final projects = await ProjectRepository(db).all();
    final strains = await StrainRepository(db).all();
    if (!mounted) return;
    setState(() {
      _projects = projects;
      _strains = strains;
      if (_projectId == null && projects.isNotEmpty) {
        _projectId = projects.first.id;
      }
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _hypothesis.dispose();
    _protocolRef.dispose();
    _resultsNotes.dispose();
    _conclusion.dispose();
    _furtherPlan.dispose();
    for (final c in _steps) {
      c.dispose();
    }
    _dataLinks.dispose();
    super.dispose();
  }

  List<String> _methodologySteps() => [
        for (final c in _steps)
          if (c.text.trim().isNotEmpty) c.text.trim()
      ];

  List<String> _parseList(TextEditingController c) => c.text
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_projectId == null) return;
    final repo = ExperimentRepository(AppDatabaseProvider.of(context));
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      if (widget.isEditing) {
        await repo.update(
          widget.experiment!.id,
          ExperimentsCompanion(
            projectId: Value(_projectId!),
            title: Value(_title.text.trim()),
            hypothesis: Value(_hypothesis.text.trim()),
            status: Value(_status),
            date: Value(_date),
            strainIds: Value(_selectedStrainIds.toList()),
            protocolRef: Value(_protocolRef.text.trim()),
            methodologySteps: Value(_methodologySteps()),
            resultsNotes: Value(_resultsNotes.text.trim()),
            conclusion: Value(_conclusion.text.trim()),
            furtherPlan: Value(_furtherPlan.text.trim()),
            dataLinks: Value(_parseList(_dataLinks)),
          ),
        );
      } else {
        await repo.create(
          ExperimentsCompanion.insert(
            projectId: _projectId!,
            title: _title.text.trim(),
            hypothesis: Value(_hypothesis.text.trim()),
            status: Value(_status),
            date: Value(_date),
            strainIds: Value(_selectedStrainIds.toList()),
            protocolRef: Value(_protocolRef.text.trim()),
            methodologySteps: Value(_methodologySteps()),
            resultsNotes: Value(_resultsNotes.text.trim()),
            conclusion: Value(_conclusion.text.trim()),
            furtherPlan: Value(_furtherPlan.text.trim()),
            dataLinks: Value(_parseList(_dataLinks)),
          ),
        );
      }
      navigator.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// A reorderable, add/remove list of methodology steps.
  Widget _methodologySection(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Methodology (step by step)',
            style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 12)),
        if (_steps.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('No steps yet — add the procedure one step at a time.',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _steps.length,
            onReorderItem: (oldIndex, newIndex) => setState(
                () => _steps.insert(newIndex, _steps.removeAt(oldIndex))),
            itemBuilder: (context, i) {
              final c = _steps[i];
              return Padding(
                key: ValueKey(c),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10, right: 4),
                        child: Icon(Icons.drag_indicator,
                            size: 18, color: scheme.onSurfaceVariant),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: SizedBox(
                          width: 22,
                          child: Text('${i + 1}.',
                              style:
                                  TextStyle(color: scheme.onSurfaceVariant))),
                    ),
                    Expanded(
                      child: TextField(
                        controller: c,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                            isDense: true, hintText: 'Step ${i + 1}'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      tooltip: 'Remove step',
                      onPressed: () =>
                          setState(() => _steps.removeAt(i).dispose()),
                    ),
                  ],
                ),
              );
            },
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                setState(() => _steps.add(TextEditingController())),
            icon: const Icon(Icons.add),
            label: const Text('Add step'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final projects = _projects;
    final strains = _strains;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit experiment' : 'New experiment'),
        actions: [
          TextButton(
            onPressed: (_saving || projects == null || projects.isEmpty)
                ? null
                : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: (projects == null || strains == null)
          ? const Center(child: CircularProgressIndicator())
          : projects.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        'Create a project first — every experiment belongs to one.',
                        textAlign: TextAlign.center),
                  ),
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _projectId,
                        decoration: const InputDecoration(labelText: 'Project'),
                        items: [
                          for (final p in projects)
                            DropdownMenuItem(value: p.id, child: Text(p.title)),
                        ],
                        onChanged: (v) => setState(() => _projectId = v),
                        validator: (v) => v == null ? 'Pick a project' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _title,
                        autofocus: !widget.isEditing,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(labelText: 'Title'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Title is required'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _hypothesis,
                        minLines: 2,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration:
                            const InputDecoration(labelText: 'Hypothesis'),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<ExperimentStatus>(
                        initialValue: _status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: [
                          for (final s in ExperimentStatus.values)
                            DropdownMenuItem(
                                value: s, child: Text(enumLabel(s))),
                        ],
                        onChanged: (v) =>
                            setState(() => _status = v ?? _status),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: Text('Date: ${formatDate(_date)}')),
                          if (_date != null)
                            IconButton(
                                icon: const Icon(Icons.clear),
                                tooltip: 'Clear',
                                onPressed: () => setState(() => _date = null)),
                          TextButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _date ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setState(() => _date = picked);
                              }
                            },
                            icon: const Icon(Icons.event),
                            label: const Text('Pick'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _protocolRef,
                        decoration:
                            const InputDecoration(labelText: 'Protocol ref'),
                      ),
                      const SizedBox(height: 20),
                      _methodologySection(scheme),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _resultsNotes,
                        minLines: 2,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration:
                            const InputDecoration(labelText: 'Results notes'),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _conclusion,
                        minLines: 2,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration:
                            const InputDecoration(labelText: 'Conclusion'),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _furtherPlan,
                        minLines: 2,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration:
                            const InputDecoration(labelText: 'Further plan'),
                      ),
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Strains used',
                            style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                                fontSize: 12)),
                      ),
                      const SizedBox(height: 8),
                      if (strains.isEmpty)
                        Text('No strains in the inventory yet.',
                            style: TextStyle(color: scheme.onSurfaceVariant))
                      else ...[
                        if (_selectedStrainIds.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              for (final s in strains.where(
                                  (s) => _selectedStrainIds.contains(s.id)))
                                InputChip(
                                  label: Text(s.name),
                                  onDeleted: () => setState(
                                      () => _selectedStrainIds.remove(s.id)),
                                ),
                            ],
                          ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showMultiSearchPicker<Strain>(
                                context,
                                title: 'Strains used',
                                items: strains,
                                selected: _selectedStrainIds,
                                idOf: (s) => s.id,
                                labelOf: (s) => s.name,
                                subtitleOf: (s) => [
                                  if (s.serialNumber.isNotEmpty)
                                    '#${s.serialNumber}',
                                  if (s.hostOrganism.isNotEmpty) s.hostOrganism,
                                  if (s.plasmid.isNotEmpty)
                                    'plasmid ${s.plasmid}',
                                ].join(' · '),
                              );
                              if (picked != null) {
                                setState(() => _selectedStrainIds
                                  ..clear()
                                  ..addAll(picked));
                              }
                            },
                            icon: const Icon(Icons.search),
                            label: Text(_selectedStrainIds.isEmpty
                                ? 'Choose strains'
                                : 'Edit selection (${_selectedStrainIds.length})'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _dataLinks,
                        decoration: const InputDecoration(
                          labelText: 'Data links',
                          helperText: 'Comma-separated URLs',
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
