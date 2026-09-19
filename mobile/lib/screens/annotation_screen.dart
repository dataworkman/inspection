import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../annotations/annotation_state.dart';

class AnnotationResult {
  const AnnotationResult({required this.payload, this.file});

  final String payload;
  final XFile? file;
}

/// Where a photo is drawn inside the annotation canvas.
class AnnotationGeometry {
  /// The largest rectangle with the photo's proportions that fits [canvas],
  /// centered (the photo is shown letterboxed).
  static Rect imageRect(Size image, Size canvas) {
    if (image.isEmpty || canvas.isEmpty) return Rect.zero;
    final scale =
        math.min(canvas.width / image.width, canvas.height / image.height);
    final size = Size(image.width * scale, image.height * scale);
    return Alignment.center.inscribe(size, Offset.zero & canvas);
  }
}

/// Draws the marks onto the photo at (up to) its own resolution, so the saved
/// annotated image is as sharp as the original and has no letterbox.
class AnnotationRenderer {
  static const maxSide = 2048;

  /// [displayWidth] is the width the photo had on screen while it was
  /// annotated; strokes and text are scaled by the ratio to the output.
  static Future<Uint8List?> render({
    required ui.Image image,
    required List<AnnotationMark> marks,
    required double displayWidth,
  }) async {
    final longest = math.max(image.width, image.height).toDouble();
    final factor = longest > maxSide ? maxSide / longest : 1.0;
    final size = Size(image.width * factor, image.height * factor);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.high,
    );
    AnnotationPainter(marks, scale: size.width / displayWidth)
        .paint(canvas, size);

    final picture = recorder.endRecording();
    final rendered =
        await picture.toImage(size.width.round(), size.height.round());
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    rendered.dispose();
    return data?.buffer.asUint8List();
  }
}

class AnnotationScreen extends StatefulWidget {
  const AnnotationScreen({super.key, required this.file});

  final XFile file;

  @override
  State<AnnotationScreen> createState() => _AnnotationScreenState();
}

class _LoadedPhoto {
  const _LoadedPhoto(this.bytes, this.image);

  final Uint8List bytes;
  final ui.Image image;

  Size get size => Size(image.width.toDouble(), image.height.toDouble());
}

class _AnnotationScreenState extends State<AnnotationScreen> {
  final _annotation = AnnotationState();
  late final Future<_LoadedPhoto> _photo = _load();
  Rect _imageRect = Rect.zero;
  bool _ignoringGesture = false;

  Future<_LoadedPhoto> _load() async {
    final bytes = await widget.file.readAsBytes();
    return _LoadedPhoto(bytes, await decodeImageFromList(bytes));
  }

  @override
  void dispose() {
    _annotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _annotation,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Annotate photo'),
          actions: [
            IconButton(
              onPressed: _finish,
              icon: const Icon(Icons.check),
              tooltip: 'Done',
            ),
          ],
        ),
        body: Column(
          children: [
            const AnnotationToolbar(),
            Expanded(
              child: FutureBuilder<_LoadedPhoto>(
                future: _photo,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _PhotoPreviewError(
                        error: snapshot.error ?? 'Unknown error');
                  }
                  final photo = snapshot.data;
                  if (photo == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return _canvas(photo);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _canvas(_LoadedPhoto photo) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvas = Size(constraints.maxWidth, constraints.maxHeight);
        final rect = AnnotationGeometry.imageRect(photo.size, canvas);
        _imageRect = rect;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Start the mark where the finger touched down, not where it had
          // moved to once the drag was recognized.
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: (details) => _panStart(details.localPosition),
          onPanUpdate: (details) {
            if (_ignoringGesture) return;
            _annotation.updateMark(
                details.localPosition - rect.topLeft, rect.size);
          },
          onPanEnd: (_) {
            if (!_ignoringGesture) _annotation.finishMark();
            _ignoringGesture = false;
          },
          onTapUp: (details) => _tap(details.localPosition),
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: rect,
                child: Image.memory(
                  photo.bytes,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  errorBuilder: (_, error, __) =>
                      _PhotoPreviewError(error: error),
                ),
              ),
              Positioned.fromRect(
                rect: rect,
                child: Consumer<AnnotationState>(
                  builder: (context, annotation, _) => CustomPaint(
                    painter: AnnotationPainter([
                      ...annotation.marks,
                      if (annotation.draft != null) annotation.draft!,
                    ]),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Positions are relative to the photo, not to the letterboxed canvas, so the
  // marks land on the same spot of the picture whatever the screen size.
  void _panStart(Offset local) {
    // Text is placed with a tap; drawing outside the photo is ignored.
    _ignoringGesture =
        !_imageRect.contains(local) || _annotation.tool == AnnotationTool.text;
    if (_ignoringGesture) return;
    _annotation.startMark(local - _imageRect.topLeft, _imageRect.size, '');
  }

  Future<void> _tap(Offset local) async {
    if (!_imageRect.contains(local)) return;
    final position = local - _imageRect.topLeft;
    final size = _imageRect.size;

    if (_annotation.tool == AnnotationTool.text) {
      final text = await _askForText();
      if (text != null && text.isNotEmpty && mounted) {
        _annotation.addMark(position, size, text);
      }
      return;
    }
    _annotation.startMark(position, size, '');
    _annotation.finishMark();
  }

  Future<String?> _askForText() => showDialog<String>(
        context: context,
        builder: (context) => const _TextPromptDialog(),
      );

  Future<void> _finish() async {
    _annotation.finishMark();
    // Nothing drawn: no annotated copy, the original is uploaded as it is.
    if (_annotation.marks.isEmpty) {
      Navigator.of(context)
          .pop(AnnotationResult(payload: _annotation.toPayload()));
      return;
    }

    XFile? annotatedFile;
    String payload = _annotation.toPayload();
    try {
      final photo = await _photo;
      payload = _annotation.toPayload(imageSize: photo.size);
      final bytes = await AnnotationRenderer.render(
        image: photo.image,
        marks: _annotation.marks,
        displayWidth: _imageRect.width,
      );
      if (bytes != null) {
        annotatedFile = XFile.fromData(
          bytes,
          name: _annotatedFilename(widget.file.name),
          mimeType: 'image/png',
          length: bytes.length,
        );
      }
    } catch (error) {
      debugPrint('Annotated image rendering failed: $error');
    }

    if (mounted) {
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

/// Owns its controller so it is only disposed once the dialog is gone.
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog();

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add text'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Text'),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class AnnotationToolbar extends StatelessWidget {
  const AnnotationToolbar({super.key});

  static const colors = [
    Color(0xffe53935),
    Color(0xfffdd835),
    Color(0xff1e88e5),
    Color(0xff43a047),
    Colors.white,
    Colors.black,
  ];

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
            for (final color in colors)
              _ColorSwatch(
                color: color,
                selected: annotation.color.toARGB32() == color.toARGB32(),
                onTap: () => annotation.setColor(color),
              ),
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

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Color ${color.toARGB32().toRadixString(16)}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          key: ValueKey('color-${color.toARGB32().toRadixString(16)}'),
          width: 30,
          height: 30,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.black26,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
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

/// Paints [marks] (stored as fractions of the photo) onto a canvas the size of
/// the photo. [scale] adapts sizes that are defined in screen pixels (strokes,
/// text, the default shapes) when painting at another resolution.
class AnnotationPainter extends CustomPainter {
  AnnotationPainter(this.marks, {this.scale = 1});

  final List<AnnotationMark> marks;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    for (final mark in marks) {
      final paint = Paint()
        ..color = mark.color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = mark.strokeWidth * scale;
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
            canvas.drawCircle(center, mark.strokeWidth * 1.4 * scale,
                paint..style = PaintingStyle.fill);
          }
        case AnnotationTool.arrow:
          final arrowEnd =
              end == center ? center.translate(56 * scale, -36 * scale) : end;
          _drawArrow(canvas, center, arrowEnd, paint);
        case AnnotationTool.circle:
          final rect = Rect.fromPoints(center,
              end == center ? center.translate(56 * scale, 56 * scale) : end);
          canvas.drawOval(rect, paint);
        case AnnotationTool.rectangle:
          canvas.drawRect(
              Rect.fromPoints(
                  center,
                  end == center
                      ? center.translate(72 * scale, 48 * scale)
                      : end),
              paint);
        case AnnotationTool.text:
          final painter = TextPainter(
              text: TextSpan(
                  text: mark.note,
                  style: TextStyle(color: mark.color, fontSize: 18 * scale)),
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
    final headLength = 18.0 * scale + paint.strokeWidth;
    final headWidth = 8.0 * scale + paint.strokeWidth;
    final base = end - unit * headLength;
    canvas.drawLine(end, base + normal * headWidth, paint);
    canvas.drawLine(end, base - normal * headWidth, paint);
  }

  @override
  bool shouldRepaint(covariant AnnotationPainter oldDelegate) => true;
}
