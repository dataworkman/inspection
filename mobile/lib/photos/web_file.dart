import 'dart:js_interop';

import 'package:image_picker/image_picker.dart';
import 'package:web/web.dart' as web;

/// Reads a file chosen in the browser into an [XFile].
Future<XFile> xFileFromWebFile(web.File file) async {
  final buffer = await file.arrayBuffer().toDart;
  return XFile.fromData(
    buffer.toDart.asUint8List(),
    name: file.name,
    mimeType: file.type.isEmpty ? null : file.type,
    length: file.size,
  );
}
