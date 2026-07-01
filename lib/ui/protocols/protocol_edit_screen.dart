import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/image_repository.dart';
import '../../data/protocol_repository.dart';
import '../../export/pdf_export.dart';
import '../app_database_provider.dart';
import '../export/pdf_preview_screen.dart';
import '../images/image_viewer_screen.dart';
import '../images/images_section.dart';

/// A step in the editor: its stable id (persisted in protocols.step_ids so
/// attached images survive reordering) paired with its text controller.
class _Step {
  _Step(this.id, this.ctrl);
  final String id;
  final TextEditingController ctrl;
}

/// Create (when [protocol] is null) or edit a protocol: name / category /
/// summary, a step-by-step composer with per-step annotated images, materials,
/// notes and general images. Exportable to a self-contained PDF.
class ProtocolEditScreen extends StatefulWidget {
  const ProtocolEditScreen({super.key, this.protocol});

  final Protocol? protocol;

  @override
  State<ProtocolEditScreen> createState() => _ProtocolEditScreenState();
}

class _ProtocolEditScreenState extends State<ProtocolEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _summary;
  late final TextEditingController _materials;
  late final TextEditingController _notes;
  final List<_Step> _steps = [];
  bool _busy = false;

  late final String _id = widget.protocol?.id ?? uuid.v4();
  late bool _saved = widget.protocol != null;

  @override
  void initState() {
    super.initState();
    final p = widget.protocol;
    _name = TextEditingController(text: p?.name ?? '');
    _category = TextEditingController(text: p?.category ?? '');
    _summary = TextEditingController(text: p?.summary ?? '');
    _materials = TextEditingController(text: p?.materials ?? '');
    _notes = TextEditingController(text: p?.notes ?? '');
    // Pair each step with its stable id, backfilling ids for protocols saved
    // before step ids existed.
    final steps = p?.steps ?? const <String>[];
    final ids = p?.stepIds ?? const <String>[];
    for (var i = 0; i < steps.length; i++) {
      _steps.add(_Step(i < ids.length ? ids[i] : uuid.v4(),
          TextEditingController(text: steps[i])));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _category, _summary, _materials, _notes]) {
      c.dispose();
    }
    for (final s in _steps) {
      s.ctrl.dispose();
    }
    super.dispose();
  }

  // Steps and their ids, filtered to non-empty text and kept aligned.
  List<String> _stepTexts() => [
        for (final s in _steps)
          if (s.ctrl.text.trim().isNotEmpty) s.ctrl.text.trim()
      ];
  List<String> _stepIds() => [
        for (final s in _steps)
          if (s.ctrl.text.trim().isNotEmpty) s.id
      ];

  Future<void> _persist() async {
    final db = AppDatabaseProvider.of(context);
    final repo = ProtocolRepository(db);
    final name = _name.text.trim();
    final keptIds = _stepIds();
    final values = ProtocolsCompanion(
      id: Value(_id),
      name: Value(name.isEmpty ? 'Protocol' : name),
      category: Value(_category.text.trim()),
      summary: Value(_summary.text.trim()),
      steps: Value(_stepTexts()),
      stepIds: Value(keptIds),
      materials: Value(_materials.text.trim()),
      notes: Value(_notes.text.trim()),
    );
    if (_saved) {
      await repo.update(_id, values);
    } else {
      await repo.create(values);
      _saved = true;
    }
    // Any image whose step was dropped (e.g. an emptied-out step) falls back to
    // a general protocol image rather than disappearing.
    await ImageRepository(db).reconcileProtocolSteps(_id, keptIds);
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await _persist();
      if (mounted) navigator.pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final db = AppDatabaseProvider.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await _persist();
      final protocol = await ProtocolRepository(db).findById(_id);
      if (protocol == null || !mounted) return;
      navigator.push(MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(
          title: 'Protocol PDF',
          fileName: 'protocol.pdf',
          builder: (fonts) => buildProtocolPdf(db, protocol, fonts),
        ),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeStep(int i) async {
    final step = _steps[i];
    // Free this step's images (they become general protocol images).
    if (_saved) {
      await ImageRepository(AppDatabaseProvider.of(context))
          .clearProtocolStep(_id, step.id);
    }
    if (!mounted) return;
    setState(() {
      _steps.removeAt(i);
      step.ctrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.protocol != null;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit protocol' : 'New protocol'),
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
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Name', hintText: 'e.g. Heat-shock transformation'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _category,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Category',
                hintText: 'e.g. Transformation, Cloning, Imaging'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _summary,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Summary / purpose', alignLabelWithHint: true),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _materials,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Materials / equipment', alignLabelWithHint: true),
          ),
          const SizedBox(height: 20),
          _stepsSection(scheme),
          if (!_saved)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Save the protocol to attach images to a step.',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant, fontSize: 12)),
            ),
          const SizedBox(height: 20),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Notes', alignLabelWithHint: true),
          ),
          const SizedBox(height: 24),

          // ---- General images (not tied to a step) ----
          Text('Other images', style: text.titleMedium),
          const SizedBox(height: 4),
          if (_saved)
            ImagesSection(
                protocolId: _id, title: 'Not tied to a step', dense: true)
          else
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        await _persist();
                        if (mounted) setState(() {});
                      },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save protocol to add images'),
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

  /// A reorderable, add/remove list of steps; each step carries its own images
  /// (shown once the protocol is saved).
  Widget _stepsSection(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Steps (step by step)',
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
              final step = _steps[i];
              return Padding(
                key: ValueKey(step.id),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                                  style: TextStyle(
                                      color: scheme.onSurfaceVariant))),
                        ),
                        Expanded(
                          child: TextField(
                            controller: step.ctrl,
                            minLines: 1,
                            maxLines: 6,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                                isDense: true, hintText: 'Step ${i + 1}'),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          tooltip: 'Remove step',
                          onPressed: () => _removeStep(i),
                        ),
                      ],
                    ),
                    if (_saved)
                      _StepImages(
                        protocolId: _id,
                        stepId: step.id,
                        ensureSaved: _persist,
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
                setState(() => _steps.add(_Step(uuid.v4(), TextEditingController()))),
            icon: const Icon(Icons.add),
            label: const Text('Add step'),
          ),
        ),
      ],
    );
  }
}

/// Compact image strip for one protocol step: thumbnails (tap to view/annotate)
/// plus an "Image" button that persists the protocol first (so the step's id is
/// saved) then attaches the picked image to this step.
class _StepImages extends StatelessWidget {
  const _StepImages({
    required this.protocolId,
    required this.stepId,
    required this.ensureSaved,
  });

  final String protocolId;
  final String stepId;
  final Future<void> Function() ensureSaved;

  Future<void> _add(BuildContext context, ImageRepository repo) async {
    await ensureSaved();
    final result =
        await FilePicker.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    await repo.add(
      protocolId: protocolId,
      stepId: stepId,
      bytes: bytes,
      contentType: contentTypeForExtension(file.extension),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ImageRepository(AppDatabaseProvider.of(context));
    return Padding(
      padding: const EdgeInsets.only(left: 26, top: 4, bottom: 4),
      child: StreamBuilder<List<AttachedImage>>(
        stream: repo.watchForProtocolStep(protocolId, stepId),
        builder: (context, snap) {
          final items = snap.data ?? const <AttachedImage>[];
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final img in items) _MiniThumb(image: img, repo: repo),
              OutlinedButton.icon(
                onPressed: () => _add(context, repo),
                icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                label: const Text('Image'),
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MiniThumb extends StatelessWidget {
  const _MiniThumb({required this.image, required this.repo});

  final AttachedImage image;
  final ImageRepository repo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ImageViewerScreen(imageId: image.id))),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: FutureBuilder<Uint8List?>(
              future: repo.bytesFor(image.id),
              builder: (context, s) {
                final bytes = s.data;
                return Container(
                  width: 64,
                  height: 64,
                  color: scheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: bytes != null
                      ? Image.memory(bytes,
                          width: 64, height: 64, fit: BoxFit.cover)
                      : Icon(Icons.image_outlined,
                          color: scheme.onSurfaceVariant),
                );
              },
            ),
          ),
          if (image.annotations.isNotEmpty)
            Positioned(
              right: 3,
              top: 3,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.85),
                    shape: BoxShape.circle),
                child: Icon(Icons.draw, size: 11, color: scheme.onSurface),
              ),
            ),
        ],
      ),
    );
  }
}
