import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/services/store_service.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_form_field.dart';
import '../../shared/widgets/app_toast.dart';

/// Page de Connexion — Adaptative (Desktop, Tablette, Mobile)
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final TextEditingController _identifierController;
  late final TextEditingController _passwordController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _identifierController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;

    if (identifier.isEmpty || password.isEmpty) {
      AppToast.warning(context, 'Veuillez remplir tous les champs.');
      return;
    }

    setState(() => _isLoading = true);

    final store = context.read<StoreService>();
    final success = await store.login(identifier, password);
    if (!mounted) return;

    setState(() => _isLoading = false);

    if (success) {
      if (store.sessionWarning != null) {
        AppToast.warning(context, store.sessionWarning!);
      } else {
        AppToast.success(context,
            'Connexion réussie ! Bienvenue ${store.currentUser?.name}');
      }
    } else {
      AppToast.error(
          context, store.loginError ?? 'La connexion n’a pas pu être établie.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showBrandPanel = constraints.maxWidth >= 900;
            final form = Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(
                  constraints.maxWidth < 460 ? AppSpacing.s4 : AppSpacing.s8,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!showBrandPanel) ...[
                          const _BrandMark(compact: true),
                          const SizedBox(height: AppSpacing.s8),
                        ],
                        Text(
                          'Connexion',
                          style: AppTypography.heading2(
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s2),
                        Text(
                          'Accédez à votre espace avec vos identifiants.',
                          style: AppTypography.bodySmall(
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        AppFormField(
                          label: 'Matricule, téléphone ou adresse e-mail',
                          controller: _identifierController,
                          prefixIcon: Icons.badge_outlined,
                          hint:
                              'Matricule, +242 06 000 00 00 ou e-mail',
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        AppFormField(
                          label: 'Mot de passe',
                          controller: _passwordController,
                          obscureText: true,
                          enablePasswordVisibility: true,
                          autofillHints: const [AutofillHints.password],
                          enableSuggestions: false,
                          autocorrect: false,
                          prefixIcon: Icons.lock_outline,
                          hint: '••••••••',
                        ),
                        const SizedBox(height: AppSpacing.s6),
                        AppButton(
                          label: 'Se connecter',
                          onPressed: _handleLogin,
                          fullWidth: true,
                          size: AppButtonSize.large,
                          isLoading: _isLoading,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            if (!showBrandPanel) return form;
            return Row(
              children: [
                const Expanded(flex: 4, child: _BrandPanel()),
                Expanded(flex: 6, child: form),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: AppColors.primary800,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 390),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BrandMark(),
                  SizedBox(height: AppSpacing.s8),
                  Text(
                    'Pilotez votre établissement avec clarté.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: AppSpacing.s4),
                  Text(
                    'Une plateforme commune pour l’administration, les enseignants et les élèves.',
                    style: TextStyle(
                      color: AppColors.primary200,
                      fontSize: 15,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: compact ? AppColors.primary600 : Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(
              'M+',
              style: TextStyle(
                color: compact ? Colors.white : AppColors.primary700,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s3),
          Text(
            'MAYELE +',
            style: TextStyle(
              color: compact
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
}
