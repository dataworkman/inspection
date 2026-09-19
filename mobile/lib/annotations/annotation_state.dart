import 'dart:convert';

import 'package:flutter/material.dart';

enum AnnotationTool { pen, arrow, circle, rectangle, text }

class AnnotationMark {
  AnnotationMark({
    required this.x,
    required this.y,
    this.endX,
    this.endY,
    this.points = const [],
    required this.note,
    required this.tool,
    required this.color,
    required this.strokeWidth,
  });

  final double x;
  final double y;
  final double? endX;
  final double? endY;
  final List<Offset> points;
  final String note;
  final AnnotationTool tool;
  final Color color;
  final double strokeWidth;

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        if (endX != null) 'end_x': endX,
        if (endY != null) 'end_y': endY,
        if (points.isNotEmpty)
          'points':
              points.map((point) => {'x': point.dx, 'y': point.dy}).toList(),
        'note': note,
        'tool': tool.name,
        'color': color.toARGB32(),
        'stroke_width': strokeWidth,
      };
}

class AnnotationState extends ChangeNotifier {
  final List<AnnotationMark> marks = [];
  final List<AnnotationMark> _redo = [];
  AnnotationTool tool = AnnotationTool.pen;
  Color color = Colors.redAccent;
  double strokeWidth = 3;
  AnnotationMark? draft;

  void setTool(AnnotationTool nextTool) {
    tool = nextTool;
    notifyListeners();
  }

  void setColor(Color nextColor) {
    color = nextColor;
    notifyListeners();
  }

  void setStrokeWidth(double nextStrokeWidth) {
    strokeWidth = nextStrokeWidth;
    notifyListeners();
  }

  void addMark(Offset position, Size imageSize, String note) {
    marks.add(AnnotationMark(
      x: position.dx / imageSize.width,
      y: position.dy / imageSize.height,
      note: note,
      tool: tool,
      color: color,
      strokeWidth: strokeWidth,
    ));
    _redo.clear();
    notifyListeners();
  }

  void startMark(Offset position, Size imageSize, String note) {
    final point = _normalized(position, imageSize);
    draft = AnnotationMark(
      x: point.dx,
      y: point.dy,
      endX: point.dx,
      endY: point.dy,
      points: tool == AnnotationTool.pen ? [point] : const [],
      note: note,
      tool: tool,
      color: color,
      strokeWidth: strokeWidth,
    );
    notifyListeners();
  }

  void updateMark(Offset position, Size imageSize) {
    final current = draft;
    if (current == null) return;

    final point = _normalized(position, imageSize);
    draft = AnnotationMark(
      x: current.x,
      y: current.y,
      endX: point.dx,
      endY: point.dy,
      points: current.tool == AnnotationTool.pen
          ? [...current.points, point]
          : current.points,
      note: current.note,
      tool: current.tool,
      color: current.color,
      strokeWidth: current.strokeWidth,
    );
    notifyListeners();
  }

  void finishMark() {
    final current = draft;
    if (current == null) return;

    marks.add(current);
    draft = null;
    _redo.clear();
    notifyListeners();
  }

  void undo() {
    if (draft != null) {
      draft = null;
      notifyListeners();
      return;
    }
    if (marks.isEmpty) return;
    _redo.add(marks.removeLast());
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    marks.add(_redo.removeLast());
    notifyListeners();
  }

  void clear() {
    _redo.addAll(marks);
    marks.clear();
    draft = null;
    notifyListeners();
  }

  String toPayload() =>
      jsonEncode({'marks': marks.map((mark) => mark.toJson()).toList()});

  Offset _normalized(Offset position, Size imageSize) {
    return Offset(
      (position.dx / imageSize.width).clamp(0, 1).toDouble(),
      (position.dy / imageSize.height).clamp(0, 1).toDouble(),
    );
  }
}
