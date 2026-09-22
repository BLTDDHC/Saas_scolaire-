import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/services/store_service.dart';

class StudentPhotoAvatar extends StatefulWidget {
  const StudentPhotoAvatar({
    super.key,
    required this.studentId,
    required this.initials,
    this.radius = 28,
    this.refreshKey,
  });

  final String studentId;
  final String initials;
  final double radius;
  final Object? refreshKey;

  @override
  State<StudentPhotoAvatar> createState() => _StudentPhotoAvatarState();
}

class _StudentPhotoAvatarState extends State<StudentPhotoAvatar> {
  Future<Uint8List?>? _photo;
  int? _storeRevision;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = context.watch<StoreService>();
    final revision = store.studentPhotoRevision(widget.studentId);
    if (_photo == null || revision != _storeRevision) {
      _storeRevision = revision;
      _photo = store.studentPhotoRemote(widget.studentId);
    }
  }

  @override
  void didUpdateWidget(covariant StudentPhotoAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studentId != widget.studentId ||
        oldWidget.refreshKey != widget.refreshKey) {
      final store = context.read<StoreService>();
      _storeRevision = store.studentPhotoRevision(widget.studentId);
      _photo = store.studentPhotoRemote(widget.studentId);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
        future: _photo,
        builder: (context, snapshot) => CircleAvatar(
          radius: widget.radius,
          backgroundColor: AppColors.avatarColorFor(widget.initials),
          backgroundImage: snapshot.data == null ? null : MemoryImage(snapshot.data!),
          child: snapshot.data == null
              ? Text(widget.initials, overflow: TextOverflow.clip)
              : null,
        ),
      );
}
