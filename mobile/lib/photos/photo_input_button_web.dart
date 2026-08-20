import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
// ignore: undefined_prefixed_name
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class PhotoInputButton extends StatefulWidget {
  const PhotoInputButton({
    super.key,
    required this.onPhotoPicked,
    this.tooltip,
  });

  final Future<void> Function(XFile file) onPhotoPicked;
  final String? tooltip;

  @override
  State<PhotoInputButton> createState() => _PhotoInputButtonState();
}

class _PhotoInputButtonState extends State<PhotoInputButton> {
  late final String _viewType =
      'photo-input-button-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      final input = html.FileUploadInputElement()
        ..accept = 'image/*'
        ..multiple = false
        ..title = widget.tooltip ?? 'Add photo';
      input.style
        ..position = 'absolute'
        ..top = '0'
        ..right = '0'
        ..bottom = '0'
        ..left = '0'
        ..width = '100%'
        ..height = '100%'
        ..opacity = '0'
        ..cursor = 'pointer';

      final button = html.DivElement()
        ..title = widget.tooltip ?? 'Add photo'
        ..append(input);
      button.style
        ..position = 'relative'
        ..width = '40px'
        ..height = '40px'
        ..borderRadius = '999px'
        ..background = '#d7e9cb'
        ..cursor = 'pointer'
        ..display = 'flex'
        ..alignItems = 'center'
        ..justifyContent = 'center';
      button.setInnerHtml(
        '&#128247;',
        treeSanitizer: html.NodeTreeSanitizer.trusted,
      );
      button.append(input);

      input.onChange.listen((_) async {
        final file = await _readSelectedFile(input);
        if (file != null && mounted) {
          await widget.onPhotoPicked(file);
        }
        input.value = '';
      });

      return button;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}

Future<XFile?> _readSelectedFile(html.FileUploadInputElement input) {
  final files = input.files;
  if (files == null || files.isEmpty) return Future.value();

  final file = files.first;
  final reader = html.FileReader();
  final completer = Completer<XFile?>();

  reader.onError.first.then((_) {
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
      completer.complete(null);
      return;
    }

    completer.complete(XFile.fromData(
      bytes,
      name: file.name,
      mimeType: file.type.isEmpty ? null : file.type,
      length: file.size,
    ));
  });
  reader.readAsArrayBuffer(file);

  return completer.future;
}
