import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/primer_repository.dart';
import '../app_database_provider.dart';

int sequenceLength(String seq) => seq.replaceAll(RegExp(r'\s'), '').length;

class PrimerEditScreen extends StatefulWidget {
  const PrimerEditScreen({super.key, this.primer});

  final Primer? primer;

  @override
  State<PrimerEditScreen> createState() => _PrimerEditScreenState();
}

class _PrimerEditScreenState extends State<PrimerEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _serial;
  late final TextEditingController _sequence;
  late final TextEditingController _target;
  late final TextEditingController _direction;
  late final TextEditingController _tm;
  late final TextEditingController _supplier;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    final p = widget.primer;
    _name = TextEditingController(text: p?.name ?? '');
    _serial = TextEditingController(text: p?.serialNumber ?? '');
    _sequence = TextEditingController(text: p?.sequence ?? '');
    _target = TextEditingController(text: p?.targetGene ?? '');
    _direction = TextEditingController(text: p?.direction ?? '');
    _tm = TextEditingController(text: p?.tm ?? '');
    _supplier = TextEditingController(text: p?.supplier ?? '');
    _notes = TextEditingController(text: p?.notes ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _serial,
      _sequence,
      _target,
      _direction,
      _tm,
      _supplier,
      _notes
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(PrimerRepository repo) async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Name is required.')));
      return;
    }
    final values = PrimersCompanion(
      name: Value(_name.text.trim()),
      serialNumber: Value(_serial.text.trim()),
      sequence: Value(_sequence.text.trim()),
      targetGene: Value(_target.text.trim()),
      direction: Value(_direction.text.trim()),
      tm: Value(_tm.text.trim()),
      supplier: Value(_supplier.text.trim()),
      notes: Value(_notes.text.trim()),
    );
    if (widget.primer == null) {
      await repo.create(values);
    } else {
      await repo.update(widget.primer!.id, values);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final repo = PrimerRepository(AppDatabaseProvider.of(context));
    final editing = widget.primer != null;
    final len = sequenceLength(_sequence.text);
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit primer' : 'New primer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name *'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _serial,
            decoration: const InputDecoration(labelText: 'Serial number'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _sequence,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(fontFamily: 'monospace', letterSpacing: 0.5),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Sequence (5′→3′)',
              helperText: len > 0 ? '$len nt' : null,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
              controller: _target,
              decoration: const InputDecoration(labelText: 'Target gene')),
          const SizedBox(height: 16),
          TextField(
              controller: _direction,
              decoration: const InputDecoration(
                  labelText: 'Direction', hintText: 'forward / reverse')),
          const SizedBox(height: 16),
          TextField(
              controller: _tm,
              decoration: const InputDecoration(
                  labelText: 'Tm', hintText: 'e.g. 58 °C')),
          const SizedBox(height: 16),
          TextField(
              controller: _supplier,
              decoration: const InputDecoration(labelText: 'Supplier')),
          const SizedBox(height: 16),
          TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Notes')),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _save(repo),
            icon: const Icon(Icons.check),
            label: Text(editing ? 'Save' : 'Create primer'),
          ),
        ],
      ),
    );
  }
}
