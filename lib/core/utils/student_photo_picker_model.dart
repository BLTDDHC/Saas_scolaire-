import 'dart:typed_data';

Uint8List? studentPhotoBytesFromReaderResult(Object? raw) {
  if (raw is Uint8List) return raw;
  if (raw is ByteBuffer) return raw.asUint8List();
  if (raw is List<int>) return Uint8List.fromList(raw);
  return null;
}

class PickedStudentPhoto {
  const PickedStudentPhoto({
    required this.name,
    required this.mimeType,
    required this.contentBase64,
    required this.sizeBytes,
    this.rejectionReason,
  });

  factory PickedStudentPhoto.rejected({
    required String name,
    required String mimeType,
    required int sizeBytes,
    required String reason,
  }) =>
      PickedStudentPhoto(
        name: name,
        mimeType: mimeType,
        contentBase64: '',
        sizeBytes: sizeBytes,
        rejectionReason: reason,
      );

  static const int maxBytes = 5 * 1024 * 1024;

  final String name;
  final String mimeType;
  final String contentBase64;
  final int sizeBytes;
  final String? rejectionReason;

  bool get isRejected => rejectionReason != null;
  bool get isValid => !isRejected && contentBase64.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'name': name,
        'mimeType': mimeType,
        'contentBase64': contentBase64,
      };
}
