import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/responsive_utils.dart';
import '../../data/services/store_service.dart';
import '../auth/change_password_dialog.dart';
import '../../navigation/nav_items.dart';
import '../../shared/widgets/app_badge.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/responsive_grid.dart';
import '../../shared/widgets/workspace_header.dart';
import 'establishments_page.dart';
import 'administrators_page.dart';
import 'directions_page.dart';
import 'plans_page.dart';
import 'subscriptions_page.dart';

class SuperAdminDashboard extends StatefulWidget {
  const SuperAdminDashboard({super.key, this.dashboardLoader});

  final Future<Map<String, dynamic>> Function()? dashboardLoader;

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard> {
  int _currentTab = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  Map<String, dynamic>? _dashboard;
  bool _dashboardRequested = false;
  bool _dashboardLoading = true;
  String? _dashboardError;
  int _subscriptionsRefreshToken = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dashboardRequested) return;
    _dashboardRequested = true;
    _loadDashboard(initial: true);
  }

  Future<void> _loadDashboard({bool initial = false}) async {
    if (!initial && mounted) {
      setState(() {
        _dashboard = null;
        _dashboardError = null;
        _dashboardLoading = true;
      });
    }
    try {
      final value = await (widget.dashboardLoader?.call() ??
          context.read<StoreService>().getSuperAdminDashboard());
      if (!mounted) return;
      setState(() {
        _dashboard = value;
        _dashboardError = null;
        _dashboardLoading = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _dashboard = null;
        _dashboardError = 'Impossible de charger le tableau de bord.';
        _dashboardLoading = false;
      });
    }
  }

  void _onTabSelect(int index) {
    setState(() {
      _currentTab = index;
      if (index == 5) _subscriptionsRefreshToken++;
    });
    if (index == 0) _loadDashboard();
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = ContextUtils.isMobile(context);
    final store = context.watch<StoreService>();
    final currentUser = store.currentUser;
    final navigation = NavItems.getNavItemsForRole(UserRole.superadmin);

    final sidebarContent = Container(
      width: 220,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBgSidebar : AppColors.lightBgSidebar,
        border: Border(
          right: BorderSide(
            color:
                isDark ? AppColors.darkBorderColor : AppColors.lightBorderColor,
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.s4),
          ...navigation.asMap().entries.map(
                (entry) => _SidebarNavTile(
                  icon: entry.value.icon,
                  label: entry.value.label,
                  isSelected: _currentTab == entry.key,
                  onTap: () => _onTabSelect(entry.key),
                ),
              ),
        ],
      ),
    );

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: isMobile
            ? IconButton(
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              )
            : null,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary600,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Center(
                child: Text('E',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            const SizedBox(width: AppSpacing.s2),
            Expanded(
              child: Text(
                isMobile ? 'Super Admin' : 'EduPro Super Admin',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: isMobile ? 14 : 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(store.isDarkMode
                ? Icons.light_mode_rounded
                : Icons.dark_mode_rounded),
            onPressed: store.toggleTheme,
            tooltip: 'Basculer le thème',
          ),
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.primary600,
            child: Text(
              currentUser?.initials ?? 'SA',
              style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.password_rounded, size: 20),
            onPressed: () => showChangePasswordDialog(context),
            tooltip: 'Modifier mon mot de passe',
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 20),
            onPressed: store.logout,
            tooltip: 'Déconnexion',
          ),
          const SizedBox(width: AppSpacing.s2),
        ],
      ),
      drawer: isMobile ? Drawer(child: sidebarContent) : null,
      body: SafeArea(
        child: Row(
          children: [
            if (!isMobile) sidebarContent,
            Expanded(
              child: IndexedStack(
                index: _currentTab,
                children: [
                  _buildDashboardOverview(isMobile),
                  const EstablishmentsPage(),
                  const AdministratorsPage(),
                  const DirectionsPage(),
                  const PlansPage(),
                  SubscriptionsPage(refreshToken: _subscriptionsRefreshToken),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardOverview(bool isMobile) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.s4 : AppSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkspaceHeader(
            title: 'Vue d’ensemble',
            subtitle: 'Indicateurs consolidés de la plateforme',
            actions: [
              OutlinedButton.icon(
                onPressed: _loadDashboard,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Actualiser'),
              ),
            ],
          ),
          if (_dashboardLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.s8),
                child: CircularProgressIndicator(
                  key: Key('superadmin-dashboard-loading'),
                ),
              ),
            )
          else if (_dashboardError != null)
            AppCard(
              key: const Key('superadmin-dashboard-error'),
              child: Column(
                children: [
                  const Icon(Icons.cloud_off_rounded,
                      color: AppColors.danger500),
                  const SizedBox(height: AppSpacing.s3),
                  Text(
                    _dashboardError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.danger500),
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  AppButton(
                    label: 'Réessayer',
                    icon: Icons.refresh_rounded,
                    onPressed: _loadDashboard,
                  ),
                ],
              ),
            )
          else
            _buildDashboardSuccess(isMobile),
        ],
      ),
    );
  }

  Widget _buildDashboardSuccess(bool isMobile) {
    final dashboard = _dashboard!;
    final establishments = Map<String, dynamic>.from(
        dashboard['establishments'] as Map? ?? const {});
    final subscriptions = Map<String, dynamic>.from(
        dashboard['subscriptions'] as Map? ?? const {});
    final users =
        Map<String, dynamic>.from(dashboard['users'] as Map? ?? const {});
    final plans =
        Map<String, dynamic>.from(dashboard['plans'] as Map? ?? const {});
    final recent = List<Map<String, dynamic>>.from(
      (establishments['recent'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
    int metric(Map<String, dynamic> section, String key) =>
        (section[key] as num?)?.toInt() ?? 0;

    final cards = [
      _StatCard(
          title: 'Établissements',
          value: metric(establishments, 'total').toString(),
          subtitle:
              '${metric(establishments, 'active')} actifs · ${metric(establishments, 'suspended')} suspendus',
          icon: Icons.business_rounded,
          color: AppColors.primary600),
      _StatCard(
          title: 'Utilisateurs',
          value: metric(users, 'total').toString(),
          subtitle: '${metric(users, 'admins')} administrateurs scolaires',
          icon: Icons.people_rounded,
          color: AppColors.info500),
      _StatCard(
          title: 'Abonnements',
          value: metric(subscriptions, 'total').toString(),
          subtitle: '${metric(subscriptions, 'active')} actifs',
          icon: Icons.card_membership_rounded,
          color: AppColors.secondary600),
      _StatCard(
          title: 'Valeur des abonnements actifs',
          value: '${metric(subscriptions, 'activeAmountTotal')} FCFA',
          subtitle: 'Montant contractuel',
          icon: Icons.payments_rounded,
          color: AppColors.warning500),
      _StatCard(
          title: 'Plans configurés',
          value: metric(plans, 'total').toString(),
          subtitle: 'Offres réellement administrées sur la plateforme',
          icon: Icons.sell_outlined,
          color: AppColors.info600),
    ];

    final statusCard = AppCard(
      title: 'État de la plateforme',
      subtitle: 'Accès et échéances nécessitant une attention',
      child: Wrap(
        spacing: AppSpacing.s6,
        runSpacing: AppSpacing.s4,
        children: [
          _StatusMetric(
              label: 'Établissements actifs',
              value: metric(establishments, 'active'),
              color: AppColors.success600),
          _StatusMetric(
              label: 'Établissements suspendus',
              value: metric(establishments, 'suspended'),
              color: AppColors.danger600),
          _StatusMetric(
              label: 'Administrateurs scolaires',
              value: metric(users, 'admins'),
              color: AppColors.info600),
          _StatusMetric(
              label: 'Abonnements actifs',
              value: metric(subscriptions, 'active'),
              color: AppColors.success600),
          _StatusMetric(
              label: 'À venir',
              value: metric(subscriptions, 'upcoming'),
              color: AppColors.primary600),
          _StatusMetric(
              label: 'En retard',
              value: metric(subscriptions, 'overdue'),
              color: AppColors.warning600),
          _StatusMetric(
              label: 'Expirés',
              value: metric(subscriptions, 'expired'),
              color: AppColors.danger600),
        ],
      ),
    );

    final recentCard = AppCard(
      title: 'Établissements récents',
      child: recent.isEmpty
          ? const Text('Aucun établissement récent',
              key: Key('superadmin-dashboard-empty'))
          : Column(
              children: recent.map((item) {
                final name = item['name']?.toString() ?? '';
                final type = item['type']?.toString() ?? '';
                final city = item['city']?.toString() ?? '';
                final status = item['status']?.toString() ?? 'suspended';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary50,
                    child: Text(
                      name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: const TextStyle(
                          color: AppColors.primary600,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text([type, city]
                      .where((value) => value.isNotEmpty)
                      .join(' • ')),
                  trailing: AppBadge(
                    label: status == 'active' ? 'Actif' : 'Suspendu',
                    variant: status == 'active'
                        ? AppBadgeVariant.success
                        : AppBadgeVariant.danger,
                  ),
                );
              }).toList(),
            ),
    );

    final actionsCard = AppCard(
      title: 'Actions rapides',
      child: Column(
        children: [
          AppButton(
              label: 'Gérer les établissements',
              icon: Icons.business_rounded,
              fullWidth: true,
              onPressed: () => _onTabSelect(1)),
          const SizedBox(height: AppSpacing.s3),
          AppButton(
              label: 'Voir les abonnements',
              icon: Icons.card_membership_rounded,
              variant: AppButtonVariant.secondary,
              fullWidth: true,
              onPressed: () => _onTabSelect(5)),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResponsiveGrid(
            desktopColumns: 4,
            tabletColumns: 2,
            mobileColumns: 1,
            children: cards),
        const SizedBox(height: AppSpacing.s6),
        statusCard,
        const SizedBox(height: AppSpacing.s6),
        if (isMobile) ...[
          recentCard,
          const SizedBox(height: AppSpacing.s4),
          actionsCard,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: recentCard),
              const SizedBox(width: AppSpacing.s6),
              Expanded(child: actionsCard),
            ],
          ),
      ],
    );
  }
}

class _SidebarNavTile extends StatelessWidget {
  const _SidebarNavTile(
      {required this.icon,
      required this.label,
      required this.isSelected,
      required this.onTap});

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.s3, vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s3, vertical: AppSpacing.s3),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0x264F46E5) : AppColors.primary50)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 20,
                  color: isSelected
                      ? AppColors.primary600
                      : (isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary)),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? AppColors.primary600
                        : (isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.title,
      required this.value,
      required this.subtitle,
      required this.icon,
      required this.color});

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.lg)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTypography.caption(
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.lightTextTertiary),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(value,
                    style: AppTypography.heading3(
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.lightTextTertiary),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusMetric extends StatelessWidget {
  const _StatusMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 150),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.s2),
            Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: AppSpacing.s2),
            Flexible(child: Text(label)),
          ],
        ),
      );
}
