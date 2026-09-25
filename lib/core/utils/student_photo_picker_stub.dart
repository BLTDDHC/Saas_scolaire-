import 'dart:convert';

import 'package:image_picker/image_picker.dart';

import 'student_photo_picker_model.dart';

String _mimeTypeForName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.bmp')) return 'image/bmp';
  if (lower.endsWith('.heic')) return 'image/heic';
  if (lower.endsWith('.heif')) return 'image/heif';
  return 'application/octet-stream';
}

Future<PickedStudentPhoto> _toPickedPhoto(XFile file) async {
  final bytes = await file.readAsBytes();
  final mimeType = file.mimeType?.trim().isNotEmpty == true
      ? file.mimeType!.trim()
      : _mimeTypeForName(file.name);

  if (bytes.length > PickedStudentPhoto.maxBytes) {
    return PickedStudentPhoto.rejected(
      name: file.name,
      mimeType: mimeType,
      sizeBytes: bytes.length,
      reason: 'Photo refusée : taille supérieure à 5 Mo.',
    );
  }
  if (!mimeType.toLowerCase().startsWith('image/')) {
    return PickedStudentPhoto.rejected(
      name: file.name,
      mimeType: mimeType,
      sizeBytes: bytes.length,
      reason: 'Fichier refusé : ce n’est pas une image exploitable.',
    );
  }
  return PickedStudentPhoto(
    name: file.name,
    mimeType: mimeType,
    sizeBytes: bytes.length,
    contentBase64: base64Encode(bytes),
  );
}

Future<List<PickedStudentPhoto>> pickStudentPhotos({bool multiple = true}) async {
  final picker = ImagePicker();
  try {
    final files = multiple
        ? await picker.pickMultiImage(imageQuality: 92)
        : <XFile>[
            if (await picker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 92,
                )
                case final XFile file)
              file,
          ];
    final result = <PickedStudentPhoto>[];
    for (final file in files) {
      result.add(await _toPickedPhoto(file));
    }
    return result;
  } catch (_) {
    return const [];
  }
}
