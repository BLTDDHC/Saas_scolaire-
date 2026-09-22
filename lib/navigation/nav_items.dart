import 'package:flutter/material.dart';
import '../core/constants/establishment_types.dart';

/// Un item de la sidebar
class NavItem {
  final String id;
  final String label;
  final IconData icon;
  final String? badge;
  final String? section;

  const NavItem({
    required this.id,
    required this.label,
    required this.icon,
    this.badge,
    this.section,
  });
}

/// Helper pour obtenir les items de la sidebar par rôle et par type d'établissement
/// Reproduction exacte de UI.getNavItems(role) dans ui.js
class NavItems {
  NavItems._();

  static List<NavItem> getNavItemsForRole(UserRole role,
      {bool isHigherEducation = false}) {
    switch (role) {
      case UserRole.superadmin:
        return const [
          NavItem(
              id: 'dashboard',
              label: 'Tableau de bord',
              icon: Icons.dashboard_rounded,
              section: 'PLATEFORME'),
          NavItem(
              id: 'establishments',
              label: 'Établissements',
              icon: Icons.business_rounded,
              section: 'PLATEFORME'),
          NavItem(
              id: 'administrators',
              label: 'Administrateurs',
              icon: Icons.admin_panel_settings_rounded,
              section: 'PLATEFORME'),
          NavItem(
              id: 'directions',
              label: 'Directions',
              icon: Icons.account_tree_rounded,
              section: 'PLATEFORME'),
          NavItem(
              id: 'plans',
              label: 'Plans & Offres',
              icon: Icons.sell_rounded,
              section: 'PLATEFORME'),
          NavItem(
              id: 'subscriptions',
              label: 'Abonnements',
              icon: Icons.card_membership_rounded,
              section: 'PLATEFORME'),
        ];

      case UserRole.admin:
        return const [
          NavItem(
              id: 'dashboard',
              label: 'Tableau de bord',
              icon: Icons.grid_view_rounded,
              section: 'GÉNÉRAL'),
          NavItem(
              id: 'students',
              label: 'Élèves',
              icon: Icons.people_alt_rounded,
              section: 'PÉDAGOGIE'),
          NavItem(
              id: 'teachers',
              label: 'Enseignants',
              icon: Icons.school_rounded,
              section: 'PÉDAGOGIE'),
          NavItem(
              id: 'classes',
              label: 'Classes',
              icon: Icons.door_front_door_rounded,
              section: 'PÉDAGOGIE'),
          NavItem(
              id: 'subjects',
              label: 'Matières',
              icon: Icons.menu_book_rounded,
              section: 'PÉDAGOGIE'),
          NavItem(
              id: 'academic_years',
              label: 'Années scolaires',
              icon: Icons.calendar_month_rounded,
              section: 'PÉDAGOGIE'),
          NavItem(
              id: 'grades',
              label: 'Résultats & soumissions',
              icon: Icons.grade_rounded,
              section: 'SUIVI'),
          NavItem(
              id: 'attendance',
              label: 'Présences',
              icon: Icons.access_time_filled_rounded,
              section: 'SUIVI'),
          NavItem(
              id: 'schedule',
              label: 'Emploi du temps',
              icon: Icons.calendar_today_rounded,
              section: 'SUIVI'),
          NavItem(
              id: 'behavior',
              label: 'Comportement',
              icon: Icons.stars_rounded,
              section: 'SUIVI'),
          NavItem(
              id: 'finance',
              label: 'Finance',
              icon: Icons.account_balance_wallet_rounded,
              section: 'SERVICES'),
          NavItem(
              id: 'documents',
              label: 'Documents',
              icon: Icons.description_rounded,
              section: 'SERVICES'),
          NavItem(
              id: 'statistics',
              label: 'Statistiques',
              icon: Icons.bar_chart_rounded,
              section: 'ADMINISTRATION'),
          NavItem(
              id: 'settings',
              label: 'Paramètres',
              icon: Icons.settings_rounded,
              section: 'ADMINISTRATION'),
        ];

      case UserRole.teacher:
        return const [
          NavItem(
              id: 'dashboard',
              label: 'Tableau de bord',
              icon: Icons.grid_view_rounded,
              section: 'ESPACE ENSEIGNANT'),
          NavItem(
              id: 'students',
              label: 'Mes élèves',
              icon: Icons.people_alt_outlined,
              section: 'PÉDAGOGIE'),
          NavItem(
              id: 'grades',
              label: 'Saisie des notes',
              icon: Icons.grade_rounded,
              section: 'PÉDAGOGIE'),
          NavItem(
              id: 'attendance',
              label: 'Faire l\'appel',
              icon: Icons.how_to_reg_rounded,
              section: 'PÉDAGOGIE'),
          NavItem(
              id: 'schedule',
              label: 'Mon Emploi du temps',
              icon: Icons.calendar_today_rounded,
              section: 'PÉDAGOGIE'),
          NavItem(
              id: 'behavior',
              label: 'Comportement',
              icon: Icons.stars_rounded,
              section: 'PÉDAGOGIE'),
        ];

      case UserRole.student:
        return const [
          NavItem(
              id: 'dashboard',
              label: 'Tableau de bord',
              icon: Icons.grid_view_rounded,
              section: 'ESPACE ÉLÈVE'),
          NavItem(
              id: 'grades',
              label: 'Notes et résultats',
              icon: Icons.grade_rounded,
              section: 'SCOLAIRE'),
          NavItem(
              id: 'schedule',
              label: 'Emploi du temps',
              icon: Icons.calendar_today_rounded,
              section: 'SCOLAIRE'),
        ];

      case UserRole.parent:
        return const [
          NavItem(
              id: 'dashboard',
              label: 'Tableau de bord',
              icon: Icons.grid_view_rounded,
              section: 'ESPACE PARENT'),
          NavItem(
              id: 'tracking',
              label: 'Suivi des enfants',
              icon: Icons.insights_rounded,
              section: 'SUIVI'),
          NavItem(
              id: 'grades',
              label: 'Notes des enfants',
              icon: Icons.grade_rounded,
              section: 'SUIVI'),
          NavItem(
              id: 'schedule',
              label: 'Emplois du temps',
              icon: Icons.calendar_today_rounded,
              section: 'SUIVI'),
        ];
    }
  }
}
