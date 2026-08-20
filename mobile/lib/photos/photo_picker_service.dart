import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'web_photo_picker.dart';

class PhotoPickerService {
  final ImagePicker _picker = ImagePicker();

  Future<XFile?> takePhoto() =>
      _picker.pickImage(source: ImageSource.camera, imageQuality: 82);

  Future<XFile?> choosePhoto() {
    if (kIsWeb) return pickWebPhoto();

    return _picker.pickImage(source: ImageSource.gallery, imageQuality: 82);
  }
}
