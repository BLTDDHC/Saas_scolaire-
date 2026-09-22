import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/services/store_service.dart';
import '../../../data/models/annual_bulletin_model.dart';
import '../../../data/models/annual_decision_model.dart';
import '../../../data/models/student_model.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/responsive_grid.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'pdf_font_theme.dart';

class AnnualBulletinPage extends StatefulWidget {
  const AnnualBulletinPage({super.key});

  @override
  State<AnnualBulletinPage> createState() => _AnnualBulletinPageState();
}

class _AnnualBulletinPageState extends State<AnnualBulletinPage> {
  String? _selectedYearId;
  String? _selectedClassId;
  String? _selectedStudentId;

  AnnualBulletinModel? _storedBulletin;
  String? _bulletinRecordId;
  String? _decisionRecordId;
  String _proposedDecision = 'A_DECIDER';

  bool _loading = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    final years = store.getAcademicYears();
    _selectedYearId ??= store.getSelectedAcademicYearId();
    final classes = store.getClassesByYear(_selectedYearId);
    final students = _selectedClassId == null
        ? <StudentModel>[]
        : store
            .getStudents()
            .where((s) => s.classId == _selectedClassId)
            .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bulletin annuel', style: AppTypography.heading2()),
          const SizedBox(height: AppSpacing.s4),

          // selectors
          ResponsiveFormGrid(
            maxColumns: 3,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                  value: _selectedYearId,
                  items: years
                      .map((y) => DropdownMenuItem<String>(
                          value: y.id, child: Text(y.name)))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _selectedYearId = v;
                    _selectedClassId = null;
                    _selectedStudentId = null;
                    _storedBulletin = null;
                    _bulletinRecordId = null;
                    _decisionRecordId = null;
                  }),
                  decoration:
                      const InputDecoration(labelText: 'Année scolaire'),
                ),
              DropdownButtonFormField<String>(
                isExpanded: true,
                  value: _selectedClassId,
                  items: classes
                      .map((c) => DropdownMenuItem<String>(
                          value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _selectedClassId = v;
                    _selectedStudentId = null;
                    _storedBulletin = null;
                    _bulletinRecordId = null;
                    _decisionRecordId = null;
                  }),
                  decoration: const InputDecoration(labelText: 'Classe'),
                ),
              DropdownButtonFormField<String>(
                isExpanded: true,
                  value: _selectedStudentId,
                  items: students
                      .map((s) => DropdownMenuItem<String>(
                          value: s.id, child: Text(s.fullName)))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _selectedStudentId = v;
                    _storedBulletin = null;
                    _bulletinRecordId = null;
                    _decisionRecordId = null;
                  }),
                  decoration: const InputDecoration(labelText: 'Élève'),
                ),
            ],
          ),

          const SizedBox(height: AppSpacing.s4),

          Row(children: [
            AppButton(
                label: 'Générer bulletin',
                onPressed: _canGenerate() ? _generateBulletin : null),
            const SizedBox(width: AppSpacing.s3),
            AppButton(
                label: 'Consulter décision',
                onPressed:
                    _storedBulletin != null ? _openDecisionSection : null),
          ]),

          const SizedBox(height: AppSpacing.s6),

          if (_loading) const Center(child: CircularProgressIndicator()),

          if (_storedBulletin != null) _buildBulletinView(_storedBulletin!),
        ],
      ),
    );
  }

  bool _canGenerate() =>
      _selectedClassId != null &&
      _selectedStudentId != null &&
      _selectedYearId != null;

  Future<void> _generateBulletin() async {
    setState(() {
      _loading = true;
    });
    final store = context.read<StoreService>();
    // create and persist a bulletin record via store (uses ResultService internally)
    final id = store.createAnnualBulletinRecord(
        classId: _selectedClassId!, studentId: _selectedStudentId!);
    if (id.isNotEmpty) {
      final bulletin = store.getAnnualBulletinById(id);
      setState(() {
        _bulletinRecordId = id;
        _storedBulletin = bulletin;
        _proposedDecision = store.proposeAnnualDecisionFromBulletin(id);
        // if a decision record exists for this student/year, load it
        final existing = store
            .getDecisionsForStudent(_selectedStudentId!)
            .where((d) => d.academicYearId == _selectedYearId)
            .toList();
        if (existing.isNotEmpty) {
          _decisionRecordId = existing.first.id;
        } else {
          _decisionRecordId = null;
        }
      });
    } else {
      // no bulletin created (maybe permission), clear state
      setState(() {
        _bulletinRecordId = null;
        _storedBulletin = null;
        _decisionRecordId = null;
      });
    }
    setState(() {
      _loading = false;
    });
  }

  Widget _buildBulletinView(AnnualBulletinModel b) {
    final store = context.read<StoreService>();
    final school = store.getEstablishmentById(b.establishmentId);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(school?.name ?? '',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Année: ${b.academicYearId}'),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Classe: ${b.classId}'),
            Text('Effectif: ${b.classSize}'),
          ]),
        ]),

        const SizedBox(height: 12),
        // Student
        Text('Élève: ${b.studentId}'),
        const SizedBox(height: 12),

        // Print / Export buttons
        Row(children: [
          AppButton(
              label: 'Imprimer / PDF',
              onPressed: () => _printAnnualPdf(b),
              icon: Icons.print_rounded),
          const SizedBox(width: AppSpacing.s3),
          AppButton(
              label: 'Exporter PDF',
              onPressed: () => _exportAnnualPdf(b),
              icon: Icons.file_download_rounded),
        ]),

        const SizedBox(height: 12),

        // Table
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Matière')),
              DataColumn(label: Text('Coef')),
              DataColumn(label: Text('T1')),
              DataColumn(label: Text('T2')),
              DataColumn(label: Text('T3')),
              DataColumn(label: Text('Moy. Annuel')),
            ],
            rows: b.subjectResults.map((s) {
              return DataRow(cells: [
                DataCell(Text(s.subjectName)),
                DataCell(Text(s.coefficient.toString())),
                DataCell(Text(s.t1?.toString() ?? '—')),
                DataCell(Text(s.t2?.toString() ?? '—')),
                DataCell(Text(s.t3?.toString() ?? '—')),
                DataCell(Text(s.annualAverage != null
                    ? s.annualAverage!.toStringAsFixed(2)
                    : '—')),
              ]);
            }).toList(),
          ),
        ),

        const SizedBox(height: 12),
        Row(children: [
          Text(
              'Moyenne générale: ${b.generalAverage != null ? b.generalAverage!.toStringAsFixed(2) : '—'}'),
          const SizedBox(width: 24),
          Text('Rang: ${b.rank != null ? '${b.rank}e / ${b.classSize}' : '—'}'),
        ]),

        const SizedBox(height: 16),

        _buildDecisionPanel(b),
      ]),
    );
  }

  Widget _buildDecisionPanel(AnnualBulletinModel b) {
    final store = context.read<StoreService>();
    final user = store.currentUser;
    final isAdmin =
        user != null && (user.role == UserRole.admin || store.isSuperAdmin());

    // ensure there is a decision record
    if (_decisionRecordId == null && _bulletinRecordId != null) {
      final existing = store
          .getDecisionsForStudent(b.studentId)
          .where((d) => d.academicYearId == b.academicYearId)
          .toList();
      if (existing.isNotEmpty) _decisionRecordId = existing.first.id;
    }

    final decisionModel = _decisionRecordId != null
        ? store.getAnnualDecisionById(_decisionRecordId!)
        : null;
    final status = decisionModel?.status ?? 'À DÉCIDER';
    final currentDecision = decisionModel?.decision ?? _proposedDecision;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Décision annuelle', style: AppTypography.heading3()),
          const SizedBox(height: 6),
          Text('Proposition système: $_proposedDecision'),
          const SizedBox(height: 4),
          Text('Statut: ${status.toUpperCase()}'),
        ]),
        Row(children: [
          if (isAdmin && (status != 'locked'))
            AppButton(
                label: 'Modifier',
                onPressed: () => _openModifyDecisionDialog(decisionModel, b)),
          const SizedBox(width: AppSpacing.s3),
          if (isAdmin && (status != 'validated' && status != 'locked'))
            AppButton(
                label: 'Valider',
                onPressed: () => _validateDecision(decisionModel)),
          const SizedBox(width: AppSpacing.s3),
          if (isAdmin && (status != 'locked'))
            AppButton(
                label: 'Verrouiller',
                onPressed: () => _lockDecision(decisionModel)),
        ])
      ]),
      const SizedBox(height: 8),
      Text('Décision actuelle: $currentDecision'),
    ]);
  }

  Future<void> _openDecisionSection() async {
    final store = context.read<StoreService>();
    if (_bulletinRecordId == null) return;
    // ensure decision exists; if not create draft
    if (_decisionRecordId == null) {
      final id = store.createAnnualDecisionFromBulletin(_bulletinRecordId!);
      setState(() {
        _decisionRecordId = id;
      });
    }
    // refresh UI
    setState(() {});
  }

  Future<void> _openModifyDecisionDialog(
      AnnualDecisionModel? decision, AnnualBulletinModel bulletin) async {
    final store = context.read<StoreService>();
    if (_decisionRecordId == null) return;
    final d = decision ?? store.getAnnualDecisionById(_decisionRecordId!);
    if (d == null) return;

    final decisions = [
      'ADMIS',
      'REDOUBLE',
      'EXCLU',
      'ABANDON',
      'DEPART',
      'A_DECIDER'
    ];
    String selected = d.decision;
    final reasonController = TextEditingController();

    final res = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Modifier la décision'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: selected,
                items: decisions
                    .map((e) =>
                        DropdownMenuItem<String>(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) selected = v;
                },
                decoration:
                    const InputDecoration(labelText: 'Nouvelle décision'),
              ),
              const SizedBox(height: 8),
              TextField(
                  controller: reasonController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Motif (obligatoire si modification)')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Annuler')),
              ElevatedButton(
                  onPressed: () {
                    if (selected != d.decision &&
                        (reasonController.text.trim().isEmpty))
                      return; // require reason when changing
                    Navigator.of(ctx).pop(true);
                  },
                  child: const Text('Enregistrer')),
            ],
          );
        });

    if (res == true) {
      final newDecision = selected;
      final reason = reasonController.text.trim();
      if (newDecision != d.decision && reason.isEmpty)
        return; // require reason when decision changed
      final ok = store.setAnnualDecision(d.id, newDecision,
          reason: reason.isEmpty ? null : reason);
      if (ok) {
        setState(() {});
      }
    }
  }

  Future<void> _validateDecision(AnnualDecisionModel? decision) async {
    final store = context.read<StoreService>();
    if (_decisionRecordId == null) return;
    final ok = store.validateAnnualDecision(_decisionRecordId!);
    if (ok) setState(() {});
  }

  Future<void> _lockDecision(AnnualDecisionModel? decision) async {
    final store = context.read<StoreService>();
    if (_decisionRecordId == null) return;
    final ok = store.lockAnnualDecision(_decisionRecordId!);
    if (ok) setState(() {});
  }

  Future<void> _printAnnualPdf(AnnualBulletinModel b) async {
    final doc = await _buildAnnualPdf(b);
    await Printing.layoutPdf(onLayout: (format) => doc.save());
  }

  Future<void> _exportAnnualPdf(AnnualBulletinModel b) async {
    final doc = await _buildAnnualPdf(b);
    final store = context.read<StoreService>();
    final students =
        store.getStudents().where((s) => s.id == b.studentId).toList();
    final student = students.isNotEmpty ? students.first : null;
    String name = 'Bulletin_Annuel_${b.academicYearId}_${b.studentId}.pdf';
    if (student != null) {
      final safeFirst =
          student.firstName.replaceAll(RegExp(r"[^A-Za-z0-9_-]"), '_');
      final safeLast =
          student.lastName.replaceAll(RegExp(r"[^A-Za-z0-9_-]"), '_');
      name = 'Bulletin_Annuel_${safeFirst}_${safeLast}_${b.academicYearId}.pdf';
    }
    await Printing.sharePdf(bytes: await doc.save(), filename: name);
  }

  Future<pw.Document> _buildAnnualPdf(AnnualBulletinModel b) async {
    final pdf = pw.Document();
    final theme = await buildSchoolPdfTheme();
    final store = context.read<StoreService>();
    final school = store.getEstablishmentById(b.establishmentId);
    final students2 =
        store.getStudents().where((s) => s.id == b.studentId).toList();
    final student2 = students2.isNotEmpty ? students2.first : null;

    final headers = ['Matière', 'Coef', 'T1', 'T2', 'T3', 'Moy. Année'];
    final rows = <List<String>>[];
    for (final s in b.subjectResults) {
      rows.add([
        s.subjectName,
        s.coefficient.toString(),
        s.t1 != null ? s.t1!.toStringAsFixed(2) : '—',
        s.t2 != null ? s.t2!.toStringAsFixed(2) : '—',
        s.t3 != null ? s.t3!.toStringAsFixed(2) : '—',
        s.annualAverage != null ? s.annualAverage!.toStringAsFixed(2) : '—',
      ]);
    }

    // determine decision to display: only if validated/locked
    String displayedDecision = 'À DÉCIDER';
    final decs = store
        .getDecisionsForStudent(b.studentId)
        .where((d) => d.academicYearId == b.academicYearId)
        .toList();
    if (decs.isNotEmpty) {
      final d = decs.first;
      if (d.status == 'validated' || d.status == 'locked')
        displayedDecision = d.decision;
    }

    pdf.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context ctx) => [
          pw.Header(
              level: 0,
              child: pw.Text(school?.name ?? '',
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold))),
          pw.Text('Année: ${b.academicYearId}'),
          pw.SizedBox(height: 8),
          pw.Text(
              'Élève: ${student2 != null ? student2.fullName : b.studentId}'),
          pw.Text(
              'Classe: ${b.classId}    Effectif: ${b.classSize}    Rang: ${b.rank != null ? '${b.rank} / ${b.classSize}' : '—'}'),
          pw.SizedBox(height: 12),
          pw.Table.fromTextArray(
            headers: headers,
            data: rows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 12),
          pw.Text(
              'Moyenne générale annuelle: ${b.generalAverage != null ? b.generalAverage!.toStringAsFixed(2) : '—'}'),
          pw.Text('Décision: $displayedDecision'),
          pw.SizedBox(height: 24),
          pw.Text('Appréciations:'),
          pw.SizedBox(height: 48),
          pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Professeur principal: ____________________'),
                pw.Text('Administration: ____________________'),
              ]),
        ],
      ),
    );

    return pdf;
  }
}
