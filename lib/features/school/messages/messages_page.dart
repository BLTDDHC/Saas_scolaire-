import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/establishment_types.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/other_models.dart';
import '../../../data/services/store_service.dart';
import '../../../data/datasources/api_client.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_form_field.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/app_modal.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/workspace_header.dart';

/// Announcements only: the school does not provide private student chat.
class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    final role = store.currentUser?.role;
    final canPublish = role == UserRole.superadmin ||
        role == UserRole.admin ||
        role == UserRole.teacher;
    final canSendExternal =
        role == UserRole.superadmin || role == UserRole.admin;
    final announcements = store.getAnnouncements();
    return WorkspacePage(
      title: role == UserRole.student ? 'Mes annonces' : 'Communication',
      subtitle: role == UserRole.student
          ? 'Informations publiées par votre établissement'
          : 'Diffusez une information claire aux personnes concernées',
      actions: [
        if (canSendExternal)
          AppButton(
              label: 'Notification externe',
              icon: Icons.send_outlined,
              variant: AppButtonVariant.secondary,
              onPressed: () => _sendExternal(context)),
        if (canPublish)
          AppButton(
              label: 'Nouvelle annonce',
              icon: Icons.campaign_outlined,
              onPressed: () => _publish(context)),
      ],
      children: [
        if (announcements.isEmpty)
          const AppEmptyState(
            iconData: Icons.campaign_outlined,
            title: 'Aucune annonce pour le moment.',
            message: 'Les nouvelles informations apparaîtront ici.',
          )
        else
          ...announcements.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s3),
                child: AppCard(
                    child: ListTile(
                  title: Text(item.title),
                  subtitle: Text(
                      '${item.content ?? ''}\n${item.author ?? 'Établissement'} · ${AppDateUtils.formatNumeric(item.date)}'),
                  isThreeLine: true,
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.thumb_up_outlined),
                    label: Text('${item.reactions.length}'),
                    onPressed: () async {
                      final ok =
                          await store.reactToAnnouncement(item.id, 'like');
                      if (context.mounted && !ok)
                        AppToast.error(context,
                            'La réaction n’a pas pu être enregistrée.');
                    },
                  ),
                )),
              )),
      ],
    );
  }

  Future<void> _sendExternal(BuildContext context) async {
    final recipient = TextEditingController();
    final subject = TextEditingController();
    final message = TextEditingController();
    var channel = 'email';
    await AppModal.show(
      context: context,
      title: 'Envoyer une notification externe',
      maxWidth: 620,
      body: StatefulBuilder(
        builder: (modalContext, refresh) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSelectField<String>(
              label: 'Canal',
              value: channel,
              items: const [
                DropdownMenuItem(value: 'email', child: Text('E-mail')),
                DropdownMenuItem(value: 'sms', child: Text('SMS')),
                DropdownMenuItem(value: 'whatsapp', child: Text('WhatsApp')),
              ],
              onChanged: (value) {
                if (value != null) refresh(() => channel = value);
              },
            ),
            const SizedBox(height: AppSpacing.s4),
            AppFormField(
              label: channel == 'email' ? 'Adresse e-mail' : 'Numéro international',
              hint: channel == 'email' ? 'parent@exemple.com' : '+242...',
              controller: recipient,
            ),
            if (channel == 'email') ...[
              const SizedBox(height: AppSpacing.s4),
              AppFormField(label: 'Objet', controller: subject),
            ],
            const SizedBox(height: AppSpacing.s4),
            AppFormField(label: 'Message', controller: message, maxLines: 5),
            const SizedBox(height: AppSpacing.s3),
            const Text(
              'L’envoi n’est déclaré réussi que si le fournisseur configuré l’accepte.',
            ),
          ],
        ),
      ),
      footer: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        AppButton(
          label: 'Annuler',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.pop(context),
        ),
        const SizedBox(width: AppSpacing.s3),
        AppButton(
          label: 'Vérifier et envoyer',
          onPressed: () async {
            if (recipient.text.trim().isEmpty || message.text.trim().isEmpty) {
              AppToast.warning(context, 'Destinataire et message sont obligatoires.');
              return;
            }
            final confirmed = await ConfirmDialog.show(
              context: context,
              title: 'Confirmer l’envoi',
              message: 'Envoyer cette notification par ${channel.toUpperCase()} à ${recipient.text.trim()} ?',
            );
            if (!confirmed || !context.mounted) return;
            try {
              final result = await context.read<StoreService>().sendExternalNotification(
                    channel: channel,
                    recipient: recipient.text.trim(),
                    subject: subject.text.trim(),
                    message: message.text.trim(),
                  );
              if (!context.mounted) return;
              Navigator.pop(context);
              AppToast.success(context,
                  'Envoi accepté par ${result['provider'] ?? 'le fournisseur'} (${result['status'] ?? 'accepted'}).');
            } on ApiException catch (error) {
              if (context.mounted) AppToast.error(context, error.message);
            } on Exception {
              if (context.mounted) {
                AppToast.error(context, 'L’envoi externe a échoué.');
              }
            }
          },
        ),
      ]),
    );
  }

  void _publish(BuildContext context) {
    final title = TextEditingController();
    final content = TextEditingController();
    final store = context.read<StoreService>();
    String? classId;
    String? targetRole;
    final cycle = TextEditingController();
    final level = TextEditingController();
    showDialog(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
                  title: const Text('Nouvelle annonce'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    AppFormField(label: 'Titre', controller: title),
                    const SizedBox(height: AppSpacing.s4),
                    AppFormField(
                        label: 'Contenu', controller: content, maxLines: 3),
                    const SizedBox(height: AppSpacing.s4),
                    DropdownButtonFormField<String?>(
                      isExpanded: true,
                        value: targetRole,
                        decoration: const InputDecoration(
                            labelText: 'Rôle ciblé (optionnel)'),
                        items: const [
                          DropdownMenuItem(
                              value: null, child: Text('Tout l’établissement')),
                          DropdownMenuItem(
                              value: 'student', child: Text('Élèves')),
                          DropdownMenuItem(
                              value: 'parent', child: Text('Parents')),
                          DropdownMenuItem(
                              value: 'teacher', child: Text('Enseignants'))
                        ],
                        onChanged: (value) =>
                            setDialogState(() => targetRole = value)),
                    const SizedBox(height: AppSpacing.s4),
                    DropdownButtonFormField<String?>(
                      isExpanded: true,
                        value: classId,
                        decoration: const InputDecoration(
                            labelText: 'Classe ciblée (optionnelle)'),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('Toutes les classes')),
                          ...store.getClasses().map((item) => DropdownMenuItem(
                              value: item.id, child: Text(item.name)))
                        ],
                        onChanged: (value) =>
                            setDialogState(() => classId = value)),
                    const SizedBox(height: AppSpacing.s4),
                    AppFormField(
                        label: 'Cycle ciblé (optionnel)', controller: cycle),
                    const SizedBox(height: AppSpacing.s4),
                    AppFormField(
                        label: 'Niveau ciblé (optionnel)', controller: level),
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Annuler')),
                    AppButton(
                        label: 'Publier',
                        onPressed: () async {
                          if (title.text.trim().isEmpty) {
                            AppToast.warning(
                                dialogContext, 'Le titre est obligatoire.');
                            return;
                          }
                          final current = store.currentUser!;
                          final ok =
                              await store.saveAnnouncement(AnnouncementModel(
                            id: 'AN_${DateTime.now().microsecondsSinceEpoch}',
                            title: title.text.trim(),
                            content: content.text.trim(),
                            author: current.name,
                            authorUserId: current.id,
                            schoolId: current.schoolId,
                            date: DateTime.now().toIso8601String(),
                            priority: 'normal',
                            classId: classId,
                            targetRole: targetRole,
                            cycle: cycle.text.trim().isEmpty
                                ? null
                                : cycle.text.trim(),
                            levelId: level.text.trim().isEmpty
                                ? null
                                : level.text.trim(),
                          ));
                          if (!dialogContext.mounted) return;
                          if (!ok) {
                            AppToast.error(dialogContext,
                                'L’annonce n’a pas pu être enregistrée.');
                            return;
                          }
                          Navigator.pop(dialogContext);
                        }),
                  ],
                )));
  }
}
