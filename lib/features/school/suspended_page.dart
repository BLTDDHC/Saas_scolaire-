import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/other_models.dart';
import '../../shared/widgets/app_badge.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';

class SuspendedSchoolPage extends StatelessWidget {
  final String? schoolName;
  final String? planName;
  final SubscriptionModel? subscription;
  final ValueChanged<String> onNavigate;

  const SuspendedSchoolPage({
    super.key,
    required this.schoolName,
    required this.planName,
    required this.subscription,
    required this.onNavigate,
  });

  String get statusLabel {
    if (subscription == null) return 'Inconnu';
    switch (subscription!.status) {
      case 'active':
        return 'Actif';
      case 'past_due':
        return 'En retard de paiement';
      case 'expired':
        return 'Abonnement expiré';
      default:
        return subscription!.status;
    }
  }

  AppBadgeVariant get statusVariant {
    if (subscription == null) return AppBadgeVariant.secondary;
    switch (subscription!.status) {
      case 'active':
        return AppBadgeVariant.success;
      case 'past_due':
        return AppBadgeVariant.warning;
      case 'expired':
        return AppBadgeVariant.danger;
      default:
        return AppBadgeVariant.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final supportEmail = 'support@edupro.com';
    final paymentStatus = subscription?.status ?? 'active';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Accès suspendu',
            style: AppTypography.heading2(
              color: isDark
                  ? AppColors.darkTextPrimary
                  : AppColors.lightTextPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            'Votre établissement est actuellement suspendu. Les fonctions de gestion scolaire sont temporairement limitées pendant la période de suspension.',
            style: AppTypography.bodyLarge(
              color: isDark
                  ? AppColors.darkTextTertiary
                  : AppColors.lightTextTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Détails de l’établissement',
                    style: AppTypography.heading4()),
                const SizedBox(height: AppSpacing.s3),
                _buildInfoRow('Établissement', schoolName ?? 'Non défini'),
                const SizedBox(height: AppSpacing.s2),
                _buildInfoRow('Plan', planName ?? 'N/A'),
                const SizedBox(height: AppSpacing.s2),
                _buildInfoRow('Statut du compte', 'Suspendu'),
                const SizedBox(height: AppSpacing.s2),
                _buildInfoRow('Statut de l’abonnement', statusLabel),
                if (subscription != null) ...[
                  const SizedBox(height: AppSpacing.s2),
                  _buildInfoRow('Début',
                      AppDateUtils.formatShort(subscription!.startDate)),
                  const SizedBox(height: AppSpacing.s2),
                  _buildInfoRow(
                      'Fin', AppDateUtils.formatShort(subscription!.endDate)),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pourquoi cette suspension ?',
                    style: AppTypography.heading4()),
                const SizedBox(height: AppSpacing.s3),
                Text(
                  'La suspension s’applique uniquement aux fonctions de gestion scolaire (élèves, enseignants, classes, matières, affectations, notes, présence, etc.). Vous pouvez toujours accéder aux sections Finance, Documents et Paramètres pour régulariser votre situation ou consulter votre compte.',
                  style: AppTypography.bodyLarge(
                    color: isDark
                        ? AppColors.darkTextTertiary
                        : AppColors.lightTextTertiary,
                  ),
                ),
                const SizedBox(height: AppSpacing.s4),
                Row(
                  children: [
                    AppBadge(label: statusLabel, variant: statusVariant),
                    const SizedBox(width: AppSpacing.s3),
                    if (paymentStatus == 'past_due' ||
                        paymentStatus == 'expired')
                      const Text(
                          'Veuillez régulariser votre paiement dès que possible.'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          Row(
            children: [
              AppButton(
                label: 'Voir les paramètres',
                variant: AppButtonVariant.primary,
                onPressed: () => onNavigate('settings'),
              ),
              const SizedBox(width: AppSpacing.s3),
              AppButton(
                label: 'Aller à Finance',
                variant: AppButtonVariant.secondary,
                onPressed: () => onNavigate('finance'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aide & contact', style: AppTypography.heading4()),
                const SizedBox(height: AppSpacing.s3),
                Text(
                  'Pour toute question, contactez notre support client à :',
                  style: AppTypography.bodyLarge(
                    color: isDark
                        ? AppColors.darkTextTertiary
                        : AppColors.lightTextTertiary,
                  ),
                ),
                const SizedBox(height: AppSpacing.s3),
                SelectableText(supportEmail,
                    style: AppTypography.body(color: AppColors.primary600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(
          flex: 3,
          child:
              Text(value, style: const TextStyle(fontWeight: FontWeight.w400)),
        ),
      ],
    );
  }
}
