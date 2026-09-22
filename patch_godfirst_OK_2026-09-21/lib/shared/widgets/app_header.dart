import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/constants/establishment_types.dart';
import '../../core/utils/responsive_utils.dart';
import '../../data/services/store_service.dart';
import '../../features/auth/change_password_dialog.dart';
import '../../features/school/students/student_photo_avatar.dart';
import 'app_button.dart';
import 'app_modal.dart';

/// Header principal EduPro — Reproduction exacte de layout.css avec adaptation mobile
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback? onMenuToggle;

  const AppHeader({
    super.key,
    this.onMenuToggle,
  });

  @override
  Size get preferredSize => const Size.fromHeight(AppLayout.headerHeight);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = ContextUtils.isMobile(context);
    final store = context.watch<StoreService>();
    final user = store.currentUser;
    final school = store.getCurrentSchool();
    final studentId = user?.role == UserRole.student
        ? store.getCurrentStudentId()
        : null;
    final academicYears = store.getAcademicYears();
    final selectedYearId = store.getSelectedAcademicYearId();

    return Container(
      height: AppLayout.headerHeight,
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? AppSpacing.s2 : AppSpacing.s4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBgHeader : AppColors.lightBgHeader,
        border: Border(
          bottom: BorderSide(
            color:
                isDark ? AppColors.darkBorderColor : AppColors.lightBorderColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Hamburger toggle (Ouvre le drawer sur mobile)
          IconButton(
            icon: const Icon(Icons.menu_rounded, size: 22),
            onPressed: onMenuToggle ??
                () {
                  Scaffold.of(context).openDrawer();
                },
            tooltip: 'Menu',
            color:
                isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
          ),
          SizedBox(width: isMobile ? 4 : AppSpacing.s2),

          // Le contexte global conserve un seul emplacement principal :
          // l'établissement ici, et l'année dans le sélecteur adjacent.
          Expanded(
            child: Text(
              user?.directionName?.isNotEmpty == true
                  ? '${school?.name ?? user?.establishment ?? 'Établissement'} — ${user!.directionName}'
                  : school?.name ?? 'EduPro SaaS',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: isMobile ? 13 : 15,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Sélecteur d'année scolaire (condensé sur mobile)
          if (academicYears.isNotEmpty) ...[
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? AppSpacing.s1 + 2 : AppSpacing.s3),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkBgInput : AppColors.lightBgHover,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: isDark
                      ? AppColors.darkBorderColor
                      : AppColors.lightBorderColor,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      size: 12, color: AppColors.primary600),
                  const SizedBox(width: 4),
                  DropdownButton<String>(
                    key: const Key('global-academic-year-selector'),
                    value: selectedYearId,
                    underline: const SizedBox(),
                    icon: const Icon(Icons.arrow_drop_down_rounded, size: 18),
                    dropdownColor:
                        isDark ? AppColors.darkBgCard : AppColors.lightBgCard,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: isMobile ? 11 : 12,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                    ),
                    items: academicYears.map((year) {
                      return DropdownMenuItem<String>(
                        value: year.id,
                        child: Text(isMobile
                            ? year.name
                            : 'Année ${year.name}${year.isActive ? " (Active)" : ""}'),
                      );
                    }).toList(),
                    onChanged: (newId) {
                      if (newId != null) {
                        store.setSelectedAcademicYearId(newId);
                      }
                    },
                  ),
                ],
              ),
            ),
            SizedBox(width: isMobile ? 4 : AppSpacing.s4),
          ],

          // Theme toggle
          IconButton(
            icon: Icon(
              store.isDarkMode
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
              size: 20,
            ),
            onPressed: () => store.toggleTheme(),
            tooltip: store.isDarkMode
                ? 'Passer au mode clair'
                : 'Passer au mode sombre',
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary,
          ),

          PopupMenuButton<String>(
            tooltip: 'Mon compte',
            onSelected: (value) {
              if (value == 'profile') {
                _showProfile(context, store);
              } else if (value == 'password') {
                showChangePasswordDialog(context);
              } else if (value == 'logout') {
                store.logout();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.person_outline_rounded),
                  title: Text('Mon profil'),
                ),
              ),
              PopupMenuItem(
                value: 'password',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.password_rounded),
                  title: Text('Modifier le mot de passe'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.logout_rounded),
                  title: Text('Se déconnecter'),
                ),
              ),
            ],
            child: studentId != null
                ? StudentPhotoAvatar(
                    studentId: studentId,
                    initials: user?.initials ?? 'U',
                    radius: isMobile ? 14 : 16,
                  )
                : CircleAvatar(
                    radius: isMobile ? 14 : 16,
                    backgroundColor:
                        AppColors.avatarColorFor(user?.name ?? 'User'),
                    child: Text(
                      user?.initials ?? 'U',
                      style: TextStyle(
                          fontSize: isMobile ? 10 : 11,
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showProfile(BuildContext context, StoreService store) {
    final user = store.currentUser;
    final school = store.getCurrentSchool();
    final studentId = user?.role == UserRole.student
        ? store.getCurrentStudentId()
        : null;
    AppModal.show(
      context: context,
      title: 'Mon profil',
      maxWidth: 520,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (studentId != null)
                StudentPhotoAvatar(
                    studentId: studentId,
                    initials: user?.initials ?? 'U')
              else
                CircleAvatar(
                  radius: 28,
                  backgroundColor:
                      AppColors.avatarColorFor(user?.name ?? 'User'),
                  child: Text(user?.initials ?? 'U',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              const SizedBox(width: AppSpacing.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user?.name ?? 'Utilisateur',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: AppSpacing.s1),
                    Text(user?.roleName ?? ''),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          _ProfileLine(label: 'Établissement', value: school?.name),
          _ProfileLine(label: 'Direction', value: user?.directionName),
          _ProfileLine(label: 'Identifiant', value: user?.email),
        ],
      ),
      footer: Wrap(
        alignment: WrapAlignment.end,
        spacing: AppSpacing.s3,
        children: [
          AppButton(
            label: 'Fermer',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.pop(context),
          ),
          AppButton(
            label: 'Modifier le mot de passe',
            icon: Icons.password_rounded,
            onPressed: () {
              Navigator.pop(context);
              showChangePasswordDialog(context);
            },
          ),
        ],
      ),
    );
  }
}

class _ProfileLine extends StatelessWidget {
  const _ProfileLine({required this.label, this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(value!,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
