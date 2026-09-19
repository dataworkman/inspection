import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../inspections/inspection_state.dart';
import '../photos/photo_input_button.dart';
import '../photos/photo_picker_service.dart';
import 'annotation_screen.dart';
import 'corrective_action_dialog.dart';

export 'annotation_screen.dart' show AnnotationResult, AnnotationScreen;

class InspectionScreen extends StatefulWidget {
  const InspectionScreen({super.key, this.photoPicker});

  /// Overridable for tests; defaults to the real camera/gallery picker.
  final PhotoPickerService? photoPicker;

  @override
  State<InspectionScreen> createState() => _InspectionScreenState();
}

class _InspectionScreenState extends State<InspectionScreen> {
  final _comment = TextEditingController();
  late final _photoPicker = widget.photoPicker ?? PhotoPickerService();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // Resuming an inspection: bring back the comment written so far.
    _comment.text = context
            .read<InspectionState>()
            .activeInspection?['comment']
            ?.toString() ??
        '';
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inspections = context.watch<InspectionState>();
    final inspection = inspections.activeInspection;
    if (inspection == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final responses = _groupResponsesByCategory(inspection['responses']);
    return Scaffold(
      appBar: AppBar(
          title: Text(
              (inspection['store'] as Map<String, dynamic>)['name'] as String)),
      // The banner sits above the list, not inside it: inserting a child at the
      // top of an unkeyed list would shift every item's state onto the wrong
      // widget and wipe what the user just entered.
      body: Column(
        children: [
          if (inspections.saveError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _SaveErrorBanner(
                message: inspections.saveErrorWillRetry
                    ? '${inspections.saveError!}. Your changes are kept on this device and will be sent when the connection is back.'
                    : inspections.saveError!,
                onRetry: () => inspections.flushPendingSaves().ignore(),
              ),
            ),
          Expanded(
            child: ListView(
              // On the web the photo button is an HtmlElementView, and Flutter's
              // platform view placeholder asserts (localToGlobal on a detached box)
              // whenever a lazy list builds and drops such a child within a frame,
              // which happens constantly while scrolling. A checklist only has a
              // couple of dozen items, so build them all once.
              scrollCacheExtent:
                  kIsWeb ? const ScrollCacheExtent.pixels(20000) : null,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                _InspectionHeader(inspection: inspection),
                const SizedBox(height: 16),
                for (final group in responses) ...[
                  _CategorySectionHeader(group: group),
                  const SizedBox(height: 8),
                  for (final response in group.responses)
                    ResponseTile(
                      key: ValueKey('response-${response['id']}'),
                      response: response,
                      onPhoto: _addPhoto,
                      onPhotoSelected: _uploadSelectedPhoto,
                    ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _comment,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                      labelText: 'Inspection comment',
                      border: OutlineInputBorder()),
                  onChanged: inspections.scheduleCommentSave,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed:
                      _submitting ? null : () => _submit(context, inspections),
                  icon: const Icon(Icons.cloud_done),
                  label:
                      Text(_submitting ? 'Submitting...' : 'Submit inspection'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(
      BuildContext context, InspectionState inspections) async {
    setState(() => _submitting = true);
    try {
      await inspections.submit(_comment.text);
      final submitted = inspections.activeInspection;
      if (context.mounted && submitted != null) {
        await Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => InspectionResultScreen(inspection: submitted)));
      }
    } catch (error) {
      // The server rejects submissions with unanswered required items,
      // missing required photos or comments; show what it says.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not submit: $error'),
              duration: const Duration(seconds: 6)),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _addPhoto(
      BuildContext context, Map<String, dynamic> response) async {
    XFile? file;
    try {
      file = await _pickPhoto(context);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Photo selection failed: $error')));
      }
      return;
    }
    final selectedFile = file;
    if (selectedFile == null || !context.mounted) return;

    await _uploadSelectedPhoto(context, response, selectedFile);
  }

  Future<void> _uploadSelectedPhoto(
    BuildContext context,
    Map<String, dynamic> response,
    XFile selectedFile,
  ) async {
    if (!context.mounted) return;

    final annotation = await Navigator.of(context).push<AnnotationResult>(
      MaterialPageRoute(builder: (_) => AnnotationScreen(file: selectedFile)),
    );
    // Backing out of the annotation screen cancels the attachment.
    if (annotation == null || !context.mounted) return;

    try {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Uploading photo...')));
      await context.read<InspectionState>().uploadPhoto(
            file: selectedFile,
            annotatedFile: annotation.file,
            responseId: response['id'] as int,
            annotationJson: annotation.payload,
            comment: 'Field photo',
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Photo attached')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Photo upload failed: $error')));
      }
    }
  }

  Future<XFile?> _pickPhoto(BuildContext context) async {
    if (kIsWeb) {
      return _photoPicker.choosePhoto();
    }

    final source = await showModalBottomSheet<_PhotoSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Photo library'),
              onTap: () => Navigator.of(context).pop(_PhotoSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Camera'),
              onTap: () => Navigator.of(context).pop(_PhotoSource.camera),
            ),
          ],
        ),
      ),
    );

    return switch (source) {
      _PhotoSource.camera => _photoPicker.takePhoto(),
      _PhotoSource.gallery => _photoPicker.choosePhoto(),
      null => null,
    };
  }
}

enum _PhotoSource { camera, gallery }

List<_CategoryResponseGroup> _groupResponsesByCategory(Object? rawResponses) {
  final responses = (rawResponses as List<dynamic>? ?? const [])
      .cast<Map<String, dynamic>>()
      .toList()
    ..sort((left, right) {
      final categoryOrder = _readInt(left['category_position'])
          .compareTo(_readInt(right['category_position']));
      if (categoryOrder != 0) return categoryOrder;

      final categoryName = (left['category']?.toString() ?? '')
          .compareTo(right['category']?.toString() ?? '');
      if (categoryName != 0) return categoryName;

      final questionOrder =
          _readInt(left['position']).compareTo(_readInt(right['position']));
      if (questionOrder != 0) return questionOrder;

      return (left['title']?.toString() ?? '')
          .compareTo(right['title']?.toString() ?? '');
    });

  final groups = <_CategoryResponseGroup>[];
  for (final response in responses) {
    final category = response['category']?.toString() ?? 'Uncategorized';
    final position = _readInt(response['category_position']);
    if (groups.isEmpty || groups.last.name != category) {
      groups.add(_CategoryResponseGroup(
        name: category,
        position: position == _lastSortPosition ? null : position,
        responses: [],
      ));
    }
    groups.last.responses.add(response);
  }

  return groups;
}

const _lastSortPosition = 1 << 30;

int _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? _lastSortPosition;
}

class _CategoryResponseGroup {
  _CategoryResponseGroup({
    required this.name,
    required this.position,
    required this.responses,
  });

  final String name;
  final int? position;
  final List<Map<String, dynamic>> responses;
}

class _SaveErrorBanner extends StatelessWidget {
  const _SaveErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.cloud_off, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Some changes are not saved: $message',
                  style: TextStyle(color: scheme.onErrorContainer)),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _CategorySectionHeader extends StatelessWidget {
  const _CategorySectionHeader({required this.group});

  final _CategoryResponseGroup group;

  @override
  Widget build(BuildContext context) {
    final answered = group.responses
        .where((response) =>
            ((response['score'] as num?) ?? 0) > 0 ||
            response['not_applicable'] == true)
        .length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffcfdac6)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            child: Text('${group.position ?? ''}'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(group.name,
                style: Theme.of(context).textTheme.titleMedium),
          ),
          Text('$answered/${group.responses.length}',
              style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _CategoryResultTable extends StatelessWidget {
  const _CategoryResultTable({
    required this.group,
    required this.responseResult,
  });

  final _CategoryResponseGroup group;
  final String Function(Map<String, dynamic> response) responseResult;

  @override
  Widget build(BuildContext context) {
    final scoredResponses = group.responses
        .where((response) =>
            response['not_applicable'] != true &&
            ((response['score'] as num?) ?? 0) > 0)
        .toList();
    final earned = scoredResponses.fold<double>(
        0, (total, response) => total + (((response['score'] as num?) ?? 0)));
    final possible = scoredResponses.fold<double>(0,
        (total, response) => total + (((response['max_score'] as num?) ?? 5)));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(group.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                _CategoryChip(
                    label: possible > 0
                        ? '${earned.round()}/${possible.round()}'
                        : 'N/A'),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                    Theme.of(context).colorScheme.surfaceContainerHighest),
                columns: const [
                  DataColumn(label: Text('Item')),
                  DataColumn(label: Text('Score')),
                  DataColumn(label: Text('Result')),
                  DataColumn(label: Text('Comment')),
                  DataColumn(label: Text('Photos')),
                ],
                rows: [
                  for (final response in group.responses)
                    DataRow(cells: [
                      DataCell(SizedBox(
                        width: 280,
                        child: Text(
                          response['title']?.toString() ?? '-',
                          overflow: TextOverflow.ellipsis,
                        ),
                      )),
                      DataCell(Text(
                          '${response['score'] ?? 0}/${response['max_score'] ?? 5}')),
                      DataCell(Text(responseResult(response))),
                      DataCell(SizedBox(
                        width: 260,
                        child: Text(
                          response['comment']?.toString().isNotEmpty == true
                              ? response['comment'].toString()
                              : '-',
                          overflow: TextOverflow.ellipsis,
                        ),
                      )),
                      DataCell(Text(
                          '${(response['photos'] as List<dynamic>? ?? const []).length}')),
                    ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InspectionHeader extends StatelessWidget {
  const _InspectionHeader({required this.inspection});

  final Map<String, dynamic> inspection;

  @override
  Widget build(BuildContext context) {
    final store = inspection['store'] as Map<String, dynamic>;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 20,
          runSpacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(store['name'] as String,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text('${store['store_code']} - ${store['address']}'),
                ],
              ),
            ),
            _InspectionMetric(
              label: 'Score',
              value: '${inspection['score'] ?? 0}',
              icon: Icons.speed,
            ),
            _InspectionMetric(
              label: 'Status',
              value: _statusLabel(inspection['status']),
              icon: Icons.assignment,
            ),
            if (inspection['grade'] != null)
              _InspectionMetric(
                label: 'Grade',
                value: inspection['grade'].toString(),
                icon: Icons.workspace_premium,
              ),
          ],
        ),
      ),
    );
  }
}

/// 'in_progress' -> 'In progress'.
String _statusLabel(Object? status) {
  final text = (status ?? '').toString().replaceAll('_', ' ');
  return text.isEmpty ? '-' : text[0].toUpperCase() + text.substring(1);
}

class _InspectionMetric extends StatelessWidget {
  const _InspectionMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffdfe5d8)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
                Text(label, style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class InspectionResultScreen extends StatelessWidget {
  const InspectionResultScreen({super.key, required this.inspection});

  final Map<String, dynamic> inspection;

  @override
  Widget build(BuildContext context) {
    final groups = _groupResponsesByCategory(inspection['responses']);
    final responses = groups.expand((group) => group.responses).toList();
    final evidenceRows = responses
        .where((response) =>
            (response['photos'] as List<dynamic>? ?? const []).isNotEmpty)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Inspection Result')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _InspectionHeader(inspection: inspection),
          const SizedBox(height: 16),
          Text('Result table', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final group in groups) ...[
            _CategoryResultTable(
              group: group,
              responseResult: _responseResult,
            ),
            const SizedBox(height: 12),
          ],
          if (evidenceRows.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Attached photos',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final response in evidenceRows)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(response['title']?.toString() ?? '-',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      PhotoStrip(
                          photos:
                              response['photos'] as List<dynamic>? ?? const []),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _responseResult(Map<String, dynamic> response) {
    if (response['not_applicable'] == true) return 'N/A';
    return switch (response['passed']) {
      true => 'Pass',
      false => 'Review',
      _ => '-',
    };
  }
}

class ResponseTile extends StatefulWidget {
  const ResponseTile(
      {super.key,
      required this.response,
      required this.onPhoto,
      required this.onPhotoSelected});

  final Map<String, dynamic> response;
  final Future<void> Function(
      BuildContext context, Map<String, dynamic> response) onPhoto;
  final Future<void> Function(
          BuildContext context, Map<String, dynamic> response, XFile file)
      onPhotoSelected;

  @override
  State<ResponseTile> createState() => _ResponseTileState();
}

class _ResponseTileState extends State<ResponseTile> {
  late double _score;
  late bool _answered;
  late bool _notApplicable;
  late final int _maxScore =
      ((widget.response['max_score'] as num?) ?? 5).toInt().clamp(1, 100);
  bool _creatingAction = false;
  final _comment = TextEditingController();
  final _commentFocus = FocusNode();
  bool _commentDirty = false;

  @override
  void initState() {
    super.initState();
    // The server stores 0 for "not answered yet"; the scale itself starts at 1.
    final savedScore = ((widget.response['score'] as num?) ?? 0).toInt();
    _answered = savedScore > 0;
    _score = savedScore > 0 ? savedScore.clamp(1, _maxScore).toDouble() : 1;
    _notApplicable = widget.response['not_applicable'] == true;
    _comment.text = widget.response['comment']?.toString() ?? '';
    // Leaving the field saves right away; typing alone is debounced.
    _commentFocus.addListener(() {
      if (!_commentFocus.hasFocus && _commentDirty && mounted) {
        _commentDirty = false;
        _save(immediate: true);
      }
    });
  }

  @override
  void dispose() {
    _commentFocus.dispose();
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existingActions = context.select<InspectionState, int>((state) =>
        state.actionsForResponse(widget.response['id'] as int).length);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.response['title'] as String,
                          style: Theme.of(context).textTheme.titleMedium),
                      _requirements(),
                    ],
                  ),
                ),
                Checkbox(
                  value: _notApplicable,
                  onChanged: (value) {
                    setState(() => _notApplicable = value ?? false);
                    _save(immediate: true);
                  },
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('N/A'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _score,
                    min: 1,
                    max: _maxScore.toDouble(),
                    divisions: _maxScore > 1 ? _maxScore - 1 : null,
                    label: _score.round().toString(),
                    onChangeStart: _notApplicable
                        ? null
                        : (_) => setState(() => _answered = true),
                    onChanged: _notApplicable
                        ? null
                        : (value) => setState(() => _score = value),
                    onChangeEnd: (_) => _save(immediate: true),
                  ),
                ),
                Text(_answered ? _score.round().toString() : '-'),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _comment,
              focusNode: _commentFocus,
              decoration: const InputDecoration(labelText: 'Comment'),
              onChanged: (_) {
                setState(() => _commentDirty = true);
                _save();
              },
              onSubmitted: (_) {
                _commentDirty = false;
                _save(immediate: true);
              },
            ),
            PhotoStrip(
                photos:
                    (widget.response['photos'] as List<dynamic>? ?? const [])),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                children: [
                  if (kIsWeb)
                    PhotoInputButton(
                      tooltip: 'Add photo',
                      onPhotoPicked: (file) => widget.onPhotoSelected(
                          context, widget.response, file),
                    )
                  else
                    IconButton.filledTonal(
                      onPressed: () => widget.onPhoto(context, widget.response),
                      icon: const Icon(Icons.add_a_photo),
                      tooltip: 'Add photo',
                    ),
                  Badge(
                    isLabelVisible: existingActions > 0,
                    label: Text('$existingActions'),
                    child: IconButton.filledTonal(
                      onPressed: _creatingAction ? null : _addAction,
                      icon: _creatingAction
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.report_problem),
                      tooltip: 'Add corrective action',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What this item still needs before the inspection can be submitted.
  Widget _requirements() {
    final needsPhoto = widget.response['photo_required'] == true;
    final needsComment = widget.response['comment_required'] == true;
    if (_notApplicable || (!needsPhoto && !needsComment)) {
      return const SizedBox.shrink();
    }
    final hasPhoto =
        (widget.response['photos'] as List<dynamic>? ?? const []).isNotEmpty;
    final hasComment = _comment.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (needsPhoto)
            _RequirementChip(label: 'Photo required', done: hasPhoto),
          if (needsComment)
            _RequirementChip(label: 'Comment required', done: hasComment),
        ],
      ),
    );
  }

  Future<void> _addAction() async {
    final inspections = context.read<InspectionState>();
    final messenger = ScaffoldMessenger.of(context);
    final draft = await showCorrectiveActionDialog(context,
        initialTitle: widget.response['title'] as String);
    if (draft == null || !mounted) return;

    setState(() => _creatingAction = true);
    try {
      await inspections.createAction(
        widget.response['id'] as int,
        title: draft.title,
        severity: draft.severity,
        description: draft.description,
        dueDate: draft.dueDate,
      );
      messenger.showSnackBar(
          const SnackBar(content: Text('Corrective action created')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(
          content: Text('Could not create corrective action: $error')));
    } finally {
      if (mounted) setState(() => _creatingAction = false);
    }
  }

  void _save({bool immediate = false}) {
    context.read<InspectionState>().scheduleResponseSave(
          widget.response['id'] as int,
          score: _answered ? _score.round() : 0,
          notApplicable: _notApplicable,
          comment: _comment.text,
          immediate: immediate,
        );
  }
}

class _RequirementChip extends StatelessWidget {
  const _RequirementChip({required this.label, required this.done});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = done ? scheme.primary : scheme.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(done ? Icons.check_circle : Icons.error_outline,
              size: 14, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class PhotoStrip extends StatelessWidget {
  const PhotoStrip({super.key, required this.photos});

  final List<dynamic> photos;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 220,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final photo = photos[index] as Map<String, dynamic>;
          final imagePath =
              photo['annotated_image_url'] ?? photo['original_image_url'];
          if (imagePath == null) return const SizedBox.shrink();

          final imageUrl = _absoluteApiUrl(context, imagePath.toString());
          return InkWell(
            onTap: () => _openPhoto(context, imageUrl),
            borderRadius: BorderRadius.circular(8),
            child: Ink(
              width: 260,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xffdfe5d8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(8)),
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: const Icon(Icons.broken_image),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.image, size: 16),
                        const SizedBox(width: 6),
                        Expanded(child: Text('Photo ${index + 1}')),
                        const Icon(Icons.open_in_full, size: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _absoluteApiUrl(BuildContext context, String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;

    final baseUrl = context.read<InspectionState>().apiClient.baseUrl;
    return '$baseUrl$path';
  }

  void _openPhoto(BuildContext context, String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Attached photo'),
            actions: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                tooltip: 'Close',
              )
            ],
          ),
          body: Container(
            color: const Color(0xff151a17),
            child: Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Image.network(imageUrl, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
