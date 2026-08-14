import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;

import 'image_capture_staging.dart';

class FlutterGalleryImageSource implements GalleryImageSource {
  FlutterGalleryImageSource({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<GalleryPickedImage?> pickImage() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
    if (image == null) return null;
    return GalleryPickedImage(
      reference: image.path,
      name: _resolvedName(image),
    );
  }
}

class FlutterCameraImageSource implements CameraImageSource {
  FlutterCameraImageSource({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<CameraCapturedImage?> captureImage() async {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      requestFullMetadata: false,
    );
    if (image == null) return null;
    return CameraCapturedImage(
      reference: image.path,
      name: _resolvedName(image),
    );
  }
}

String _resolvedName(XFile image) {
  final name = image.name.trim();
  if (name.isNotEmpty) return name;
  return path.basename(image.path);
}
