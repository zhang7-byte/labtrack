import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../data/clone_repository.dart';
import '../../data/database.dart';
import '../../data/primer_repository.dart';
import '../../data/strain_repository.dart';
import '../../export/pdf_export.dart';
import '../app_database_provider.dart';
import '../export/pdf_preview_screen.dart';
import '../search_picker.dart';
import 'clone_vector.dart';

/// Mutable working copy of one fragment row.
class _FragmentDraft {
  _FragmentDraft({
    this.name = '',
    this.templateStrainId = '',
    this.fwdPrimerId = '',
    this.revPrimerId = '',
    this.sizeBp = '',
    this.notes = '',
  });
  final Key key = UniqueKey();
  String name;
  String templateStrainId;
  String fwdPrimerId;
  String revPrimerId;
  String sizeBp;
  String notes;

  CloneFragment toFragment() => CloneFragment(
        name: name,
        templateStrainId: templateStrainId,
        fwdPrimerId: fwdPrimerId,
        revPrimerId: revPrimerId,
        sizeBp: sizeBp,
        notes: notes,
      );
}

/// Create (when [construction] is null) or edit one Gibson clone construction.
class CloneEditScreen extends StatefulWidget {
  const CloneEditScreen({super.key, this.construction});

  final CloneConstruction? construction;

  @override
  State<CloneEditScreen> createState() => _CloneEditScreenState();
}

class _CloneEditScreenState extends State<CloneEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _notes;
  late final TextEditingController _backboneName;
  late final TextEditingController _enzymes;
  String _backboneStrainId = '';
  final List<_FragmentDraft> _fragments = [];

  List<Strain> _strains = const [];
  List<Primer> _primers = const [];
  bool _loading = true;
  bool _busy = false;

  late final String _id = widget.construction?.id ?? uuid.v4();
  late bool _saved = widget.construction != null;

  @override
  void initState() {
    super.initState();
    final c = widget.construction;
    _name = TextEditingController(text: c?.name ?? '');
    _notes = TextEditingController(text: c?.notes ?? '');
    _backboneName = TextEditingController(text: c?.backboneName ?? '');
    _enzymes = TextEditingController(text: c?.enzymes ?? '');
    _backboneStrainId = c?.backboneStrainId ?? '';
    for (final f in c?.fragments ?? const <CloneFragment>[]) {
      _fragments.add(_FragmentDraft(
        name: f.name,
        templateStrainId: f.templateStrainId,
        fwdPrimerId: f.fwdPrimerId,
        revPrimerId: f.revPrimerId,
        sizeBp: f.sizeBp,
        notes: f.notes,
      ));
    }
    _load();
  }

  Future<void> _load() async {
    final db = AppDatabaseProvider.of(context);
    final strains = await StrainRepository(db).watchAll().first;
    final primers = await PrimerRepository(db).watchAll().first;
    if (!mounted) return;
    setState(() {
      _strains = strains;
      _primers = primers;
      _loading = false;
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _notes, _backboneName, _enzymes]) {
      c.dispose();
    }
    super.dispose();
  }

  CloneConstruction _draft() {
    final now = DateTime.now();
    return CloneConstruction(
      id: _id,
      createdAt: now,
      updatedAt: now,
      workspaceId: '',
      name: _name.text,
      notes: _notes.text,
      backboneName: _backboneName.text,
      backboneStrainId: _backboneStrainId,
      enzymes: _enzymes.text,
      fragments: _fragments.map((d) => d.toFragment()).toList(),
    );
  }

  Future<void> _persist(CloneRepository repo) async {
    final values = CloneConstructionsCompanion(
      id: Value(_id),
      name: Value(_name.text.trim()),
      notes: Value(_notes.text.trim()),
      backboneName: Value(_backboneName.text.trim()),
      backboneStrainId: Value(_backboneStrainId),
      enzymes: Value(_enzymes.text.trim()),
      fragments: Value(_fragments.map((d) => d.toFragment()).toList()),
    );
    if (_saved) {
      await repo.update(_id, values);
    } else {
      await repo.create(values);
      _saved = true;
    }
  }

  Future<void> _save() async {
    final repo = CloneRepository(AppDatabaseProvider.of(context));
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
      final repo = CloneRepository(db);
      await _persist(repo);
      final c = await repo.findById(_id);
      if (c == null) return;
      navigator.push(MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(
          title: 'Construction PDF',
          fileName: 'labtrack-construction.pdf',
          builder: (fonts) => buildClonePdf(db, c, fonts),
        ),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.construction != null;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit construction' : 'New construction'),
        actions: [
          IconButton(
            tooltip: 'Export to PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _busy ? null : _export,
          ),
          TextButton(onPressed: _busy ? null : _save, child: const Text('Save')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'Construction name',
                      hintText: 'e.g. pLT-GFP-hLFABP'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),

                // Live vector preview.
                Text('Assembled vector',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Container(
                  height: 300,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: CustomPaint(
                    painter: CloneVectorPainter(_draft(),
                        primerNames: _primerNames()),
                    size: Size.infinite,
                  ),
                ),
                const SizedBox(height: 24),

                // Backbone.
                Text('Backbone',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _backboneName,
                  decoration: const InputDecoration(
                      labelText: 'Vector / plasmid name',
                      hintText: 'e.g. pUC19'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _StrainDropdown(
                  label: 'Stock strain',
                  strains: _strains,
                  value: _backboneStrainId,
                  onChanged: (v) => setState(() => _backboneStrainId = v),
                ),
                _StrainDetail(strain: _strainById(_backboneStrainId)),
                const SizedBox(height: 12),
                TextField(
                  controller: _enzymes,
                  decoration: const InputDecoration(
                    labelText: 'Restriction enzymes',
                    hintText: 'to linearise the backbone, e.g. EcoRI, HindIII',
                  ),
                ),
                const SizedBox(height: 24),

                // Fragments.
                Row(
                  children: [
                    Text('Fragments (${_fragments.length})',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _fragments.add(_FragmentDraft())),
                      icon: const Icon(Icons.add),
                      label: const Text('Add fragment'),
                    ),
                  ],
                ),
                if (_fragments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('No fragments yet. Add the inserts to assemble '
                        'into the backbone.',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
                for (var i = 0; i < _fragments.length; i++)
                  _FragmentCard(
                    key: _fragments[i].key,
                    index: i,
                    draft: _fragments[i],
                    strains: _strains,
                    primers: _primers,
                    strainById: _strainById,
                    onChanged: () => setState(() {}),
                    onRemove: () => setState(() => _fragments.removeAt(i)),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Notes'),
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

  Strain? _strainById(String id) {
    if (id.isEmpty) return null;
    for (final s in _strains) {
      if (s.id == id) return s;
    }
    return null;
  }

  Map<String, String> _primerNames() => {for (final p in _primers) p.id: p.name};
}

class _FragmentCard extends StatelessWidget {
  const _FragmentCard({
    super.key,
    required this.index,
    required this.draft,
    required this.strains,
    required this.primers,
    required this.strainById,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _FragmentDraft draft;
  final List<Strain> strains;
  final List<Primer> primers;
  final Strain? Function(String) strainById;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Fragment ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  tooltip: 'Remove fragment',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onRemove,
                ),
              ],
            ),
            TextFormField(
              initialValue: draft.name,
              decoration: const InputDecoration(labelText: 'Fragment name'),
              onChanged: (v) {
                draft.name = v;
                onChanged();
              },
            ),
            const SizedBox(height: 10),
            _StrainDropdown(
              label: 'Template strain',
              strains: strains,
              value: draft.templateStrainId,
              onChanged: (v) {
                draft.templateStrainId = v;
                onChanged();
              },
            ),
            _StrainDetail(strain: strainById(draft.templateStrainId)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _PrimerDropdown(
                    label: 'Fwd primer',
                    primers: primers,
                    value: draft.fwdPrimerId,
                    onChanged: (v) {
                      draft.fwdPrimerId = v;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PrimerDropdown(
                    label: 'Rev primer',
                    primers: primers,
                    value: draft.revPrimerId,
                    onChanged: (v) {
                      draft.revPrimerId = v;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: draft.sizeBp,
              decoration: const InputDecoration(
                  labelText: 'Amplicon size', hintText: 'e.g. 1.2 kb'),
              onChanged: (v) => draft.sizeBp = v,
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: draft.notes,
              decoration: const InputDecoration(labelText: 'Notes'),
              onChanged: (v) => draft.notes = v,
            ),
          ],
        ),
      ),
    );
  }
}

class _StrainDropdown extends StatelessWidget {
  const _StrainDropdown({
    required this.label,
    required this.strains,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<Strain> strains;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SearchPickerField<Strain>(
      label: label,
      items: strains,
      selectedId: value,
      idOf: (s) => s.id,
      labelOf: (s) => s.name,
      subtitleOf: (s) => [
        if (s.serialNumber.isNotEmpty) '#${s.serialNumber}',
        if (s.plasmid.isNotEmpty) 'plasmid ${s.plasmid}',
        if (s.hostOrganism.isNotEmpty) s.hostOrganism,
      ].join(' · '),
      onChanged: onChanged,
    );
  }
}

class _PrimerDropdown extends StatelessWidget {
  const _PrimerDropdown({
    required this.label,
    required this.primers,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<Primer> primers;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SearchPickerField<Primer>(
      label: label,
      items: primers,
      selectedId: value,
      idOf: (p) => p.id,
      labelOf: (p) => p.name,
      subtitleOf: (p) => [
        if (p.serialNumber.isNotEmpty) '#${p.serialNumber}',
        if (p.targetGene.isNotEmpty) p.targetGene,
        if (p.direction.isNotEmpty) p.direction,
      ].join(' · '),
      onChanged: onChanged,
    );
  }
}

/// Shows the selection-relevant details of a referenced strain.
class _StrainDetail extends StatelessWidget {
  const _StrainDetail({required this.strain});

  final Strain? strain;

  @override
  Widget build(BuildContext context) {
    final s = strain;
    if (s == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final parts = [
      if (s.plasmid.isNotEmpty) 'Plasmid: ${s.plasmid}',
      if (s.genotype.isNotEmpty) 'Genotype: ${s.genotype}',
      if (s.constructNotes.isNotEmpty) s.constructNotes,
      if (s.notes.isNotEmpty) s.notes,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Text(
        parts.isEmpty
            ? 'No selection details recorded for ${s.name}.'
            : parts.join('  ·  '),
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
