import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../../shared/widgets/workspace_header.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/student_photo_picker.dart';
import '../../../core/utils/pdf_download.dart';
import '../../../data/datasources/api_client.dart';
import '../../../data/models/student_model.dart';
import '../../../data/models/registration_model.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_date_field.dart';
import '../../../shared/widgets/app_form_field.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/responsive_grid.dart';
import '../documents/receipt_pdf.dart';
import 'student_photo_avatar.dart';
import 'student_photo_import_dialog.dart';

void showStudentProfileModal(BuildContext context, StudentModel student) {
  var savingPhoto = false;
  var photoRevision = 0;
  PickedStudentPhoto? pendingPhoto;
  showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(student.fullName),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: pendingPhoto == null
                    ? StudentPhotoAvatar(
                        studentId: student.id,
                        initials: student.initials,
                        radius: 52,
                        refreshKey: photoRevision,
                      )
                    : CircleAvatar(
                        radius: 52,
                        backgroundImage: MemoryImage(
                          base64Decode(pendingPhoto!.contentBase64),
                        ),
                      ),
              ),
              if (pendingPhoto != null) ...[
                const SizedBox(height: AppSpacing.s2),
                Center(
                  child: Text(
                    'Aperçu — ${pendingPhoto!.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall(),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.s3),
              Center(
                child: Wrap(
                  spacing: AppSpacing.s2,
                  runSpacing: AppSpacing.s2,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: savingPhoto
                          ? null
                          : () async {
                              final files =
                                  await pickStudentPhotos(multiple: false);
                              if (files.isEmpty || !context.mounted) return;
                              final file = files.first;
                              if (!file.isValid) {
                                AppToast.error(
                                    context,
                                    file.rejectionReason ??
                                        'Cette image ne peut pas être importée.');
                                return;
                              }
                              setDialogState(() => pendingPhoto = file);
                            },
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text(pendingPhoto == null
                          ? 'Modifier la photo'
                          : 'Choisir une autre photo'),
                    ),
                    if (pendingPhoto != null)
                      FilledButton.icon(
                        onPressed: savingPhoto
                            ? null
                            : () async {
                                final file = pendingPhoto!;
                                setDialogState(() => savingPhoto = true);
                                try {
                                  await context
                                      .read<StoreService>()
                                      .updateStudentPhotoRemote(
                                          student.id, file.toJson());
                                  if (context.mounted) {
                                    setDialogState(() {
                                      photoRevision++;
                                      pendingPhoto = null;
                                    });
                                    AppToast.success(
                                        context, 'Photo mise à jour.');
                                  }
                                } on ApiException catch (error) {
                                  if (context.mounted) {
                                    AppToast.error(context, error.message);
                                  }
                                } finally {
                                  if (context.mounted) {
                                    setDialogState(() => savingPhoto = false);
                                  }
                                }
                              },
                        icon: savingPhoto
                            ? const SizedBox.square(
                                dimension: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.cloud_upload_outlined),
                        label: Text(
                            savingPhoto ? 'Enregistrement…' : 'Envoyer'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s4),
              Text('Matricule : ${student.matricule ?? '—'}'),
              Text('Classe : ${student.className ?? 'Non inscrit'}'),
              Text('Téléphone : ${student.phone ?? '—'}'),
              Text('Responsable : ${student.parent ?? '—'}'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: savingPhoto ? null : () => Navigator.pop(context),
              child: const Text('Fermer'))
        ],
      ),
    ),
  );
}

void openStudentRegistrationModal(
  BuildContext context,
  StudentModel? student, {
  String? preselectedYearId,
  String? preselectedClassId,
  String? preselectedRegistrationType,
  DateTime? preselectedDate,
}) {
  if (student == null) {
    AppToast.warning(context, 'Sélectionnez d’abord un élève.');
    return;
  }
  final store = context.read<StoreService>();
  final yearId = preselectedYearId ?? store.getSelectedAcademicYearId();
  final classes = store.getClassesByYear(yearId);
  final requestedClassId = preselectedClassId ?? student.classId;
  // A re-enrolled pupil comes from the previous academic year. That old class
  // must never be used as the value of the target-year selector: it is not an
  // item in the new year's list and Flutter would reject the dropdown value.
  String? classId = classes.any((item) => item.id == requestedClassId)
      ? requestedClassId
      : (classes.isEmpty ? null : classes.first.id);
  final hasExistingRegistration = student.academicYearId == yearId &&
      student.classId != null &&
      student.classId!.isNotEmpty;
  String schoolRegime = const {'normal', 'part_time', 'full_time'}
          .contains(preselectedRegistrationType)
      ? preselectedRegistrationType!
      : 'normal';
  bool hasTd = false;
  bool tdAllowedForClass(String? selectedClassId) {
    final selected = classes.where((item) => item.id == selectedClassId);
    if (selected.isEmpty) return false;
    final level = (selected.first.level ?? '').trim().toUpperCase();
    return const {'CM2', '3E', 'TERMINALE'}.contains(level);
  }

  showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Inscription académique'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: classId,
                decoration: const InputDecoration(labelText: 'Classe'),
                items: classes
                    .map((item) => DropdownMenuItem(
                        value: item.id, child: Text(item.name)))
                    .toList(),
                onChanged: (value) => setState(() {
                  classId = value;
                  if (!tdAllowedForClass(value)) hasTd = false;
                }),
              ),
              if (!hasExistingRegistration) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: schoolRegime,
                  decoration: const InputDecoration(labelText: 'Régime'),
                  items: const [
                    DropdownMenuItem(value: 'normal', child: Text('Normal')),
                    DropdownMenuItem(
                        value: 'part_time', child: Text('Mi-temps')),
                    DropdownMenuItem(
                        value: 'full_time', child: Text('Plein temps')),
                  ],
                  onChanged: (value) =>
                      setState(() => schoolRegime = value ?? 'normal'),
                ),
                if (tdAllowedForClass(classId))
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Option TD'),
                    subtitle:
                        const Text('Option académique, sans montant financier'),
                    value: hasTd,
                    onChanged: (value) =>
                        setState(() => hasTd = value ?? false),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              if (classId == null) {
                AppToast.warning(dialogContext, 'Une classe est obligatoire.');
                return;
              }
              try {
                await store.changeStudentClassRemote(student.id, classId!,
                    schoolRegime: schoolRegime, hasTd: hasTd);
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                AppToast.success(
                    context, 'Inscription académique enregistrée.');
              } on ApiException catch (error) {
                if (dialogContext.mounted) {
                  AppToast.error(dialogContext, error.message);
                }
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
}

class StudentsPage extends StatefulWidget {
  const StudentsPage(
      {super.key, this.initialClassName, this.openAddModal = false});

  final String? initialClassName;
  final bool openAddModal;

  @override
  State<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends State<StudentsPage> {
  bool _loading = true;
  String? _error;
  String _search = '';
  String? _classId;
  String? _cycleId;
  String? _levelId;
  String? _loadedYearId;
  List<Map<String, dynamic>> _preEnrollments = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      if (mounted && widget.openAddModal) _openStudentEditor();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final yearId = context.read<StoreService>().getSelectedAcademicYearId();
    if (_loadedYearId != null && yearId != _loadedYearId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final store = context.read<StoreService>();
      _loadedYearId = store.getSelectedAcademicYearId();
      final results = await Future.wait<dynamic>([
        store.refreshStudentsRemote(
          academicYearId: _loadedYearId,
          cycleId: _cycleId,
          levelId: _levelId,
          classId: _classId,
        ),
        store.preEnrollmentsRemote(
          academicYearId: _loadedYearId,
          status: 'submitted',
        ),
      ]);
      _preEnrollments = List<Map<String, dynamic>>.from(results[1] as List);
    } on Exception catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openStudentEditor([
    StudentModel? student,
    Map<String, dynamic>? preEnrollment,
  ]) async {
    final store = context.read<StoreService>();
    final allClasses =
        store.getClassesByYear(store.getSelectedAcademicYearId());
    final cycles =
        store.getSchoolCycles().where((item) => item.isActive).toList();
    final first = TextEditingController(text: student?.firstName ?? '');
    final last = TextEditingController(text: student?.lastName ?? '');
    final email = TextEditingController(text: student?.email ?? '');
    final phone = TextEditingController(text: student?.phone ?? '');
    DateTime? birthDate = AppDateUtils.parse(student?.birthDate);
    final nationality = TextEditingController(text: student?.nationality ?? '');
    final address = TextEditingController(text: student?.address ?? '');
    final primaryGuardian = student?.guardians
        .cast<Map<String, dynamic>>()
        .where((guardian) => guardian['isPrimary'] == true)
        .firstOrNull;
    final guardianName = TextEditingController(
        text: primaryGuardian == null
            ? ''
            : '${primaryGuardian['lastName'] ?? ''} ${primaryGuardian['firstName'] ?? ''}'
                .trim());
    final guardianPhone = TextEditingController(
        text: primaryGuardian?['phone']?.toString() ?? '');
    final guardianEmail = TextEditingController(
        text: primaryGuardian?['email']?.toString() ?? '');
    final guardianSecondPhone = TextEditingController(
        text: primaryGuardian?['secondPhone']?.toString() ?? '');
    final guardianAddress = TextEditingController(
        text: primaryGuardian?['address']?.toString() ?? '');
    final guardianProfession = TextEditingController(
        text: primaryGuardian?['profession']?.toString() ?? '');
    String? selectedClass = preEnrollment?['desiredClassId']?.toString() ??
        student?.classId ??
        (allClasses.isEmpty ? null : allClasses.first.id);
    final initialClasses =
        allClasses.where((item) => item.id == selectedClass).toList();
    final initialClass = initialClasses.isEmpty ? null : initialClasses.first;
    String? selectedCycle = initialClass?.cycleId;
    String? selectedLevel =
        initialClass?.structuredLevelId ?? initialClass?.levelId;
    String gender = student?.sex ?? 'M';
    String schoolRegime =
        preEnrollment?['schoolRegime']?.toString() ?? 'normal';
    String guardianType =
        primaryGuardian?['relationship']?.toString() ?? 'tuteur';
    bool hasTd = false;
    bool orphanFather = false;
    bool orphanMother = false;
    bool medicallyFit = true;
    String selectedCycleCode() {
      final selectedClassRows =
          allClasses.where((item) => item.id == selectedClass);
      if (selectedClassRows.isEmpty) return '';
      final cycleId = selectedClassRows.first.cycleId;
      final cycle = store
          .getSchoolCycles()
          .where((item) => item.id == cycleId)
          .firstOrNull;
      return (cycle?.code ?? '').trim().toUpperCase();
    }

    bool regimeRequiredForSelectedClass() =>
        const {'MATERNELLE', 'PRIMAIRE'}.contains(selectedCycleCode());

    if (regimeRequiredForSelectedClass()) {
      if (!const {'part_time', 'full_time'}.contains(schoolRegime)) {
        schoolRegime = 'full_time';
      }
    } else {
      schoolRegime = 'normal';
    }

    bool tdAllowedForSelectedClass() {
      final selected = allClasses.where((item) => item.id == selectedClass);
      if (selected.isEmpty) return false;
      final level = (selected.first.level ?? '').trim().toUpperCase();
      return const {'CM2', '3E', 'TERMINALE'}.contains(level);
    }

    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          StatefulBuilder(builder: (context, setDialogState) {
        final levels = selectedCycle == null
            ? const <dynamic>[]
            : store
                .getSchoolLevelsByCycleId(selectedCycle!)
                .where((item) => item.status == 'active')
                .toList();
        final classes = allClasses.where((item) {
          final levelId = item.structuredLevelId ?? item.levelId;
          return item.cycleId == selectedCycle && levelId == selectedLevel;
        }).toList();
        return AlertDialog(
          title: Text(preEnrollment != null
              ? 'Finaliser l’inscription'
              : student == null
                  ? 'Nouvel élève'
                  : 'Modifier l’élève'),
          content: SizedBox(
            width: 820,
            child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('IDENTITÉ ÉLÈVE',
                        style:
                            AppTypography.label(color: AppColors.primary600)),
                    const SizedBox(height: AppSpacing.s3),
                    ResponsiveFormGrid(children: [
                      AppFormField(label: 'Prénom *', controller: first),
                      AppFormField(label: 'Nom *', controller: last),
                    ]),
                    const SizedBox(height: AppSpacing.s5),
                    ResponsiveFormGrid(children: [
                      AppDateField(
                        label: 'Date de naissance',
                        value: birthDate,
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                        onChanged: (value) =>
                            setDialogState(() => birthDate = value),
                      ),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: gender,
                        decoration: const InputDecoration(labelText: 'Sexe'),
                        items: const [
                          DropdownMenuItem(value: 'M', child: Text('Masculin')),
                          DropdownMenuItem(value: 'F', child: Text('Féminin')),
                        ],
                        onChanged: (value) => gender = value ?? gender,
                      ),
                    ]),
                    const SizedBox(height: AppSpacing.s5),
                    ResponsiveFormGrid(children: [
                      AppFormField(
                          label: 'Nationalité *', controller: nationality),
                      AppFormField(label: 'Adresse *', controller: address),
                    ]),
                    const SizedBox(height: AppSpacing.s5),
                    Text('SITUATION PERSONNELLE',
                        style:
                            AppTypography.label(color: AppColors.primary600)),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Orphelin de père'),
                      value: orphanFather,
                      onChanged: (value) =>
                          setDialogState(() => orphanFather = value ?? false),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Orphelin de mère'),
                      subtitle: Text(orphanFather && orphanMother
                          ? 'Orphelin des deux parents'
                          : 'Cochez les deux cases si les deux parents sont décédés.'),
                      value: orphanMother,
                      onChanged: (value) =>
                          setDialogState(() => orphanMother = value ?? false),
                    ),
                    Row(children: [
                      Expanded(
                          child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Apte'),
                        value: medicallyFit,
                        onChanged: (_) =>
                            setDialogState(() => medicallyFit = true),
                      )),
                      Expanded(
                          child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Inapte'),
                        value: !medicallyFit,
                        onChanged: (_) =>
                            setDialogState(() => medicallyFit = false),
                      )),
                    ]),
                    const SizedBox(height: AppSpacing.s5),
                    Text('SCOLARITÉ',
                        style:
                            AppTypography.label(color: AppColors.primary600)),
                    const SizedBox(height: AppSpacing.s3),
                    ResponsiveFormGrid(children: [
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: selectedCycle,
                        decoration: const InputDecoration(labelText: 'Cycle *'),
                        items: cycles
                            .map((item) => DropdownMenuItem(
                                value: item.id, child: Text(item.name)))
                            .toList(),
                        onChanged: (value) => setDialogState(() {
                          selectedCycle = value;
                          selectedLevel = null;
                          selectedClass = null;
                          schoolRegime = 'normal';
                          hasTd = false;
                        }),
                      ),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue:
                            levels.any((item) => item.id == selectedLevel)
                                ? selectedLevel
                                : null,
                        decoration:
                            const InputDecoration(labelText: 'Niveau *'),
                        items: levels
                            .map((item) => DropdownMenuItem<String>(
                                value: item.id, child: Text(item.name)))
                            .toList(),
                        onChanged: selectedCycle == null
                            ? null
                            : (value) => setDialogState(() {
                                  selectedLevel = value;
                                  selectedClass = null;
                                  schoolRegime = 'normal';
                                  hasTd = false;
                                }),
                      ),
                    ]),
                    const SizedBox(height: AppSpacing.s3),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue:
                          classes.any((item) => item.id == selectedClass)
                              ? selectedClass
                              : null,
                      decoration: const InputDecoration(labelText: 'Classe *'),
                      items: classes
                          .map((item) => DropdownMenuItem(
                              value: item.id, child: Text(item.name)))
                          .toList(),
                      onChanged: selectedLevel == null
                          ? null
                          : (value) => setDialogState(() {
                                selectedClass = value;
                                if (regimeRequiredForSelectedClass()) {
                                  if (!const {'part_time', 'full_time'}
                                      .contains(schoolRegime)) {
                                    schoolRegime = 'full_time';
                                  }
                                } else {
                                  schoolRegime = 'normal';
                                }
                                if (!tdAllowedForSelectedClass()) hasTd = false;
                              }),
                    ),
                    ...[
                      const SizedBox(height: AppSpacing.s3),
                      if ((student == null || preEnrollment != null) &&
                          regimeRequiredForSelectedClass())
                        DropdownButtonFormField<String>(
                          key: const Key('student-school-regime'),
                          isExpanded: true,
                          initialValue: const {'part_time', 'full_time'}
                                  .contains(schoolRegime)
                              ? schoolRegime
                              : 'full_time',
                          decoration:
                              const InputDecoration(labelText: 'Régime *'),
                          items: const [
                            DropdownMenuItem(
                                value: 'part_time', child: Text('Mi-temps')),
                            DropdownMenuItem(
                                value: 'full_time', child: Text('Plein temps')),
                          ],
                          onChanged: (value) => setDialogState(
                              () => schoolRegime = value ?? 'full_time'),
                        ),
                      if ((student == null || preEnrollment != null) &&
                          tdAllowedForSelectedClass())
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Option TD'),
                          subtitle: const Text(
                              'Option académique, sans montant financier'),
                          value: hasTd,
                          onChanged: (value) =>
                              setDialogState(() => hasTd = value ?? false),
                        ),
                      const SizedBox(height: AppSpacing.s5),
                      Text('RESPONSABLE LÉGAL PRINCIPAL',
                          style:
                              AppTypography.label(color: AppColors.primary600)),
                      const SizedBox(height: AppSpacing.s3),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: guardianType,
                        decoration: const InputDecoration(labelText: 'Type *'),
                        items: const [
                          DropdownMenuItem(
                              value: 'tuteur', child: Text('Tuteur')),
                          DropdownMenuItem(
                              value: 'tutrice', child: Text('Tutrice')),
                        ],
                        onChanged: (value) => setDialogState(
                            () => guardianType = value ?? 'tuteur'),
                      ),
                      const SizedBox(height: AppSpacing.s3),
                      ResponsiveFormGrid(children: [
                        AppFormField(
                            label: 'Nom puis prénom *',
                            controller: guardianName),
                        AppFormField(
                            label: 'Téléphone du responsable légal *',
                            controller: guardianPhone),
                      ]),
                      const SizedBox(height: AppSpacing.s5),
                      ResponsiveFormGrid(children: [
                        AppFormField(
                            label: 'Deuxième téléphone',
                            controller: guardianSecondPhone),
                        AppFormField(
                            label: 'E-mail de connexion parent',
                            controller: guardianEmail),
                      ]),
                      const SizedBox(height: AppSpacing.s3),
                      ResponsiveFormGrid(children: [
                        AppFormField(
                            label: 'Profession *',
                            controller: guardianProfession),
                        AppFormField(
                            label: 'Adresse du responsable *',
                            controller: guardianAddress),
                      ]),
                    ],
                  ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (first.text.trim().isEmpty ||
                          last.text.trim().isEmpty ||
                          birthDate == null ||
                          nationality.text.trim().isEmpty ||
                          address.text.trim().isEmpty ||
                          selectedClass == null) {
                        AppToast.warning(context,
                            'Prénom, nom et classe sont obligatoires.');
                        return;
                      }
                      final guardianParts =
                          guardianName.text.trim().split(RegExp(r'\s+'));
                      if ((student == null ||
                              preEnrollment != null ||
                              primaryGuardian != null) &&
                          (guardianParts.length < 2 ||
                              guardianPhone.text.trim().isEmpty ||
                              guardianAddress.text.trim().isEmpty ||
                              guardianProfession.text.trim().isEmpty)) {
                        AppToast.warning(context,
                            'Nom complet, telephone, adresse et profession du responsable obligatoires.');
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        final payload = <String, dynamic>{
                          'firstName': first.text.trim(),
                          'lastName': last.text.trim(),
                          'gender': gender,
                          if (birthDate != null)
                            'birthDate': AppDateUtils.toIso(birthDate!),
                          'nationality': nationality.text.trim(),
                          'address': address.text.trim(),
                          if (email.text.trim().isNotEmpty)
                            'email': email.text.trim(),
                          if (phone.text.trim().isNotEmpty)
                            'phone': phone.text.trim(),
                        };
                        final saved = student == null
                            ? await store.createStudentRemote(payload,
                                classId: selectedClass,
                                schoolRegime: schoolRegime,
                                hasTd: hasTd,
                                registrationOptions: {
                                    'orphanFather': orphanFather,
                                    'orphanMother': orphanMother,
                                    'fitness': medicallyFit ? 'fit' : 'unfit',
                                  })
                            : await store.updateStudentRemote(
                                student.id, payload);
                        if (student != null &&
                            preEnrollment == null &&
                            selectedClass != student.classId) {
                          await store.changeStudentClassRemote(
                              student.id, selectedClass!);
                        }
                        if ((student == null || preEnrollment != null) &&
                            guardianName.text.trim().isNotEmpty &&
                            guardianPhone.text.trim().isNotEmpty) {
                          final parts = guardianParts;
                          await store.createGuardianAndLinkRemote(
                            studentId: saved.id,
                            firstName: parts.sublist(1).join(' '),
                            lastName: parts.first,
                            phone: guardianPhone.text.trim(),
                            secondPhone: guardianSecondPhone.text.trim(),
                            email: guardianEmail.text.trim(),
                            address: guardianAddress.text.trim(),
                            profession: guardianProfession.text.trim(),
                            relationship: guardianType,
                          );
                        }
                        if (student != null && primaryGuardian != null) {
                          await store.updateGuardianRemote(
                            primaryGuardian['id'].toString(),
                            {
                              'firstName': guardianParts.sublist(1).join(' '),
                              'lastName': guardianParts.first,
                              'phone': guardianPhone.text.trim(),
                              'secondPhone': guardianSecondPhone.text.trim(),
                              if (guardianEmail.text.trim().isNotEmpty)
                                'email': guardianEmail.text.trim(),
                              'address': guardianAddress.text.trim(),
                              'profession': guardianProfession.text.trim(),
                            },
                          );
                        }
                        if (preEnrollment != null) {
                          await store.approvePreEnrollmentRemote(
                            preEnrollment['id'].toString(),
                            classId: selectedClass,
                            schoolRegime:
                                preEnrollment['schoolRegime']?.toString() ??
                                    schoolRegime,
                            hasTd: hasTd,
                            options: {
                              'orphanFather': orphanFather,
                              'orphanMother': orphanMother,
                              'fitness': medicallyFit ? 'fit' : 'unfit',
                            },
                          );
                        }
                        if (!dialogContext.mounted || !mounted) return;
                        Navigator.pop(dialogContext);
                        AppToast.success(
                            this.context,
                            student == null
                                ? 'Élève créé et inscrit.'
                                : preEnrollment != null
                                    ? 'Inscription définitive validée.'
                                    : 'Élève modifié.');
                        await _load();
                      } on ApiException catch (error) {
                        if (dialogContext.mounted) {
                          AppToast.error(dialogContext, error.message);
                        }
                      } on Exception {
                        if (dialogContext.mounted) {
                          AppToast.error(dialogContext,
                              'Impossible de joindre le serveur.');
                        }
                      } finally {
                        if (dialogContext.mounted) {
                          setDialogState(() => saving = false);
                        }
                      }
                    },
              child: Text(saving ? 'Enregistrement…' : 'Enregistrer'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _openEntryFlow() async {
    var entryType = 'registration';
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Enregistrer un élève'),
          content: SizedBox(
            width: 460,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: entryType,
              decoration: const InputDecoration(labelText: 'Type d’entrée'),
              items: const [
                DropdownMenuItem(
                    value: 'registration', child: Text('Inscription')),
                DropdownMenuItem(
                    value: 're_registration', child: Text('Réinscription')),
              ],
              onChanged: (value) =>
                  setState(() => entryType = value ?? entryType),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, entryType),
                child: const Text('Continuer')),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (selected == 'registration') {
      await _openPreEnrollmentForm(registrationKind: 'registration');
      return;
    }
    await _openReEnrollmentPicker();
  }

  Future<void> _openPreEnrollmentForm({
    required String registrationKind,
    StudentModel? existingStudent,
    Map<String, dynamic>? existingPreEnrollment,
  }) async {
    final store = context.read<StoreService>();
    final yearId = store.getSelectedAcademicYearId();
    final classes = store.getClassesByYear(yearId);
    if (yearId == null || classes.isEmpty) {
      AppToast.warning(
          context, 'Sélectionnez une année et créez au moins une classe.');
      return;
    }
    final first = TextEditingController(
        text: existingPreEnrollment?['firstName']?.toString() ??
            existingStudent?.firstName ??
            '');
    final last = TextEditingController(
        text: existingPreEnrollment?['lastName']?.toString() ??
            existingStudent?.lastName ??
            '');
    String? classId = existingPreEnrollment?['desiredClassId']?.toString();
    if (!classes.any((item) => item.id == classId)) classId = classes.first.id;
    String schoolRegime =
        existingPreEnrollment?['schoolRegime']?.toString() ?? 'normal';

    String cycleCodeForClass(String? selectedClassId) {
      final rows = classes.where((item) => item.id == selectedClassId);
      if (rows.isEmpty) return '';
      final cycle = store
          .getSchoolCycles()
          .where((item) => item.id == rows.first.cycleId)
          .firstOrNull;
      return (cycle?.code ?? '').trim().toUpperCase();
    }

    bool regimeRequired() =>
        const {'MATERNELLE', 'PRIMAIRE'}.contains(cycleCodeForClass(classId));
    if (regimeRequired() &&
        !const {'part_time', 'full_time'}.contains(schoolRegime)) {
      schoolRegime = 'full_time';
    }
    if (!regimeRequired()) schoolRegime = 'normal';
    var saving = false;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(registrationKind == 'reenrollment'
              ? 'Pré-réinscription'
              : 'Préinscription'),
          content: SizedBox(
            width: 620,
            child: ResponsiveFormGrid(children: [
              AppFormField(
                label: 'Nom *',
                controller: last,
                enabled: registrationKind != 'reenrollment',
              ),
              AppFormField(
                label: 'Prénom *',
                controller: first,
                enabled: registrationKind != 'reenrollment',
              ),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: classId,
                decoration:
                    const InputDecoration(labelText: 'Classe souhaitée *'),
                items: classes
                    .map((item) => DropdownMenuItem(
                          value: item.id,
                          child:
                              Text(item.name, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: saving
                    ? null
                    : (value) => setDialogState(() {
                          classId = value;
                          schoolRegime = regimeRequired()
                              ? 'full_time'
                              : 'normal';
                        }),
              ),
              if (regimeRequired())
                DropdownButtonFormField<String>(
                  key: const Key('pre-enrollment-regime'),
                  isExpanded: true,
                  initialValue: schoolRegime,
                  decoration: const InputDecoration(labelText: 'Régime *'),
                  items: const [
                    DropdownMenuItem(
                        value: 'part_time', child: Text('Mi-temps')),
                    DropdownMenuItem(
                        value: 'full_time', child: Text('Plein temps')),
                  ],
                  onChanged: saving
                      ? null
                      : (value) => setDialogState(
                          () => schoolRegime = value ?? 'full_time'),
                ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (first.text.trim().isEmpty ||
                          last.text.trim().isEmpty ||
                          classId == null) {
                        AppToast.warning(dialogContext,
                            'Nom, prénom et classe sont obligatoires.');
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        final response = existingPreEnrollment == null
                            ? await store.createPreEnrollmentRemote(
                                studentId: existingStudent?.id,
                                firstName: first.text.trim(),
                                lastName: last.text.trim(),
                                academicYearId: yearId,
                                desiredClassId: classId!,
                                schoolRegime: schoolRegime,
                                registrationKind: registrationKind,
                              )
                            : await store.updatePreEnrollmentRemote(
                                existingPreEnrollment['id'].toString(), {
                                'firstName': first.text.trim(),
                                'lastName': last.text.trim(),
                                'desiredClassId': classId,
                                'schoolRegime': schoolRegime,
                              });
                        if (dialogContext.mounted)
                          Navigator.pop(dialogContext, response);
                      } on ApiException catch (error) {
                        if (dialogContext.mounted)
                          AppToast.error(dialogContext, error.message);
                      } finally {
                        if (dialogContext.mounted)
                          setDialogState(() => saving = false);
                      }
                    },
              child: Text(saving ? 'Enregistrement…' : 'Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || result == null) return;
    final receipt = result['receipt'];
    if (receipt is Map) {
      await _showPreEnrollmentReceipt(Map<String, dynamic>.from(receipt));
    } else {
      AppToast.success(context, 'Préinscription mise à jour.');
    }
    await _load();
  }

  Future<void> _showPreEnrollmentReceipt(Map<String, dynamic> receipt) async {
    final pdf = await buildFinanceReceiptPdf(receipt);
    final bytes = await pdf.save();
    final filename = 'Recu_${receipt['receiptNumber'] ?? 'preinscription'}.pdf';
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Préinscription enregistrée'),
        content: Text(
          'Le reçu ${receipt['receiptNumber'] ?? ''} est enregistré dans Documents > Reçus.\n'
          'Montant encaissé : ${receipt['amount'] ?? 0} FCFA.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fermer'),
          ),
          OutlinedButton.icon(
            onPressed: () => downloadPdfFile(bytes, filename),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Télécharger'),
          ),
          FilledButton.icon(
            onPressed: () => Printing.layoutPdf(
              name: filename,
              onLayout: (_) async => bytes,
            ),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Imprimer'),
          ),
        ],
      ),
    );
  }

  Future<void> _openReEnrollmentPicker() async {
    final store = context.read<StoreService>();
    final targetYearId = store.getSelectedAcademicYearId();
    if (targetYearId == null) {
      AppToast.warning(context, 'Sélectionnez d’abord l’année scolaire cible.');
      return;
    }
    final picked = await showDialog<StudentModel>(
      context: context,
      builder: (_) => _ReEnrollmentPickerDialog(
        store: store,
        targetAcademicYearId: targetYearId,
      ),
    );
    if (!mounted || picked == null) return;
    StudentModel selected = picked;
    try {
      selected = await store.studentDetailsRemote(
        picked.id,
        academicYearId: picked.academicYearId,
      );
    } on ApiException catch (error) {
      if (mounted) AppToast.error(context, error.message);
      return;
    }
    if (!mounted) return;
    await _openPreEnrollmentForm(
      registrationKind: 'reenrollment',
      existingStudent: selected,
    );
  }

  String _regimeLabel(String? value) => switch (value) {
        'part_time' => 'Mi-temps',
        'full_time' => 'Plein temps',
        _ => 'Non applicable',
      };

  Future<void> _changeRegime(
      StudentModel student, StudentRegistrationModel registration) async {
    var regime = registration.schoolRegime == 'part_time'
        ? 'full_time'
        : 'part_time';
    var effectiveDate = DateTime.now();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Changer le régime — ${student.fullName}'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: const Key('change-student-regime'),
                  initialValue: regime,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Nouveau régime'),
                  items: const [
                    DropdownMenuItem(
                        value: 'part_time', child: Text('Mi-temps')),
                    DropdownMenuItem(
                        value: 'full_time', child: Text('Plein temps')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => regime = value ?? regime),
                ),
                const SizedBox(height: AppSpacing.s3),
                AppDateField(
                  label: 'Mois d’effet',
                  value: effectiveDate,
                  firstDate: AppDateUtils.parse(registration.registrationDate) ??
                      DateTime(DateTime.now().year - 1),
                  lastDate: DateTime(DateTime.now().year + 2, 12, 31),
                  onChanged: (value) => setDialogState(() =>
                      effectiveDate = DateTime(value.year, value.month, 1)),
                ),
                const SizedBox(height: AppSpacing.s3),
                const Text(
                  'Le changement s’applique à partir du premier jour du mois sélectionné. Les paiements déjà validés restent inchangés.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<StoreService>().changeStudentRegimeRemote(
            registration.id,
            regime,
            effectiveDate,
          );
      if (!mounted) return;
      AppToast.success(context, 'Le nouveau régime a été enregistré.');
    } on ApiException catch (error) {
      if (mounted) AppToast.error(context, error.message);
    }
  }

  Future<void> _showHistory(StudentModel student) async {
    final history = await context
        .read<StoreService>()
        .studentRegistrationHistoryRemote(student.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Historique — ${student.fullName}'),
        content: SizedBox(
          width: 620,
          child: history.isEmpty
              ? const Text('Aucune inscription annuelle.')
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 480),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: history.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = history[index];
                      final hasRegime = const {'part_time', 'full_time'}
                          .contains(item.schoolRegime);
                      final regimeHistory =
                          (item.options['regimeHistory'] as List? ?? const []);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history_edu),
                        title: Text(item.className ?? 'Classe inconnue'),
                        subtitle: Text([
                          item.academicYearId ?? 'Année inconnue',
                          item.status,
                          if (hasRegime)
                            'Régime : ${_regimeLabel(item.schoolRegime)}',
                          if (hasRegime && regimeHistory.isNotEmpty)
                            '${regimeHistory.length} période(s) de régime',
                        ].join(' · ')),
                        trailing: hasRegime
                            ? TextButton(
                                onPressed: () async {
                                  Navigator.pop(dialogContext);
                                  await _changeRegime(student, item);
                                  if (mounted) await _showHistory(student);
                                },
                                child: const Text('Changer le régime'),
                              )
                            : null,
                      );
                    },
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _provisionStudentAccess(StudentModel student) async {
    final reset = student.userId != null && student.userId!.isNotEmpty;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title:
            Text(reset ? 'Réinitialiser l’accès élève' : 'Créer l’accès élève'),
        content: Text(reset
            ? 'Un nouveau mot de passe temporaire remplacera l’ancien. Le matricule scolaire reste inchangé.'
            : 'L’accès sera lié à ce profil élève. La connexion se fera avec son matricule scolaire.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(reset ? 'Réinitialiser' : 'Créer l’accès')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final access =
          await context.read<StoreService>().provisionStudentAccess(student.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Accès élève prêt'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Matricule'),
              SelectableText(
                access['matricule']!,
                key: const Key('student-login-matricule'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.s3),
              const Text(
                  'Copiez ce mot de passe maintenant. Il expire après 24 heures et ne permet qu’une connexion avant son remplacement.'),
              const SizedBox(height: AppSpacing.s3),
              SelectableText(
                access['temporaryPassword']!,
                key: const Key('temporary-student-password'),
                style: const TextStyle(
                    fontFamily: 'monospace', fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('J’ai copié les informations')),
          ],
        ),
      );
    } on ApiException catch (error) {
      if (mounted) AppToast.error(context, error.message);
    } on Exception {
      if (mounted) {
        AppToast.error(context, 'Impossible de joindre le serveur.');
      }
    }
  }

  Future<void> _provisionParentAccess(StudentModel student) async {
    final primary = student.guardians
        .cast<Map<String, dynamic>>()
        .where((item) => item['isPrimary'] == true)
        .firstOrNull;
    if (primary == null) {
      AppToast.warning(
          context, 'Rattachez d’abord un responsable principal à cet élève.');
      return;
    }
    final reset = '${primary['userId'] ?? ''}'.isNotEmpty;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
            reset ? 'Réinitialiser l’accès parent' : 'Créer l’accès parent'),
        content: Text(reset
            ? 'Un nouveau mot de passe temporaire remplacera l’ancien. Le parent pourra ensuite se connecter avec son e-mail ou son numéro de téléphone enregistré.'
            : 'L’accès sera strictement lié aux enfants rattachés à ce responsable. Après création, le parent pourra utiliser son e-mail ou son numéro de téléphone enregistré pour se connecter.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(reset ? 'Réinitialiser' : 'Créer l’accès')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final access = await context
          .read<StoreService>()
          .provisionParentAccess('${primary['id']}');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Accès parent prêt'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Identifiants possibles'),
              SelectableText(access['email']!,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if ('${primary['phone'] ?? ''}'.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s1),
                SelectableText('${primary['phone']}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
              const SizedBox(height: AppSpacing.s3),
              const Text(
                  'Copiez ce mot de passe maintenant. Il expire après 24 heures et doit être remplacé à la première connexion.'),
              const SizedBox(height: AppSpacing.s3),
              SelectableText(access['temporaryPassword']!,
                  key: const Key('temporary-parent-password'),
                  style: const TextStyle(
                      fontFamily: 'monospace', fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('J’ai copié les informations')),
          ],
        ),
      );
    } on ApiException catch (error) {
      if (mounted) AppToast.error(context, error.message);
    } on Exception {
      if (mounted) AppToast.error(context, 'Impossible de joindre le serveur.');
    }
  }

  Future<void> _finalizePreEnrollment(Map<String, dynamic> item) async {
    try {
      final student = await context.read<StoreService>().studentDetailsRemote(
            item['studentId'].toString(),
            academicYearId: item['academicYearId']?.toString(),
          );
      if (!mounted) return;
      await _openStudentEditor(student, item);
    } on ApiException catch (error) {
      if (mounted) AppToast.error(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    final students = store.getStudents().where((student) {
      if (_search.isEmpty) return true;
      final query = _search.toLowerCase();
      return student.fullName.toLowerCase().contains(query) ||
          (student.matricule?.toLowerCase().contains(query) ?? false);
    }).toList();
    students.sort((left, right) {
      final byLastName =
          left.lastName.toLowerCase().compareTo(right.lastName.toLowerCase());
      return byLastName != 0
          ? byLastName
          : left.firstName
              .toLowerCase()
              .compareTo(right.firstName.toLowerCase());
    });
    final cycles = store.getSchoolCycles();
    final levels = _cycleId == null
        ? store.getSchoolLevels()
        : store.getSchoolLevelsByCycleId(_cycleId!);
    final classes =
        store.getClassesByYear(store.getSelectedAcademicYearId()).where((item) {
      if (_cycleId != null && item.cycleId != _cycleId) return false;
      if (_levelId != null && item.levelId != _levelId) return false;
      return true;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        WorkspaceHeader(
            title: 'Élèves et inscriptions',
            subtitle:
                'Retrouvez un élève, gérez son inscription et son dossier scolaire. Les inscriptions alimentent automatiquement Finance.',
            actions: [
              AppButton(
                  label: 'Importer les photos',
                  icon: Icons.add_photo_alternate_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => showStudentPhotoImportDialog(context)),
              AppButton(
                  label: 'Inscrire / Réinscrire',
                  icon: Icons.person_add_alt_1,
                  onPressed: _openEntryFlow),
            ]),
        const SizedBox(height: AppSpacing.s5),
        if (!_loading && _preEnrollments.isNotEmpty) ...[
          AppCard(
            title: 'Préinscrits (${_preEnrollments.length})',
            child: Column(
              children: _preEnrollments
                  .map((item) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          child: Icon(Icons.hourglass_top_rounded),
                        ),
                        title: Text(item['studentName']?.toString() ?? 'Élève'),
                        subtitle: Text(
                          '${item['desiredClassName'] ?? 'Classe non renseignée'} · '
                          '${item['registrationKind'] == 'reenrollment' ? 'Réinscription' : 'Inscription'}',
                        ),
                        trailing: Wrap(spacing: AppSpacing.s2, children: [
                          IconButton(
                            tooltip: 'Modifier la préinscription',
                            onPressed: () => _openPreEnrollmentForm(
                              registrationKind:
                                  item['registrationKind']?.toString() ??
                                      'registration',
                              existingPreEnrollment: item,
                            ),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          FilledButton.icon(
                            onPressed: () => _finalizePreEnrollment(item),
                            icon: const Icon(Icons.how_to_reg_rounded),
                            label: const Text('Inscrire maintenant'),
                          ),
                        ]),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.s5),
        ],
        Wrap(spacing: AppSpacing.s3, runSpacing: AppSpacing.s3, children: [
          ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AppFormField(
                  label: '',
                  hint: 'Nom ou matricule…',
                  prefixIcon: Icons.search,
                  onChanged: (value) => setState(() => _search = value))),
          SizedBox(
              width: 190,
              child: DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _cycleId,
                  decoration: const InputDecoration(labelText: 'Cycle'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tous')),
                    ...cycles.map((item) => DropdownMenuItem(
                        value: item.id, child: Text(item.name)))
                  ],
                  onChanged: (value) {
                    setState(() {
                      _cycleId = value;
                      _levelId = null;
                      _classId = null;
                    });
                    _load();
                  })),
          SizedBox(
              width: 190,
              child: DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _levelId,
                  decoration: const InputDecoration(labelText: 'Niveau'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tous')),
                    ...levels.map((item) => DropdownMenuItem(
                        value: item.id, child: Text(item.name)))
                  ],
                  onChanged: (value) {
                    setState(() {
                      _levelId = value;
                      _classId = null;
                    });
                    _load();
                  })),
          SizedBox(
              width: 190,
              child: DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _classId,
                  decoration: const InputDecoration(labelText: 'Classe'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Toutes')),
                    ...classes.map((item) => DropdownMenuItem(
                        value: item.id, child: Text(item.name)))
                  ],
                  onChanged: (value) {
                    setState(() => _classId = value);
                    _load();
                  })),
        ]),
        const SizedBox(height: AppSpacing.s5),
        if (_loading)
          const Center(
              child: CircularProgressIndicator(key: Key('students-loading')))
        else if (_error != null)
          AppCard(
              child: Column(children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.s3),
            AppButton(label: 'Réessayer', onPressed: _load)
          ]))
        else if (students.isEmpty)
          const AppEmptyState(
            iconData: Icons.people_outline_rounded,
            title: 'Aucun élève trouvé.',
            message:
                'Modifiez les filtres ou commencez une nouvelle inscription.',
          )
        else
          AppCard(
              padding: EdgeInsets.zero,
              child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 28,
                    dataRowMinHeight: 58,
                    dataRowMaxHeight: 68,
                    columns: const [
                      DataColumn(label: Text('Photo')),
                      DataColumn(label: Text('Matricule')),
                      DataColumn(label: Text('Nom')),
                      DataColumn(label: Text('Prénom')),
                      DataColumn(label: Text('Classe')),
                      DataColumn(label: Text('Responsable')),
                      DataColumn(label: Text('Actions'))
                    ],
                    rows: students
                        .map((student) => DataRow(cells: [
                              DataCell(StudentPhotoAvatar(
                                studentId: student.id,
                                initials: student.initials,
                                radius: 18,
                              )),
                              DataCell(Text(student.matricule ?? '—')),
                              DataCell(SizedBox(
                                width: 150,
                                child: Text(
                                  student.lastName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              )),
                              DataCell(SizedBox(
                                width: 150,
                                child: Text(
                                  student.firstName,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )),
                              DataCell(AppBadge(
                                  label: student.className ?? 'Non inscrit',
                                  variant: AppBadgeVariant.primary)),
                              DataCell(Text(student.parent ?? '—')),
                              DataCell(Row(children: [
                                if (!const {
                                  'maternelle',
                                  'primaire'
                                }.contains((student.cycle ?? '').toLowerCase()))
                                  IconButton(
                                      key: Key('student-access-${student.id}'),
                                      tooltip: student.userId == null ||
                                              student.userId!.isEmpty
                                          ? 'Créer l’accès de connexion'
                                          : 'Réinitialiser le mot de passe',
                                      onPressed: () =>
                                          _provisionStudentAccess(student),
                                      icon: Icon(student.userId == null ||
                                              student.userId!.isEmpty
                                          ? Icons.person_add_alt_1_rounded
                                          : Icons.password_rounded)),
                                IconButton(
                                    key: Key('parent-access-${student.id}'),
                                    tooltip:
                                        'Créer ou réinitialiser l’accès parent',
                                    onPressed: () =>
                                        _provisionParentAccess(student),
                                    icon: const Icon(
                                        Icons.family_restroom_rounded)),
                                IconButton(
                                    tooltip: 'Historique',
                                    onPressed: () => _showHistory(student),
                                    icon: const Icon(Icons.history)),
                                IconButton(
                                    tooltip: 'Réinscrire',
                                    onPressed: () =>
                                        openStudentRegistrationModal(
                                            context, student),
                                    icon:
                                        const Icon(Icons.how_to_reg_outlined)),
                                IconButton(
                                    tooltip: 'Modifier',
                                    onPressed: () =>
                                        _openStudentEditor(student),
                                    icon: const Icon(Icons.edit_outlined)),
                                IconButton(
                                    tooltip: 'Archiver',
                                    onPressed: () async {
                                      final confirmed = await ConfirmDialog.show(
                                          context: context,
                                          title: 'Archiver l’élève',
                                          message:
                                              'Archiver ${student.fullName} sans supprimer son historique ?',
                                          isDanger: true);
                                      if (!confirmed || !context.mounted) {
                                        return;
                                      }
                                      try {
                                        await store
                                            .archiveStudentRemote(student.id);
                                        if (context.mounted) {
                                          AppToast.success(
                                              context, 'Élève archivé.');
                                        }
                                      } on ApiException catch (error) {
                                        if (context.mounted) {
                                          AppToast.error(
                                              context, error.message);
                                        }
                                      }
                                    },
                                    icon: const Icon(Icons.archive_outlined,
                                        color: AppColors.danger500)),
                              ])),
                            ]))
                        .toList(),
                  ))),
      ]),
    );
  }
}

class _ReEnrollmentPickerDialog extends StatefulWidget {
  const _ReEnrollmentPickerDialog({
    required this.store,
    required this.targetAcademicYearId,
  });

  final StoreService store;
  final String targetAcademicYearId;

  @override
  State<_ReEnrollmentPickerDialog> createState() =>
      _ReEnrollmentPickerDialogState();
}

class _ReEnrollmentPickerDialogState extends State<_ReEnrollmentPickerDialog> {
  final _lastName = TextEditingController();
  final _firstName = TextEditingController();
  final _matricule = TextEditingController();
  List<StudentModel> _students = const [];
  List<Map<String, dynamic>> _classes = const [];
  String? _classId;
  String? _previousYearName;
  String? _selectedId;
  String? _error;
  int _total = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _lastName.dispose();
    _firstName.dispose();
    _matricule.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.store.reEnrollmentCandidatesRemote(
        targetAcademicYearId: widget.targetAcademicYearId,
        classId: _classId,
        lastName: _lastName.text,
        firstName: _firstName.text,
        matricule: _matricule.text,
      );
      if (!mounted) return;
      final rows = (data['items'] as List? ?? const [])
          .map((item) =>
              StudentModel.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
      final previousYear = data['previousAcademicYear'] as Map?;
      setState(() {
        _students = rows;
        _classes = (data['classes'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _previousYearName = previousYear?['name']?.toString();
        _total = (data['total'] as num?)?.toInt() ?? rows.length;
        _selectedId = rows.any((item) => item.id == _selectedId)
            ? _selectedId
            : (rows.isEmpty ? null : rows.first.id);
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de rechercher les élèves à réinscrire.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _students.where((item) => item.id == _selectedId).toList();
    return AlertDialog(
      title: const Text('Réinscrire un élève existant'),
      content: SizedBox(
        width: 760,
        height: MediaQuery.sizeOf(context).height * .84,
        child: ListView(
          children: [
            Text(
              _previousYearName == null
                  ? 'Recherche dans l’année scolaire précédente'
                  : 'Élèves inscrits en $_previousYearName',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.s3),
            ResponsiveFormGrid(
              children: [
                DropdownButtonFormField<String?>(
                  key: const ValueKey('reenrollment-class-filter'),
                  isExpanded: true,
                  value: _classId,
                  decoration:
                      const InputDecoration(labelText: 'Filtrer par classe'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Toutes les classes'),
                    ),
                    ..._classes.map((item) => DropdownMenuItem<String?>(
                          value: '${item['id']}',
                          child: Text('${item['name']}',
                              overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: _loading
                      ? null
                      : (value) {
                          setState(() => _classId = value);
                          _search();
                        },
                ),
                AppFormField(label: 'Nom', controller: _lastName),
                AppFormField(label: 'Prénom', controller: _firstName),
                AppFormField(label: 'Matricule', controller: _matricule),
              ],
            ),
            const SizedBox(height: AppSpacing.s3),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _loading ? null : _search,
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search_rounded),
                label: const Text('Rechercher'),
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
            if (_error != null)
              AppCard(
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.danger500)),
              )
            else if (!_loading)
              Text(
                '$_total élève(s) éligible(s) · ${_students.length} affiché(s)',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            const SizedBox(height: AppSpacing.s2),
            SizedBox(
              height: 190,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _students.isEmpty
                      ? const AppEmptyState(
                          iconData: Icons.person_search_outlined,
                          title: 'Aucun élève éligible',
                          message:
                              'Vérifiez les filtres. Les élèves déjà inscrits dans l’année cible sont exclus.',
                        )
                      : ListView.separated(
                          itemCount: _students.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final student = _students[index];
                            return RadioListTile<String>(
                              value: student.id,
                              groupValue: _selectedId,
                              onChanged: (value) =>
                                  setState(() => _selectedId = value),
                              title: Text(student.fullName),
                              subtitle: Text([
                                student.matricule ?? 'Sans matricule',
                                student.className ?? 'Classe inconnue',
                                student.level,
                              ]
                                  .whereType<String>()
                                  .where((value) => value.isNotEmpty)
                                  .join(' · ')),
                            );
                          },
                        ),
            ),
            if (selected.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s3),
              AppCard(
                title: 'Élève sélectionné',
                child: Text([
                  selected.first.fullName,
                  selected.first.matricule ?? 'Sans matricule',
                  selected.first.sex,
                  selected.first.birthDate,
                  selected.first.className,
                  selected.first.level,
                ]
                    .whereType<String>()
                    .where((value) => value.isNotEmpty)
                    .join(' · ')),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: selected.isEmpty
              ? null
              : () => Navigator.pop(context, selected.first),
          child: const Text('Continuer'),
        ),
      ],
    );
  }
}
