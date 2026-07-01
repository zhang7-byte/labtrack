import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/strain_repository.dart';
import '../app_database_provider.dart';

/// Create (when [strain] is null) or edit a strain.
class StrainEditScreen extends StatefulWidget {
  const StrainEditScreen({super.key, this.strain});

  final Strain? strain;

  bool get isEditing => strain != null;

  @override
  State<StrainEditScreen> createState() => _StrainEditScreenState();
}

class _StrainEditScreenState extends State<StrainEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.strain;
    _c = {
      'name': TextEditingController(text: s?.name ?? ''),
      'serial': TextEditingController(text: s?.serialNumber ?? ''),
      'host': TextEditingController(text: s?.hostOrganism ?? ''),
      'genotype': TextEditingController(text: s?.genotype ?? ''),
      'plasmid': TextEditingController(text: s?.plasmid ?? ''),
      'construct': TextEditingController(text: s?.constructNotes ?? ''),
      'markers':
          TextEditingController(text: s?.selectionMarkers.join(', ') ?? ''),
      'freezer': TextEditingController(text: s?.freezerLocation ?? ''),
      'notes': TextEditingController(text: s?.notes ?? ''),
    };
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _t(String k) => _c[k]!.text.trim();

  List<String> _list(String k) => _c[k]!
      .text
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = StrainRepository(AppDatabaseProvider.of(context));
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      final companion = StrainsCompanion(
        name: Value(_t('name')),
        serialNumber: Value(_t('serial')),
        hostOrganism: Value(_t('host')),
        genotype: Value(_t('genotype')),
        plasmid: Value(_t('plasmid')),
        constructNotes: Value(_t('construct')),
        selectionMarkers: Value(_list('markers')),
        freezerLocation: Value(_t('freezer')),
        notes: Value(_t('notes')),
      );
      if (widget.isEditing) {
        await repo.update(widget.strain!.id, companion);
      } else {
        await repo.create(StrainsCompanion.insert(
          name: _t('name'),
          serialNumber: Value(_t('serial')),
          hostOrganism: Value(_t('host')),
          genotype: Value(_t('genotype')),
          plasmid: Value(_t('plasmid')),
          constructNotes: Value(_t('construct')),
          selectionMarkers: Value(_list('markers')),
          freezerLocation: Value(_t('freezer')),
          notes: Value(_t('notes')),
        ));
      }
      navigator.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String key, String label, {int maxLines = 1, String? helper}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: _c[key],
        minLines: maxLines > 1 ? 2 : 1,
        maxLines: maxLines,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label, helperText: helper),
        validator: key == 'name'
            ? (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit strain' : 'New strain'),
        actions: [
          TextButton(
              onPressed: _saving ? null : _save, child: const Text('Save')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field('name', 'Name'),
            _field('serial', 'Serial number'),
            _field('host', 'Host organism'),
            _field('genotype', 'Genotype'),
            _field('plasmid', 'Plasmid'),
            _field('construct', 'Construct notes', maxLines: 4),
            _field('markers', 'Selection markers',
                helper: 'Comma-separated, e.g. Kanamycin, Ampicillin'),
            _field('freezer', 'Freezer location'),
            _field('notes', 'Notes', maxLines: 4),
          ],
        ),
      ),
    );
  }
}
