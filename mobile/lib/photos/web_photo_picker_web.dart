import 'dart:async';
import 'dart:js_interop';

import 'package:image_picker/image_picker.dart';
import 'package:web/web.dart' as web;

import 'web_file.dart';

/// Opens the browser's file chooser for one image. Completes with null when
/// the chooser is dismissed.
Future<XFile?> pickWebPhoto() {
  final completer = Completer<XFile?>();
  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..accept = 'image/*'
    ..multiple = false;

  void complete(XFile? file) {
    input.remove();
    if (!completer.isCompleted) completer.complete(file);
  }

  input.addEventListener(
    'change',
    (web.Event _) {
      final file = input.files?.item(0);
      if (file == null) {
        complete(null);
        return;
      }
      xFileFromWebFile(file).then(complete, onError: (Object error) {
        input.remove();
        if (!completer.isCompleted) completer.completeError(error);
      });
    }.toJS,
  );
  input.addEventListener('cancel', ((web.Event _) => complete(null)).toJS);

  web.document.body?.append(input);
  input.click();

  return completer.future;
}
