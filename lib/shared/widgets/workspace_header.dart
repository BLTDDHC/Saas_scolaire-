import 'package:flutter/material.dart';
import '../../core/theme/app_spacing.dart';
import 'app_page_header.dart';
import 'app_empty_state.dart';
import 'app_card.dart';

/// A consistent, wrapping heading for desktop workspaces and narrow windows.
class WorkspaceHeader extends StatelessWidget {
  const WorkspaceHeader(
      {super.key,
      required this.title,
      required this.subtitle,
      this.actions = const []});
  final String title, subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child:
            AppPageHeader(title: title, subtitle: subtitle, actions: actions),
      );
}

/// Cadre de page commun aux espaces Super Admin, Direction, Enseignant et
/// Élève. Il exploite les écrans de bureau jusqu'à 1920 px sans transformer les
/// formulaires en lignes démesurées, et réduit naturellement les marges dans
/// une fenêtre étroite.
class WorkspacePage extends StatelessWidget {
  const WorkspacePage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.actions = const [],
    this.maxWidth = 1760,
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;
  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth < 720
              ? AppSpacing.s4
              : constraints.maxWidth < 1366
                  ? AppSpacing.s5
                  : constraints.maxWidth < 1920
                      ? AppSpacing.s6
                      : AppSpacing.s8;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontal,
              AppSpacing.s5,
              horizontal,
              AppSpacing.s8,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WorkspaceHeader(
                      title: title,
                      subtitle: subtitle,
                      actions: actions,
                    ),
                    ...children,
                  ],
                ),
              ),
            ),
          );
        },
      );
}

class WorkspaceLoadingState extends StatelessWidget {
  const WorkspaceLoadingState({
    super.key,
    this.label = 'Chargement en cours…',
  });

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: AppCard(
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: .72),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: AppSpacing.s2),
                        const ClipRRect(
                          borderRadius:
                              BorderRadius.all(Radius.circular(AppRadius.full)),
                          child: LinearProgressIndicator(minHeight: 4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class WorkspaceErrorState extends StatelessWidget {
  const WorkspaceErrorState({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => AppEmptyState(
        iconData: Icons.cloud_off_outlined,
        title: message,
        message: 'Vérifiez votre connexion puis réessayez.',
        actionLabel: onRetry == null ? null : 'Réessayer',
        onAction: onRetry,
      );
}

class WorkspaceSectionHeader extends StatelessWidget {
  const WorkspaceSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.s2,
          bottom: AppSpacing.s3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.s1),
                    Text(subtitle!,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            if (action != null) action!,
          ],
        ),
      );
}

class WorkspaceNotice extends StatelessWidget {
  const WorkspaceNotice(
      {super.key, required this.message, this.error = false, this.onRetry});
  final String message;
  final bool error;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color:
                error ? colors.errorContainer : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(error ? Icons.error_outline : Icons.info_outline),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ]));
  }
}
