import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class PhotoInputButton extends StatelessWidget {
  const PhotoInputButton({
    super.key,
    required this.onPhotoPicked,
    this.tooltip,
  });

  final Future<void> Function(XFile file) onPhotoPicked;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: null,
      icon: const Icon(Icons.add_a_photo),
      tooltip: tooltip,
    );
  }
}
