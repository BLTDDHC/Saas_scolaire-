import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/establishment_model.dart';
import '../../data/models/education/school_cycle_model.dart';
import '../../data/models/plan_model.dart';
import '../../data/datasources/api_client.dart';
import '../../data/services/store_service.dart';
import '../../shared/widgets/app_badge.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_form_field.dart';
import '../../shared/widgets/app_modal.dart';
import '../../shared/widgets/app_page_header.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/responsive_grid.dart';
import '../../shared/widgets/confirm_dialog.dart';

/// Page de gestion des Établissements (Super Admin) — Reproduction exacte de establishments.js
class EstablishmentsPage extends StatefulWidget {
  const EstablishmentsPage({super.key});

  @override
  State<EstablishmentsPage> createState() => _EstablishmentsPageState();
}

class _EstablishmentsPageState extends State<EstablishmentsPage> {
  String _searchQuery = '';
  String? _statusFilter;
  List<EstablishmentModel>? _apiResults;
  bool _isLoading = true;
  bool _initialLoadRequested = false;
  String? _loadError;
  int _requestSequence = 0;
  bool _isLoadingCreationOptions = false;

  List<SchoolCycleModel> _cycleModels(
    List<Map<String, dynamic>> catalog,
    Set<String> selectedCodes,
  ) =>
      catalog
          .where((item) => selectedCodes.contains(item['code']))
          .map(SchoolCycleModel.fromJson)
          .toList();

  String _cycleSummary(EstablishmentModel establishment) {
    final active =
        establishment.cycles.where((cycle) => cycle.isActive).toList();
    if (active.isEmpty) return 'Non configurés';
    if (active.length == 1) return active.first.name;
    return active.map((cycle) => cycle.code.substring(0, 1)).join(' + ');
  }

  Widget _cycleSelector({
    required List<Map<String, dynamic>> catalog,
    required Set<String> selectedCodes,
    required ValueChanged<String> onToggle,
    required String keyPrefix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CYCLES DE L’ÉTABLISSEMENT *', style: AppTypography.heading4()),
        const SizedBox(height: AppSpacing.s2),
        const Text(
          'Sélectionnez un ou plusieurs cycles. Les directions seront configurées séparément.',
          style: TextStyle(fontSize: 12, color: AppColors.lightTextTertiary),
        ),
        const SizedBox(height: AppSpacing.s2),
        ...catalog.map((item) {
          final code = item['code']?.toString() ?? '';
          final name = item['name']?.toString() ?? code;
          return CheckboxListTile(
            key: Key('$keyPrefix-$code'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(name),
            subtitle: Text(code),
            value: selectedCodes.contains(code),
            onChanged: (_) => onToggle(code),
          );
        }),
      ],
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialLoadRequested) return;
    _initialLoadRequested = true;
    _refreshFilters();
  }

  Future<void> _refreshFilters() async {
    final request = ++_requestSequence;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final results =
          await context.read<StoreService>().searchSuperAdminEstablishments(
                search: _searchQuery,
                status: _statusFilter,
              );
      if (mounted && request == _requestSequence) {
        setState(() {
          _apiResults = results;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted && request == _requestSequence) {
        setState(() {
          _apiResults = null;
          _isLoading = false;
          _loadError = 'Impossible de charger les établissements.';
        });
      }
    }
  }

  Future<void> _openEditModal(
      BuildContext context, EstablishmentModel establishment) async {
    List<Map<String, dynamic>> cycleCatalog;
    try {
      cycleCatalog = await context.read<StoreService>().getSchoolCycleCatalog();
    } on Exception {
      if (context.mounted) {
        AppToast.error(context,
            'Impossible de charger le catalogue des cycles. Réessayez.');
      }
      return;
    }
    if (!context.mounted) return;
    if (cycleCatalog.isEmpty) {
      AppToast.warning(context, 'Le catalogue des cycles est vide.');
      return;
    }
    final selectedCycleCodes = establishment.cycles
        .where((cycle) => cycle.isActive)
        .map((cycle) => cycle.code)
        .toSet();
    final nameController = TextEditingController(text: establishment.name);
    final codeController =
        TextEditingController(text: establishment.code ?? '');
    final cityController = TextEditingController(text: establishment.city);
    final addressController =
        TextEditingController(text: establishment.address ?? '');
    final phoneController =
        TextEditingController(text: establishment.phone ?? '');
    final emailController =
        TextEditingController(text: establishment.email ?? '');

    AppModal.show(
      context: context,
      title: 'Modifier l\'établissement',
      maxWidth: 560,
      body: StatefulBuilder(
        builder: (context, setModalState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppFormField(label: 'Nom *', controller: nameController),
            const SizedBox(height: AppSpacing.s4),
            AppFormField(
              key: const Key('edit-establishment-code'),
              label: 'Code établissement *',
              controller: codeController,
              hint: 'KHE',
            ),
            const SizedBox(height: AppSpacing.s4),
            AppFormField(label: 'Ville', controller: cityController),
            const SizedBox(height: AppSpacing.s4),
            AppFormField(label: 'Adresse', controller: addressController),
            const SizedBox(height: AppSpacing.s4),
            AppFormField(label: 'Téléphone', controller: phoneController),
            const SizedBox(height: AppSpacing.s4),
            AppFormField(label: 'Email', controller: emailController),
            const SizedBox(height: AppSpacing.s5),
            _cycleSelector(
              catalog: cycleCatalog,
              selectedCodes: selectedCycleCodes,
              keyPrefix: 'edit-cycle',
              onToggle: (code) => setModalState(() {
                if (!selectedCycleCodes.add(code)) {
                  selectedCycleCodes.remove(code);
                }
              }),
            ),
          ],
        ),
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
              label: 'Annuler',
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.pop(context)),
          const SizedBox(width: AppSpacing.s3),
          AppButton(
            label: 'Enregistrer',
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                AppToast.warning(context, 'Le nom est obligatoire.');
                return;
              }
              final code = codeController.text
                  .trim()
                  .toUpperCase()
                  .replaceAll(RegExp(r'[^A-Z0-9]'), '');
              if (!RegExp(r'^[A-Z][A-Z0-9]{1,5}$').hasMatch(code)) {
                AppToast.warning(context,
                    'Le code doit contenir 2 à 6 lettres/chiffres et commencer par une lettre.');
                return;
              }
              if (selectedCycleCodes.isEmpty) {
                AppToast.warning(
                    context, 'Sélectionnez au moins un cycle scolaire.');
                return;
              }
              final updated = establishment.copyWith(
                name: nameController.text.trim(),
                code: code,
                city: cityController.text.trim(),
                address: addressController.text.trim(),
                phone: phoneController.text.trim(),
                email: emailController.text.trim(),
                cycles: _cycleModels(cycleCatalog, selectedCycleCodes),
              );
              bool ok;
              try {
                ok = await context
                    .read<StoreService>()
                    .updateManagedEstablishment(
                      updated,
                      cycleCodes: selectedCycleCodes.toList(),
                      rethrowErrors: true,
                    );
              } on ApiException catch (error) {
                if (context.mounted) AppToast.error(context, error.message);
                return;
              } on Exception {
                if (context.mounted) {
                  AppToast.error(
                      context, 'La modification transactionnelle a échoué.');
                }
                return;
              }
              if (!context.mounted) return;
              if (!ok) {
                AppToast.error(
                    context, 'La modification n\'a pas pu être enregistrée.');
                return;
              }
              Navigator.pop(context);
              await _refreshFilters();
              if (mounted) {
                AppToast.success(
                    this.context, 'Établissement modifié dans PostgreSQL.');
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openAddModal(BuildContext context) async {
    if (_isLoadingCreationOptions) return;
    setState(() => _isLoadingCreationOptions = true);
    final store = context.read<StoreService>();
    List<PlanModel> activePlans;
    List<Map<String, dynamic>> cycleCatalog;
    try {
      activePlans = (await store.getSuperAdminPlans())
          .where((plan) => plan.isActive)
          .toList();
      cycleCatalog = await store.getSchoolCycleCatalog();
    } on Exception {
      if (context.mounted) {
        AppToast.error(context,
            'Impossible de charger les plans ou les cycles. Réessayez.');
      }
      return;
    } finally {
      if (mounted) setState(() => _isLoadingCreationOptions = false);
    }
    if (!context.mounted) return;
    if (activePlans.isEmpty) {
      AppToast.warning(context,
          'Aucun plan actif n’est disponible pour une nouvelle souscription.');
      return;
    }
    if (cycleCatalog.isEmpty) {
      AppToast.warning(context, 'Le catalogue des cycles est vide.');
      return;
    }
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final cityController = TextEditingController(text: 'Brazzaville');
    final countryController = TextEditingController(text: 'Congo');
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final adminNameController = TextEditingController();
    final adminEmailController = TextEditingController();
    final adminPhoneController = TextEditingController();
    final academicYearController = TextEditingController(
      text: AppDateUtils.currentAcademicYearName(),
    );
    PlanModel selectedPlan = activePlans.first;
    final selectedCycleCodes = <String>{};
    bool useBaseConfiguration = true;

    AppModal.show(
      context: context,
      title: 'Créer un nouvel établissement',
      maxWidth: 600,
      body: StatefulBuilder(
        builder: (context, setModalState) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AppFormField(
                label: 'Nom de l\'établissement *',
                controller: nameController,
                hint: 'ex: Lycée Excellence',
              ),
              const SizedBox(height: AppSpacing.s4),
              AppFormField(
                key: const Key('create-establishment-code'),
                label: 'Code établissement *',
                controller: codeController,
                hint: 'KHE',
              ),
              const SizedBox(height: AppSpacing.s4),
              AppSelectField<PlanModel>(
                label: 'Plan d\'abonnement *',
                value: selectedPlan,
                items: activePlans
                    .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(
                            '${p.name} (${p.price} ${p.currency} / ${p.durationDays} jours)')))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setModalState(() => selectedPlan = val);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                '${selectedPlan.features.length} fonctionnalité(s) incluse(s) dans ce plan',
                key: const Key('selected-plan-feature-count'),
                style: const TextStyle(
                    fontSize: 12, color: AppColors.lightTextTertiary),
              ),
              const SizedBox(height: AppSpacing.s5),
              _cycleSelector(
                catalog: cycleCatalog,
                selectedCodes: selectedCycleCodes,
                keyPrefix: 'create-cycle',
                onToggle: (code) => setModalState(() {
                  if (!selectedCycleCodes.add(code)) {
                    selectedCycleCodes.remove(code);
                  }
                }),
              ),
              const SizedBox(height: AppSpacing.s5),
              const Text(
                'CONFIGURATION INITIALE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary600,
                ),
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                'Voulez-vous commencer avec la configuration de base ?',
                style: AppTypography.heading4(),
              ),
              RadioGroup<bool>(
                groupValue: useBaseConfiguration,
                onChanged: (value) => setModalState(
                  () => useBaseConfiguration = value ?? true,
                ),
                child: Column(
                  children: const [
                    RadioListTile<bool>(
                      key: Key('base-configuration-yes'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text('Oui, créer la configuration de base'),
                      value: true,
                    ),
                    RadioListTile<bool>(
                      key: Key('base-configuration-no'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text('Non, configurer manuellement'),
                      value: false,
                    ),
                  ],
                ),
              ),
              if (useBaseConfiguration) ...[
                const SizedBox(height: AppSpacing.s2),
                AppFormField(
                  key: const Key('initial-academic-year'),
                  label: 'Année scolaire initiale *',
                  controller: academicYearController,
                  hint: '2026-2027',
                ),
                const SizedBox(height: AppSpacing.s2),
                const Text(
                  'L’année, les trois trimestres, les niveaux, séries du lycée, matières et barèmes de référence seront créés. Tout restera modifiable.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.lightTextTertiary,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.s4),
              const Text(
                'Un mot de passe initial sécurisé sera généré et affiché une seule fois après la création.',
                style:
                    TextStyle(fontSize: 12, color: AppColors.lightTextTertiary),
              ),
              const SizedBox(height: AppSpacing.s4),
              ResponsiveFormGrid(
                children: [
                  AppFormField(label: 'Ville', controller: cityController),
                  AppFormField(label: 'Pays', controller: countryController),
                ],
              ),
              const SizedBox(height: AppSpacing.s4),
              ResponsiveFormGrid(
                children: [
                  AppFormField(
                    label: 'Email établissement',
                    controller: emailController,
                    hint: 'contact@ecole.com',
                  ),
                  AppFormField(
                    label: 'Téléphone',
                    controller: phoneController,
                    hint: '+242 06...',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s6),
              const Text(
                'RESPONSABLE ADMINISTRATEUR',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary600),
              ),
              const SizedBox(height: AppSpacing.s3),
              AppFormField(
                label: 'Nom complet du responsable *',
                controller: adminNameController,
                hint: 'ex: Marie Koffi',
              ),
              const SizedBox(height: AppSpacing.s4),
              ResponsiveFormGrid(
                children: [
                  AppFormField(
                    label: 'Email responsable *',
                    controller: adminEmailController,
                    hint: 'admin@ecole.com',
                  ),
                  AppFormField(
                    label: 'Téléphone responsable',
                    controller: adminPhoneController,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s4),
            ],
          );
        },
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: 'Annuler',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: AppSpacing.s3),
          AppButton(
            label: 'Créer l\'établissement',
            variant: AppButtonVariant.primary,
            onPressed: () async {
              final name = nameController.text.trim();
              final code = codeController.text
                  .trim()
                  .toUpperCase()
                  .replaceAll(RegExp(r'[^A-Z0-9]'), '');
              final adminName = adminNameController.text.trim();
              final adminEmail = adminEmailController.text.trim();

              if (name.isEmpty || adminName.isEmpty || adminEmail.isEmpty) {
                AppToast.warning(
                    context, 'Veuillez remplir les champs obligatoires (*).');
                return;
              }
              if (!RegExp(r'^[A-Z][A-Z0-9]{1,5}$').hasMatch(code)) {
                AppToast.warning(context,
                    'Le code doit contenir 2 à 6 lettres/chiffres et commencer par une lettre.');
                return;
              }
              if (selectedCycleCodes.isEmpty) {
                AppToast.warning(
                    context, 'Sélectionnez au moins un cycle scolaire.');
                return;
              }
              final initialAcademicYear = academicYearController.text.trim();
              if (useBaseConfiguration) {
                final match = RegExp(r'^(\d{4})-(\d{4})$')
                    .firstMatch(initialAcademicYear);
                if (match == null ||
                    int.parse(match.group(2)!) !=
                        int.parse(match.group(1)!) + 1) {
                  AppToast.warning(context,
                      'Saisissez une année scolaire valide, par exemple 2026-2027.');
                  return;
                }
              }

              final store = context.read<StoreService>();

              final estab = EstablishmentModel(
                id: '',
                name: name,
                code: code,
                type: 'Établissement scolaire',
                institutionType: InstitutionType.school,
                cycles: _cycleModels(cycleCatalog, selectedCycleCodes),
                city: cityController.text.trim(),
                country: countryController.text.trim(),
                email: emailController.text.trim(),
                phone: phoneController.text.trim(),
                admin: adminName,
                administrator: EstablishmentAdmin(
                  name: adminName,
                  email: adminEmail,
                  phone: adminPhoneController.text.trim(),
                ),
                plan: selectedPlan.name,
                status: 'active',
              );

              String initialPassword;
              try {
                initialPassword = await store.createManagedEstablishment(
                  establishment: estab,
                  adminName: adminName,
                  adminEmail: adminEmail,
                  adminPhone: adminPhoneController.text.trim(),
                  useBaseConfiguration: useBaseConfiguration,
                  initialAcademicYear:
                      useBaseConfiguration ? initialAcademicYear : null,
                );
              } on ApiException catch (error) {
                if (context.mounted) AppToast.error(context, error.message);
                return;
              } on Exception {
                if (context.mounted) {
                  AppToast.error(context,
                      'La création transactionnelle a échoué. Aucune donnée partielle n’a été conservée.');
                }
                return;
              }
              if (!context.mounted) return;
              Navigator.pop(context);
              await _refreshFilters();
              if (!mounted) return;
              AppModal.show(
                context: this.context,
                title: 'Compte administrateur créé',
                body: SelectableText(
                  '${useBaseConfiguration ? 'Établissement créé avec sa configuration de base.\nVous pourrez modifier cette configuration à tout moment.\n\n' : 'Établissement créé. La configuration initiale reste à effectuer manuellement.\n\n'}'
                  'Créez ensuite une direction et rattachez-lui ce compte avant sa première connexion.\n\n'
                  'Mot de passe initial (à communiquer une seule fois) :\n$initialPassword',
                ),
                footer: AppButton(
                    label: 'Fermer',
                    onPressed: () => Navigator.pop(this.context)),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _resetAdminPassword(
      BuildContext modalContext, String userId, String email) async {
    final confirmed = await ConfirmDialog.show(
      context: modalContext,
      title: 'Réinitialiser le mot de passe',
      message:
          'Un nouveau mot de passe temporaire sera généré pour $email. Il ne sera affiché qu’une seule fois et l’ancien mot de passe cessera de fonctionner.',
      confirmLabel: 'Réinitialiser',
      isDanger: true,
    );
    if (!confirmed || !modalContext.mounted || !mounted) return;
    try {
      final temporaryPassword =
          await modalContext.read<StoreService>().resetAdminPassword(userId);
      if (!modalContext.mounted || !mounted) return;
      Navigator.pop(modalContext);
      AppModal.show(
        context: context,
        title: 'Mot de passe temporaire généré',
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Copiez ce mot de passe maintenant. Il ne sera plus affiché après la fermeture, expire après 24 heures et ne permet qu’une connexion avant son remplacement.'),
            const SizedBox(height: AppSpacing.s4),
            SelectableText(temporaryPassword,
                style: const TextStyle(
                    fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          ],
        ),
        footer: Wrap(
          spacing: AppSpacing.s3,
          children: [
            AppButton(
              label: 'Copier',
              icon: Icons.copy_rounded,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: temporaryPassword));
                if (mounted) {
                  AppToast.success(context, 'Mot de passe copié.');
                }
              },
            ),
            AppButton(
                label: 'Fermer',
                variant: AppButtonVariant.secondary,
                onPressed: () => Navigator.pop(context)),
          ],
        ),
      );
    } on ApiException catch (error) {
      if (mounted) AppToast.error(context, error.message);
    } on Exception {
      if (mounted) {
        AppToast.error(context, 'La réinitialisation a échoué.');
      }
    }
  }

  void _openAdminModal(BuildContext context, EstablishmentModel estab) {
    final store = context.read<StoreService>();
    final adminData = estab.administrator ??
        EstablishmentAdmin(
            name: estab.admin,
            email: estab.email ?? '',
            phone: estab.phone ?? '');
    final adminUserId = adminData.id;

    final nameController = TextEditingController(text: adminData.name);
    final emailController = TextEditingController(text: adminData.email);
    final phoneController = TextEditingController(text: adminData.phone ?? '');

    AppModal.show(
      context: context,
      title: 'Administrateur — ${estab.name}',
      maxWidth: 560,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppFormField(
              label: 'Nom complet de l\'administrateur',
              controller: nameController),
          const SizedBox(height: AppSpacing.s4),
          AppFormField(
              label: 'Email de l\'administrateur',
              controller: emailController,
              keyboardType: TextInputType.emailAddress),
          const SizedBox(height: AppSpacing.s4),
          AppFormField(
              label: 'Téléphone de l\'administrateur',
              controller: phoneController,
              keyboardType: TextInputType.phone),
          const SizedBox(height: AppSpacing.s6),
          Text('Statut du compte', style: AppTypography.heading4()),
          const SizedBox(height: AppSpacing.s2),
          AppBadge(
              label: adminData.status == 'active'
                  ? 'Compte actif'
                  : 'Compte suspendu',
              variant: adminData.status == 'active'
                  ? AppBadgeVariant.success
                  : AppBadgeVariant.danger),
          const SizedBox(height: AppSpacing.s3),
          Text(
            adminData.mustChangePassword
                ? 'Changement de mot de passe obligatoire'
                : 'Mot de passe configuré',
          ),
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
              label: 'Annuler',
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.pop(context)),
          const SizedBox(width: AppSpacing.s3),
          if (adminUserId != null)
            AppButton(
              label: 'Réinitialiser le mot de passe',
              variant: AppButtonVariant.danger,
              onPressed: () =>
                  _resetAdminPassword(context, adminUserId, adminData.email),
            )
          else
            AppButton(
                label: 'Créer le compte',
                variant: AppButtonVariant.primary,
                onPressed: () async {
                  final name = nameController.text.trim();
                  final email = emailController.text.trim();
                  if (name.isEmpty || email.isEmpty) {
                    AppToast.warning(context,
                        'Veuillez renseigner le nom et l\'email de l\'administrateur.');
                    return;
                  }

                  final initialPassword = await store.createAccount(
                    name: name,
                    email: email,
                    role: UserRole.admin,
                    schoolId: estab.id,
                  );
                  if (initialPassword == null) {
                    if (context.mounted) {
                      AppToast.error(context,
                          'Le compte administrateur n’a pas pu être créé.');
                    }
                    return;
                  }
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  AppModal.show(
                    context: context,
                    title: 'Compte administrateur créé',
                    body: SelectableText(
                        'Mot de passe initial (à communiquer une seule fois) :\n$initialPassword'),
                    footer: AppButton(
                        label: 'Fermer',
                        onPressed: () => Navigator.pop(context)),
                  );
                }),
        ],
      ),
    );
  }

  String _subscriptionStatusLabel(String status) {
    switch (status) {
      case 'active':
        return 'Actif';
      case 'upcoming':
        return 'À venir';
      case 'overdue':
        return 'En retard';
      case 'expired':
        return 'Expiré';
      default:
        return 'Non renseigné';
    }
  }

  Future<void> _openDetailModal(
      BuildContext context, EstablishmentModel summary) async {
    setState(() => _isLoading = true);
    try {
      final establishment = await context
          .read<StoreService>()
          .getSuperAdminEstablishment(summary.id);
      if (!mounted || !context.mounted) return;
      setState(() => _isLoading = false);
      final admin = establishment.administrator;
      final subscription = establishment.subscription;
      AppModal.show(
        context: context,
        title: 'Détail — ${establishment.name}',
        maxWidth: 680,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('IDENTITÉ', style: AppTypography.heading4()),
            const SizedBox(height: AppSpacing.s2),
            Text(establishment.city),
            Text(establishment.country ?? 'Pays non renseigné'),
            if (establishment.address?.isNotEmpty ?? false)
              Text(establishment.address!),
            if (establishment.email?.isNotEmpty ?? false)
              Text(establishment.email!),
            if (establishment.phone?.isNotEmpty ?? false)
              Text(establishment.phone!),
            const SizedBox(height: AppSpacing.s5),
            Text('CYCLES', style: AppTypography.heading4()),
            const SizedBox(height: AppSpacing.s2),
            if (establishment.cycles.isEmpty)
              const Text('Aucun cycle scolaire configuré')
            else
              Wrap(
                spacing: AppSpacing.s2,
                runSpacing: AppSpacing.s2,
                children: establishment.cycles
                    .map((cycle) => AppBadge(
                          label: cycle.name,
                          variant: AppBadgeVariant.info,
                        ))
                    .toList(),
              ),
            const SizedBox(height: AppSpacing.s5),
            Text('ACCÈS', style: AppTypography.heading4()),
            const SizedBox(height: AppSpacing.s2),
            AppBadge(
              label: establishment.status == 'active' ? 'Actif' : 'Suspendu',
              variant: establishment.status == 'active'
                  ? AppBadgeVariant.success
                  : AppBadgeVariant.danger,
            ),
            const SizedBox(height: AppSpacing.s5),
            Text('ADMIN ASSOCIÉ', style: AppTypography.heading4()),
            const SizedBox(height: AppSpacing.s2),
            if (admin == null)
              const Text('Aucun ADMIN associé')
            else ...[
              Text(admin.name),
              Text(admin.email),
              if (admin.phone?.isNotEmpty ?? false) Text(admin.phone!),
              Text(admin.status == 'active'
                  ? 'Compte actif'
                  : 'Compte suspendu'),
              Text(admin.mustChangePassword
                  ? 'Changement de mot de passe obligatoire'
                  : 'Mot de passe configuré'),
            ],
            const SizedBox(height: AppSpacing.s5),
            Text('ABONNEMENT', style: AppTypography.heading4()),
            const SizedBox(height: AppSpacing.s2),
            if (subscription == null)
              const Text('Aucun abonnement associé')
            else ...[
              Text('Plan : ${subscription.plan}'),
              Text('Statut : ${_subscriptionStatusLabel(subscription.status)}'),
              Text(
                  'Début : ${AppDateUtils.formatNumeric(subscription.startDate, fallback: 'Non renseigné')}'),
              Text(
                  'Expiration : ${AppDateUtils.formatNumeric(subscription.endDate, fallback: 'Non renseignée')}'),
              Text('Montant : ${subscription.price}'),
            ],
            const SizedBox(height: AppSpacing.s5),
            Text('MODULES DISPONIBLES', style: AppTypography.heading4()),
            const SizedBox(height: AppSpacing.s2),
            Text('Plan actuel : ${establishment.plan.toUpperCase()}'),
            Text(
                'Fonctionnalités incluses : ${establishment.planFeatureLabels.isEmpty ? "Aucune" : establishment.planFeatureLabels.join(", ")}'),
            const SizedBox(height: AppSpacing.s2),
            const Text(
                'Fonctionnalités actuellement disponibles pour cet établissement'),
            Text(establishment.enabledModules.isEmpty
                ? 'Aucun module activé'
                : establishment.enabledModuleLabels.join(', ')),
            const SizedBox(height: AppSpacing.s5),
            Text(
                'Créé le : ${AppDateUtils.formatNumeric(establishment.createdAt ?? establishment.date, fallback: 'Non renseigné')}'),
          ],
        ),
        footer: AppButton(
          label: 'Fermer',
          onPressed: () => Navigator.pop(context),
        ),
      );
    } on Exception {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppToast.error(context, 'Le détail de l’établissement est indisponible.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final store = context.read<StoreService>();
    final allEstabs = _apiResults ?? const <EstablishmentModel>[];

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppPageHeader(
              title: 'Établissements partenaires',
              subtitle: _isLoading
                  ? 'Chargement des établissements...'
                  : _loadError != null
                      ? 'Données indisponibles'
                      : '${allEstabs.length} établissement(s) trouvé(s)',
              actions: [
                AppButton(
                  key: const Key('create-establishment'),
                  label: _isLoadingCreationOptions
                      ? 'Chargement...'
                      : 'Nouvel établissement',
                  variant: AppButtonVariant.primary,
                  icon: Icons.add_rounded,
                  onPressed: _isLoadingCreationOptions
                      ? null
                      : () => _openAddModal(context),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s6),

            // Barre de recherche
            Wrap(
              spacing: AppSpacing.s3,
              runSpacing: AppSpacing.s3,
              children: [
                SizedBox(
                  width: 320,
                  child: AppFormField(
                    label: '',
                    hint: 'Rechercher un établissement...',
                    prefixIcon: Icons.search_rounded,
                    onChanged: (val) {
                      _searchQuery = val;
                      _refreshFilters();
                    },
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: AppSelectField<String?>(
                    label: 'Statut',
                    value: _statusFilter,
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Tous')),
                      DropdownMenuItem(value: 'active', child: Text('Actifs')),
                      DropdownMenuItem(
                          value: 'suspended', child: Text('Suspendus')),
                    ],
                    onChanged: (value) {
                      _statusFilter = value;
                      _refreshFilters();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s4),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.s8),
                  child: CircularProgressIndicator(
                    key: Key('establishments-loading'),
                  ),
                ),
              )
            else if (_loadError != null)
              AppCard(
                key: const Key('establishments-error'),
                child: Column(
                  children: [
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.s3),
                    AppButton(
                      label: 'Réessayer',
                      icon: Icons.refresh_rounded,
                      onPressed: _refreshFilters,
                    ),
                  ],
                ),
              )
            else if (allEstabs.isEmpty)
              const AppCard(
                key: Key('establishments-empty'),
                child: Text('Aucun établissement trouvé'),
              )
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      isDark ? AppColors.darkBgTableStripe : AppColors.gray100,
                    ),
                    columns: const [
                      DataColumn(label: Text('ID')),
                      DataColumn(label: Text('Établissement')),
                      DataColumn(label: Text('Cycles')),
                      DataColumn(label: Text('Responsable')),
                      DataColumn(label: Text('Ville')),
                      DataColumn(label: Text('Abonnement')),
                      DataColumn(label: Text('Plan')),
                      DataColumn(label: Text('Statut')),
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: allEstabs.map((e) {
                      final planUpper =
                          (e.subscription?.plan ?? e.plan).toUpperCase();
                      AppBadgeVariant planVariant;
                      switch (e.plan.toLowerCase()) {
                        case 'free':
                          planVariant = AppBadgeVariant.secondary;
                          break;
                        case 'basic':
                          planVariant = AppBadgeVariant.info;
                          break;
                        case 'pro':
                          planVariant = AppBadgeVariant.primary;
                          break;
                        case 'enterprise':
                          planVariant = AppBadgeVariant.warning;
                          break;
                        default:
                          planVariant = AppBadgeVariant.primary;
                      }

                      return DataRow(
                        cells: [
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.darkBgBody
                                    : AppColors.gray100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                e.id,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: AppColors.primary600,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(e.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                                if (e.email != null && e.email!.isNotEmpty)
                                  Text(e.email!,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? AppColors.darkTextTertiary
                                              : AppColors.lightTextTertiary)),
                              ],
                            ),
                          ),
                          DataCell(AppBadge(
                            label: _cycleSummary(e),
                            variant: AppBadgeVariant.secondary,
                          )),
                          DataCell(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(e.admin,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 12)),
                                if (e.administrator?.email != null)
                                  Text(e.administrator!.email,
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: isDark
                                              ? AppColors.darkTextTertiary
                                              : AppColors.lightTextTertiary)),
                              ],
                            ),
                          ),
                          DataCell(Text(e.city,
                              style: const TextStyle(fontSize: 13))),
                          DataCell(AppBadge(
                            label: _subscriptionStatusLabel(
                                e.subscription?.status ?? ''),
                            variant: e.subscription?.status == 'active'
                                ? AppBadgeVariant.success
                                : e.subscription?.status == 'upcoming'
                                    ? AppBadgeVariant.info
                                    : e.subscription?.status == 'overdue'
                                        ? AppBadgeVariant.warning
                                        : AppBadgeVariant.danger,
                          )),
                          DataCell(
                              AppBadge(label: planUpper, variant: planVariant)),
                          DataCell(
                            AppBadge(
                              label:
                                  e.status == 'active' ? 'Actif' : 'Suspendu',
                              variant: e.status == 'active'
                                  ? AppBadgeVariant.success
                                  : AppBadgeVariant.danger,
                            ),
                          ),
                          DataCell(Text(AppDateUtils.formatNumeric(e.date),
                              style: const TextStyle(fontSize: 12))),
                          DataCell(
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.visibility_outlined,
                                      size: 18),
                                  tooltip: 'Consulter',
                                  onPressed: () => _openDetailModal(context, e),
                                ),
                                IconButton(
                                  icon:
                                      const Icon(Icons.edit_outlined, size: 18),
                                  tooltip: 'Modifier',
                                  onPressed: () => _openEditModal(context, e),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.person_outline_rounded,
                                      size: 18),
                                  tooltip: 'Gérer l\'admin',
                                  onPressed: () {
                                    _openAdminModal(context, e);
                                  },
                                ),
                                IconButton(
                                  icon: Icon(
                                    e.status == 'active'
                                        ? Icons.pause_circle_outline
                                        : Icons.play_circle_outline,
                                    size: 18,
                                    color: e.status == 'active'
                                        ? AppColors.warning500
                                        : AppColors.success500,
                                  ),
                                  tooltip: e.status == 'active'
                                      ? 'Suspendre'
                                      : 'Réactiver',
                                  onPressed: () async {
                                    final confirm = await ConfirmDialog.show(
                                      context: context,
                                      title: e.status == 'active'
                                          ? 'Suspendre l\'établissement'
                                          : 'Réactiver l\'établissement',
                                      message:
                                          'Voulez-vous vraiment ${e.status == 'active' ? 'suspendre' : 'réactiver'} "${e.name}" ?',
                                      confirmLabel: e.status == 'active'
                                          ? 'Suspendre'
                                          : 'Réactiver',
                                      isDanger: e.status == 'active',
                                    );
                                    if (confirm && context.mounted) {
                                      final updated = await store
                                          .updateManagedEstablishment(
                                              e.copyWith(
                                        status: e.status == 'active'
                                            ? 'suspended'
                                            : 'active',
                                      ));
                                      if (!context.mounted) return;
                                      if (updated) {
                                        await _refreshFilters();
                                        if (!context.mounted) return;
                                        AppToast.success(context,
                                            'Statut mis à jour dans PostgreSQL.');
                                      } else {
                                        AppToast.error(context,
                                            'Le statut n’a pas pu être mis à jour.');
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
