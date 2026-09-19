import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:web/web.dart' as web;

import 'web_file.dart';

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
      final title = widget.tooltip ?? 'Add photo';
      final input = web.document.createElement('input') as web.HTMLInputElement
        ..type = 'file'
        ..accept = 'image/*'
        ..multiple = false
        ..title = title;
      input.style.display = 'none';

      // A <label> around the input: the browser opens the chooser from the
      // user's own click on it, which every browser allows.
      final button = web.document.createElement('label') as web.HTMLLabelElement
        ..title = title
        ..textContent = '\u{1F4F7}';
      const styles = {
        'position': 'relative',
        'width': '40px',
        'height': '40px',
        'border-radius': '999px',
        'background': '#d7e9cb',
        'cursor': 'pointer',
        'display': 'flex',
        'align-items': 'center',
        'justify-content': 'center',
      };
      styles.forEach((name, value) => button.style.setProperty(name, value));
      button.append(input);

      input.addEventListener(
        'change',
        (web.Event _) {
          final file = input.files?.item(0);
          if (file == null) return;
          xFileFromWebFile(file).then((photo) async {
            if (mounted) await widget.onPhotoPicked(photo);
          }).whenComplete(() => input.value = '');
        }.toJS,
      );

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
