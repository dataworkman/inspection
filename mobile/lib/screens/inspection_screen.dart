import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../inspections/inspection_state.dart';
import '../photos/photo_input_button.dart';
import '../photos/photo_picker_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_card.dart';
import '../widgets/content_width.dart';
import '../widgets/score_ring.dart';
import '../widgets/section_title.dart';
import '../widgets/status_pill.dart';
import 'annotation_screen.dart';
import 'corrective_action_dialog.dart';

export 'annotation_screen.dart' show AnnotationResult, AnnotationScreen;

/// Result labels of a finished item (see InspectionResponse#passed on the server).
const _passLabel = 'Pass';
const _needsWorkLabel = 'Needs work';

bool _isAnswered(Map<String, dynamic> response) =>
    ((response['score'] as num?) ?? 0) > 0 ||
    response['not_applicable'] == true;

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

    final groups = _groupResponsesByCategory(inspection['responses']);
    final all = groups.expand((group) => group.responses).toList();
    final answered = all.where(_isAnswered).length;
    final store = inspection['store'] as Map<String, dynamic>;

    return Scaffold(
      appBar: AppBar(title: Text(store['name'] as String)),
      // The banner sits above the list, not inside it: inserting a child at the
      // top of an unkeyed list would shift every item's state onto the wrong
      // widget and wipe what the user just entered.
      body: Column(
        children: [
          if (inspections.saveError != null)
            _SaveErrorBanner(
              message: inspections.saveErrorWillRetry
                  ? '${inspections.saveError!}. Your changes are kept on this device and will be sent when the connection is back.'
                  : inspections.saveError!,
              onRetry: () => inspections.flushPendingSaves().ignore(),
            ),
          Expanded(
            child: ContentWidth(
              child: ListView(
                // On the web the photo button is an HtmlElementView, and Flutter's
                // platform view placeholder asserts (localToGlobal on a detached box)
                // whenever a lazy list builds and drops such a child within a frame,
                // which happens constantly while scrolling. A checklist only has a
                // couple of dozen items, so build them all once.
                scrollCacheExtent:
                    kIsWeb ? const ScrollCacheExtent.pixels(20000) : null,
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg,
                    AppSpacing.lg, AppSpacing.xxl),
                children: [
                  _InspectionHeader(
                      inspection: inspection,
                      answered: answered,
                      total: all.length),
                  const SizedBox(height: AppSpacing.xl),
                  for (final group in groups) ...[
                    _CategorySectionHeader(group: group),
                    for (final response in group.responses)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: ResponseTile(
                          key: ValueKey('response-${response['id']}'),
                          response: response,
                          onPhoto: _addPhoto,
                          onPhotoSelected: _uploadSelectedPhoto,
                        ),
                      ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  const SectionTitle('Inspection notes'),
                  AppCard(
                    child: TextField(
                      controller: _comment,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Inspection comment',
                        alignLabelWithHint: true,
                      ),
                      onChanged: inspections.scheduleCommentSave,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _SubmitBar(
        answered: answered,
        total: all.length,
        submitting: _submitting,
        onSubmit: () => _submit(context, inspections),
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
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo library'),
              onTap: () => Navigator.of(context).pop(_PhotoSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
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
    final colors = toneColors(Tone.danger);
    return Material(
      color: colors.background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, size: 20, color: colors.foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Some changes are not saved: $message',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: colors.foreground)),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: colors.foreground),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Summary of the inspection: score, status, and how much is answered.
class _InspectionHeader extends StatelessWidget {
  const _InspectionHeader({
    required this.inspection,
    this.answered,
    this.total,
    this.showProgress = true,
  });

  final Map<String, dynamic> inspection;
  final int? answered;
  final int? total;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = inspection['store'] as Map<String, dynamic>;
    final grade = inspection['grade']?.toString();
    final score = inspection['score'] as num?;
    final inProgress = inspection['status'] != 'submitted';
    final submittedAt = parseApiTime(inspection['submitted_at']);
    final inspector =
        (inspection['inspector'] as Map<String, dynamic>?)?['name']?.toString();
    final template =
        (inspection['template'] as Map<String, dynamic>?)?['name']?.toString();

    final meta = [
      if (!inProgress && submittedAt != null)
        'Submitted ${formatDate(submittedAt)}',
      if (inspector != null) inspector,
      if (template != null) template,
    ].join(' - ');

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ScoreRing(
                  score: inProgress && (score ?? 0) == 0 ? null : score,
                  size: 64),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(store['name'] as String,
                        style: theme.textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text('${store['store_code']} - ${store['address']}',
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        StatusPill(
                          label: humanize(inspection['status']),
                          tone: inProgress ? Tone.info : Tone.brand,
                        ),
                        if (grade != null)
                          StatusPill(label: grade, tone: toneForGrade(grade)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(meta, style: theme.textTheme.bodySmall),
          ],
          if (showProgress && total != null && total! > 0) ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: LinearProgressIndicator(
                      value: (answered ?? 0) / total!,
                      minHeight: 6,
                      color: AppColors.primary,
                      backgroundColor: AppColors.surfaceMuted,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text('$answered of $total answered',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CategorySectionHeader extends StatelessWidget {
  const _CategorySectionHeader({required this.group});

  final _CategoryResponseGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final answered = group.responses.where(_isAnswered).length;
    final complete = answered == group.responses.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: AppColors.primary, shape: BoxShape.circle),
            child: Text('${group.position ?? ''}',
                style:
                    theme.textTheme.labelMedium?.copyWith(color: Colors.white)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(group.name, style: theme.textTheme.titleMedium)),
          StatusPill(
            label: '$answered/${group.responses.length}',
            tone: complete ? Tone.success : Tone.neutral,
            icon: complete ? Icons.check : null,
          ),
        ],
      ),
    );
  }
}

/// Sticky bar with progress and the submit button.
class _SubmitBar extends StatelessWidget {
  const _SubmitBar({
    required this.answered,
    required this.total,
    required this.submitting,
    required this.onSubmit,
  });

  final int answered;
  final int total;
  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.surface,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.borderSoft)),
        ),
        child: SafeArea(
          top: false,
          // heightFactor: 1 keeps the bar as tall as its content; a plain
          // Align/Center would expand to the whole screen height.
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$answered of $total answered',
                              style: theme.textTheme.titleSmall),
                          Text(
                              answered == total
                                  ? 'Ready to submit'
                                  : '${total - answered} left',
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: submitting ? null : onSubmit,
                      icon: submitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white))
                          : const Icon(Icons.check_rounded),
                      label: Text(
                          submitting ? 'Submitting...' : 'Submit inspection'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- finished inspection -----------------------------------------------------

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
    final comment = inspection['comment']?.toString() ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Inspection Result')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
          children: [
            _InspectionHeader(inspection: inspection, showProgress: false),
            if (comment.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Inspector notes',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: AppSpacing.xs),
                    Text(comment),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            const SectionTitle('Result table'),
            for (final group in groups)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _CategoryResultTable(
                  group: group,
                  responseResult: _responseResult,
                ),
              ),
            if (evidenceRows.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              const SectionTitle('Attached photos'),
              for (final response in evidenceRows)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(response['title']?.toString() ?? '-',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: AppSpacing.md),
                        PhotoStrip(
                            photos: response['photos'] as List<dynamic>? ??
                                const []),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _responseResult(Map<String, dynamic> response) {
    if (response['not_applicable'] == true) return 'N/A';
    return switch (response['passed']) {
      true => _passLabel,
      false => _needsWorkLabel,
      _ => '-',
    };
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
    final ratio = possible > 0 ? earned / possible : null;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Text(group.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                StatusPill(
                  label: possible > 0
                      ? '${earned.round()}/${possible.round()}'
                      : 'N/A',
                  tone:
                      ratio == null ? Tone.neutral : toneForScore(ratio * 100),
                ),
              ],
            ),
          ),
          for (final response in group.responses) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: _ResultRow(
                  response: response, result: responseResult(response)),
            ),
          ],
        ],
      ),
    );
  }
}

/// One checklist item of a finished inspection, readable at phone width:
/// title and notes on the left, score and result on the right.
class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.response, required this.result});

  final Map<String, dynamic> response;
  final String result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comment = response['comment']?.toString() ?? '';
    final photos = (response['photos'] as List<dynamic>? ?? const []).length;
    final scored = response['not_applicable'] != true &&
        ((response['score'] as num?) ?? 0) > 0;
    final tone = switch (result) {
      _passLabel => Tone.success,
      _needsWorkLabel => Tone.warning,
      _ => Tone.neutral,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(response['title']?.toString() ?? '-',
                  style: theme.textTheme.bodyLarge),
              if (comment.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(comment, style: theme.textTheme.bodySmall),
                ),
              if (photos > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.photo_camera_outlined,
                          size: 14, color: AppColors.textFaint),
                      const SizedBox(width: 4),
                      Text('$photos', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
                scored
                    ? '${response['score']}/${response['max_score'] ?? 5}'
                    : '-',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            StatusPill(label: result, tone: tone, dense: true),
          ],
        ),
      ],
    );
  }
}

// --- one checklist item ------------------------------------------------------

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
  /// Null while the item is unanswered (the server stores 0).
  int? _score;
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
    final savedScore = ((widget.response['score'] as num?) ?? 0).toInt();
    _score = savedScore > 0 ? savedScore.clamp(1, _maxScore) : null;
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

  void _selectScore(int value) {
    setState(() => _score = value);
    _save(immediate: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existingActions = context.select<InspectionState, int>((state) =>
        state.actionsForResponse(widget.response['id'] as int).length);
    final answered = _score != null || _notApplicable;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      color: answered ? null : null,
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
                        style: theme.textTheme.titleMedium),
                    _requirements(),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilterChip(
                label: const Text('N/A'),
                selected: _notApplicable,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                selectedColor: AppColors.surfaceMuted,
                side: const BorderSide(color: AppColors.border),
                onSelected: (value) {
                  setState(() => _notApplicable = value);
                  _save(immediate: true);
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _rating(context),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _comment,
            focusNode: _commentFocus,
            minLines: 1,
            maxLines: 4,
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
          if ((widget.response['photos'] as List<dynamic>? ?? const [])
              .isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            PhotoStrip(
                photos:
                    (widget.response['photos'] as List<dynamic>? ?? const [])),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (kIsWeb)
                PhotoInputButton(
                  tooltip: 'Add photo',
                  label: 'Photo',
                  onPhotoPicked: (file) =>
                      widget.onPhotoSelected(context, widget.response, file),
                )
              else
                Tooltip(
                  message: 'Add photo',
                  child: OutlinedButton.icon(
                    onPressed: () => widget.onPhoto(context, widget.response),
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: const Text('Photo'),
                  ),
                ),
              Badge(
                isLabelVisible: existingActions > 0,
                label: Text('$existingActions'),
                child: Tooltip(
                  message: 'Add corrective action',
                  child: OutlinedButton.icon(
                    onPressed: _creatingAction ? null : _addAction,
                    icon: _creatingAction
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.flag_outlined, size: 18),
                    label: const Text('Action'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// One tappable number per point of the scale; a slider only for unusually
  /// long scales.
  Widget _rating(BuildContext context) {
    final theme = Theme.of(context);
    if (_maxScore > 10) {
      return Row(
        children: [
          Expanded(
            child: Slider(
              value: (_score ?? 1).toDouble(),
              min: 1,
              max: _maxScore.toDouble(),
              divisions: _maxScore - 1,
              label: (_score ?? 1).toString(),
              onChanged: _notApplicable
                  ? null
                  : (value) => setState(() => _score = value.round()),
              onChangeEnd: (_) => _save(immediate: true),
            ),
          ),
          Text(_score?.toString() ?? '-'),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var value = 1; value <= _maxScore; value++) ...[
              if (value > 1) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _RatingButton(
                  key: ValueKey('rating-$value'),
                  value: value,
                  selected: _score == value,
                  enabled: !_notApplicable,
                  onTap: () => _selectScore(value),
                ),
              ),
            ],
          ],
        ),
        if (_maxScore == 5) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Poor', style: theme.textTheme.bodySmall),
              Text('Excellent', style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ],
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
          score: _score ?? 0,
          notApplicable: _notApplicable,
          comment: _comment.text,
          immediate: immediate,
        );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    super.key,
    required this.value,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final int value;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = selected ? AppColors.primary : AppColors.surface;
    final foreground = !enabled
        ? AppColors.textFaint
        : selected
            ? Colors.white
            : AppColors.text;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: 'Score $value',
      child: Material(
        color: enabled ? background : AppColors.surfaceMuted,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(
              color: selected ? AppColors.primary : AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.control),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            height: 46,
            child: Center(
              child: Text('$value',
                  style:
                      theme.textTheme.titleMedium?.copyWith(color: foreground)),
            ),
          ),
        ),
      ),
    );
  }
}

class _RequirementChip extends StatelessWidget {
  const _RequirementChip({required this.label, required this.done});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) => StatusPill(
        label: label,
        tone: done ? Tone.success : Tone.warning,
        icon: done ? Icons.check_circle : Icons.error_outline,
        dense: true,
      );
}

// --- photos --------------------------------------------------------------------

class PhotoStrip extends StatelessWidget {
  const PhotoStrip({super.key, required this.photos});

  final List<dynamic> photos;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 176,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (context, index) {
          final photo = photos[index] as Map<String, dynamic>;
          final imagePath =
              photo['annotated_image_url'] ?? photo['original_image_url'];
          if (imagePath == null) return const SizedBox.shrink();

          final imageUrl = _absoluteApiUrl(context, imagePath.toString());
          return SizedBox(
            width: 232,
            child: Material(
              color: AppColors.surfaceMuted,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                side: const BorderSide(color: AppColors.borderSoft),
              ),
              child: InkWell(
                onTap: () => _openPhoto(context, imageUrl),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image_outlined,
                              color: AppColors.textFaint)),
                    ),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.zoom_out_map,
                                size: 12, color: Colors.white),
                            const SizedBox(width: 4),
                            Text('Photo ${index + 1}',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
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
        backgroundColor: const Color(0xff101512),
        child: Scaffold(
          backgroundColor: const Color(0xff101512),
          appBar: AppBar(
            backgroundColor: const Color(0xff101512),
            foregroundColor: Colors.white,
            shape: const Border(),
            title: Text('Attached photo',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.white)),
            actions: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                tooltip: 'Close',
              )
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Image.network(imageUrl, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}
