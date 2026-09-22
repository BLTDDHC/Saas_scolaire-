import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

enum ToastType { success, error, warning, info }

/// Système de Toast / Notifications volantes EduPro.
///
/// Les messages sont affichés dans l'overlay racine plutôt que dans le
/// ScaffoldMessenger local. Ils restent donc visibles au-dessus des modales,
/// dialogues et autres couches UI.
class AppToast {
  AppToast._();

  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void show(
    BuildContext context, {
    required String message,
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 4),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(type == ToastType.error
            ? humanErrorMessage(message)
            : message.trim()),
        behavior: SnackBarBehavior.floating,
        duration: duration,
      ));
      return;
    }

    _dismissTimer?.cancel();
    _currentEntry?.remove();
    _currentEntry = null;

    Color bgColor;
    Color accentColor;
    IconData icon;

    switch (type) {
      case ToastType.success:
        bgColor = AppColors.success50;
        accentColor = AppColors.success600;
        icon = Icons.check_circle_rounded;
        break;
      case ToastType.error:
        bgColor = AppColors.danger50;
        accentColor = AppColors.danger600;
        icon = Icons.error_rounded;
        break;
      case ToastType.warning:
        bgColor = AppColors.warning50;
        accentColor = AppColors.warning700;
        icon = Icons.warning_rounded;
        break;
      case ToastType.info:
        bgColor = AppColors.info50;
        accentColor = AppColors.info600;
        icon = Icons.info_rounded;
        break;
    }

    final visibleMessage =
        type == ToastType.error ? humanErrorMessage(message) : message.trim();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) {
        final media = MediaQuery.maybeOf(overlayContext);
        final width = media?.size.width ?? 420;
        final topInset = media?.padding.top ?? 0;
        final toastWidth = width < 460 ? width - 32 : 420.0;
        return Positioned(
          top: topInset + 16,
          right: width < 460 ? 16 : 24,
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: toastWidth),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bgColor,
                  border: Border.all(color: accentColor.withValues(alpha: .35)),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 24,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s4,
                    vertical: AppSpacing.s3,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(icon, color: accentColor, size: 21),
                      ),
                      const SizedBox(width: AppSpacing.s3),
                      Expanded(
                        child: Text(
                          visibleMessage,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall(
                            color: AppColors.lightTextPrimary,
                          ).copyWith(fontWeight: AppTypography.wMedium),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s2),
                      InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () {
                          _dismissTimer?.cancel();
                          entry.remove();
                          if (identical(_currentEntry, entry)) {
                            _currentEntry = null;
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(Icons.close_rounded,
                              color: accentColor, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    _currentEntry = entry;
    void cancelWhenOverlayDisappears() {
      if (!entry.mounted && identical(_currentEntry, entry)) {
        _dismissTimer?.cancel();
        _dismissTimer = null;
        _currentEntry = null;
        entry.removeListener(cancelWhenOverlayDisappears);
      }
    }
    entry.addListener(cancelWhenOverlayDisappears);
    overlay.insert(entry);
    _dismissTimer = Timer(duration, () {
      if (identical(_currentEntry, entry)) {
        _currentEntry = null;
      }
      if (entry.mounted) entry.remove();
    });
  }

  static void success(BuildContext context, String message) =>
      show(context, message: message, type: ToastType.success);

  static void error(BuildContext context, String message) => show(
        context,
        message: message,
        type: ToastType.error,
        duration: const Duration(seconds: 6),
      );

  static void warning(BuildContext context, String message) =>
      show(context, message: message, type: ToastType.warning);

  static void info(BuildContext context, String message) =>
      show(context, message: message, type: ToastType.info);

  static String humanErrorMessage(
    String message, {
    String fallback = 'Une erreur est survenue. Veuillez réessayer.',
  }) {
    final value = message.trim();
    final technical = RegExp(
      r'https?://|/api/|postgres|sqlalchemy|traceback|exception|http\s*5\d\d|\b[0-9a-f]{8}-[0-9a-f-]{27,}\b',
      caseSensitive: false,
    );
    if (value.isEmpty || technical.hasMatch(value)) {
      return fallback;
    }
    return value;
  }
}
