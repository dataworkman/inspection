import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../annotations/annotation_state.dart';
import '../inspections/inspection_state.dart';
import '../photos/photo_input_button.dart';
import '../photos/photo_picker_service.dart';

class InspectionScreen extends StatefulWidget {
  const InspectionScreen({super.key});

  @override
  State<InspectionScreen> createState() => _InspectionScreenState();
}

class _InspectionScreenState extends State<InspectionScreen> {
  final _comment = TextEditingController();
  final _photoPicker = PhotoPickerService();

  @override
  Widget build(BuildContext context) {
    final inspections = context.watch<InspectionState>();
    final inspection = inspections.activeInspection;
    if (inspection == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final responses = inspection['responses'] as List<dynamic>;
    return Scaffold(
      appBar: AppBar(
          title: Text(
              (inspection['store'] as Map<String, dynamic>)['name'] as String)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _InspectionHeader(inspection: inspection),
          const SizedBox(height: 16),
          for (final raw in responses)
            ResponseTile(
              response: raw as Map<String, dynamic>,
              onPhoto: _addPhoto,
              onPhotoSelected: _uploadSelectedPhoto,
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _comment,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
                labelText: 'Inspection comment', border: OutlineInputBorder()),
            onChanged: (value) => inspections.updateComment(value),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              await inspections.submit(_comment.text);
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.cloud_done),
            label: const Text('Submit inspection'),
          ),
        ],
      ),
    );
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
          MaterialPageRoute(
              builder: (_) => AnnotationScreen(file: selectedFile)),
        ) ??
        const AnnotationResult(payload: '{}');
    if (!context.mounted) return;

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
              value: inspection['status'].toString(),
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
  late bool _passed;
  late bool _notApplicable;
  final _comment = TextEditingController();

  @override
  void initState() {
    super.initState();
    _score = ((widget.response['score'] as num?) ?? 1).toDouble().clamp(1, 5);
    _passed = widget.response['passed'] == true;
    _notApplicable = widget.response['not_applicable'] == true;
    _comment.text = widget.response['comment']?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
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
                      _CategoryChip(
                          label: widget.response['category'] as String),
                      const SizedBox(height: 8),
                      Text(widget.response['title'] as String,
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                ),
                Checkbox(
                  value: _notApplicable,
                  onChanged: (value) {
                    setState(() => _notApplicable = value ?? false);
                    _save(context);
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
                    max: 5,
                    divisions: 4,
                    label: _score.round().toString(),
                    onChanged: _notApplicable
                        ? null
                        : (value) => setState(() => _score = value),
                    onChangeEnd: (_) => _save(context),
                  ),
                ),
                Text(_score.round().toString()),
                const SizedBox(width: 12),
                const Text('Pass'),
                Switch(
                    value: _passed,
                    onChanged: (value) => setState(() => _passed = value)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _comment,
              decoration: const InputDecoration(labelText: 'Comment'),
              onSubmitted: (_) => _save(context),
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
                  IconButton.filledTonal(
                    onPressed: () =>
                        context.read<InspectionState>().createAction(
                              widget.response['id'] as int,
                              widget.response['title'] as String,
                            ),
                    icon: const Icon(Icons.report_problem),
                    tooltip: 'Add corrective action',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context) {
    return context.read<InspectionState>().updateResponse(
          widget.response['id'] as int,
          score: _score.round(),
          notApplicable: _notApplicable,
          passed: _passed,
          comment: _comment.text,
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
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
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

class AnnotationResult {
  const AnnotationResult({required this.payload, this.file});

  final String payload;
  final XFile? file;
}

class AnnotationScreen extends StatefulWidget {
  const AnnotationScreen({super.key, required this.file});

  final XFile file;

  @override
  State<AnnotationScreen> createState() => _AnnotationScreenState();
}

class _AnnotationScreenState extends State<AnnotationScreen> {
  final _previewKey = GlobalKey();
  late final Future<Uint8List> _bytes = widget.file.readAsBytes();

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AnnotationState(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Annotate photo'),
          actions: [
            Consumer<AnnotationState>(
              builder: (context, annotation, _) => IconButton(
                onPressed: () => _finish(context, annotation),
                icon: const Icon(Icons.check),
                tooltip: 'Done',
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            const AnnotationToolbar(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final canvasSize =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) => context
                        .read<AnnotationState>()
                        .startMark(details.localPosition, canvasSize, 'Issue'),
                    onPanUpdate: (details) => context
                        .read<AnnotationState>()
                        .updateMark(details.localPosition, canvasSize),
                    onPanEnd: (_) =>
                        context.read<AnnotationState>().finishMark(),
                    onTapUp: (details) {
                      final annotation = context.read<AnnotationState>();
                      annotation.startMark(
                          details.localPosition, canvasSize, 'Issue');
                      annotation.finishMark();
                    },
                    child: RepaintBoundary(
                      key: _previewKey,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          FutureBuilder<Uint8List>(
                            future: _bytes,
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return _PhotoPreviewError(
                                    error: snapshot.error ?? 'Unknown error');
                              }
                              if (!snapshot.hasData) {
                                return const Center(
                                    child: CircularProgressIndicator());
                              }
                              return _PickedPhotoImage(
                                file: widget.file,
                                bytes: snapshot.data!,
                              );
                            },
                          ),
                          Consumer<AnnotationState>(
                            builder: (context, annotation, child) =>
                                CustomPaint(
                                    painter: AnnotationPainter([
                              ...annotation.marks,
                              if (annotation.draft != null) annotation.draft!,
                            ])),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finish(BuildContext context, AnnotationState annotation) async {
    annotation.finishMark();
    final payload = annotation.toPayload();
    XFile? annotatedFile;
    try {
      final boundary = _previewKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final bytes = data?.buffer.asUint8List();
        if (bytes != null) {
          annotatedFile = XFile.fromData(
            bytes,
            name: _annotatedFilename(widget.file.name),
            mimeType: 'image/png',
            length: bytes.length,
          );
        }
      }
    } catch (error) {
      debugPrint('Annotated image capture failed: $error');
    }

    if (context.mounted) {
      Navigator.of(context)
          .pop(AnnotationResult(payload: payload, file: annotatedFile));
    }
  }

  String _annotatedFilename(String originalName) {
    final stem = originalName.contains('.')
        ? originalName.substring(0, originalName.lastIndexOf('.'))
        : (originalName.isEmpty ? 'inspection-photo' : originalName);
    return '$stem-annotated.png';
  }
}

class AnnotationToolbar extends StatelessWidget {
  const AnnotationToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final annotation = context.watch<AnnotationState>();
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SegmentedButton<AnnotationTool>(
              segments: const [
                ButtonSegment(
                    value: AnnotationTool.pen,
                    icon: Icon(Icons.draw),
                    tooltip: 'Pen'),
                ButtonSegment(
                    value: AnnotationTool.arrow,
                    icon: Icon(Icons.arrow_outward),
                    tooltip: 'Arrow'),
                ButtonSegment(
                    value: AnnotationTool.circle,
                    icon: Icon(Icons.circle_outlined),
                    tooltip: 'Circle'),
                ButtonSegment(
                    value: AnnotationTool.rectangle,
                    icon: Icon(Icons.crop_square),
                    tooltip: 'Rectangle'),
                ButtonSegment(
                    value: AnnotationTool.text,
                    icon: Icon(Icons.text_fields),
                    tooltip: 'Text'),
              ],
              selected: {annotation.tool},
              showSelectedIcon: false,
              onSelectionChanged: (selected) =>
                  annotation.setTool(selected.first),
            ),
            const SizedBox(width: 12),
            IconButton(
                onPressed: annotation.undo,
                icon: const Icon(Icons.undo),
                tooltip: 'Undo'),
            IconButton(
                onPressed: annotation.redo,
                icon: const Icon(Icons.redo),
                tooltip: 'Redo'),
            IconButton(
                onPressed: annotation.clear,
                icon: const Icon(Icons.clear),
                tooltip: 'Clear'),
            const SizedBox(width: 12),
            SizedBox(
              width: 180,
              child: Slider(
                  value: annotation.strokeWidth,
                  min: 1,
                  max: 8,
                  onChanged: annotation.setStrokeWidth),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickedPhotoImage extends StatelessWidget {
  const _PickedPhotoImage({required this.file, required this.bytes});

  final XFile file;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    final fallback = Image.memory(
      bytes,
      fit: BoxFit.contain,
      errorBuilder: (_, error, __) => _PhotoPreviewError(error: error),
    );

    if (!kIsWeb || file.path.isEmpty) return fallback;

    return Image.network(
      file.path,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

class _PhotoPreviewError extends StatelessWidget {
  const _PhotoPreviewError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Photo preview failed: $error',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}

class AnnotationPainter extends CustomPainter {
  AnnotationPainter(this.marks);

  final List<AnnotationMark> marks;

  @override
  void paint(Canvas canvas, Size size) {
    for (final mark in marks) {
      final paint = Paint()
        ..color = mark.color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = mark.strokeWidth;
      final center = Offset(mark.x * size.width, mark.y * size.height);
      final end = Offset((mark.endX ?? mark.x) * size.width,
          (mark.endY ?? mark.y) * size.height);
      switch (mark.tool) {
        case AnnotationTool.pen:
          if (mark.points.length > 1) {
            final path = Path()
              ..moveTo(mark.points.first.dx * size.width,
                  mark.points.first.dy * size.height);
            for (final point in mark.points.skip(1)) {
              path.lineTo(point.dx * size.width, point.dy * size.height);
            }
            canvas.drawPath(path, paint);
          } else {
            canvas.drawCircle(center, mark.strokeWidth * 1.4,
                paint..style = PaintingStyle.fill);
          }
        case AnnotationTool.arrow:
          final arrowEnd = end == center ? center.translate(56, -36) : end;
          _drawArrow(canvas, center, arrowEnd, paint);
        case AnnotationTool.circle:
          final rect = Rect.fromPoints(
              center, end == center ? center.translate(56, 56) : end);
          canvas.drawOval(rect, paint);
        case AnnotationTool.rectangle:
          canvas.drawRect(
              Rect.fromPoints(
                  center, end == center ? center.translate(72, 48) : end),
              paint);
        case AnnotationTool.text:
          final painter = TextPainter(
              text: TextSpan(
                  text: mark.note,
                  style: TextStyle(color: mark.color, fontSize: 18)),
              textDirection: TextDirection.ltr);
          painter.layout();
          painter.paint(canvas, center);
      }
    }
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
    final direction = end - start;
    if (direction.distance == 0) return;
    final unit = direction / direction.distance;
    final normal = Offset(-unit.dy, unit.dx);
    final headLength = 18.0 + paint.strokeWidth;
    final headWidth = 8.0 + paint.strokeWidth;
    final base = end - unit * headLength;
    canvas.drawLine(end, base + normal * headWidth, paint);
    canvas.drawLine(end, base - normal * headWidth, paint);
  }

  @override
  bool shouldRepaint(covariant AnnotationPainter oldDelegate) =>
      oldDelegate.marks != marks;
}
