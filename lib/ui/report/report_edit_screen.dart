import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/experiment_repository.dart';
import '../../data/project_repository.dart';
import '../../data/report_repository.dart';
import '../../export/pdf_export.dart';
import '../app_database_provider.dart';
import '../export/pdf_preview_screen.dart';
import '../images/images_section.dart';
import '../labels.dart';

/// Create (when [report] is null) or edit a single PI progress report: header +
/// summary, a project/experiment selection (empty = everything), and inserted
/// figures. The data sections are gathered live when exported (see
/// [buildReportPdf]).
class ReportEditScreen extends StatefulWidget {
  const ReportEditScreen({super.key, this.report});

  final Report? report;

  @override
  State<ReportEditScreen> createState() => _ReportEditScreenState();
}

class _ReportEditScreenState extends State<ReportEditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _recipient;
  late final TextEditingController _author;
  late final TextEditingController _summary;
  DateTime? _periodStart;
  DateTime? _periodEnd;
  bool _busy = false;

  final Set<String> _selProjects = {};
  final Set<String> _selExperiments = {};
  List<Project> _projects = const [];
  List<Experiment> _experiments = const [];
  bool _loadingScope = true;

  late final String _id = widget.report?.id ?? uuid.v4();
  late bool _saved = widget.report != null;

  @override
  void initState() {
    super.initState();
    final r = widget.report;
    _title = TextEditingController(text: r?.title ?? 'Progress report');
    _recipient = TextEditingController(text: r?.recipient ?? '');
    _author = TextEditingController(text: r?.author ?? '');
    _summary = TextEditingController(text: r?.summary ?? '');
    _periodStart = r?.periodStart;
    _periodEnd = r?.periodEnd;
    _selProjects.addAll(r?.projectIds ?? const []);
    _selExperiments.addAll(r?.experimentIds ?? const []);
    _loadScope();
  }

  Future<void> _loadScope() async {
    final db = AppDatabaseProvider.of(context);
    final projects = await ProjectRepository(db).watchAll().first;
    final experiments = await ExperimentRepository(db).watchAll().first;
    if (!mounted) return;
    setState(() {
      _projects = projects;
      _experiments = experiments;
      _loadingScope = false;
    });
  }

  @override
  void dispose() {
    for (final c in [_title, _recipient, _author, _summary]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _periodStart : _periodEnd) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => isStart ? _periodStart = picked : _periodEnd = picked);
    }
  }

  Future<void> _persist(ReportRepository repo) async {
    final values = ReportsCompanion(
      id: Value(_id),
      title: Value(
          _title.text.trim().isEmpty ? 'Progress report' : _title.text.trim()),
      recipient: Value(_recipient.text.trim()),
      author: Value(_author.text.trim()),
      periodStart: Value(_periodStart),
      periodEnd: Value(_periodEnd),
      summary: Value(_summary.text.trim()),
      projectIds: Value(_selProjects.toList()),
      experimentIds: Value(_selExperiments.toList()),
    );
    if (_saved) {
      await repo.update(_id, values);
    } else {
      await repo.create(values);
      _saved = true;
    }
  }

  Future<void> _save() async {
    final repo = ReportRepository(AppDatabaseProvider.of(context));
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await _persist(repo);
      navigator.pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final db = AppDatabaseProvider.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final repo = ReportRepository(db);
      await _persist(repo);
      final report = await repo.findById(_id);
      if (report == null) return;
      navigator.push(MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(
          title: 'Report PDF',
          fileName: 'labtrack-report.pdf',
          builder: (fonts) => buildReportPdf(db, report, fonts),
        ),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.report != null;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit report' : 'New report'),
        actions: [
          IconButton(
            tooltip: 'Export to PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _busy ? null : _export,
          ),
          TextButton(
              onPressed: _busy ? null : _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Report title'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _recipient,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'To (PI)', hintText: 'e.g. Dr. Su'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _author,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'From (you)'),
          ),
          const SizedBox(height: 8),
          _DateField(
            label: 'Period start',
            value: _periodStart,
            onPick: () => _pickDate(isStart: true),
            onClear: () => setState(() => _periodStart = null),
          ),
          _DateField(
            label: 'Period end',
            value: _periodEnd,
            onPick: () => _pickDate(isStart: false),
            onClear: () => setState(() => _periodEnd = null),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _summary,
            minLines: 5,
            maxLines: 14,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Summary / highlights',
              hintText: 'What to tell your PI.',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),

          // ---- Scope: which projects / experiments to include ----
          Text('Include in report', style: text.titleMedium),
          Text(
            'Leave everything unchecked to include all projects & experiments. '
            'Selecting a project includes its experiments; tick specific '
            'experiments to narrow it.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 4),
          if (_loadingScope)
            const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()))
          else if (_projects.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('No projects in this workspace.',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            )
          else
            for (final p in _projects) _projectTile(p),
          const SizedBox(height: 24),

          // ---- Figures (report-specific images, annotatable) ----
          Text('Figures', style: text.titleMedium),
          const SizedBox(height: 4),
          if (_saved)
            ImagesSection(reportId: _id, title: 'Figures', dense: true)
          else
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        await _persist(
                            ReportRepository(AppDatabaseProvider.of(context)));
                        if (mounted) setState(() {});
                      },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save report to add figures'),
              ),
            ),

          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Export PDF'),
          ),
        ],
      ),
    );
  }

  Widget _projectTile(Project p) {
    final exps = _experiments.where((e) => e.projectId == p.id).toList();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 16),
      leading: Checkbox(
        value: _selProjects.contains(p.id),
        onChanged: (v) => setState(() =>
            v == true ? _selProjects.add(p.id) : _selProjects.remove(p.id)),
      ),
      title: Text(p.title),
      subtitle: exps.isEmpty ? const Text('No experiments') : null,
      children: [
        for (final e in exps)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: _selExperiments.contains(e.id),
            onChanged: (v) => setState(() => v == true
                ? _selExperiments.add(e.id)
                : _selExperiments.remove(e.id)),
            title: Text(e.title),
          ),
      ],
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
