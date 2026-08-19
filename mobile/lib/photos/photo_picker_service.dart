import 'dart:io';

import 'package:image_picker/image_picker.dart';

class PhotoPickerService {
  final ImagePicker _picker = ImagePicker();

  Future<File?> takePhoto() async {
    final image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 82);
    return image == null ? null : File(image.path);
  }

  Future<File?> choosePhoto() async {
    final image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 82);
    return image == null ? null : File(image.path);
  }
}
