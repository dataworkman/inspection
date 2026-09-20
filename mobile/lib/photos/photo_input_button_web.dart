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
    this.label,
  });

  final Future<void> Function(XFile file) onPhotoPicked;
  final String? tooltip;

  /// Text next to the camera icon; icon only when null.
  final String? label;

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
      final label = widget.label;
      final button = web.document.createElement('label') as web.HTMLLabelElement
        ..title = title
        ..innerHTML =
            ('<svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor" '
                    'style="flex:none"><path d="M12 15.2a3.2 3.2 0 1 0 0-6.4 3.2 3.2 0 0 0 0 6.4z"/>'
                    '<path d="M9 2 7.17 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2h-3.17L15 2H9zm3 15c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5z"/></svg>'
                    '${label == null ? '' : '<span>$label</span>'}')
                .toJS;
      const styles = {
        'position': 'relative',
        'box-sizing': 'border-box',
        'width': '100%',
        'height': '100%',
        'border': '1px solid #D9E0DB',
        'border-radius': '10px',
        'background': '#FFFFFF',
        'color': '#17211C',
        'cursor': 'pointer',
        'display': 'flex',
        'align-items': 'center',
        'justify-content': 'center',
        'gap': '8px',
        'font': '600 14px Roboto, sans-serif',
        'user-select': 'none',
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
      width: widget.label == null ? 44 : 112,
      height: 44,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
