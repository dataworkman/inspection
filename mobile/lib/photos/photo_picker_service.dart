import 'package:image_picker/image_picker.dart';

class PhotoPickerService {
  final ImagePicker _picker = ImagePicker();

  Future<XFile?> takePhoto() =>
      _picker.pickImage(source: ImageSource.camera, imageQuality: 82);

  Future<XFile?> choosePhoto() =>
      _picker.pickImage(source: ImageSource.gallery, imageQuality: 82);
}
