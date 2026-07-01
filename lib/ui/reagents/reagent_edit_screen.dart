import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/reagent_repository.dart';
import '../app_database_provider.dart';
import '../labels.dart';

/// Create (when [reagent] is null) or edit a reagent or buffer.
class ReagentEditScreen extends StatefulWidget {
  const ReagentEditScreen({super.key, this.reagent, this.initialKind});

  final Reagent? reagent;

  /// Default kind for a NEW entry: 'reagent' (default) or 'buffer'.
  final String? initialKind;

  bool get isEditing => reagent != null;

  @override
  State<ReagentEditScreen> createState() => _ReagentEditScreenState();
}

class _ReagentEditScreenState extends State<ReagentEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  DateTime? _expiry;
  bool _saving = false;
  late String _kind;

  @override
  void initState() {
    super.initState();
    final r = widget.reagent;
    _c = {
      'name': TextEditingController(text: r?.name ?? ''),
      'supplier': TextEditingController(text: r?.supplier ?? ''),
      'catalog': TextEditingController(text: r?.catalogNo ?? ''),
      'lot': TextEditingController(text: r?.lot ?? ''),
      'location': TextEditingController(text: r?.location ?? ''),
      'quantity': TextEditingController(text: r?.quantity ?? ''),
      'recipe': TextEditingController(text: r?.recipe ?? ''),
      'notes': TextEditingController(text: r?.notes ?? ''),
    };
    _expiry = r?.expiryDate;
    _kind = r?.kind ?? widget.initialKind ?? 'reagent';
  }

  bool get _isBuffer => _kind == 'buffer';

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _t(String k) => _c[k]!.text.trim();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = ReagentRepository(AppDatabaseProvider.of(context));
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      if (widget.isEditing) {
        await repo.update(
          widget.reagent!.id,
          ReagentsCompanion(
            name: Value(_t('name')),
            kind: Value(_kind),
            supplier: Value(_isBuffer ? '' : _t('supplier')),
            catalogNo: Value(_isBuffer ? '' : _t('catalog')),
            lot: Value(_isBuffer ? '' : _t('lot')),
            location: Value(_t('location')),
            expiryDate: Value(_expiry),
            quantity: Value(_t('quantity')),
            recipe: Value(_t('recipe')),
            notes: Value(_t('notes')),
          ),
        );
      } else {
        await repo.create(ReagentsCompanion.insert(
          name: _t('name'),
          kind: Value(_kind),
          supplier: Value(_isBuffer ? '' : _t('supplier')),
          catalogNo: Value(_isBuffer ? '' : _t('catalog')),
          lot: Value(_isBuffer ? '' : _t('lot')),
          location: Value(_t('location')),
          expiryDate: Value(_expiry),
          quantity: Value(_t('quantity')),
          recipe: Value(_t('recipe')),
          notes: Value(_t('notes')),
        ));
      }
      if (mounted) navigator.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String key, String label, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: _c[key],
        minLines: maxLines > 1 ? 2 : 1,
        maxLines: maxLines,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label),
        validator: key == 'name'
            ? (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final noun = _isBuffer ? 'buffer' : 'reagent';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit $noun' : 'New $noun'),
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
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'reagent',
                      label: Text('Reagent'),
                      icon: Icon(Icons.science_outlined)),
                  ButtonSegment(
                      value: 'buffer',
                      label: Text('Buffer'),
                      icon: Icon(Icons.opacity_outlined)),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
            ),
            _field('recipe', _isBuffer ? 'Recipe' : 'Recipe / composition',
                maxLines: 5),
            if (!_isBuffer) ...[
              _field('supplier', 'Supplier'),
              _field('catalog', 'Catalog no.'),
              _field('lot', 'Lot'),
            ],
            _field('location', 'Location'),
            _field('quantity', 'Quantity'),
            Row(
              children: [
                Expanded(child: Text('Expiry date: ${formatDate(_expiry)}')),
                if (_expiry != null)
                  IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Clear',
                      onPressed: () => setState(() => _expiry = null)),
                TextButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _expiry ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _expiry = picked);
                  },
                  icon: const Icon(Icons.event),
                  label: const Text('Pick'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _field('notes', 'Notes', maxLines: 4),
          ],
        ),
      ),
    );
  }
}
