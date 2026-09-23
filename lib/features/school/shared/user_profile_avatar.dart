import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/services/store_service.dart';

class UserProfileAvatar extends StatefulWidget {
  const UserProfileAvatar({
    super.key,
    required this.initials,
    this.radius = 28,
  });

  final String initials;
  final double radius;

  @override
  State<UserProfileAvatar> createState() => _UserProfileAvatarState();
}

class _UserProfileAvatarState extends State<UserProfileAvatar> {
  Future<Uint8List?>? _photo;
  int? _revision;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = context.watch<StoreService>();
    if (_photo == null || _revision != store.ownProfilePhotoRevision) {
      _revision = store.ownProfilePhotoRevision;
      _photo = store.ownProfilePhotoRemote();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
        future: _photo,
        builder: (context, snapshot) => CircleAvatar(
          radius: widget.radius,
          backgroundColor: AppColors.avatarColorFor(widget.initials),
          backgroundImage:
              snapshot.data == null ? null : MemoryImage(snapshot.data!),
          child: snapshot.data == null
              ? Text(
                  widget.initials,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(color: Colors.white),
                )
              : null,
        ),
      );
}
