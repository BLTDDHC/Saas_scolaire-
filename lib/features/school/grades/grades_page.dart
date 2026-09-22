import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/grade_model.dart';
import '../../../data/models/evaluation_model.dart';
import '../../../data/models/student_model.dart';
import '../../../data/models/subject_model.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_form_field.dart';
import '../../../shared/widgets/app_toast.dart';

/// Page des Notes & Évaluations — Cycle de vie strict, configuration par l'établissement et fiches grisées
class GradesPage extends StatefulWidget {
  const GradesPage({super.key});

  @override
  State<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends State<GradesPage>
    with SingleTickerProviderStateMixin {
  String? _selectedClass;
  String? _selectedSubject;
  String? _selectedPeriodId;
  EvaluationModel? _currentEvaluation;

  // Filtre de vue pour l'enseignant : 'actives' (En cours & À corriger) vs 'archives' (Clôturées & Validées)
  String _teacherViewFilter = 'actives';

  // Mode de vue pour l'administrateur : 'consultation', 'a_valider', 'config'
  String _adminViewMode = 'consultation';

  final Map<String, TextEditingController> _gradeControllers = {};
  final Map<String, String> _presenceMap =
      {}; // studentId -> 'present' | 'absent'

  @override
  void dispose() {
    for (final c in _gradeControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _loadGradesForEvaluation(
      EvaluationModel evaluation, StoreService store) {
    for (final c in _gradeControllers.values) {
      c.dispose();
    }
    _gradeControllers.clear();
    _presenceMap.clear();

    final students = store
        .getStudents()
        .where((s) => s.classId == evaluation.classId)
        .toList();
    final grades = store.getGradesByEvaluation(evaluation.id);

    for (final s in students) {
      final g = grades.firstWhere(
        (gr) => gr.studentId == s.id,
        orElse: () => GradeModel(
            id: '', studentId: '', subjectId: '', eval: '', grade: null),
      );

      if (g.id.isNotEmpty) {
        _gradeControllers[s.id] = TextEditingController(
          text: g.grade != null
              ? (g.grade! % 1 == 0
                  ? g.grade!.toInt().toString()
                  : g.grade.toString())
              : '',
        );
        _presenceMap[s.id] =
            g.presence ?? (g.grade != null ? 'present' : 'present');
      } else {
        _gradeControllers[s.id] = TextEditingController(text: '');
        _presenceMap[s.id] = 'present';
      }
    }
    setState(() {
      _currentEvaluation = evaluation;
    });
  }

  Future<bool> _saveDraftGrades(StoreService store,
      {bool showToast = true}) async {
    if (_currentEvaluation == null || _selectedSubject == null) return false;

    final maxScore = _currentEvaluation!.maxScore;
    final students =
        store.getStudents().where((s) => s.classId == _selectedClass).toList();
    int errors = 0;
    final pending = <GradeModel>[];

    for (final s in students) {
      final studentId = s.id;
      final controller = _gradeControllers[studentId];
      final presence = _presenceMap[studentId] ?? 'present';
      final existing = store.getGradeByStudentAndEvaluation(
          studentId, _currentEvaluation!.id);

      if (presence == 'absent') {
        final gradeModel = GradeModel(
          id: existing?.id ?? '',
          studentId: studentId,
          subjectId: _selectedSubject!,
          eval: _currentEvaluation!.title,
          grade: null,
          evaluationId: _currentEvaluation!.id,
          presence: 'absent',
          enteredBy: store.currentUser?.id ?? '',
          academicYearId: store.getSelectedAcademicYearId(),
        );
        pending.add(gradeModel);
        continue;
      }

      final rawText = controller?.text.trim() ?? '';
      if (rawText.isEmpty) {
        pending.add(GradeModel(
          id: existing?.id ?? '',
          studentId: studentId,
          subjectId: _selectedSubject!,
          eval: _currentEvaluation!.title,
          grade: null,
          evaluationId: _currentEvaluation!.id,
          presence: 'not_recorded',
          enteredBy: store.currentUser?.id ?? '',
          academicYearId: store.getSelectedAcademicYearId(),
        ));
        continue;
      }

      final val = double.tryParse(rawText.replaceAll(',', '.'));
      if (val == null || val < 0 || val > maxScore) {
        errors++;
        continue;
      }

      final gradeModel = GradeModel(
        id: existing?.id ?? '',
        studentId: studentId,
        subjectId: _selectedSubject!,
        eval: _currentEvaluation!.title,
        grade: val,
        evaluationId: _currentEvaluation!.id,
        presence: 'present',
        enteredBy: store.currentUser?.id ?? '',
        academicYearId: store.getSelectedAcademicYearId(),
      );

      pending.add(gradeModel);
    }

    if (errors > 0) {
      if (showToast) {
        AppToast.error(
            context,
            '$errors note(s) invalides — respectez le barème ' +
                maxScore.toStringAsFixed(0) +
                '.');
      }
      return false;
    }
    if (pending.isEmpty) return false;
    try {
      final saved = await store.saveEvaluationGradesRemote(
          _currentEvaluation!.id, pending);
      if (showToast && mounted) {
        AppToast.success(
            context,
            'Notes enregistrées dans PostgreSQL (' +
                saved.length.toString() +
                ').');
      }
      return true;
    } catch (error) {
      if (showToast && mounted) {
        AppToast.error(context, 'Enregistrement refusé : $error');
      }
      return false;
    }
  }

  void _showCloseConfirmationDialog(
      BuildContext context, StoreService store, List<StudentModel> students) {
    if (_currentEvaluation == null) return;

    final maxScore = _currentEvaluation!.maxScore;
    int gradedCount = 0;
    int absentCount = 0;
    int unrecordedCount = 0;
    List<String> invalidStudents = [];

    for (final s in students) {
      final presence = _presenceMap[s.id] ?? 'present';
      if (presence == 'absent') {
        absentCount++;
        continue;
      }
      final text = _gradeControllers[s.id]?.text.trim() ?? '';
      if (text.isEmpty) {
        unrecordedCount++;
      } else {
        final val = double.tryParse(text.replaceAll(',', '.'));
        if (val == null || val < 0 || val > maxScore) {
          invalidStudents.add('${s.fullName} (valeur invalide : "$text")');
        } else {
          gradedCount++;
        }
      }
    }

    if (invalidStudents.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text('Impossible de clôturer'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Certaines notes dépassent le barème (/$maxScore) ou sont invalides :',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...invalidStudents.take(5).map((msg) => Text('• $msg')),
              if (invalidStudents.length > 5)
                Text('... et ${invalidStudents.length - 5} autre(s).'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Compris'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.lock_clock_rounded, color: Color(0xFF3B82F6)),
            const SizedBox(width: 8),
            Text('Clôturer ${_currentEvaluation!.title}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Vous êtes sur le point de clôturer la saisie des notes pour cette évaluation.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• Total élèves : ${students.length}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('• Notes saisies : $gradedCount',
                      style: const TextStyle(
                          color: Colors.green, fontWeight: FontWeight.w600)),
                  Text('• Absents : $absentCount',
                      style: const TextStyle(
                          color: Colors.orange, fontWeight: FontWeight.w600)),
                  Text('• Non renseignés : $unrecordedCount',
                      style: TextStyle(
                          color: unrecordedCount > 0 ? Colors.red : Colors.grey,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚠️ Après clôture, la fiche sera grisée et vous ne pourrez plus modifier directement les notes.',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          AppButton(
            label: 'Confirmer la clôture',
            icon: Icons.check_circle_outline,
            variant: AppButtonVariant.primary,
            onPressed: () async {
              Navigator.pop(ctx);
              final saved = await _saveDraftGrades(store, showToast: false);
              if (!saved) {
                if (context.mounted) {
                  AppToast.error(
                      context, 'Les notes n’ont pas pu être enregistrées.');
                }
                return;
              }
              try {
                final updated = await store.changeEvaluationStatusRemote(
                    _currentEvaluation!.id, 'submitted');
                if (!context.mounted) return;
                setState(() {
                  _currentEvaluation = updated;
                });
                AppToast.success(context,
                    'Évaluation clôturée et transmise pour validation.');
              } catch (error) {
                if (context.mounted) {
                  AppToast.error(context, 'Échec de la clôture : $error');
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(
      BuildContext context, StoreService store, EvaluationModel ev) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.cancel_outlined, color: Colors.red),
            const SizedBox(width: 8),
            Text('Rejeter ${ev.title}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Veuillez indiquer le motif obligatoire du rejet :'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                hintText:
                    'Ex: Vérifier la note de Jean, revoir la saisie de Marie...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          AppButton(
            label: 'Rejeter l\'évaluation',
            variant: AppButtonVariant.danger,
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                AppToast.error(context, 'Le motif du rejet est obligatoire.');
                return;
              }
              Navigator.pop(ctx);
              try {
                final updated = await store.changeEvaluationStatusRemote(
                    ev.id, 'rejected',
                    reason: reason);
                if (!context.mounted) return;
                setState(() {
                  if (_currentEvaluation?.id == ev.id) {
                    _currentEvaluation = updated;
                  }
                });
                AppToast.success(context,
                    'Évaluation rejetée avec notification envoyée à l\'enseignant.');
              } catch (error) {
                if (context.mounted) {
                  AppToast.error(
                      context, 'Impossible de rejeter l\'évaluation : $error');
                }
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final store = context.watch<StoreService>();

    final allClasses = store.getClasses();
    final allSubjects = store.getSubjects();
    final allStudents = store.getStudents();
    final currentUser = store.currentUser;
    final yearId = store.getSelectedAcademicYearId() ?? '';

    List classes = allClasses;
    List subjects = allSubjects;

    final hasTeachersInSchool = store
        .getTeachers()
        .any((t) => t.schoolId == (store.getCurrentSchool()?.id ?? ''));

    final isTeacher =
        currentUser != null && currentUser.role == UserRole.teacher;
    final isAdmin = store.isSuperAdmin() ||
        (currentUser != null && currentUser.role == UserRole.admin);

    if (!store.isSuperAdmin() && isTeacher) {
      classes = allClasses
          .where((c) => store.isTeacherAssignedTo(
              teacherId: currentUser.id, classId: c.id, academicYearId: yearId))
          .toList();
      subjects = allSubjects
          .where((s) => store.isTeacherAssignedTo(
              teacherId: currentUser.id,
              subjectId: s.id,
              academicYearId: yearId))
          .toList();
    } else if (!hasTeachersInSchool && isAdmin) {
      classes = allClasses;
      subjects = allSubjects;
    }

    _selectedClass ??= classes.isNotEmpty
        ? (classes.first is Map ? classes.first['id'] : classes.first.id)
        : null;
    _selectedSubject ??= subjects.isNotEmpty
        ? (subjects.first is Map ? subjects.first['id'] : subjects.first.id)
        : null;
    _selectedPeriodId ??= 'T1';

    // Générer/assurer automatiquement les évaluations prévues par l'établissement
    if (_selectedClass != null &&
        _selectedSubject != null &&
        _selectedPeriodId != null &&
        yearId.isNotEmpty) {
      store.ensureEvaluationsGenerated(
        classId: _selectedClass!,
        subjectId: _selectedSubject!,
        periodId: _selectedPeriodId!,
        academicYearId: yearId,
      );
    }

    final filteredStudents = _selectedClass != null
        ? allStudents.where((s) => s.classId == _selectedClass).toList()
        : <StudentModel>[];

    // Récupérer les évaluations de ce contexte
    final evaluationsForContext =
        (_selectedClass != null && _selectedSubject != null)
            ? store.getEvaluationsForContext(
                classId: _selectedClass!,
                subjectId: _selectedSubject!,
                periodId: _selectedPeriodId,
                academicYearId: yearId,
              )
            : <EvaluationModel>[];

    // Auto-sélection de la première évaluation active ou de la première évaluation
    if (_currentEvaluation == null ||
        _currentEvaluation!.classId != _selectedClass ||
        _currentEvaluation!.subjectId != _selectedSubject ||
        _currentEvaluation!.periodId != _selectedPeriodId) {
      if (evaluationsForContext.isNotEmpty) {
        // Enseignant : préférer une évaluation en cours ou à corriger
        EvaluationModel candidate = evaluationsForContext.first;
        if (isTeacher) {
          final activeCandidate = evaluationsForContext.firstWhere(
            (e) => e.status == 'draft' || e.status == 'rejected',
            orElse: () => evaluationsForContext.first,
          );
          candidate = activeCandidate;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadGradesForEvaluation(candidate, store);
        });
      }
    }

    final evalStatus = _currentEvaluation?.status ?? 'none';
    final isClosedOrValidated = evalStatus == 'submitted' ||
        evalStatus == 'validated' ||
        evalStatus == 'locked';
    final canTeacherEdit =
        isTeacher && (evalStatus == 'draft' || evalStatus == 'rejected');

    // List of evaluations to validate for Admin view
    final allSchoolEvaluations = store.getEvaluations();
    final evalsAwaitingValidation =
        allSchoolEvaluations.where((e) => e.status == 'submitted').toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête principal
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: AppSpacing.s3,
            runSpacing: AppSpacing.s3,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notes & Évaluations',
                    style: AppTypography.heading2(
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isTeacher
                        ? 'Saisie des notes sur les évaluations prévues par l\'établissement'
                        : 'Supervision, validation administrative et configuration des évaluations',
                    style: AppTypography.bodySmall(
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.lightTextTertiary,
                    ),
                  ),
                ],
              ),

              // Menu sélecteur pour Administrateur
              if (isAdmin)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildAdminNavButton(
                      title: 'Consultation & Notes',
                      icon: Icons.edit_note_rounded,
                      isSelected: _adminViewMode == 'consultation',
                      onTap: () =>
                          setState(() => _adminViewMode = 'consultation'),
                    ),
                    const SizedBox(width: 8),
                    _buildAdminNavButton(
                      title: 'À Valider (${evalsAwaitingValidation.length})',
                      icon: Icons.pending_actions_rounded,
                      isSelected: _adminViewMode == 'a_valider',
                      badgeCount: evalsAwaitingValidation.length,
                      onTap: () => setState(() => _adminViewMode = 'a_valider'),
                    ),
                    const SizedBox(width: 8),
                    _buildAdminNavButton(
                      title: '⚙️ Configuration',
                      icon: Icons.settings_suggest_rounded,
                      isSelected: _adminViewMode == 'config',
                      onTap: () => setState(() => _adminViewMode = 'config'),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),

          // SI MODE ADMINISTRATEUR = CONFIGURATION DES PÉRIODES
          if (isAdmin && _adminViewMode == 'config') ...[
            _buildAdminConfigSection(context, store, yearId, isDark),
          ]
          // SI MODE ADMINISTRATEUR = ÉVALUATIONS À VALIDER
          else if (isAdmin && _adminViewMode == 'a_valider') ...[
            _buildAdminValidationQueueSection(
                context, store, evalsAwaitingValidation, isDark),
          ]
          // VUE DE SAISIE & CONSULTATION (Enseignant et Admin)
          else ...[
            // Sélecteur pour Enseignant : Mes Évaluations vs Archives
            if (isTeacher) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildTeacherFilterChip(
                    label: '🟢 Mes Évaluations Actives',
                    isSelected: _teacherViewFilter == 'actives',
                    onTap: () => setState(() => _teacherViewFilter = 'actives'),
                  ),
                  _buildTeacherFilterChip(
                    label: '🩶 Archives (Clôturées / Validées)',
                    isSelected: _teacherViewFilter == 'archives',
                    onTap: () =>
                        setState(() => _teacherViewFilter = 'archives'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s4),
            ],

            // Barre de Filtres : Classe, Matière, Période
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.s4),
              child: Wrap(
                spacing: AppSpacing.s4,
                runSpacing: AppSpacing.s4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    child: AppSelectField<String?>(
                      label: 'Classe',
                      value: _selectedClass,
                      items: classes
                          .map((c) => DropdownMenuItem<String?>(
                              value: c.id as String?, child: Text(c.name)))
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedClass = val;
                          _currentEvaluation = null;
                          _gradeControllers.clear();
                          _presenceMap.clear();
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: AppSelectField<String?>(
                      label: 'Matière',
                      value: _selectedSubject,
                      items: subjects
                          .map((s) => DropdownMenuItem<String?>(
                                value: s.id as String?,
                                child: Text(
                                    '${s.icon ?? "📚"} ${s.name} (Coef ${s.coefficient})'),
                              ))
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedSubject = val;
                          _currentEvaluation = null;
                          _gradeControllers.clear();
                          _presenceMap.clear();
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: Builder(builder: (ctx) {
                      final periodConfigs = store.getEvaluationPeriodConfigs(
                          academicYearId: yearId);
                      final items = periodConfigs.map((cfg) {
                        String prefix = cfg.status == 'active'
                            ? '🟢 '
                            : (cfg.status == 'closed' ? '🩶 ' : '🔒 ');
                        String suffix = cfg.status == 'active'
                            ? ' (Actif)'
                            : (cfg.status == 'closed'
                                ? ' (Clôturé)'
                                : ' (Verrouillé)');
                        return DropdownMenuItem<String?>(
                          value: cfg.periodId,
                          child: Text('$prefix${cfg.periodName}$suffix'),
                        );
                      }).toList();
                      return AppSelectField<String?>(
                        label: 'Période',
                        value: _selectedPeriodId,
                        items: items,
                        onChanged: (val) {
                          setState(() {
                            _selectedPeriodId = val;
                            _currentEvaluation = null;
                            _gradeControllers.clear();
                            _presenceMap.clear();
                          });
                        },
                      );
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s6),

            // BARRE DES ÉVALUATIONS PRÉVUES PAR L'ÉTABLISSEMENT
            if (_selectedClass != null && _selectedSubject != null) ...[
              AppCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s4, vertical: AppSpacing.s3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.rule_folder_outlined,
                                size: 18,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary),
                            const SizedBox(width: 8),
                            Text(
                              'Évaluations prévues pour la période',
                              style: AppTypography.caption(
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary,
                              ).copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5),
                            ),
                          ],
                        ),
                        Text(
                          'Configuration : ${evaluationsForContext.where((e) => e.type == 'devoir').length} devoir(s) • ${evaluationsForContext.any((e) => e.type == 'composition') ? "1 composition" : "Sans composition"}',
                          style: AppTypography.caption(color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: evaluationsForContext.map((ev) {
                          final isSelected = _currentEvaluation?.id == ev.id;
                          return _buildEvaluationTab(
                            evaluation: ev,
                            isSelected: isSelected,
                            onTap: () {
                              if (_currentEvaluation?.id != ev.id) {
                                _loadGradesForEvaluation(ev, store);
                              }
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s4),
            ],

            // Avertissement Trimestre Verrouillé
            if (_selectedPeriodId != null &&
                store.isPeriodLocked(_selectedPeriodId!,
                    academicYearId: yearId,
                    classId: _selectedClass,
                    subjectId: _selectedSubject))
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.s4),
                padding: const EdgeInsets.all(AppSpacing.s4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_clock_rounded,
                        color: Colors.orange, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Trimestre Verrouillé',
                            style: TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Ce trimestre est configuré mais verrouillé. Il ne pourra être ouvert que lorsque le trimestre précédent sera intégralement clôturé.',
                            style: TextStyle(
                                color: isDark
                                    ? Colors.orange.shade200
                                    : Colors.orange.shade900,
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Alerte en cas de REJET (À CORRIGER)
            if (_currentEvaluation != null &&
                _currentEvaluation!.status == 'rejected')
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.s4),
                padding: const EdgeInsets.all(AppSpacing.s4),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.red, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Évaluation Rejetée par l\'administration — À corriger',
                            style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Motif : ${_currentEvaluation!.rejectionReason ?? "Veuillez vérifier et corriger les notes."}',
                            style: TextStyle(
                                color: isDark
                                    ? Colors.red.shade200
                                    : Colors.red.shade900,
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // FICHE GRISE AVERTISSEMENT (Lecture Seule)
            if (_currentEvaluation != null && isClosedOrValidated && isTeacher)
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.s4),
                padding: const EdgeInsets.all(AppSpacing.s3 + 2),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline_rounded,
                        color: Colors.grey, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentEvaluation!.status == 'validated'
                            ? 'Fiche Validée par l\'administration (Lecture seule verrouillée).'
                            : 'Fiche Clôturée et transmise pour validation (Lecture seule).',
                        style: const TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            // Carte d'état & Actions sur l'évaluation active
            if (_currentEvaluation != null) ...[
              AppCard(
                padding: const EdgeInsets.all(AppSpacing.s4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor:
                              _getStatusColor(_currentEvaluation!.status)
                                  .withOpacity(0.15),
                          child: Icon(
                              _getStatusIcon(_currentEvaluation!.status),
                              color:
                                  _getStatusColor(_currentEvaluation!.status),
                              size: 20),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _currentEvaluation!.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16),
                                ),
                                const SizedBox(width: 8),
                                _buildStatusBadge(_currentEvaluation!.status),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Barème : /${_currentEvaluation!.maxScore.toStringAsFixed(0)} • Type : ${_currentEvaluation!.type == "devoir" ? "Devoir" : "Composition"}',
                              style: AppTypography.caption(
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // BOUTONS D'ACTION SELON LE RÔLE
                    Row(
                      children: [
                        // Enseignant : Enregistrer les notes & Clôturer
                        if (canTeacherEdit) ...[
                          AppButton(
                            label: 'Enregistrer les notes',
                            icon: Icons.save_outlined,
                            variant: AppButtonVariant.secondary,
                            onPressed: () => _saveDraftGrades(store),
                          ),
                          const SizedBox(width: 8),
                          AppButton(
                            label: _currentEvaluation!.status == 'rejected'
                                ? 'Clôturer à nouveau'
                                : 'Clôturer l\'évaluation',
                            icon: Icons.lock_clock_rounded,
                            variant: AppButtonVariant.primary,
                            onPressed: () => _showCloseConfirmationDialog(
                                context, store, filteredStudents),
                          ),
                        ],

                        // Administrateur sur fiche soumise : Valider & Rejeter (PAS de Soumettre/Clôturer)
                        if (isAdmin &&
                            _currentEvaluation!.status == 'submitted') ...[
                          AppButton(
                            label: 'Rejeter',
                            icon: Icons.cancel_outlined,
                            variant: AppButtonVariant.danger,
                            onPressed: () => _showRejectDialog(
                                context, store, _currentEvaluation!),
                          ),
                          const SizedBox(width: 8),
                          AppButton(
                            label: 'Valider',
                            icon: Icons.check_circle_rounded,
                            variant: AppButtonVariant.success,
                            onPressed: () async {
                              try {
                                final updated =
                                    await store.changeEvaluationStatusRemote(
                                        _currentEvaluation!.id, 'validated');
                                if (!context.mounted) return;
                                setState(() {
                                  _currentEvaluation = updated;
                                });
                                AppToast.success(
                                    context, 'Évaluation validée avec succès.');
                              } catch (error) {
                                if (!context.mounted) return;
                                AppToast.error(context,
                                    'Impossible de valider l\'évaluation : $error');
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s4),
            ],

            // SI L'ÉVALUATION EST VERROUILLÉE : Affichage panneau verrouillé
            if (_currentEvaluation != null &&
                _currentEvaluation!.status == 'locked')
              AppCard(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.lock_rounded,
                              size: 40, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${_currentEvaluation!.title} est actuellement verrouillé(e)',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'La saisie des notes pour cette évaluation sera automatiquement disponible dès que l\'évaluation précédente aura été clôturée par l\'enseignant.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            // SINON TABLEAU DE SAISIE DES NOTES
            else
              Opacity(
                opacity: (isClosedOrValidated && isTeacher) ? 0.85 : 1.0,
                child: AppCard(
                  padding: EdgeInsets.zero,
                  child: _currentEvaluation == null
                      ? const Padding(
                          padding: EdgeInsets.all(AppSpacing.s8),
                          child: Center(
                              child: Text(
                                  'Sélectionnez une évaluation pour commencer.')),
                        )
                      : filteredStudents.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(AppSpacing.s8),
                              child: Center(
                                  child: Text(
                                      'Aucun élève trouvé dans cette classe.')),
                            )
                          : SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(
                                  isClosedOrValidated && isTeacher
                                      ? (isDark
                                          ? Colors.grey.shade900
                                          : Colors.grey.shade200)
                                      : (isDark
                                          ? AppColors.darkBgTableStripe
                                          : AppColors.gray100),
                                ),
                                columns: const [
                                  DataColumn(label: Text('Matricule')),
                                  DataColumn(label: Text('Élève')),
                                  DataColumn(label: Text('Statut')),
                                  DataColumn(label: Text('Note (/20)')),
                                  DataColumn(label: Text('Appréciation')),
                                ],
                                rows: filteredStudents.map((s) {
                                  final studentId = s.id;
                                  final controller =
                                      _gradeControllers.putIfAbsent(
                                    studentId,
                                    () => TextEditingController(),
                                  );
                                  final presence =
                                      _presenceMap[studentId] ?? 'present';
                                  final rawText = controller.text.trim();
                                  final gradeVal = double.tryParse(
                                      rawText.replaceAll(',', '.'));
                                  final isInvalid = rawText.isNotEmpty &&
                                      (gradeVal == null ||
                                          gradeVal < 0 ||
                                          gradeVal >
                                              _currentEvaluation!.maxScore);

                                  String displayApp;
                                  AppBadgeVariant badgeVar =
                                      AppBadgeVariant.info;

                                  if (presence == 'absent') {
                                    displayApp = 'ABSENT';
                                    badgeVar = AppBadgeVariant.warning;
                                  } else if (rawText.isEmpty) {
                                    displayApp = 'Non saisi';
                                    badgeVar = AppBadgeVariant.secondary;
                                  } else if (isInvalid) {
                                    displayApp = 'Invalide';
                                    badgeVar = AppBadgeVariant.danger;
                                  } else if (gradeVal != null) {
                                    if (gradeVal >= 16) {
                                      displayApp = 'Très Bien';
                                      badgeVar = AppBadgeVariant.success;
                                    } else if (gradeVal >= 14) {
                                      displayApp = 'Bien';
                                      badgeVar = AppBadgeVariant.success;
                                    } else if (gradeVal >= 12) {
                                      displayApp = 'Assez Bien';
                                      badgeVar = AppBadgeVariant.primary;
                                    } else if (gradeVal >= 10) {
                                      displayApp = 'Passable';
                                      badgeVar = AppBadgeVariant.warning;
                                    } else {
                                      displayApp = 'Insuffisant';
                                      badgeVar = AppBadgeVariant.danger;
                                    }
                                  } else {
                                    displayApp = '—';
                                  }

                                  final isEditable = canTeacherEdit ||
                                      (isAdmin && !isClosedOrValidated);

                                  return DataRow(
                                    cells: [
                                      DataCell(Text(s.matricule ?? '—',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontFamily: 'monospace'))),
                                      DataCell(
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 14,
                                              backgroundColor:
                                                  AppColors.avatarColorFor(
                                                      s.fullName),
                                              child: Text(s.initials,
                                                  style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(s.fullName,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                      // Statut Présence
                                      DataCell(
                                        DropdownButton<String>(
                                          value: presence,
                                          underline: const SizedBox.shrink(),
                                          items: const [
                                            DropdownMenuItem(
                                              value: 'present',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.check_circle,
                                                      size: 14,
                                                      color: Colors.green),
                                                  SizedBox(width: 6),
                                                  Text('Présent',
                                                      style: TextStyle(
                                                          fontSize: 13)),
                                                ],
                                              ),
                                            ),
                                            DropdownMenuItem(
                                              value: 'absent',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.cancel,
                                                      size: 14,
                                                      color: Colors.orange),
                                                  SizedBox(width: 6),
                                                  Text('Absent',
                                                      style: TextStyle(
                                                          fontSize: 13,
                                                          color: Colors.orange,
                                                          fontWeight:
                                                              FontWeight.bold)),
                                                ],
                                              ),
                                            ),
                                          ],
                                          onChanged: isEditable
                                              ? (val) {
                                                  setState(() {
                                                    _presenceMap[studentId] =
                                                        val ?? 'present';
                                                    if (val == 'absent') {
                                                      _gradeControllers[
                                                              studentId]
                                                          ?.text = '';
                                                    }
                                                  });
                                                }
                                              : null,
                                        ),
                                      ),
                                      // Saisie Note
                                      DataCell(
                                        SizedBox(
                                          width: 110,
                                          child: presence == 'absent'
                                              ? Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 10,
                                                      vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: Colors.orange
                                                        .withOpacity(0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                  ),
                                                  child: const Center(
                                                    child: Text('ABS',
                                                        style: TextStyle(
                                                            color:
                                                                Colors.orange,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold)),
                                                  ),
                                                )
                                              : TextField(
                                                  controller: controller,
                                                  enabled: isEditable,
                                                  keyboardType:
                                                      const TextInputType
                                                          .numberWithOptions(
                                                          decimal: true),
                                                  onChanged: (_) =>
                                                      setState(() {}),
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: isInvalid
                                                        ? Colors.red
                                                        : null,
                                                  ),
                                                  decoration: InputDecoration(
                                                    hintText: '—',
                                                    contentPadding:
                                                        const EdgeInsets
                                                            .symmetric(
                                                            horizontal: 10,
                                                            vertical: 8),
                                                    border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                      borderSide: BorderSide(
                                                        color: isInvalid
                                                            ? Colors.red
                                                            : Colors.grey
                                                                .withOpacity(
                                                                    0.3),
                                                      ),
                                                    ),
                                                    focusedBorder:
                                                        OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                      borderSide: BorderSide(
                                                        color: isInvalid
                                                            ? Colors.red
                                                            : AppColors
                                                                .primary600,
                                                        width: 2,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      ),
                                      DataCell(AppBadge(
                                          label: displayApp,
                                          variant: badgeVar)),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // Onglet pour chaque évaluation prévue
  Widget _buildEvaluationTab({
    required EvaluationModel evaluation,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final statusColor = _getStatusColor(evaluation.status);
    final statusIcon = _getStatusIcon(evaluation.status);
    final isClosed = evaluation.status == 'submitted';

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? statusColor.withOpacity(0.12)
                  : (isClosed
                      ? Colors.grey.withOpacity(0.15)
                      : Colors.grey.withOpacity(0.05)),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? statusColor
                    : (isClosed
                        ? Colors.grey.shade400
                        : Colors.grey.withOpacity(0.2)),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, size: 16, color: statusColor),
                const SizedBox(width: 8),
                Text(
                  evaluation.title,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? statusColor
                        : (isClosed ? Colors.grey.shade700 : null),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Section de configuration pour l'Administrateur
  Widget _buildAdminConfigSection(
      BuildContext context, StoreService store, String yearId, bool isDark) {
    final configs = store.getEvaluationPeriodConfigs(academicYearId: yearId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Explication locale de la hiérarchie, sans répéter l'année globale.
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.school_rounded,
                      color: AppColors.primary600, size: 24),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Organisation des périodes',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '💡 Vous pouvez configurer les 3 trimestres à l\'avance (nombre de devoirs et composition). En revanche, l\'ouverture opérationnelle des trimestres et des évaluations s\'effectue de manière séquentielle (un seul trimestre actif à la fois).',
                style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                    fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s4),

        // Carte des trimestres
        AppCard(
          title: 'Configuration et Statut des Trimestres',
          subtitle:
              'Définissez le nombre de devoirs et la composition, et gérez l\'ouverture séquentielle des périodes.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...configs.map((cfg) {
                final isActive = cfg.status == 'active';
                final isClosed = cfg.status == 'closed';
                final canOpen =
                    store.canOpenPeriod(cfg.periodId, academicYearId: yearId);

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color:
                        isDark ? AppColors.darkBgTableStripe : AppColors.gray50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isActive
                          ? Colors.green.withOpacity(0.5)
                          : (isClosed
                              ? Colors.grey.withOpacity(0.3)
                              : Colors.blueGrey.withOpacity(0.2)),
                      width: isActive ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(cfg.periodName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              const SizedBox(width: 10),
                              if (isActive)
                                const AppBadge(
                                    label: '🟢 ACTIF',
                                    variant: AppBadgeVariant.success)
                              else if (isClosed)
                                const AppBadge(
                                    label: '🩶 CLÔTURÉ',
                                    variant: AppBadgeVariant.secondary)
                              else
                                const AppBadge(
                                    label: '🔒 VERROUILLÉ',
                                    variant: AppBadgeVariant.warning),
                            ],
                          ),
                          if (!isActive && canOpen)
                            AppButton(
                              label: 'Ouvrir ce trimestre',
                              icon: Icons.lock_open_rounded,
                              size: AppButtonSize.small,
                              variant: AppButtonVariant.primary,
                              onPressed: () {
                                final ok = store.openPeriod(cfg.periodId,
                                    academicYearId: yearId);
                                if (ok) {
                                  AppToast.success(context,
                                      '${cfg.periodName} est maintenant actif.');
                                } else {
                                  AppToast.error(context,
                                      'Impossible d\'ouvrir ${cfg.periodName}.');
                                }
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Text('Nombre de devoirs : ',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w500)),
                              const SizedBox(width: 8),
                              DropdownButton<int>(
                                value: cfg.homeworkCount,
                                items: [1, 2, 3, 4, 5, 6]
                                    .map((n) => DropdownMenuItem(
                                        value: n, child: Text('$n devoir(s)')))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    store.savePeriodConfig(
                                        cfg.copyWith(homeworkCount: val));
                                    AppToast.success(context,
                                        '${cfg.periodName} : $val devoirs configurés.');
                                  }
                                },
                              ),
                              const SizedBox(width: 24),
                              const Text('Composition : ',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w500)),
                              Switch(
                                value: cfg.hasComposition,
                                onChanged: (val) {
                                  store.savePeriodConfig(
                                      cfg.copyWith(hasComposition: val));
                                  AppToast.success(context,
                                      '${cfg.periodName} : Composition ${val ? "activée" : "désactivée"}.');
                                },
                              ),
                            ],
                          ),
                          // Évaluations prévues résumé
                          Text(
                            'Évaluations prévues : ${List.generate(cfg.homeworkCount, (i) => "Devoir ${i + 1}").join(", ")}${cfg.hasComposition ? ", Composition" : ""}',
                            style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  // File d'attente des évaluations à valider pour l'Administrateur
  Widget _buildAdminValidationQueueSection(BuildContext context,
      StoreService store, List<EvaluationModel> evals, bool isDark) {
    if (evals.isEmpty) {
      return AppCard(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.check_circle_outline_rounded,
                    size: 48, color: Colors.green.withOpacity(0.7)),
                const SizedBox(height: 12),
                const Text('Toutes les évaluations sont à jour !',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                const Text(
                    'Aucune évaluation clôturée en attente de validation.',
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
      );
    }

    return AppCard(
      title: 'Évaluations en Attente de Validation (${evals.length})',
      padding: EdgeInsets.zero,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: evals.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, idx) {
          final ev = evals[idx];
          final cls = store.getClassById(ev.classId);
          final subj = store.getSubjects().firstWhere(
              (s) => s.id == ev.subjectId,
              orElse: () => SubjectModel(
                  id: '', name: ev.subjectId, coefficient: 1, schoolId: ''));

          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF3B82F6).withOpacity(0.15),
              child: const Icon(Icons.description_outlined,
                  color: Color(0xFF3B82F6)),
            ),
            title: Text(
                '${ev.title} — ${cls?.name ?? ev.classId} • ${subj.name}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                'Période : ${ev.periodId ?? "N/A"} • Soumise le : ${ev.submittedAt ?? "Récemment"}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppButton(
                  label: 'Consulter',
                  size: AppButtonSize.small,
                  variant: AppButtonVariant.secondary,
                  onPressed: () {
                    setState(() {
                      _selectedClass = ev.classId;
                      _selectedSubject = ev.subjectId;
                      _selectedPeriodId = ev.periodId;
                      _adminViewMode = 'consultation';
                    });
                    _loadGradesForEvaluation(ev, store);
                  },
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: 'Rejeter',
                  size: AppButtonSize.small,
                  variant: AppButtonVariant.danger,
                  onPressed: () => _showRejectDialog(context, store, ev),
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: 'Valider',
                  size: AppButtonSize.small,
                  variant: AppButtonVariant.success,
                  onPressed: () async {
                    try {
                      await store.changeEvaluationStatusRemote(
                          ev.id, 'validated');
                      if (!context.mounted) return;
                      AppToast.success(
                          context, 'Évaluation ' + ev.title + ' validée.');
                    } catch (error) {
                      if (context.mounted) {
                        AppToast.error(context, 'Validation refusée : $error');
                      }
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAdminNavButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    int? badgeCount,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary600.withOpacity(0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppColors.primary600
                : Colors.grey.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: isSelected ? AppColors.primary600 : Colors.grey),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? AppColors.primary600 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeacherFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary600.withOpacity(0.12)
              : Colors.grey.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary600 : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppColors.primary600 : null,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    switch (status) {
      case 'draft':
        return const AppBadge(
            label: 'En cours',
            variant: AppBadgeVariant.success,
            icon: Icons.edit_note);
      case 'submitted':
        return const AppBadge(
            label: '🩶 Clôturée',
            variant: AppBadgeVariant.secondary,
            icon: Icons.lock_clock);
      case 'rejected':
        return const AppBadge(
            label: '🔴 À corriger',
            variant: AppBadgeVariant.danger,
            icon: Icons.warning_amber_rounded);
      case 'validated':
        return const AppBadge(
            label: '🟢 Validée',
            variant: AppBadgeVariant.success,
            icon: Icons.check_circle);
      case 'locked':
        return const AppBadge(
            label: '🔒 Verrouillée',
            variant: AppBadgeVariant.secondary,
            icon: Icons.lock);
      default:
        return AppBadge(label: status, variant: AppBadgeVariant.secondary);
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'draft':
        return const Color(0xFF10B981); // Vert En cours
      case 'submitted':
        return const Color(0xFF6B7280); // Gris Clôturé
      case 'rejected':
        return const Color(0xFFEF4444); // Rouge Rejeté
      case 'validated':
        return const Color(0xFF10B981); // Vert Validé
      case 'locked':
        return const Color(0xFF4B5563); // Gris foncé
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'draft':
        return Icons.circle;
      case 'submitted':
        return Icons.lock_clock_rounded;
      case 'rejected':
        return Icons.warning_rounded;
      case 'validated':
        return Icons.check_circle_rounded;
      case 'locked':
        return Icons.lock_rounded;
      default:
        return Icons.radio_button_unchecked;
    }
  }
}
