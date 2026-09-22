import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/datasources/api_client.dart';
import '../../../data/models/academic_year_model.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_form_field.dart';
import '../../../shared/widgets/app_modal.dart';
import '../../../shared/widgets/app_page_header.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/responsive_grid.dart';

class AcademicYearsPage extends StatefulWidget {
  const AcademicYearsPage({super.key});
  @override
  State<AcademicYearsPage> createState() => _AcademicYearsPageState();
}

class _AcademicYearsPageState extends State<AcademicYearsPage> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<StoreService>().refreshAcademicOrganization();
    } on Exception catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAddModal() async {
    final store = context.read<StoreService>();
    final nameController = TextEditingController();
    final startController = TextEditingController();
    final endController = TextEditingController();
    final sources = store.getAcademicYears();
    String? sourceYearId = sources.isEmpty
        ? null
        : (store.getActiveAcademicYear()?.id ?? sources.first.id);
    var submitting = false;
    await AppModal.show(
      context: context,
      title: 'Créer une année scolaire',
      maxWidth: 480,
      body: Column(mainAxisSize: MainAxisSize.min, children: [
        AppFormField(
            label: 'Nom *', controller: nameController, hint: '2026-2027'),
        const SizedBox(height: AppSpacing.s4),
        ResponsiveFormGrid(
          children: [
            AppFormField(
                label: 'Date de début *',
                controller: startController,
                hint: 'JJ-MM-AAAA'),
            AppFormField(
                label: 'Date de fin *',
                controller: endController,
                hint: 'JJ-MM-AAAA'),
          ],
        ),
        if (sources.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s4),
          AppSelectField<String>(
            label: 'Reprendre la configuration de',
            value: sourceYearId,
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('Ne rien copier'),
              ),
              ...sources.map((year) => DropdownMenuItem(
                    value: year.id,
                    child: Text(year.name, overflow: TextOverflow.ellipsis),
                  )),
            ],
            onChanged: (value) => sourceYearId = value,
          ),
          const SizedBox(height: AppSpacing.s2),
          const Text(
            'La copie reprend uniquement les classes, coefficients/barèmes, règles, calendrier et affectations des enseignants. Aucun élève, paiement, note ou document n’est copié.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ]),
      footer: StatefulBuilder(builder: (modalContext, setModalState) {
        Future<void> submit() async {
          final name = nameController.text.trim();
          final start = AppDateUtils.parseUserInputStrict(startController.text);
          final end = AppDateUtils.parseUserInputStrict(endController.text);
          if (name.isEmpty ||
              start == null ||
              end == null ||
              !end.isAfter(start)) {
            AppToast.warning(modalContext,
                'Format attendu : JJ-MM-AAAA, avec une fin après le début.');
            return;
          }
          setModalState(() => submitting = true);
          try {
            final service = modalContext.read<StoreService>();
            final created = await service.createAcademicYearRemote(
                name: name,
                start: AppDateUtils.toIso(start),
                end: AppDateUtils.toIso(end));
            var copied = false;
            if (sourceYearId != null) {
              await service.copyAcademicYearConfigurationRemote(
                targetYearId: created.id,
                sourceYearId: sourceYearId!,
              );
              copied = true;
            }
            if (!modalContext.mounted || !mounted) return;
            Navigator.pop(modalContext);
            AppToast.success(
                context,
                copied
                    ? 'Année scolaire créée et configuration reprise.'
                    : 'Année scolaire créée.');
          } on ApiException catch (error) {
            if (modalContext.mounted) {
              AppToast.error(modalContext, error.message);
            }
          } on Exception {
            if (modalContext.mounted) {
              AppToast.error(modalContext, 'Impossible de joindre le serveur.');
            }
          } finally {
            if (modalContext.mounted) setModalState(() => submitting = false);
          }
        }

        return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          AppButton(
              label: 'Annuler',
              variant: AppButtonVariant.secondary,
              onPressed: submitting ? null : () => Navigator.pop(modalContext)),
          const SizedBox(width: AppSpacing.s3),
          AppButton(
              label: submitting ? 'Création...' : 'Créer',
              onPressed: submitting ? null : submit),
        ]);
      }),
    );
  }

  Future<void> _activate(String id, String name) async {
    try {
      await context.read<StoreService>().activateAcademicYearRemote(id);
      if (mounted) {
        AppToast.success(context, '$name est maintenant l’année active.');
      }
    } on ApiException catch (error) {
      if (mounted) AppToast.error(context, error.message);
    } on Exception {
      if (mounted) AppToast.error(context, 'Impossible de joindre le serveur.');
    }
  }

  Future<void> _openEditModal(AcademicYearModel year) async {
    final name = TextEditingController(text: year.name);
    final start = TextEditingController(text: year.start);
    final end = TextEditingController(text: year.end);
    await AppModal.show(
      context: context,
      title: 'Modifier l’année scolaire',
      maxWidth: 480,
      body: Column(mainAxisSize: MainAxisSize.min, children: [
        AppFormField(label: 'Nom *', controller: name),
        const SizedBox(height: AppSpacing.s4),
        ResponsiveFormGrid(
          children: [
            AppFormField(label: 'Date de début *', controller: start),
            AppFormField(label: 'Date de fin *', controller: end),
          ],
        ),
      ]),
      footer: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        AppButton(
            label: 'Annuler',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.pop(context)),
        const SizedBox(width: AppSpacing.s3),
        AppButton(
            label: 'Enregistrer',
            onPressed: () async {
              final from = AppDateUtils.parseUserInputStrict(start.text);
              final to = AppDateUtils.parseUserInputStrict(end.text);
              if (name.text.trim().isEmpty ||
                  from == null ||
                  to == null ||
                  !to.isAfter(from)) {
                AppToast.warning(context,
                    'Format attendu : JJ-MM-AAAA, avec une fin après le début.');
                return;
              }
              try {
                await context.read<StoreService>().updateAcademicYearRemote(
                    id: year.id,
                    name: name.text.trim(),
                    start: AppDateUtils.toIso(from),
                    end: AppDateUtils.toIso(to));
                if (!context.mounted) return;
                Navigator.pop(context);
                AppToast.success(context, 'Année scolaire modifiée.');
              } on ApiException catch (error) {
                if (context.mounted) AppToast.error(context, error.message);
              }
            }),
      ]),
    );
  }

  Future<void> _copyConfiguration(AcademicYearModel target) async {
    final store = context.read<StoreService>();
    final sources = store
        .getAcademicYears()
        .where((year) => year.id != target.id)
        .toList();
    if (sources.isEmpty) {
      AppToast.warning(context, 'Aucune autre année scolaire à copier.');
      return;
    }
    String sourceId = sources.first.id;
    var submitting = false;
    await AppModal.show(
      context: context,
      title: 'Copier une configuration annuelle',
      maxWidth: 560,
      body: StatefulBuilder(
        builder: (modalContext, refresh) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cible : ${target.name}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.s3),
            AppSelectField<String>(
              label: 'Copier depuis',
              value: sourceId,
              items: sources
                  .map((year) => DropdownMenuItem(
                        value: year.id,
                        child: Text(year.name,
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: submitting
                  ? null
                  : (value) {
                      if (value != null) refresh(() => sourceId = value);
                    },
            ),
            const SizedBox(height: AppSpacing.s3),
            const Text(
              'La copie ajoute uniquement la configuration manquante : classes, '
              'matières configurées, barèmes/coefficient, affectations des enseignants, '
              'règles d’évaluation et paramètres du calendrier. Les mêmes enseignants '
              'sont réutilisés sans dupliquer leur identité. Aucun élève, paiement, note, '
              'document ou historique n’est copié.',
            ),
          ],
        ),
      ),
      footer: StatefulBuilder(
        builder: (modalContext, refresh) => Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.s3,
          runSpacing: AppSpacing.s2,
          children: [
            AppButton(
              label: 'Annuler',
              variant: AppButtonVariant.secondary,
              onPressed: submitting ? null : () => Navigator.pop(modalContext),
            ),
            AppButton(
              label: submitting ? 'Copie...' : 'Copier la configuration',
              onPressed: submitting
                  ? null
                  : () async {
                      refresh(() => submitting = true);
                      try {
                        final result = await modalContext
                            .read<StoreService>()
                            .copyAcademicYearConfigurationRemote(
                              targetYearId: target.id,
                              sourceYearId: sourceId,
                            );
                        if (!modalContext.mounted) return;
                        Navigator.pop(modalContext);
                        final created = Map<String, dynamic>.from(
                            result['created'] as Map? ?? const {});
                        final total = created.values.fold<int>(
                            0, (sum, value) => sum + (value as num? ?? 0).toInt());
                        if (mounted) {
                          AppToast.success(context,
                              'Configuration copiée : $total élément(s) ajouté(s).');
                        }
                      } on ApiException catch (error) {
                        if (modalContext.mounted) {
                          AppToast.error(modalContext, error.message);
                        }
                      } on Exception {
                        if (modalContext.mounted) {
                          AppToast.error(modalContext,
                              'Impossible de copier la configuration.');
                        }
                      } finally {
                        if (modalContext.mounted) {
                          refresh(() => submitting = false);
                        }
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(String id, String name) async {
    final confirmed = await ConfirmDialog.show(
        context: context,
        title: 'Supprimer l’année scolaire',
        message:
            'Supprimer « $name » ? Cette action est refusée si elle contient des classes.',
        isDanger: true);
    if (!confirmed || !mounted) return;
    try {
      await context.read<StoreService>().deleteAcademicYearRemote(id);
      if (mounted) AppToast.success(context, 'Année supprimée.');
    } on ApiException catch (error) {
      if (mounted) AppToast.error(context, error.message);
    } on Exception {
      if (mounted) AppToast.error(context, 'Impossible de joindre le serveur.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    final years = store.getAcademicYears();
    final selectedId = store.getSelectedAcademicYearId();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppPageHeader(
          title: 'Années scolaires',
          subtitle:
              'L’année active est métier ; l’année sélectionnée est votre contexte de travail.',
          actions: [
            AppButton(
                label: 'Nouvelle année',
                icon: Icons.add_rounded,
                onPressed: _openAddModal),
          ],
        ),
        const SizedBox(height: AppSpacing.s6),
        if (_loading)
          const Center(
              child:
                  CircularProgressIndicator(key: Key('academic-years-loading')))
        else if (_error != null)
          AppCard(
              child: Column(children: [
            const Text('Impossible de charger les années scolaires.'),
            const SizedBox(height: AppSpacing.s2),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.s3),
            AppButton(label: 'Réessayer', onPressed: _load),
          ]))
        else if (years.isEmpty)
          AppCard(
              child: Column(children: [
            const Icon(Icons.calendar_month_outlined, size: 40),
            const SizedBox(height: AppSpacing.s3),
            const Text('Aucune année scolaire.'),
            const SizedBox(height: AppSpacing.s3),
            AppButton(
                label: 'Créer la première année', onPressed: _openAddModal),
          ]))
        else
          AppCard(
              padding: EdgeInsets.zero,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Année')),
                    DataColumn(label: Text('Début')),
                    DataColumn(label: Text('Fin')),
                    DataColumn(label: Text('État')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: years
                      .map((year) => DataRow(cells: [
                            DataCell(Text(year.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold))),
                            DataCell(Text(year.start)),
                            DataCell(Text(year.end)),
                            DataCell(Wrap(spacing: 6, children: [
                              if (year.isActive)
                                const AppBadge(
                                    label: 'ACTIVE',
                                    variant: AppBadgeVariant.success),
                              if (year.id == selectedId)
                                const AppBadge(
                                    label: 'SÉLECTIONNÉE',
                                    variant: AppBadgeVariant.primary),
                              if (!year.isActive && year.id != selectedId)
                                const AppBadge(
                                    label: 'INACTIVE',
                                    variant: AppBadgeVariant.secondary),
                            ])),
                            DataCell(Row(children: [
                              IconButton(
                                  tooltip: 'Modifier',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _openEditModal(year)),
                              if (year.id != selectedId)
                                IconButton(
                                    key: Key('select-year-${year.id}'),
                                    tooltip: 'Utiliser comme contexte',
                                    icon: const Icon(Icons.visibility_outlined),
                                    onPressed: () => store
                                        .setSelectedAcademicYearId(year.id)),
                              if (years.length > 1)
                                IconButton(
                                    key: Key('copy-year-config-${year.id}'),
                                    tooltip: 'Copier une configuration annuelle',
                                    icon: const Icon(Icons.copy_all_outlined),
                                    onPressed: () => _copyConfiguration(year)),
                              if (!year.isActive)
                                IconButton(
                                    key: Key('activate-year-${year.id}'),
                                    tooltip: 'Définir comme année active',
                                    color: AppColors.success500,
                                    icon:
                                        const Icon(Icons.check_circle_outline),
                                    onPressed: () =>
                                        _activate(year.id, year.name)),
                              if (!year.isActive)
                                IconButton(
                                    tooltip: 'Supprimer',
                                    color: AppColors.danger500,
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () =>
                                        _delete(year.id, year.name)),
                            ])),
                          ]))
                      .toList(),
                ),
              )),
      ]),
    );
  }
}
