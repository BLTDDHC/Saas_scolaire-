import 'package:flutter/material.dart';
import 'app_button.dart';
import 'app_modal.dart';

/// Dialog de confirmation (Suppression, Action irréversible)
class ConfirmDialog {
  ConfirmDialog._();

  static Future<bool> show({
    required BuildContext context,
    required String title,
    required String message,
    String confirmLabel = 'Confirmer',
    String cancelLabel = 'Annuler',
    bool isDanger = false,
  }) async {
    final result = await AppModal.show<bool>(
      context: context,
      title: title,
      maxWidth: 440,
      body: Text(
        message,
        style: const TextStyle(fontSize: 14, height: 1.5),
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: cancelLabel,
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          const SizedBox(width: 8),
          AppButton(
            label: confirmLabel,
            variant: isDanger ? AppButtonVariant.danger : AppButtonVariant.primary,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
