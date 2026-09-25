import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/datasources/api_client.dart';
import '../../data/models/plan_model.dart';
import '../../data/services/store_service.dart';
import '../../shared/widgets/app_badge.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_page_header.dart';
import '../../shared/widgets/app_toast.dart';

class PlansPage extends StatefulWidget {
  const PlansPage({
    super.key,
    this.loader,
    this.detailLoader,
    this.creator,
    this.updater,
    this.catalogLoader,
  });

  final Future<List<PlanModel>> Function()? loader;
  final Future<PlanModel> Function(String id)? detailLoader;
  final Future<PlanModel> Function(PlanModel plan)? creator;
  final Future<PlanModel> Function(PlanModel plan)? updater;
  final Future<List<Map<String, dynamic>>> Function()? catalogLoader;

  @override
  State<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends State<PlansPage> {
  List<PlanModel>? _plans;
  bool _loading = true;
  bool _loadStarted = false;
  String? _error;
  List<Map<String, dynamic>> _moduleCatalog = const [];

  String _moduleLabel(String id) {
    for (final module in _moduleCatalog) {
      if (module['id'] == id) return module['label']?.toString() ?? id;
    }
    return id;
  }

  String _capabilityLabel(String id) {
    for (final module in _moduleCatalog) {
      for (final raw in module['capabilities'] as List? ?? const []) {
        final capability = Map<String, dynamic>.from(raw as Map);
        if (capability['id'] == id) {
          return capability['label']?.toString() ?? id;
        }
      }
    }
    return id;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadStarted) {
      _loadStarted = true;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _plans = null;
    });
    try {
      final StoreService? store =
          widget.loader == null || widget.catalogLoader == null
              ? context.read<StoreService>()
              : null;
      // La liste commerciale est l'information principale de cet écran. Le
      // catalogue des modules sert uniquement au formulaire d'édition et ne
      // doit donc jamais empêcher l'affichage des plans existants.
      final plans = await (widget.loader?.call() ?? store!.getSuperAdminPlans())
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _loading = false;
      });
      try {
        final catalog = await (widget.catalogLoader?.call() ??
                store!.getSuperAdminModuleCatalog())
            .timeout(const Duration(seconds: 20));
        if (!mounted) return;
        setState(() => _moduleCatalog = catalog);
      } on Exception {
        // Les plans restent consultables même si le catalogue secondaire est
        // momentanément indisponible.
      }
    } on Exception {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les plans.';
      });
    }
  }

  Future<void> _openForm([PlanModel? existing]) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final description =
        TextEditingController(text: existing?.description ?? '');
    final price = TextEditingController(text: existing?.price.toString() ?? '');
    final duration =
        TextEditingController(text: existing?.durationDays.toString() ?? '365');
    final featureSearch = TextEditingController();
    final selectedFeatures = <String>{
      ...?existing?.features.where(
          (feature) => _moduleCatalog.any((item) => item['id'] == feature)),
    };
    final capabilityCatalog = _moduleCatalog
        .expand((module) => (module['capabilities'] as List? ?? const []))
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final selectedCapabilities = <String>{
      ...?((existing?.limits['capabilities'] as List?)
          ?.map((value) => value.toString())),
    };
    String selectedCurrency = existing?.currency ?? 'FCFA';
    String selectedStatus = existing?.status ?? 'active';
    String searchQuery = '';
    String? formError;
    bool submitting = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Créer un plan' : 'Modifier le plan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Informations générales',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                TextField(
                  key: const Key('plan-name'),
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nom *'),
                ),
                TextField(
                  key: const Key('plan-description'),
                  controller: description,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                TextField(
                  key: const Key('plan-price'),
                  controller: price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Prix de l’offre (FCFA) *'),
                ),
                TextField(
                  key: const Key('plan-duration'),
                  controller: duration,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Durée en jours *'),
                ),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: const Key('plan-currency'),
                  initialValue: selectedCurrency,
                  decoration: const InputDecoration(labelText: 'Devise'),
                  items: const [
                    DropdownMenuItem(value: 'FCFA', child: Text('FCFA')),
                  ],
                  onChanged: (value) {
                    if (value != null) selectedCurrency = value;
                  },
                ),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: const Key('plan-status'),
                  initialValue: selectedStatus,
                  decoration: const InputDecoration(labelText: 'Statut'),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Actif')),
                    DropdownMenuItem(value: 'inactive', child: Text('Inactif')),
                  ],
                  onChanged: (value) {
                    if (value != null) selectedStatus = value;
                  },
                ),
                const SizedBox(height: AppSpacing.s5),
                const Text('Fonctionnalités incluses',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Text(
                    'Le catalogue ci-dessous provient du backend. Sélectionnez uniquement les modules réellement inclus dans cette offre.'),
                const SizedBox(height: AppSpacing.s2),
                TextField(
                  key: const Key('plan-feature-search'),
                  controller: featureSearch,
                  decoration: const InputDecoration(
                    labelText: 'Rechercher une fonctionnalité',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setDialogState(
                      () => searchQuery = value.trim().toLowerCase()),
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                    '${selectedFeatures.length} fonctionnalité(s) sélectionnée(s)',
                    key: const Key('plan-feature-count')),
                if (_moduleCatalog.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.s3),
                    child: Text('Aucune fonctionnalité disponible.',
                        key: Key('plan-catalog-empty')),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final group in _moduleCatalog
                              .map((item) =>
                                  item['group']?.toString() ?? 'Scolarité')
                              .toSet()) ...[
                            if (_moduleCatalog.any((module) {
                              final id = module['id'].toString().toLowerCase();
                              final label =
                                  module['label']?.toString().toLowerCase() ??
                                      id;
                              return (module['group']?.toString() ??
                                          'Scolarité') ==
                                      group &&
                                  (searchQuery.isEmpty ||
                                      id.contains(searchQuery) ||
                                      label.contains(searchQuery) ||
                                      group
                                          .toLowerCase()
                                          .contains(searchQuery));
                            }))
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: AppSpacing.s3),
                                child: Text(group,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                              ),
                            for (final module in _moduleCatalog.where((module) {
                              final id = module['id'].toString().toLowerCase();
                              final label =
                                  module['label']?.toString().toLowerCase() ??
                                      id;
                              return (module['group']?.toString() ??
                                          'Scolarité') ==
                                      group &&
                                  (searchQuery.isEmpty ||
                                      id.contains(searchQuery) ||
                                      label.contains(searchQuery) ||
                                      group
                                          .toLowerCase()
                                          .contains(searchQuery));
                            }))
                              CheckboxListTile(
                                key: Key('plan-feature-${module['id']}'),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(module['label']?.toString() ??
                                    module['id'].toString()),
                                value: selectedFeatures
                                    .contains(module['id'].toString()),
                                onChanged: (selected) => setDialogState(() {
                                  final id = module['id'].toString();
                                  if (selected ?? false) {
                                    selectedFeatures.add(id);
                                  } else {
                                    selectedFeatures.remove(id);
                                  }
                                }),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (capabilityCatalog.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s4),
                  const Text('Capacités détaillées',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const Text(
                      'Séparez la gestion interne des publications destinées aux utilisateurs.'),
                  const SizedBox(height: AppSpacing.s2),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final group in capabilityCatalog
                              .map((item) => item['group'].toString())
                              .toSet()) ...[
                            Padding(
                              padding: const EdgeInsets.only(
                                  top: AppSpacing.s3, bottom: AppSpacing.s1),
                              child: Text(group,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                            ),
                            for (final capability in capabilityCatalog.where(
                                (item) => item['group'].toString() == group))
                              CheckboxListTile(
                                key: Key('plan-capability-${capability['id']}'),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text('${capability['label']}'),
                                subtitle: Text(selectedCapabilities
                                        .contains(capability['id'])
                                    ? 'Incluse dans ce forfait'
                                    : 'Non incluse'),
                                value: selectedCapabilities
                                    .contains(capability['id']),
                                onChanged: (selected) => setDialogState(() {
                                  final id = capability['id'].toString();
                                  if (selected ?? false) {
                                    selectedCapabilities.add(id);
                                  } else {
                                    selectedCapabilities.remove(id);
                                  }
                                }),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                if (formError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s3),
                    child: Text(formError!,
                        key: const Key('plan-form-error'),
                        style: const TextStyle(color: AppColors.danger500)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  submitting ? null : () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const Key('plan-save'),
              onPressed: submitting ? null : () async {
                final parsedPrice = int.tryParse(price.text.trim());
                final parsedDuration = int.tryParse(duration.text.trim());
                if (name.text.trim().length < 2 ||
                    parsedPrice == null ||
                    parsedPrice < 0 ||
                    parsedDuration == null ||
                    parsedDuration <= 0) {
                  setDialogState(() => formError =
                      'Nom, prix positif ou nul et durée positive sont obligatoires.');
                  return;
                }
                setDialogState(() {
                  submitting = true;
                  formError = null;
                });
                final plan = PlanModel(
                  id: existing?.id ?? '',
                  name: name.text.trim(),
                  description: description.text.trim(),
                  price: parsedPrice,
                  durationDays: parsedDuration,
                  currency: selectedCurrency,
                  status: selectedStatus,
                  features: _moduleCatalog
                      .map((module) => module['id'].toString())
                      .where(selectedFeatures.contains)
                      .toList(),
                  limits: {
                    ...?existing?.limits,
                    'capabilitiesConfigured': true,
                    'capabilities': selectedCapabilities.toList()..sort(),
                  },
                  subscriptionCount: existing?.subscriptionCount ?? 0,
                );
                try {
                  if (existing == null) {
                    await (widget.creator?.call(plan) ??
                        this
                            .context
                            .read<StoreService>()
                            .createSuperAdminPlan(plan));
                  } else {
                    await (widget.updater?.call(plan) ??
                        this
                            .context
                            .read<StoreService>()
                            .updateSuperAdminPlan(plan));
                  }
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  await _load();
                } on ApiException catch (error) {
                  if (dialogContext.mounted) {
                    setDialogState(() => formError = AppToast.humanErrorMessage(
                          error.message,
                          fallback:
                              'Impossible d’enregistrer ce plan. Veuillez réessayer.',
                        ));
                  }
                } on Exception {
                  if (dialogContext.mounted) {
                    setDialogState(() => formError =
                        'Impossible d’enregistrer ce plan. Veuillez réessayer.');
                  }
                } finally {
                  if (dialogContext.mounted) {
                    setDialogState(() => submitting = false);
                  }
                }
              },
              child: submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDetail(PlanModel summary) async {
    try {
      final plan = await (widget.detailLoader?.call(summary.id) ??
          context.read<StoreService>().getSuperAdminPlan(summary.id));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(plan.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(plan.description.isEmpty
                  ? 'Aucune description'
                  : plan.description),
              const SizedBox(height: AppSpacing.s3),
              Text('Prix de l’offre : ${plan.price} ${plan.currency}'),
              Text('Durée : ${plan.durationDays} jours'),
              Text('Statut : ${plan.isActive ? "Actif" : "Inactif"}'),
              Text('Abonnements liés : ${plan.subscriptionCount}'),
              Text(
                  'Fonctionnalités : ${plan.features.isEmpty ? "Aucune" : plan.features.map(_moduleLabel).join(", ")}'),
              Text(
                  'Capacités détaillées : ${(plan.limits['capabilities'] as List? ?? const []).isEmpty ? "Aucune" : (plan.limits['capabilities'] as List).map((item) => _capabilityLabel(item.toString())).join(", ")}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } on Exception {
      if (!mounted) return;
      AppToast.error(context, 'Impossible de charger le détail du plan.');
    }
  }

  Future<void> _toggle(PlanModel plan) async {
    final deactivate = plan.isActive;
    if (deactivate) {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Désactiver le plan'),
              content: const Text(
                  'Les abonnements existants resteront inchangés. Le plan ne pourra plus être utilisé pour une nouvelle souscription.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Annuler')),
                FilledButton(
                    key: const Key('confirm-plan-deactivation'),
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Désactiver')),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
    }
    if (!mounted) return;
    try {
      final updated = plan.copyWith(status: deactivate ? 'inactive' : 'active');
      await (widget.updater?.call(updated) ??
          context.read<StoreService>().updateSuperAdminPlan(updated));
      if (mounted) await _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      AppToast.error(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppPageHeader(
            title: 'Plans & Offres',
            subtitle: 'Catalogue réel des offres de la plateforme.',
            actions: [
              AppButton(
                key: const Key('create-plan'),
                label: 'Créer un plan',
                icon: Icons.add_rounded,
                onPressed: _openForm,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s5),
          if (_loading)
            const Center(
                child: CircularProgressIndicator(key: Key('plans-loading')))
          else if (_error != null)
            AppCard(
              key: const Key('plans-error'),
              child: Column(
                children: [
                  Text(_error!,
                      style: const TextStyle(color: AppColors.danger500)),
                  const SizedBox(height: AppSpacing.s3),
                  AppButton(label: 'Réessayer', onPressed: _load),
                ],
              ),
            )
          else if (_plans!.isEmpty)
            const AppCard(
              key: Key('plans-empty'),
              child: Text('Aucun plan enregistré.'),
            )
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStatePropertyAll(
                      isDark ? AppColors.darkBgTableStripe : AppColors.gray100),
                  columns: const [
                    DataColumn(label: Text('Plan')),
                    DataColumn(label: Text('Prix de l’offre')),
                    DataColumn(label: Text('Durée')),
                    DataColumn(label: Text('Statut')),
                    DataColumn(label: Text('Abonnements')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: _plans!
                      .map((plan) => DataRow(cells: [
                            DataCell(Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(plan.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                if (plan.description.isNotEmpty)
                                  SizedBox(
                                      width: 260,
                                      child: Text(plan.description,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis)),
                              ],
                            )),
                            DataCell(Text('${plan.price} ${plan.currency}')),
                            DataCell(Text('${plan.durationDays} jours')),
                            DataCell(AppBadge(
                              label: plan.isActive ? 'Actif' : 'Inactif',
                              variant: plan.isActive
                                  ? AppBadgeVariant.success
                                  : AppBadgeVariant.danger,
                            )),
                            DataCell(Text(plan.subscriptionCount.toString())),
                            DataCell(Row(children: [
                              IconButton(
                                tooltip: 'Consulter',
                                onPressed: () => _showDetail(plan),
                                icon: const Icon(Icons.visibility_outlined),
                              ),
                              IconButton(
                                tooltip: 'Modifier',
                                onPressed: () => _openForm(plan),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip:
                                    plan.isActive ? 'Désactiver' : 'Activer',
                                onPressed: () => _toggle(plan),
                                icon: Icon(plan.isActive
                                    ? Icons.pause_circle_outline
                                    : Icons.play_circle_outline),
                              ),
                            ])),
                          ]))
                      .toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
