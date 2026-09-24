import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/datasources/api_client.dart';
import '../../../data/models/establishment_model.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_form_field.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/workspace_header.dart';
import 'calendar_settings_card.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();
  final _countryController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  EstablishmentModel? _school;
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isSaving = false;
  String? _loadError;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _loadEstablishment();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _countryController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _fillForm(EstablishmentModel school) {
    _addressController.text = school.address ?? '';
    _countryController.text = school.country ?? '';
    _phoneController.text = school.phone ?? '';
    _emailController.text = school.email ?? '';
  }

  Future<void> _loadEstablishment() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final school =
          await context.read<StoreService>().loadCurrentEstablishment();
      if (!mounted) return;
      _fillForm(school);
      setState(() {
        _school = school;
        _isLoading = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _loadError =
            'Impossible de charger les informations de l’établissement.';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveEstablishment() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    try {
      final updated =
          await context.read<StoreService>().updateCurrentEstablishment({
        'address': _addressController.text.trim(),
        'country': _countryController.text.trim(),
        'phone': _phoneController.text.trim(),
        'email': _emailController.text.trim(),
      });
      if (!mounted) return;
      _fillForm(updated);
      setState(() {
        _school = updated;
        _isEditing = false;
      });
      AppToast.success(
          context, 'Informations de l’établissement enregistrées.');
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _saveError = AppToast.humanErrorMessage(
              error.message,
              fallback: 'L’enregistrement a échoué. Veuillez réessayer.',
            ));
      }
    } on Exception {
      if (mounted)
        setState(
            () => _saveError = 'Serveur indisponible. Veuillez réessayer.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return null;
    if (email.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email))
      return 'Adresse e-mail invalide.';
    return null;
  }

  String? _validatePhone(String? value) {
    final phone = value?.trim() ?? '';
    if (phone.isEmpty) return null;
    if (!RegExp(r'^\+?[0-9][0-9 .()\-]{5,30}$').hasMatch(phone))
      return 'Numéro invalide (format local ou +242 accepté).';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    final user = store.currentUser;
    return WorkspacePage(
      title: 'Paramètres',
      subtitle: 'Votre profil, l’établissement, l’affichage et les réglages du compte',
      children: [
        AppCard(
          title: 'Mon Profil Utilisateur',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
                backgroundColor: AppColors.avatarColorFor(user?.name ?? 'User'),
                child: Text(user?.initials ?? 'U',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold))),
            title: Text(user?.name ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${user?.email ?? ''} • ${user?.roleName ?? ''}'),
          ),
        ),
        const SizedBox(height: AppSpacing.s6),
        _buildEstablishmentCard(),
        const SizedBox(height: AppSpacing.s6),
        if (store.getCurrentSchool()?.enabledModules.contains('schedule') ==
            true) ...[
          const CalendarSettingsCard(),
          const SizedBox(height: AppSpacing.s6),
        ],
        AppCard(
          title: 'Thème & Apparence',
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(store.isDarkMode ? 'Thème sombre actif' : 'Thème clair actif'),
            Switch(
                value: store.isDarkMode,
                onChanged: (_) => store.toggleTheme(),
                activeThumbColor: AppColors.primary600),
          ]),
        ),
      ],
    );
  }

  Widget _buildEstablishmentCard() {
    if (_isLoading) {
      return const AppCard(
          child: Center(
              child: Padding(
                  padding: EdgeInsets.all(AppSpacing.s6),
                  child: CircularProgressIndicator(
                      key: Key('establishment-loading')))));
    }
    if (_loadError != null || _school == null) {
      return AppCard(
          child: Column(children: [
        Text(_loadError ?? 'Établissement introuvable.'),
        const SizedBox(height: AppSpacing.s3),
        AppButton(label: 'Réessayer', onPressed: _loadEstablishment),
      ]));
    }
    final school = _school!;
    return AppCard(
      title: 'Informations de l’établissement',
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppFormField(label: 'Nom', initialValue: school.name, enabled: false),
          const SizedBox(height: AppSpacing.s3),
          AppFormField(
              label: 'Type', initialValue: school.type, enabled: false),
          const SizedBox(height: AppSpacing.s3),
          AppFormField(
              label: 'Ville', initialValue: school.city, enabled: false),
          const SizedBox(height: AppSpacing.s3),
          AppFormField(
              label: 'Adresse',
              controller: _addressController,
              enabled: _isEditing && !_isSaving,
              validator: (value) => (value?.trim().length ?? 0) > 500
                  ? '500 caractères maximum.'
                  : null),
          const SizedBox(height: AppSpacing.s3),
          AppFormField(
              label: 'Pays',
              controller: _countryController,
              enabled: _isEditing && !_isSaving,
              validator: (value) => (value?.trim().length ?? 0) > 120
                  ? '120 caractères maximum.'
                  : null),
          const SizedBox(height: AppSpacing.s3),
          AppFormField(
              label: 'Téléphone',
              controller: _phoneController,
              enabled: _isEditing && !_isSaving,
              keyboardType: TextInputType.phone,
              validator: _validatePhone),
          const SizedBox(height: AppSpacing.s3),
          AppFormField(
              label: 'Email de l’établissement',
              controller: _emailController,
              enabled: _isEditing && !_isSaving,
              keyboardType: TextInputType.emailAddress,
              validator: _validateEmail),
          if (_saveError != null) ...[
            const SizedBox(height: AppSpacing.s3),
            Text(_saveError!,
                style: const TextStyle(color: AppColors.danger500)),
          ],
          const SizedBox(height: AppSpacing.s4),
          if (_isEditing)
            Wrap(spacing: AppSpacing.s3, runSpacing: AppSpacing.s2, children: [
              AppButton(
                  label: 'Enregistrer',
                  isLoading: _isSaving,
                  onPressed: _isSaving ? null : _saveEstablishment),
              AppButton(
                  label: 'Annuler',
                  variant: AppButtonVariant.secondary,
                  onPressed: _isSaving
                      ? null
                      : () {
                          _fillForm(school);
                          setState(() {
                            _isEditing = false;
                            _saveError = null;
                          });
                        }),
            ])
          else
            AppButton(
                label: 'Modifier les coordonnées',
                onPressed: () => setState(() => _isEditing = true)),
        ]),
      ),
    );
  }
}
