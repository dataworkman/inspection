import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

Future<XFile?> pickWebPhoto() {
  final completer = Completer<XFile?>();
  final input = html.FileUploadInputElement()
    ..accept = 'image/*'
    ..multiple = false;

  void complete(XFile? file) {
    input.remove();
    if (!completer.isCompleted) completer.complete(file);
  }

  input.onChange.first.then((_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      complete(null);
      return;
    }
    final file = files.first;

    final reader = html.FileReader();
    reader.onError.first.then((_) {
      input.remove();
      if (!completer.isCompleted) {
        completer.completeError(reader.error ?? 'Photo read failed');
      }
    });
    reader.onLoadEnd.first.then((_) {
      final result = reader.result;
      final bytes = switch (result) {
        ByteBuffer buffer => buffer.asUint8List(),
        Uint8List bytes => bytes,
        _ => null,
      };
      if (bytes == null) {
        complete(null);
        return;
      }

      complete(XFile.fromData(
        bytes,
        name: file.name,
        mimeType: file.type.isEmpty ? null : file.type,
        length: file.size,
      ));
    });
    reader.readAsArrayBuffer(file);
  });

  html.document.body?.append(input);
  input.click();

  return completer.future;
}
