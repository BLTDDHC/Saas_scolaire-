import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../data/models/other_models.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/workspace_header.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (_loading || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<StoreService>().refreshWorkflowNotificationsRemote();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Impossible de charger les notifications.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _composeTeacherNotification(StoreService store) async {
    final title = TextEditingController();
    final message = TextEditingController();
    var category = 'administrative';
    var sending = false;
    final sent = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Notifier les enseignants'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Titre *'),
                    maxLength: 160,
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Catégorie *'),
                    items: const [
                      DropdownMenuItem(
                          value: 'administrative',
                          child: Text('Information administrative')),
                      DropdownMenuItem(
                          value: 'grades', child: Text('Notes / résultats')),
                      DropdownMenuItem(
                          value: 'deadline', child: Text('Échéance')),
                      DropdownMenuItem(
                          value: 'information', child: Text('Information')),
                    ],
                    onChanged: sending
                        ? null
                        : (value) =>
                            setDialogState(() => category = value ?? category),
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  TextField(
                    controller: message,
                    decoration: const InputDecoration(labelText: 'Message *'),
                    minLines: 4,
                    maxLines: 8,
                    maxLength: 4000,
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Seuls les enseignants actifs de votre périmètre autorisé recevront cette notification.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  sending ? null : () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton.icon(
              onPressed: sending
                  ? null
                  : () async {
                      if (title.text.trim().isEmpty ||
                          message.text.trim().isEmpty) {
                        AppToast.warning(
                            context, 'Renseignez le titre et le message.');
                        return;
                      }
                      setDialogState(() => sending = true);
                      try {
                        final result = await store.notifyTeachersInApp(
                          title: title.text,
                          message: message.text,
                          category: category,
                        );
                        if (!context.mounted) return;
                        Navigator.pop(dialogContext, true);
                        AppToast.success(
                          context,
                          '${result['recipientCount'] ?? 0} enseignant(s) notifié(s).',
                        );
                      } catch (error) {
                        if (context.mounted) {
                          AppToast.error(context,
                              'Envoi refusé : ${AppToast.humanErrorMessage(error.toString())}');
                          setDialogState(() => sending = false);
                        }
                      }
                    },
              icon: sending
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded),
              label: Text(sending ? 'Envoi…' : 'Envoyer'),
            ),
          ],
        ),
      ),
    );
    title.dispose();
    message.dispose();
    if (sent == true && mounted) await _load();
  }

  String _typeLabel(String? type) => const {
        'grade_entry_open': 'Saisie des notes',
        'evaluation_submitted': 'Notes soumises',
        'results_ready': 'Résultats',
        'results_available': 'Résultats disponibles',
        'teacher_announcement': 'Information',
      }[type] ??
      (type == null || type.isEmpty ? 'Information' : type);

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    final items = store.getNotifications().toList()
      ..sort((left, right) => right.time.compareTo(left.time));
    final unread = items.where((item) => !item.read).length;
    final isAdmin = store.currentUser?.role == UserRole.admin;

    return WorkspacePage(
      title: 'Notifications',
      subtitle:
          'Informations personnelles et alertes liées à votre activité scolaire',
      actions: [
        if (isAdmin)
          AppButton(
            label: 'Notifier les enseignants',
            icon: Icons.campaign_outlined,
            onPressed:
                _loading ? null : () => _composeTeacherNotification(store),
          ),
        if (unread > 0)
          AppButton(
            label: 'Tout marquer comme lu',
            icon: Icons.done_all_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: () => store.markAllNotificationsAsRead(
                schoolId: store.currentUser?.schoolId),
          ),
        IconButton.filledTonal(
          tooltip: 'Actualiser',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          AppCard(
            child: Row(
              children: [
                Expanded(child: Text(_error!)),
                TextButton(onPressed: _load, child: const Text('Réessayer')),
              ],
            ),
          ),
        if (items.isEmpty && !_loading)
          const AppEmptyState(
            iconData: Icons.notifications_none_rounded,
            title: 'Aucune notification',
            message:
                'Les notifications qui vous concernent apparaîtront ici.',
          )
        else if (items.isNotEmpty)
          AppCard(
            title: unread == 0
                ? 'Toutes les notifications sont lues'
                : '$unread notification(s) non lue(s)',
            child: Column(
              children: items.map((NotificationModel item) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Icon(item.read
                        ? Icons.notifications_none_rounded
                        : Icons.notifications_active_rounded),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: TextStyle(
                              fontWeight: item.read
                                  ? FontWeight.w500
                                  : FontWeight.w700),
                        ),
                      ),
                      AppBadge(
                        label: _typeLabel(item.type),
                        variant: item.read
                            ? AppBadgeVariant.secondary
                            : AppBadgeVariant.primary,
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((item.message ?? '').isNotEmpty) Text(item.message!),
                      const SizedBox(height: 4),
                      Text(item.time),
                    ],
                  ),
                  trailing: item.read
                      ? null
                      : IconButton(
                          tooltip: 'Marquer comme lu',
                          onPressed: () =>
                              store.markNotificationAsRead(item.id),
                          icon: const Icon(Icons.done_rounded),
                        ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
