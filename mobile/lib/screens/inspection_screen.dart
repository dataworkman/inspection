import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../annotations/annotation_state.dart';
import '../inspections/inspection_state.dart';
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
    if (inspection == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final responses = inspection['responses'] as List<dynamic>;
    return Scaffold(
      appBar: AppBar(title: Text((inspection['store'] as Map<String, dynamic>)['name'] as String)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Score: ${inspection['score'] ?? 0}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          for (final raw in responses) ResponseTile(response: raw as Map<String, dynamic>, onPhoto: _addPhoto),
          const SizedBox(height: 12),
          TextField(
            controller: _comment,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Inspection comment', border: OutlineInputBorder()),
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

  Future<void> _addPhoto(BuildContext context, Map<String, dynamic> response) async {
    final file = await _photoPicker.takePhoto() ?? await _photoPicker.choosePhoto();
    if (file == null || !context.mounted) return;

    final annotation = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => AnnotationScreen(file: file)),
    );
    if (!context.mounted) return;

    await context.read<InspectionState>().uploadPhoto(
          file: file,
          responseId: response['id'] as int,
          annotationJson: annotation ?? '{}',
          comment: 'Field photo',
        );
  }
}

class ResponseTile extends StatefulWidget {
  const ResponseTile({super.key, required this.response, required this.onPhoto});

  final Map<String, dynamic> response;
  final Future<void> Function(BuildContext context, Map<String, dynamic> response) onPhoto;

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
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.response['category'] as String, style: Theme.of(context).textTheme.labelMedium),
            Text(widget.response['title'] as String, style: Theme.of(context).textTheme.titleMedium),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('N/A'),
              value: _notApplicable,
              onChanged: (value) {
                setState(() => _notApplicable = value ?? false);
                _save(context);
              },
            ),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _score,
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: _score.round().toString(),
                    onChanged: _notApplicable ? null : (value) => setState(() => _score = value),
                    onChangeEnd: (_) => _save(context),
                  ),
                ),
                Text(_score.round().toString()),
                Switch(value: _passed, onChanged: (value) => setState(() => _passed = value)),
              ],
            ),
            TextField(
              controller: _comment,
              decoration: const InputDecoration(labelText: 'Comment'),
              onSubmitted: (_) => _save(context),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                children: [
                  IconButton.filledTonal(
                    onPressed: () => widget.onPhoto(context, widget.response),
                    icon: const Icon(Icons.add_a_photo),
                    tooltip: 'Add photo',
                  ),
                  IconButton.filledTonal(
                    onPressed: () => context.read<InspectionState>().createAction(
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

class AnnotationScreen extends StatelessWidget {
  const AnnotationScreen({super.key, required this.file});

  final File file;

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
                onPressed: () => Navigator.of(context).pop(annotation.toPayload()),
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
                  final imageSize = Size(constraints.maxWidth, constraints.maxHeight);
                  return GestureDetector(
                    onTapUp: (details) => context.read<AnnotationState>().addMark(details.localPosition, imageSize, 'Issue'),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(file, fit: BoxFit.contain),
                        Consumer<AnnotationState>(
                          builder: (context, annotation, child) => CustomPaint(painter: AnnotationPainter(annotation.marks)),
                        ),
                      ],
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
}

class AnnotationToolbar extends StatelessWidget {
  const AnnotationToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final annotation = context.watch<AnnotationState>();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          IconButton(onPressed: () => annotation.setTool(AnnotationTool.pen), icon: const Icon(Icons.draw), tooltip: 'Pen'),
          IconButton(onPressed: () => annotation.setTool(AnnotationTool.arrow), icon: const Icon(Icons.arrow_outward), tooltip: 'Arrow'),
          IconButton(onPressed: () => annotation.setTool(AnnotationTool.circle), icon: const Icon(Icons.circle_outlined), tooltip: 'Circle'),
          IconButton(onPressed: () => annotation.setTool(AnnotationTool.rectangle), icon: const Icon(Icons.crop_square), tooltip: 'Rectangle'),
          IconButton(onPressed: () => annotation.setTool(AnnotationTool.text), icon: const Icon(Icons.text_fields), tooltip: 'Text'),
          IconButton(onPressed: annotation.undo, icon: const Icon(Icons.undo), tooltip: 'Undo'),
          IconButton(onPressed: annotation.redo, icon: const Icon(Icons.redo), tooltip: 'Redo'),
          IconButton(onPressed: annotation.clear, icon: const Icon(Icons.clear), tooltip: 'Clear'),
          Slider(value: annotation.strokeWidth, min: 1, max: 8, onChanged: annotation.setStrokeWidth),
        ],
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
        ..strokeWidth = mark.strokeWidth;
      final center = Offset(mark.x * size.width, mark.y * size.height);
      switch (mark.tool) {
        case AnnotationTool.pen:
          canvas.drawCircle(center, 4, paint..style = PaintingStyle.fill);
        case AnnotationTool.arrow:
          canvas.drawLine(center.translate(-26, 20), center.translate(26, -20), paint);
          canvas.drawLine(center.translate(26, -20), center.translate(6, -18), paint);
          canvas.drawLine(center.translate(26, -20), center.translate(18, 0), paint);
        case AnnotationTool.circle:
          canvas.drawCircle(center, 24, paint);
        case AnnotationTool.rectangle:
          canvas.drawRect(Rect.fromCenter(center: center, width: 56, height: 36), paint);
        case AnnotationTool.text:
          final painter = TextPainter(text: TextSpan(text: mark.note, style: TextStyle(color: mark.color, fontSize: 18)), textDirection: TextDirection.ltr);
          painter.layout();
          painter.paint(canvas, center);
      }
    }
  }

  @override
  bool shouldRepaint(covariant AnnotationPainter oldDelegate) => oldDelegate.marks != marks;
}
