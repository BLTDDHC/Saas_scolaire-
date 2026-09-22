import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'student_photo_picker_model.dart';

String _mimeTypeFor(html.File file) {
  if (file.type.trim().isNotEmpty) return file.type.trim();
  final lower = file.name.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.bmp')) return 'image/bmp';
  if (lower.endsWith('.heic')) return 'image/heic';
  if (lower.endsWith('.heif')) return 'image/heif';
  return 'application/octet-stream';
}

Future<List<PickedStudentPhoto>> pickStudentPhotos({bool multiple = true}) async {
  final input = html.FileUploadInputElement()
    ..accept = 'image/*'
    ..multiple = multiple;
  final selected = Completer<List<PickedStudentPhoto>>();
  input.onChange.first.then((_) async {
    final result = <PickedStudentPhoto>[];
    for (final file in input.files ?? const <html.File>[]) {
      final mimeType = _mimeTypeFor(file);
      if (file.size > PickedStudentPhoto.maxBytes) {
        result.add(PickedStudentPhoto.rejected(
          name: file.name,
          mimeType: mimeType,
          sizeBytes: file.size,
          reason: 'Photo refusée : taille supérieure à 5 Mo.',
        ));
        continue;
      }
      if (!mimeType.toLowerCase().startsWith('image/')) {
        result.add(PickedStudentPhoto.rejected(
          name: file.name,
          mimeType: mimeType,
          sizeBytes: file.size,
          reason: 'Fichier refusé : ce n’est pas une image exploitable.',
        ));
        continue;
      }
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;
      final raw = reader.result;
      if (raw is! ByteBuffer) {
        result.add(PickedStudentPhoto.rejected(
          name: file.name,
          mimeType: mimeType,
          sizeBytes: file.size,
          reason: 'Lecture du fichier impossible.',
        ));
        continue;
      }
      result.add(PickedStudentPhoto(
        name: file.name,
        mimeType: mimeType,
        sizeBytes: file.size,
        contentBase64: base64Encode(Uint8List.view(raw)),
      ));
    }
    selected.complete(result);
  });
  input.click();
  return selected.future;
}
