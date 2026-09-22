import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/establishment_types.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/school_module_access.dart';
import '../../data/services/store_service.dart';
import '../../features/auth/change_password_dialog.dart';
import '../../navigation/nav_items.dart';

/// Sidebar adaptative EduPro — Reproduction exacte de layout.css (.sidebar)
class AppSidebar extends StatelessWidget {
  final String activePageId;
  final ValueChanged<String> onPageSelected;
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;

  const AppSidebar({
    super.key,
    required this.activePageId,
    required this.onPageSelected,
    this.isCollapsed = false,
    this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final store = context.watch<StoreService>();
    final user = store.currentUser;
    final school = store.getCurrentSchool();
    final isUniv = school?.isHigherEducation ?? false;

    final isSuspended = school?.status == 'suspended';
    final allowedWhileSuspended = {
      'dashboard',
      'finance',
      'documents',
      'settings'
    };
    final configuredModules = school?.enabledModules ?? const <String>[];
    final navItems = NavItems.getNavItemsForRole(
      user?.role ?? UserRole.admin,
      isHigherEducation: isUniv,
    ).where((item) {
      if (item.id == 'documents' && user?.role != UserRole.admin) return false;
      if (isSuspended && !allowedWhileSuspended.contains(item.id)) return false;
      // Devoirs utilise désormais le même moteur que Notes & Évaluations.
      if (item.id == 'assignments') return false;
      return isSchoolPageEnabled(item.id, configuredModules);
    }).toList();

    // Group items by section
    final Map<String, List<NavItem>> grouped = {};
    for (final item in navItems) {
      final section = item.section ?? 'MENU';
      grouped.putIfAbsent(section, () => []).add(item);
    }

    return AnimatedContainer(
      duration: AppDurations.base,
      width: isCollapsed
          ? AppLayout.sidebarCollapsedWidth
          : AppLayout.sidebarWidth,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBgSidebar : AppColors.lightBgSidebar,
        border: Border(
          right: BorderSide(
            color:
                isDark ? AppColors.darkBorderColor : AppColors.lightBorderColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Sidebar Logo Header
          Container(
            height: AppLayout.headerHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? AppColors.darkBorderColor
                      : AppColors.lightBorderColor,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary600,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Center(
                    child: Text('E',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.white)),
                  ),
                ),
                if (!isCollapsed) ...[
                  const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'EduPro',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary600,
                          ),
                        ),
                        Text(
                          school?.type ?? 'SaaS Scolaire',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? AppColors.darkTextTertiary
                                : AppColors.lightTextTertiary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Nav Items List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
              children: grouped.entries.expand((entry) {
                final sectionTitle = entry.key;
                final items = entry.value;

                return [
                  if (!isCollapsed)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: AppSpacing.s4,
                        right: AppSpacing.s4,
                        top: AppSpacing.s3,
                        bottom: AppSpacing.s2,
                      ),
                      child: Text(
                        sectionTitle,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: isDark
                              ? AppColors.darkTextTertiary
                              : AppColors.lightTextTertiary,
                        ),
                      ),
                    ),
                  ...items.map((item) {
                    final isSelected = activePageId == item.id;
                    return _SidebarTile(
                      item: item,
                      isSelected: isSelected,
                      isCollapsed: isCollapsed,
                      onTap: () => onPageSelected(item.id),
                    );
                  }),
                ];
              }).toList(),
            ),
          ),

          // User Footer
          Container(
            padding: const EdgeInsets.all(AppSpacing.s3),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? AppColors.darkBorderColor
                      : AppColors.lightBorderColor,
                  width: 1,
                ),
              ),
            ),
            child: isCollapsed
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.password_rounded, size: 20),
                        onPressed: () => showChangePasswordDialog(context),
                        tooltip: 'Modifier mon mot de passe',
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout_rounded, size: 20),
                        onPressed: () => store.logout(),
                        tooltip: 'Déconnexion',
                      ),
                    ],
                  )
                : Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor:
                            AppColors.avatarColorFor(user?.name ?? 'User'),
                        child: Text(
                          user?.initials ?? 'U',
                          style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              user?.name ?? 'Utilisateur',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.lightTextPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              user?.roleName ?? '',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? AppColors.darkTextTertiary
                                    : AppColors.lightTextTertiary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.password_rounded, size: 18),
                        onPressed: () => showChangePasswordDialog(context),
                        tooltip: 'Modifier mon mot de passe',
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.lightTextTertiary,
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        onPressed: () => store.logout(),
                        tooltip: 'Déconnexion',
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.lightTextTertiary,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatefulWidget {
  final NavItem item;
  final bool isSelected;
  final bool isCollapsed;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.item,
    required this.isSelected,
    required this.isCollapsed,
    required this.onTap,
  });

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tileColor = widget.isSelected
        ? (isDark ? const Color(0x264F46E5) : AppColors.primary50)
        : (_isHovered
            ? (isDark ? AppColors.darkBgHover : AppColors.lightBgHover)
            : Colors.transparent);

    final iconTextColor = widget.isSelected
        ? AppColors.primary600
        : (_isHovered
            ? (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary)
            : (isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary));

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.s2, vertical: 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: widget.isCollapsed ? AppSpacing.s2 : AppSpacing.s3,
              vertical: AppSpacing.s2 + 2,
            ),
            decoration: BoxDecoration(
              color: tileColor,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: widget.isSelected
                  ? const Border(
                      left: BorderSide(color: AppColors.primary600, width: 3))
                  : null,
            ),
            child: Row(
              mainAxisAlignment: widget.isCollapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(widget.item.icon, size: 18, color: iconTextColor),
                if (!widget.isCollapsed) ...[
                  const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    child: Text(
                      widget.item.label,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: widget.isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: iconTextColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.item.badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.danger500,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        widget.item.badge!,
                        style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
