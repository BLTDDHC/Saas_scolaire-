import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/services/store_service.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_form_field.dart';
import '../../shared/widgets/app_modal.dart';
import '../../shared/widgets/app_toast.dart';

Future<void> showChangePasswordDialog(BuildContext context) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => const _ChangePasswordDialog(),
  );
  if (changed == true && context.mounted) {
    AppToast.success(context, 'Votre mot de passe a été modifié.');
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirmation = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_current.text.isEmpty) {
      setState(() => _error = 'Saisissez votre mot de passe actuel.');
      return;
    }
    if (_next.text.length < 8 || _next.text.length > 128) {
      setState(() =>
          _error = 'Le mot de passe doit contenir entre 8 et 128 caractères.');
      return;
    }
    if (!RegExp(r'[a-z]').hasMatch(_next.text) ||
        !RegExp(r'[A-Z]').hasMatch(_next.text) ||
        !RegExp(r'\d').hasMatch(_next.text) ||
        !RegExp(r'[^A-Za-z0-9]').hasMatch(_next.text)) {
      setState(() => _error =
          'Ajoutez une minuscule, une majuscule, un chiffre et un caractère spécial.');
      return;
    }
    if (_next.text != _confirmation.text) {
      setState(() => _error = 'Les mots de passe ne correspondent pas.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final store = context.read<StoreService>();
    final success = await store.changePassword(
        _current.text, _next.text, _confirmation.text);
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
      return;
    }
    _current.clear();
    setState(() {
      _loading = false;
      _error = store.passwordChangeError ?? 'Le changement a échoué.';
    });
  }

  @override
  Widget build(BuildContext context) => AppModal(
        title: 'Modifier mon mot de passe',
        maxWidth: 460,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppFormField(
              key: const Key('current-password'),
              label: 'Mot de passe actuel',
              controller: _current,
              obscureText: true,
              enablePasswordVisibility: true,
              enableSuggestions: false,
              autocorrect: false,
            ),
            const SizedBox(height: 16),
            AppFormField(
              key: const Key('new-password'),
              label: 'Nouveau mot de passe',
              controller: _next,
              obscureText: true,
              enablePasswordVisibility: true,
              enableSuggestions: false,
              autocorrect: false,
            ),
            const SizedBox(height: 16),
            AppFormField(
              key: const Key('new-password-confirmation'),
              label: 'Confirmation du mot de passe',
              controller: _confirmation,
              obscureText: true,
              enablePasswordVisibility: true,
              enableSuggestions: false,
              autocorrect: false,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('change-password-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
        footer: Wrap(alignment: WrapAlignment.end, spacing: 12, children: [
          AppButton(
            label: 'Annuler',
            variant: AppButtonVariant.secondary,
            onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          ),
          AppButton(
            key: const Key('submit-password-change'),
            label: _loading ? 'Modification…' : 'Modifier',
            onPressed: _loading ? null : _submit,
          ),
        ]),
      );
}
