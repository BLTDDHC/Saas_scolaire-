import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/services/store_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/responsive_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_modal.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/responsive_grid.dart';
import 'bulletin_generator.dart';
import 'document_history.dart';
import 'document_reports_panel.dart';
import '../../../shared/widgets/workspace_header.dart';

/// Item de template de document
class DocTemplateItem {
  final String id;
  final String title;
  final String description;
  final String icon;
  final String category;

  const DocTemplateItem({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.category,
  });
}

/// Page de Génération de Documents (12 templates) — Adaptative (Desktop, Tablette, Mobile)
class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key});

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();

  static const templates = _DocumentsPageState.templates;
}

class _DocumentsPageState extends State<DocumentsPage> {
  int _historyVersion = 0;

  static const templates = [
    DocTemplateItem(
      id: 'cert_scolarite',
      title: 'Certificat de Scolarité',
      description: 'Atteste l\'inscription de l\'élève pour l\'année en cours',
      icon: '📄',
      category: 'Élèves',
    ),
    DocTemplateItem(
      id: 'attestation_inscription',
      title: 'Attestation d\'Inscription',
      description: 'Document officiel d\'admission et de paiement',
      icon: '📑',
      category: 'Élèves',
    ),
    DocTemplateItem(
      id: 'bulletin_notes',
      title: 'Bulletin de Notes',
      description: 'Relevé des notes et appréciations du trimestre/semestre',
      icon: '📊',
      category: 'Évaluations',
    ),
    DocTemplateItem(
      id: 'releve_notes',
      title: 'Relevé de Notes Officiel',
      description: 'Synthèse annuelle complète des résultats',
      icon: '📈',
      category: 'Évaluations',
    ),
    DocTemplateItem(
      id: 'fiche_eleve',
      title: 'Fiche Renseignement Élève',
      description: 'Données personnelles, tuteurs et coordonnées',
      icon: '👨‍🎓',
      category: 'Élèves',
    ),
    DocTemplateItem(
      id: 'liste_classe',
      title: 'Liste Officielle de Classe',
      description: 'Liste d\'appel avec effectif et professeurs',
      icon: '📋',
      category: 'Classes',
    ),
    DocTemplateItem(
      id: 'emploi_du_temps',
      title: 'Emploi du Temps Imprimable',
      description: 'Planning hebdomadaire au format A4',
      icon: '🗓️',
      category: 'Planning',
    ),
    DocTemplateItem(
      id: 'feuille_presence',
      title: 'Feuille de Présence Mensuelle',
      description: 'Grille d\'émargement pour le contrôle des absences',
      icon: '⏱️',
      category: 'Planning',
    ),
    DocTemplateItem(
      id: 'fiche_enseignant',
      title: 'Fiche Enseignant',
      description: 'Coordonnées, diplômes et matières enseignées',
      icon: '👨‍🏫',
      category: 'Enseignants',
    ),
    DocTemplateItem(
      id: 'attestation_affectation',
      title: 'Attestation d\'Affectation',
      description: 'Liaison officielle professeur - classe',
      icon: '📌',
      category: 'Enseignants',
    ),
    DocTemplateItem(
      id: 'recu_paiement',
      title: 'Reçu de Paiement Scolaire',
      description: 'Justificatif officiel de règlement de frais',
      icon: '🧾',
      category: 'Finance',
    ),
    DocTemplateItem(
      id: 'attestation_reussite',
      title: 'Attestation de Réussite / Diplôme',
      description:
          'Attestation de fin de cycle ou passage en classe supérieure',
      icon: '🎓',
      category: 'Évaluations',
    ),
  ];

  void _previewDocument(BuildContext context, DocTemplateItem template) {
    if (template.id == 'bulletin_notes') {
      // Open bulletin generator modal
      AppModal.show(
        context: context,
        title: 'Générateur de bulletin — ${template.title}',
        maxWidth: 900,
        body: BulletinGenerator(onGenerated: () {
          if (mounted) {
            setState(() => _historyVersion++);
            AppToast.success(context, 'Bulletin généré');
          }
        }),
        footer: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              label: 'Fermer',
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: AppSpacing.s3),
            AppButton(
              label: 'Aide',
              variant: AppButtonVariant.primary,
              onPressed: () {
                AppToast.info(context,
                    'Sélectionnez la classe, l\'élève et la période puis cliquez sur Générer.');
              },
            ),
          ],
        ),
      );
      return;
    }

    AppToast.info(context,
        'Ce modèle ne dispose pas encore d’une génération reliée aux données. Aucun document n’a été émis.');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = ContextUtils.isMobile(context);
    final role = context.watch<StoreService>().currentUser?.role;
    final canGenerate = role == UserRole.admin || role == UserRole.superadmin;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.s4 : AppSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WorkspaceHeader(
              title: 'Documents scolaires',
              subtitle:
                  'Retrouvez les documents émis et préparez les bulletins à partir des résultats officiels.'),
          if (canGenerate)
            AppCard(
                title: 'Bulletins de notes',
                subtitle:
                    'Choisissez la classe, l’élève et le trimestre. Aucun résultat provisoire n’est présenté comme officiel.',
                child: FilledButton.icon(
                    onPressed: () => _previewDocument(context,
                        templates.firstWhere((t) => t.id == 'bulletin_notes')),
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('Préparer un bulletin'))),
          if (!canGenerate)
            const WorkspaceNotice(
                message:
                    'Consultez les documents et reçus liés à votre profil. La génération reste réservée à l’administration.'),
          const SizedBox(height: 24),
          DocumentHistory(key: ValueKey(_historyVersion)),
          if (canGenerate) ...[
            const SizedBox(height: AppSpacing.s5),
            DocumentReportsPanel(
              onGenerated: () {
                if (mounted) setState(() => _historyVersion++);
              },
            ),
          ],
          const SizedBox(height: AppSpacing.s6),

          // Grid des 12 templates adaptative
          if (canGenerate)
            ExpansionTile(
                title: const Text('Autres modèles — indisponibles'),
                subtitle: const Text(
                    'Ces modèles ne sont pas encore reliés à une génération officielle.'),
                children: [
                  ResponsiveGrid(
                    desktopColumns: 4,
                    tabletColumns: 2,
                    mobileColumns: 1,
                    children: templates
                        .where((t) => t.id != 'bulletin_notes')
                        .map((t) {
                      return AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(t.icon,
                                    style: const TextStyle(fontSize: 22)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    t.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.s2),
                            Text(
                              t.description,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: AppSpacing.s3),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                AppButton(
                                  label: t.id == 'bulletin_notes'
                                      ? 'Générer'
                                      : 'Indisponible',
                                  size: AppButtonSize.small,
                                  icon: Icons.description_rounded,
                                  variant: AppButtonVariant.primary,
                                  onPressed: t.id == 'bulletin_notes'
                                      ? () => _previewDocument(context, t)
                                      : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  )
                ]),
        ],
      ),
    );
  }
}
