import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/date_utils.dart';
import '../../data/services/store_service.dart';
import '../../shared/widgets/app_badge.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/responsive_grid.dart';
import '../../shared/widgets/workspace_header.dart';

class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage({super.key, this.refreshToken = 0, this.loader});
  final int refreshToken;
  final Future<Map<String, dynamic>> Function()? loader;

  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  late Future<Map<String, dynamic>> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  @override
  void didUpdateWidget(covariant SubscriptionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _data = _load();
  }

  Future<Map<String, dynamic>> _load() =>
      widget.loader?.call() ??
      context.read<StoreService>().getSuperAdminSubscriptions();

  void _retry() {
    final next = _load();
    setState(() {
      _data = next;
    });
  }

  AppBadgeVariant _subscriptionVariant(String status) {
    if (status == 'active') return AppBadgeVariant.success;
    if (status == 'past_due') return AppBadgeVariant.warning;
    return AppBadgeVariant.danger;
  }

  String _subscriptionLabel(String status) {
    if (status == 'active') return 'Actif';
    if (status == 'past_due') return 'En retard';
    if (status == 'expired') return 'Expiré';
    if (status == 'upcoming') return 'À venir';
    if (status == 'overdue') return 'En retard';
    return status;
  }

  Future<void> _renew(Map<String, dynamic> subscription) async {
    final store = context.read<StoreService>();
    final plans = (await store.getSuperAdminPlans())
        .where((plan) => plan.status == 'active')
        .toList();
    if (!mounted) return;
    if (plans.isEmpty) {
      AppToast.warning(context, 'Aucun plan actif n’est disponible.');
      return;
    }
    final matchingPlans = plans
        .where((plan) =>
            plan.name.toLowerCase() ==
            '${subscription['plan'] ?? ''}'.toLowerCase())
        .toList();
    var selectedPlan =
        matchingPlans.isEmpty ? plans.first : matchingPlans.first;
    var startDate = DateTime.now();
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, refresh) => AlertDialog(
                    title: const Text('Renouveler l’abonnement'),
                    content: SizedBox(
                        width: 430,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: selectedPlan.id,
                              decoration:
                                  const InputDecoration(labelText: 'Plan'),
                              items: plans
                                  .map((plan) => DropdownMenuItem(
                                      value: plan.id,
                                      child: Text(
                                          '${plan.name} · ${plan.durationDays} jours')))
                                  .toList(),
                              onChanged: (id) => refresh(() => selectedPlan =
                                  plans.firstWhere((plan) => plan.id == id))),
                          const SizedBox(height: 16),
                          ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Date de début'),
                              subtitle: Text(AppDateUtils.formatNumeric(
                                  startDate.toIso8601String())),
                              trailing:
                                  const Icon(Icons.calendar_month_outlined),
                              onTap: () async {
                                final picked = await showDatePicker(
                                    context: dialogContext,
                                    initialDate: startDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100));
                                if (picked != null) {
                                  refresh(() => startDate = picked);
                                }
                              }),
                          const SizedBox(height: 8),
                          Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                  'Durée appliquée : ${selectedPlan.durationDays} jours. La date de fin sera calculée automatiquement.')),
                        ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Annuler')),
                      FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Renouveler')),
                    ])));
    if (confirmed != true || !mounted) return;
    try {
      await store.renewSuperAdminSubscription(
          '${subscription['id']}', selectedPlan.name, startDate);
      if (!mounted) return;
      AppToast.success(context, 'Abonnement renouvelé');
      _retry();
    } catch (_) {
      if (mounted) {
        AppToast.error(context, 'Impossible de renouveler cet abonnement.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return WorkspacePage(
      title: 'Gestion des Abonnements SaaS',
      subtitle: 'Plans, échéances et accès des établissements',
      children: [
        FutureBuilder<Map<String, dynamic>>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: Padding(
                      padding: EdgeInsets.all(AppSpacing.s8),
                      child: CircularProgressIndicator(
                          key: Key('subscriptions-loading'))));
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return AppCard(
                  child: Column(children: [
                const Text('Impossible de charger les abonnements.'),
                const SizedBox(height: AppSpacing.s3),
                AppButton(label: 'Réessayer', onPressed: _retry),
              ]));
            }
            final response = snapshot.data!;
            final items = List<Map<String, dynamic>>.from(
                (response['items'] as List? ?? const [])
                    .map((item) => Map<String, dynamic>.from(item as Map)));
            final summary = Map<String, dynamic>.from(
                response['summary'] as Map? ?? const {});
            int metric(String key) => (summary[key] as num?)?.toInt() ?? 0;
            Widget statCard(String title, String value, [Color? color]) =>
                AppCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title, style: AppTypography.bodySmall()),
                      const SizedBox(height: 4),
                      Text(value, style: AppTypography.statValue(color: color)),
                    ]));
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const WorkspaceNotice(
                      message:
                          'La durée et la date d’expiration sont calculées à partir du plan sélectionné. À son échéance, l’accès de l’établissement est suspendu.',
                    ),
                    ResponsiveGrid(
                      desktopColumns: 5,
                      tabletColumns: 2,
                      mobileColumns: 1,
                      children: [
                        statCard(
                            'Total Abonnements', metric('total').toString()),
                        statCard('Abonnements Actifs',
                            metric('active').toString(), AppColors.success500),
                        statCard('En Retard', metric('pastDue').toString(),
                            AppColors.warning500),
                        statCard('Abonnements Expirés',
                            metric('expired').toString(), AppColors.danger500),
                        statCard(
                            'Montant actif total',
                            '${metric('activeAmount')} FCFA',
                            AppColors.primary600),
                      ]),
                  const SizedBox(height: AppSpacing.s6),
                  if (items.isEmpty)
                    const AppCard(child: Text('Aucun abonnement enregistré.'))
                  else
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(isDark
                              ? AppColors.darkBgTableStripe
                              : AppColors.gray100),
                          columns: const [
                            DataColumn(label: Text('Client / Établissement')),
                            DataColumn(label: Text('État établissement')),
                            DataColumn(label: Text('Plan')),
                            DataColumn(label: Text('Statut plan')),
                            DataColumn(label: Text('Prix offre')),
                            DataColumn(label: Text('Tarif abonnement')),
                            DataColumn(label: Text('Date début')),
                            DataColumn(label: Text('Date fin')),
                            DataColumn(label: Text('Jours restants')),
                            DataColumn(label: Text('Statut abonnement')),
                            DataColumn(label: Text('Action')),
                          ],
                          rows: items.map((item) {
                            final subscriptionStatus =
                                item['status']?.toString() ?? 'unknown';
                            final establishmentStatus =
                                item['establishmentStatus']?.toString() ??
                                    'unknown';
                            final planDefinition = item['planDefinition'] is Map
                                ? Map<String, dynamic>.from(
                                    item['planDefinition'] as Map)
                                : null;
                            final planStatus =
                                item['planStatus']?.toString() ?? 'unmanaged';
                            return DataRow(cells: [
                              DataCell(Text(item['client']?.toString() ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold))),
                              DataCell(AppBadge(
                                  label: establishmentStatus == 'active'
                                      ? 'Actif'
                                      : establishmentStatus == 'suspended'
                                          ? 'Suspendu'
                                          : 'Inconnu',
                                  variant: establishmentStatus == 'active'
                                      ? AppBadgeVariant.success
                                      : AppBadgeVariant.danger)),
                              DataCell(AppBadge(
                                  label: planDefinition?['name']?.toString() ??
                                      item['plan']?.toString() ??
                                      '',
                                  variant: AppBadgeVariant.primary)),
                              DataCell(AppBadge(
                                  label: planStatus == 'active'
                                      ? 'Actif'
                                      : planStatus == 'inactive'
                                          ? 'Inactif'
                                          : 'Non référencé',
                                  variant: planStatus == 'active'
                                      ? AppBadgeVariant.success
                                      : planStatus == 'inactive'
                                          ? AppBadgeVariant.danger
                                          : AppBadgeVariant.warning)),
                              DataCell(Text(planDefinition == null
                                  ? 'Non disponible'
                                  : '${planDefinition['price']} ${planDefinition['currency']}')),
                              DataCell(Text(item['price']?.toString() ?? '')),
                              DataCell(Text(AppDateUtils.formatNumeric(
                                  item['startDate']?.toString()))),
                              DataCell(Text(AppDateUtils.formatNumeric(
                                  item['endDate']?.toString()))),
                              DataCell(Text(item['daysRemaining'] == null
                                  ? 'Non disponible'
                                  : '${item['daysRemaining']} jour(s)')),
                              DataCell(AppBadge(
                                  label: _subscriptionLabel(subscriptionStatus),
                                  variant: _subscriptionVariant(
                                      subscriptionStatus))),
                              DataCell(TextButton.icon(
                                  onPressed: () => _renew(item),
                                  icon: const Icon(Icons.autorenew),
                                  label: const Text('Renouveler'))),
                            ]);
                          }).toList(),
                        ),
                      ),
                    ),
                ]);
          },
        ),
      ],
    );
  }
}
