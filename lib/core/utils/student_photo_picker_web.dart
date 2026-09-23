import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'student_photo_picker_model.dart';

Uint8List? studentPhotoBytesFromReaderResult(Object? raw) {
  if (raw is Uint8List) return raw;
  if (raw is ByteBuffer) return raw.asUint8List();
  if (raw is List<int>) return Uint8List.fromList(raw);
  return null;
}

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
      try {
        reader.readAsArrayBuffer(file);
        await Future.any([
          reader.onLoad.first,
          reader.onError.first.then((_) =>
              throw StateError('Lecture du fichier impossible.')),
        ]);
        final bytes = studentPhotoBytesFromReaderResult(reader.result);
        if (bytes == null || bytes.isEmpty) {
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
          contentBase64: base64Encode(bytes),
        ));
      } catch (_) {
        result.add(PickedStudentPhoto.rejected(
          name: file.name,
          mimeType: mimeType,
          sizeBytes: file.size,
          reason: 'Lecture du fichier impossible.',
        ));
      }
    }
    selected.complete(result);
  });
  input.click();
  return selected.future;
}
