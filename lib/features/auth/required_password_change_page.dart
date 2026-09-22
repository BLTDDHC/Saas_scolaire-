import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/services/store_service.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_form_field.dart';

class RequiredPasswordChangePage extends StatefulWidget {
  const RequiredPasswordChangePage({super.key});

  @override
  State<RequiredPasswordChangePage> createState() =>
      _RequiredPasswordChangePageState();
}

class _RequiredPasswordChangePageState
    extends State<RequiredPasswordChangePage> {
  final _newPassword = TextEditingController();
  final _confirmation = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _newPassword.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _newPassword.text;
    if (password.length < 8 || password.length > 128) {
      setState(() =>
          _error = 'Le mot de passe doit contenir entre 8 et 128 caractères.');
      return;
    }
    if (!RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'\d').hasMatch(password) ||
        !RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      setState(() => _error =
          'Ajoutez une minuscule, une majuscule, un chiffre et un caractère spécial.');
      return;
    }
    if (password != _confirmation.text) {
      setState(() => _error = 'Les mots de passe ne correspondent pas.');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final store = context.read<StoreService>();
      final success = await store.changeRequiredPassword(password);
      if (!success && mounted)
        setState(() =>
            _error = store.passwordChangeError ?? 'Le changement a échoué.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
      _newPassword.clear();
      _confirmation.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.password_rounded,
                      size: 48, color: AppColors.primary600),
                  const SizedBox(height: AppSpacing.s4),
                  Text('Changement de mot de passe obligatoire',
                      textAlign: TextAlign.center,
                      style: AppTypography.heading2(
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.lightTextPrimary)),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                      'Pour sécuriser votre compte, choisissez un nouveau mot de passe avant de continuer.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall()),
                  const SizedBox(height: AppSpacing.s6),
                  AppFormField(
                      label: 'Nouveau mot de passe',
                      controller: _newPassword,
                      obscureText: true,
                      enablePasswordVisibility: true,
                      autofillHints: const [AutofillHints.newPassword],
                      enableSuggestions: false,
                      autocorrect: false,
                      prefixIcon: Icons.lock_outline_rounded),
                  const SizedBox(height: AppSpacing.s4),
                  AppFormField(
                      label: 'Confirmation du mot de passe',
                      controller: _confirmation,
                      obscureText: true,
                      enablePasswordVisibility: true,
                      autofillHints: const [AutofillHints.newPassword],
                      enableSuggestions: false,
                      autocorrect: false,
                      prefixIcon: Icons.lock_reset_rounded),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.s4),
                    Text(_error!,
                        key: const Key('password-change-error'),
                        style: const TextStyle(color: AppColors.danger500),
                        textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: AppSpacing.s6),
                  AppButton(
                      label: _isLoading
                          ? 'Modification...'
                          : 'Changer le mot de passe',
                      onPressed: _isLoading ? null : _submit,
                      fullWidth: true),
                  const SizedBox(height: AppSpacing.s3),
                  TextButton(
                      onPressed: _isLoading
                          ? null
                          : context.read<StoreService>().logout,
                      child: const Text('Se déconnecter')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
