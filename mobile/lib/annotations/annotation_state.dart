import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';

class AnnotationMark {
  AnnotationMark({required this.x, required this.y, required this.note});

  final double x;
  final double y;
  final String note;

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'note': note};
}

class AnnotationState extends ChangeNotifier {
  final List<AnnotationMark> marks = [];

  void addMark(Offset position, Size imageSize, String note) {
    marks.add(AnnotationMark(x: position.dx / imageSize.width, y: position.dy / imageSize.height, note: note));
    notifyListeners();
  }

  String toPayload() => jsonEncode({'marks': marks.map((mark) => mark.toJson()).toList()});
}
