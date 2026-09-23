@TestOn('browser')

import 'dart:typed_data';

import 'package:edupro_flutter_web/core/utils/student_photo_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('photo web reader accepts ByteBuffer and Uint8List results', () {
    final source = Uint8List.fromList([1, 2, 3, 4]);

    final fromBuffer = studentPhotoBytesFromReaderResult(source.buffer);
    final fromBytes = studentPhotoBytesFromReaderResult(source);

    expect(fromBuffer, isNotNull);
    expect(fromBuffer, orderedEquals(source));
    expect(fromBytes, orderedEquals(source));
    expect(studentPhotoBytesFromReaderResult('invalid'), isNull);
  });
}
