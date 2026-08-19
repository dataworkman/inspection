import 'dart:convert';

import 'package:flutter/material.dart';

enum AnnotationTool { pen, arrow, circle, rectangle, text }

class AnnotationMark {
  AnnotationMark({
    required this.x,
    required this.y,
    required this.note,
    required this.tool,
    required this.color,
    required this.strokeWidth,
  });

  final double x;
  final double y;
  final String note;
  final AnnotationTool tool;
  final Color color;
  final double strokeWidth;

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'note': note,
        'tool': tool.name,
        'color': color.value,
        'stroke_width': strokeWidth,
      };
}

class AnnotationState extends ChangeNotifier {
  final List<AnnotationMark> marks = [];
  final List<AnnotationMark> _redo = [];
  AnnotationTool tool = AnnotationTool.pen;
  Color color = Colors.redAccent;
  double strokeWidth = 3;

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

  void undo() {
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
    notifyListeners();
  }

  String toPayload() => jsonEncode({'marks': marks.map((mark) => mark.toJson()).toList()});
}
