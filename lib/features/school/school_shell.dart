import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/responsive_utils.dart';
import '../../core/utils/notification_date_utils.dart';
import '../../core/utils/school_module_access.dart';
import '../../data/services/store_service.dart';
import '../../shared/widgets/app_header.dart';
import '../../shared/widgets/app_sidebar.dart';
import 'academic_years/academic_years_page.dart';
import 'affectations/affectations_page.dart';
import 'attendance/attendance_page.dart';
import 'behavior/behavior_page.dart';
import 'classes/classes_page.dart';
import 'dashboard/school_dashboard.dart';
import 'dashboard/parent_tracking_page.dart';
import 'documents/documents_page.dart';
import 'finance/finance_page.dart';
import 'finance/parent_finance_page.dart';
import 'grades/canonical_grades_page.dart';
import 'grades/student_results_page.dart';
import 'periods/periods_page.dart';
import 'notifications/notifications_page.dart';
import 'schedule/schedule_page.dart';
import 'settings/settings_page.dart';
import 'statistics/statistics_page.dart';
import 'students/students_page.dart';
import 'students/teacher_students_page.dart';
import 'subjects/subjects_page.dart';
import 'suspended_page.dart';
import 'teachers/teachers_page.dart';

int? subscriptionCountdownDays(String? rawEndDate, {DateTime? today}) {
  final endDate = DateTime.tryParse(rawEndDate ?? '');
  if (endDate == null) return null;
  final current = today ?? DateTime.now();
  final currentDay = DateTime(current.year, current.month, current.day);
  final endDay = DateTime(endDate.year, endDate.month, endDate.day);
  final days = endDay.difference(currentDay).inDays;
  return days >= 0 && days <= 15 ? days : null;
}

/// Shell principal pour l'interface scolaire — Adaptatif (Desktop, Tablette, Mobile)
class SchoolShell extends StatefulWidget {
  const SchoolShell({super.key});

  @override
  State<SchoolShell> createState() => _SchoolShellState();
}

class _SchoolShellState extends State<SchoolShell> {
  String _activePageId = 'dashboard';
  bool _isSidebarCollapsed = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  Timer? _notificationRefreshTimer;

  bool _pageAllowedForRole(UserRole? role, String pageId) {
    if (role == UserRole.admin) return true;
    const studentPages = {'dashboard', 'grades', 'schedule', 'notifications'};
    const parentPages = {
      'dashboard',
      'tracking',
      'grades',
      'schedule',
      'parent_finance',
      'notifications'
    };
    const teacherPages = {
      'dashboard',
      'students',
      'grades',
      'attendance',
      'schedule',
      'behavior',
      'notifications',
    };
    if (role == UserRole.student) return studentPages.contains(pageId);
    if (role == UserRole.parent) return parentPages.contains(pageId);
    if (role == UserRole.teacher) return teacherPages.contains(pageId);
    return pageId == 'dashboard';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshWorkflowNotifications();
      _notificationRefreshTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => _refreshWorkflowNotifications(),
      );
    });
  }

  Future<void> _refreshWorkflowNotifications() async {
    try {
      await context.read<StoreService>().refreshWorkflowNotificationsRemote();
    } on Exception {
      // Une indisponibilité réseau ne doit jamais bloquer l'espace de travail.
    }
  }

  @override
  void dispose() {
    _notificationRefreshTimer?.cancel();
    super.dispose();
  }

  void _navigateTo(String pageId) {
    final store = context.read<StoreService>();
    // Documents est strictement administratif et Communication reste retiré.
    final role = store.currentUser?.role;
    if (!_pageAllowedForRole(role, pageId)) {
      pageId = 'dashboard';
    }
    if (pageId == 'messages') {
      pageId = 'dashboard';
    }
    if (pageId == 'settings' && role != UserRole.admin) {
      pageId = 'dashboard';
    }
    final modules =
        store.getCurrentSchool()?.enabledModules ?? const <String>[];
    if (!isSchoolPageEnabled(pageId, modules)) {
      pageId = 'dashboard';
    }
    final isSuspended = store.isCurrentSchoolSuspended();
    const allowedWhileSuspended = {
      'dashboard',
      'finance',
      'documents',
      'settings'
    };
    if (isSuspended && !allowedWhileSuspended.contains(pageId)) {
      pageId = 'dashboard';
    }

    setState(() => _activePageId = pageId);
    // Sur mobile, fermer automatiquement le drawer après la sélection
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
  }

  Widget _buildPageView() {
    final store = context.read<StoreService>();
    final modules =
        store.getCurrentSchool()?.enabledModules ?? const <String>[];
    final isSuspended = store.isCurrentSchoolSuspended();
    const allowedWhileSuspended = {
      'dashboard',
      'finance',
      'documents',
      'settings'
    };
    var effectivePageId =
        isSuspended && !allowedWhileSuspended.contains(_activePageId)
            ? 'dashboard'
            : _activePageId;
    if (!_pageAllowedForRole(store.currentUser?.role, effectivePageId)) {
      effectivePageId = 'dashboard';
    }
    if (!isSchoolPageEnabled(effectivePageId, modules)) {
      effectivePageId = 'dashboard';
    }
    if (store.currentUser?.role != UserRole.admin &&
        effectivePageId == 'documents') {
      effectivePageId = 'dashboard';
    }
    if (effectivePageId == 'messages') effectivePageId = 'dashboard';
    if (effectivePageId == 'settings' &&
        store.currentUser?.role != UserRole.admin) {
      effectivePageId = 'dashboard';
    }

    if (isSuspended && effectivePageId == 'dashboard') {
      return SuspendedSchoolPage(
        schoolName: store.getCurrentSchool()?.name,
        planName: store.getCurrentSchool()?.plan.toUpperCase(),
        subscription: store.getCurrentSchoolSubscription(),
        onNavigate: _navigateTo,
      );
    }

    switch (effectivePageId) {
      case 'dashboard':
        return SchoolDashboard(onNavigate: _navigateTo);
      case 'students':
        return store.currentUser?.role == UserRole.teacher
            ? const TeacherStudentsPage()
            : const StudentsPage();
      case 'teachers':
        return const TeachersPage();
      case 'classes':
        return const ClassesPage();
      case 'subjects':
        return const SubjectsPage();
      case 'affectations':
        return const AffectationsPage();
      case 'academic_years':
        return const AcademicYearsPage();
      case 'periods':
        return const PeriodsPage();
      case 'notifications':
        return const NotificationsPage();
      case 'grades':
        if (store.currentUser?.role == UserRole.student) {
          return const StudentResultsPage();
        }
        if (store.currentUser?.role == UserRole.parent) {
          return const ParentResultsPage();
        }
        return const CanonicalGradesPage();
      case 'tracking':
        return store.currentUser?.role == UserRole.parent
            ? const ParentTrackingPage()
            : SchoolDashboard(onNavigate: _navigateTo);
      case 'attendance':
        return const AttendancePage();
      case 'behavior':
        return const BehaviorPage();
      case 'schedule':
        return const SchedulePage();
      case 'assignments':
        return const CanonicalGradesPage();
      case 'finance':
        return const FinancePage();
      case 'parent_finance':
        return const ParentFinancePage();
      case 'documents':
        return const DocumentsPage();
      case 'statistics':
        return const StatisticsPage();
      case 'settings':
        return const SettingsPage();
      default:
        return SchoolDashboard(onNavigate: _navigateTo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = ContextUtils.isMobile(context);

    final sidebarWidget = AppSidebar(
      activePageId: _activePageId,
      onPageSelected: _navigateTo,
      isCollapsed: _isSidebarCollapsed,
      onToggleCollapse: () {
        setState(() => _isSidebarCollapsed = !_isSidebarCollapsed);
      },
    );

    return Scaffold(
      key: _scaffoldKey,
      drawer: isMobile ? Drawer(child: sidebarWidget) : null,
      body: SafeArea(
        child: Row(
          children: [
            // On Desktop/Tablet, permanent sidebar
            if (!isMobile) sidebarWidget,
            // Header + Main Content Area
            Expanded(
              child: Column(
                children: [
                  AppHeader(
                    onMenuToggle: () {
                      if (isMobile) {
                        _scaffoldKey.currentState?.openDrawer();
                      } else {
                        setState(
                            () => _isSidebarCollapsed = !_isSidebarCollapsed);
                      }
                    },
                  ),
                  const _SubscriptionCountdownNotice(),
                  const _AcademicContextNotice(),
                  const _WorkflowNotificationsBar(),
                  Expanded(
                    child: Container(
                      color:
                          isDark ? AppColors.darkBgBody : AppColors.lightBgBody,
                      child: _buildPageView(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionCountdownNotice extends StatelessWidget {
  const _SubscriptionCountdownNotice();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    if (store.currentUser?.role != UserRole.admin) {
      return const SizedBox.shrink();
    }
    final schoolSubscription = store.getCurrentSchool()?.subscription;
    final fallbackSubscription = store.getCurrentSchoolSubscription();
    final rawEndDate = schoolSubscription?.endDate ?? fallbackSubscription?.endDate;
    final end = DateTime.tryParse(rawEndDate ?? '');
    final days = subscriptionCountdownDays(rawEndDate);
    if (end == null || days == null) return const SizedBox.shrink();
    final label = days == 0
        ? 'Votre abonnement expire aujourd’hui.'
        : 'Votre abonnement expire dans $days jour${days > 1 ? 's' : ''}.';
    return Material(
      key: const Key('subscription-countdown-notice'),
      color: days <= 3 ? AppColors.danger50 : AppColors.warning50,
      child: ListTile(
        dense: true,
        leading: Icon(
          days <= 3 ? Icons.error_outline_rounded : Icons.schedule_rounded,
          color: days <= 3 ? AppColors.danger600 : AppColors.warning700,
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('Échéance : ${end.day.toString().padLeft(2, '0')}/'
            '${end.month.toString().padLeft(2, '0')}/${end.year}'),
      ),
    );
  }
}

class _WorkflowNotificationsBar extends StatelessWidget {
  const _WorkflowNotificationsBar();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    final items = store
        .getNotifications()
        .where((item) =>
            !item.read &&
            const {'grade_entry_open', 'results_available'}.contains(item.type))
        .toList()
      ..sort((left, right) => notificationDate(right.time)
          .compareTo(notificationDate(left.time)));
    if (items.isEmpty) return const SizedBox.shrink();
    final latest = items.first;
    return Material(
      color: AppColors.info50,
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.notifications_active_outlined,
            color: AppColors.info600),
        title: Text(latest.title,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: latest.message == null ? null : Text(latest.message!),
        trailing: Wrap(spacing: AppSpacing.s2, children: [
          if (items.length > 1)
            TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text('${items.length} notifications'),
                  content: SizedBox(
                    width: 520,
                    child: ListView(
                      shrinkWrap: true,
                      children: () {
                        final widgets = <Widget>[];
                        String? currentMonth;
                        for (final item in items) {
                          final month = notificationMonthKey(item.time);
                          if (month != currentMonth) {
                            widgets.add(Padding(
                              padding: const EdgeInsets.only(
                                  top: AppSpacing.s2),
                              child: Text(
                                notificationMonthLabel(item.time),
                                style: Theme.of(dialogContext)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                        fontWeight: FontWeight.w800),
                              ),
                            ));
                            currentMonth = month;
                          }
                          widgets.add(ListTile(
                            title: Text(item.title),
                            subtitle: Text(item.message ?? ''),
                          ));
                        }
                        return widgets;
                      }(),
                    ),
                  ),
                  actions: [
                    FilledButton(
                      onPressed: () {
                        store.markAllNotificationsAsRead(
                            schoolId: store.currentUser?.schoolId);
                        Navigator.pop(dialogContext);
                      },
                      child: const Text('Tout marquer comme lu'),
                    ),
                  ],
                ),
              ),
              child: Text('Voir tout (${items.length})'),
            ),
          IconButton(
            tooltip: 'Marquer comme lu',
            onPressed: () => store.markNotificationAsRead(latest.id),
            icon: const Icon(Icons.close_rounded),
          ),
        ]),
      ),
    );
  }
}

class _AcademicContextNotice extends StatelessWidget {
  const _AcademicContextNotice();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    final years = store.getAcademicYears();
    final active = store.getActiveAcademicYear();
    final selected = store.getSelectedAcademicYear();
    final isHistorical =
        active != null && selected != null && active.id != selected.id;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (years.isNotEmpty && !isHistorical) return const SizedBox.shrink();

    return Container(
      key: const Key('admin-academic-context-notice'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4, vertical: AppSpacing.s2),
      color: isHistorical
          ? AppColors.warning50
          : (isDark ? AppColors.darkBgCard : AppColors.lightBgCard),
      child: Wrap(
        spacing: AppSpacing.s2,
        runSpacing: AppSpacing.s2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (years.isEmpty) const Text('Aucune année scolaire configurée.'),
          if (isHistorical)
            const Icon(Icons.history_rounded,
                size: 18, color: AppColors.warning700),
          if (isHistorical)
            Text('Consultation historique : ${selected.name}',
                key: const Key('historical-year-indicator'),
                style: const TextStyle(
                    color: AppColors.warning700, fontWeight: FontWeight.bold)),
          if (isHistorical)
            TextButton(
              key: const Key('return-to-active-year'),
              onPressed: () => store.setSelectedAcademicYearId(active.id),
              child: Text('Revenir à ${active.name}'),
            ),
        ],
      ),
    );
  }
}
