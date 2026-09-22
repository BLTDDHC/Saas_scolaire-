import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/pdf_download.dart';
import '../../../data/datasources/api_client.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/workspace_header.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/responsive_grid.dart';
import 'package:printing/printing.dart';
import 'pdf_helpers.dart';
import 'receipt_pdf.dart';
import 'document_report_pdf.dart';

enum _DocumentAction { preview, download, send }

bool _supportsPdfActions(Map<String, dynamic> document) {
  final metadata =
      Map<String, dynamic>.from(document['metadata'] as Map? ?? const {});
  return document['type'] == 'generated_report' ||
      document['type'] == 'payment_receipt' ||
      document['type'] == 'official_results' ||
      metadata['documentKind'] == 'bulletin' ||
      metadata['documentKind'] == 'receipt';
}

mixin _DocumentPdfActions<T extends StatefulWidget> on State<T> {
  Future<void> _openDocument(
      Map<String, dynamic> document, _DocumentAction action) async {
    final metadata =
        Map<String, dynamic>.from(document['metadata'] as Map? ?? const {});
    if (document['type'] == 'generated_report') {
      await _openGeneratedReport(document, action: action);
    } else if (document['type'] == 'official_results' ||
        metadata['documentKind'] == 'bulletin') {
      await _openBulletin(document, action: action);
    } else if (document['type'] == 'payment_receipt' ||
        metadata['documentKind'] == 'receipt') {
      await _openReceipt(document, action: action);
    } else if (mounted) {
      AppToast.warning(context, 'Aucun fichier PDF n’est associé à ce document.');
    }
  }

  Future<void> _presentPdf(
      List<int> rawBytes, String filename, _DocumentAction action) async {
    final bytes = Uint8List.fromList(rawBytes);
    switch (action) {
      case _DocumentAction.preview:
        await Printing.layoutPdf(name: filename, onLayout: (_) => bytes);
      case _DocumentAction.download:
        await downloadPdfFile(bytes, filename);
      case _DocumentAction.send:
        await Printing.sharePdf(bytes: bytes, filename: filename);
    }
  }

  Future<void> _openGeneratedReport(Map<String, dynamic> document,
      {required _DocumentAction action}) async {
    try {
      final metadata =
          Map<String, dynamic>.from(document['metadata'] as Map? ?? {});
      final report =
          Map<String, dynamic>.from(metadata['report'] as Map? ?? {});
      if (report.isEmpty) throw StateError('Rapport indisponible');
      final pdf = await buildSchoolReportPdf(report);
      final bytes = await pdf.save();
      await _presentPdf(bytes, schoolReportFileName(report), action);
    } catch (_) {
      if (mounted) AppToast.error(context, 'Ce rapport n’est plus disponible.');
    }
  }

  Future<void> _openBulletin(Map<String, dynamic> document,
      {required _DocumentAction action}) async {
    final store = context.read<StoreService>();
    try {
      final metadata =
          Map<String, dynamic>.from(document['metadata'] as Map? ?? {});
      final studentId = metadata['studentId']?.toString();
      final periodId = metadata['periodId']?.toString();
      final yearId = document['academicYearId']?.toString();
      final classId = document['entityId']?.toString();
      if (document['status'] != 'generated' ||
          studentId == null ||
          periodId == null ||
          yearId == null ||
          classId == null) {
        throw StateError('Document indisponible');
      }
      final source = await store.studentBulletinRemote(studentId, yearId);
      final selected = (source['periods'] as List? ?? const [])
          .cast<Map>()
          .where((period) => period['periodId']?.toString() == periodId)
          .toList();
      if (selected.length != 1 ||
          selected.single['calculationStatus'] != 'official') {
        throw StateError('Résultat non officiel ou périmé');
      }
      final schoolClass = store.getClassById(classId);
      final school = schoolClass == null
          ? null
          : store.getEstablishmentById(schoolClass.schoolId);
      final data = trimesterPdfDataFromOfficialSource(
          source: source,
          selected: Map<String, dynamic>.from(selected.single),
          school: {'name': school?.name ?? '', 'city': school?.city ?? ''},
          studentId: studentId,
          yearId: yearId,
          periodId: periodId,
          signatoryTitle: metadata['signatoryTitle']?.toString(),
          colorTheme: metadata['colorTheme']?.toString() ?? 'auto');
      final pdf = await buildTrimesterPdfFromData(data);
      final bytes = await pdf.save();
      await _presentPdf(bytes, bulletinFileName(data), action);
    } catch (_) {
      if (mounted) {
        AppToast.error(context,
            'Ce bulletin doit être régénéré depuis les résultats officiels.');
      }
    }
  }

  Future<void> _openReceipt(Map<String, dynamic> document,
      {required _DocumentAction action}) async {
    try {
      final metadata =
          Map<String, dynamic>.from(document['metadata'] as Map? ?? {});
      final receiptId =
          metadata['receiptId']?.toString() ?? document['entityId']?.toString();
      if (receiptId == null) throw StateError('Reçu indisponible');
      final receipt = await context
          .read<StoreService>()
          .fetchFinanceReceipt(receiptId, document['schoolId']?.toString());
      final pdf = await buildFinanceReceiptPdf(receipt);
      final bytes = await pdf.save();
      await _presentPdf(
          bytes, 'Reçu - ${receipt['receiptNumber'] ?? receiptId}.pdf', action);
    } catch (_) {
      if (mounted) AppToast.error(context, 'Ce reçu n’est plus disponible.');
    }
  }
}

class DocumentHistory extends StatefulWidget {
  const DocumentHistory({super.key});
  @override
  State<DocumentHistory> createState() => _DocumentHistoryState();
}

class _DocumentHistoryState extends State<DocumentHistory>
    with _DocumentPdfActions<DocumentHistory> {
  String? _year;
  String _search = '';
  Future<Map<String, dynamic>>? _request;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = context.watch<StoreService>();
    final year = store.getSelectedAcademicYearId();
    if (_request == null || year != _year) {
      _year = year;
      _request = _load(store);
    }
  }

  Future<Map<String, dynamic>> _load(StoreService store) async {
    final overview = await store.documentOverviewRemote(academicYearId: _year);
    final rows = <Map<String, dynamic>>[];
    final totals = <String, int>{};
    for (final category in const [
      'Bulletins',
      'Reçus',
      'Documents scolaires',
      'Documents administratifs'
    ]) {
      final page = Map<String, dynamic>.from(overview[category] as Map? ?? {});
      totals[category] = (page['total'] as num?)?.toInt() ?? 0;
      for (final raw in page['items'] as List? ?? const []) {
        final d = Map<String, dynamic>.from(raw as Map);
        final meta = Map<String, dynamic>.from(d['metadata'] as Map? ?? {});
        rows.add({
          ...d,
          'displayType': meta['documentKind'] == 'bulletin'
              ? 'Bulletin'
              : {
                    'official_results': 'Résultats officiels',
                    'payment_receipt': 'Reçu de paiement',
                    'generated_report': d['title']?.toString() ?? 'Rapport scolaire',
                    'student_record': 'Fiche élève',
                    'class_list': 'Liste de classe',
                    'enrollment_certificate': 'Certificat de scolarité'
                  }[d['type']] ??
                  'Document administratif',
          'category': category,
          'student': d['studentName'] ?? 'Non renseigné',
          'class': d['className'] ?? 'Non renseignée',
          'period': meta['periodName'] ?? 'Non renseignée'
        });
      }
    }
    return {'rows': rows, 'totals': totals};
  }


  IconData _categoryIcon(String category) => switch (category) {
        'Bulletins' => Icons.school_outlined,
        'Reçus' => Icons.receipt_long_outlined,
        'Documents scolaires' => Icons.description_outlined,
        _ => Icons.business_center_outlined,
      };

  Widget _documentsTable(List<Map<String, dynamic>> rows) =>
      ResponsiveDataTable(
          child: DataTable(
              columns: const [
            DataColumn(label: Text('Document')),
            DataColumn(label: Text('Élève')),
            DataColumn(label: Text('Classe')),
            DataColumn(label: Text('Période')),
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Statut')),
            DataColumn(label: Text('Action'))
          ],
              rows: rows
                  .map((d) => DataRow(cells: [
                        DataCell(ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Text('${d['displayType']}',
                              overflow: TextOverflow.ellipsis),
                        )),
                        DataCell(Text('${d['student']}',
                            overflow: TextOverflow.ellipsis)),
                        DataCell(Text('${d['class']}',
                            overflow: TextOverflow.ellipsis)),
                        DataCell(Text('${d['period']}',
                            overflow: TextOverflow.ellipsis)),
                        DataCell(Text(AppDateUtils.formatNumeric(
                            d['date']?.toString(),
                            fallback: 'Non renseignée'))),
                        DataCell(Text(d['status'] == 'generated'
                            ? 'Émis'
                            : d['status'] == 'obsolete' ||
                                    d['status'] == 'stale'
                                ? 'À régénérer'
                                : d['status'] == 'cancelled'
                                    ? 'Annulé'
                                    : 'À vérifier')),
                        DataCell(d['status'] == 'generated' &&
                                (d['displayType'] == 'Bulletin' ||
                                    d['displayType'] == 'Reçu de paiement' ||
                                    d['type'] == 'generated_report')
                            ? Wrap(spacing: 4, runSpacing: 4, children: [
                                TextButton(
                                    onPressed: () => _openDocument(
                                        d, _DocumentAction.preview),
                                    child: const Text('Voir')),
                                TextButton(
                                    onPressed: () => _openDocument(
                                        d, _DocumentAction.download),
                                    child: const Text('Télécharger')),
                                TextButton(
                                    onPressed: () => _openDocument(
                                        d, _DocumentAction.send),
                                    child: const Text('Envoyer')),
                              ])
                            : const Text('Archivé')),
                      ]))
                  .toList()));

  void reload() =>
      setState(() => _request = _load(context.read<StoreService>()));

  @override
  Widget build(BuildContext context) => AppCard(
      title: 'Documents émis',
      subtitle:
          'Historique officiel de l’année sélectionnée. La génération et le PDF restent soumis aux résultats officiels.',
      headerAction: IconButton(
          onPressed: reload,
          tooltip: 'Actualiser les documents',
          icon: const Icon(Icons.refresh)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: TextField(
                decoration: const InputDecoration(
                    labelText: 'Rechercher un document ou un élève',
                    prefixIcon: Icon(Icons.search)),
                onChanged: (value) =>
                    setState(() => _search = value.toLowerCase()))),
        const SizedBox(height: 16),
        FutureBuilder<Map<String, dynamic>>(
            future: _request,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) {
                return WorkspaceNotice(
                    message: 'Impossible de charger les documents. Réessayez.',
                    error: true,
                    onRetry: reload);
              }
              final data = snapshot.data ?? const <String, dynamic>{};
              final totals = Map<String, int>.from(
                (data['totals'] as Map? ?? const {}).map(
                  (key, value) => MapEntry('$key', (value as num).toInt()),
                ),
              );
              final rows = List<Map<String, dynamic>>.from(
                (data['rows'] as List? ?? const [])
                    .map((item) => Map<String, dynamic>.from(item as Map)),
              )
                  .where((d) =>
                      '${d['displayType']} ${d['student']} ${d['class']} ${d['period']}'
                          .toLowerCase()
                          .contains(_search))
                  .toList();
              if (rows.isEmpty) {
                return const WorkspaceNotice(
                    message:
                        'Aucun document correspondant pour cette année. Générez un bulletin depuis les résultats officiels.');
              }
              const categories = [
                'Bulletins',
                'Reçus',
                'Documents scolaires',
                'Documents administratifs'
              ];
              return Column(
                  children: categories.map((category) {
                final categoryRows = rows
                    .where((document) => document['category'] == category)
                    .toList();
                final latest = categoryRows.isEmpty
                    ? null
                    : AppDateUtils.formatNumeric(
                        categoryRows.first['date']?.toString(),
                        fallback: 'Non renseignée');
                return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        child: ExpansionTile(
                            leading: Icon(_categoryIcon(category)),
                            title: Text('$category (${totals[category] ?? 0})'),
                            subtitle: Text(categoryRows.isEmpty
                                ? 'Aucun document'
                                : '${totals[category] ?? 0} document(s) · Dernier : $latest'),
                            children: [
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (_) => DocumentCategoryPage(
                                              category: category))),
                                  child: const Text('Voir tout'),
                                ),
                              ),
                              if (categoryRows.isEmpty)
                                const Padding(
                                    padding: EdgeInsets.all(20),
                                    child: Text(
                                        'Aucun document émis dans cette catégorie.'))
                              else
                                _documentsTable(categoryRows),
                            ])));
              }).toList());
            }),
      ]));
}

/// Historique dédié : une seule page serveur (100 éléments au plus) est chargée.
class DocumentCategoryPage extends StatefulWidget {
  const DocumentCategoryPage({super.key, required this.category});
  final String category;
  @override
  State<DocumentCategoryPage> createState() => _DocumentCategoryPageState();
}

class _DocumentCategoryPageState extends State<DocumentCategoryPage>
    with _DocumentPdfActions<DocumentCategoryPage> {
  int _page = 1;
  String? _yearId, _cycleId, _levelId, _classId, _generatedMonth, _nature;
  final _lastName = TextEditingController();
  final _firstName = TextEditingController();
  final _matricule = TextEditingController();
  Timer? _debounce;
  Future<Map<String, dynamic>>? _request;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_request == null) {
      _yearId = context.read<StoreService>().getSelectedAcademicYearId();
      _request = _load();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _lastName.dispose();
    _firstName.dispose();
    _matricule.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() =>
      context.read<StoreService>().documentHistoryPageRemote({
        'category': widget.category,
        'page': '$_page',
        'page_size': '100',
        if (_yearId != null) 'academic_year_id': _yearId!,
        if (_cycleId != null) 'cycle_id': _cycleId!,
        if (_levelId != null) 'level_id': _levelId!,
        if (_classId != null) 'class_id': _classId!,
        if (_generatedMonth != null) 'generated_month': _generatedMonth!,
        if (_nature != null) 'nature': _nature!,
        if (_lastName.text.trim().isNotEmpty)
          'last_name': _lastName.text.trim(),
        if (_firstName.text.trim().isNotEmpty)
          'first_name': _firstName.text.trim(),
        if (_matricule.text.trim().isNotEmpty)
          'matricule': _matricule.text.trim(),
      });

  void _reload() {
    setState(() {
      _request = _load();
    });
  }

  void _filterChanged() {
    _page = 1;
    _reload();
  }

  void _textChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _filterChanged);
  }

  void _resetFilters() {
    _debounce?.cancel();
    _lastName.clear();
    _firstName.clear();
    _matricule.clear();
    final store = context.read<StoreService>();
    _yearId = store.getSelectedAcademicYearId();
    _cycleId = _levelId = _classId = _generatedMonth = _nature = null;
    _page = 1;
    _reload();
  }

  String _monthLabel(String value) {
    const months = [
      'Janvier',
      'Février',
      'Mars',
      'Avril',
      'Mai',
      'Juin',
      'Juillet',
      'Août',
      'Septembre',
      'Octobre',
      'Novembre',
      'Décembre',
    ];
    final parts = value.split('-');
    final month = parts.length == 2 ? int.tryParse(parts[1]) : null;
    if (month == null || month < 1 || month > 12) return value;
    return '${months[month - 1]} ${parts.first}';
  }

  Widget _premiumRestriction(ApiException error) => AppCard(
        title: 'Fonctionnalité avancée',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppToast.humanErrorMessage(
              error.message,
              fallback:
                  'Cette fonctionnalité est disponible dans un forfait supérieur.',
            )),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => AppToast.info(
                  context, 'Contactez le Super Admin pour changer de forfait.'),
              child: const Text('Changer de forfait'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar:
            AppBar(title: Text('Tous les ${widget.category.toLowerCase()}')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.category == 'Bulletins') _bulletinFilters(),
            if (widget.category == 'Reçus') _receiptFilters(),
            const SizedBox(height: 12),
            FutureBuilder<Map<String, dynamic>>(
                future: _request,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.error is ApiException &&
                      (snapshot.error as ApiException).statusCode == 403) {
                    return _premiumRestriction(snapshot.error as ApiException);
                  }
                  if (snapshot.hasError) {
                    return const Center(child: Text('Chargement impossible.'));
                  }
                  final data = snapshot.data ?? const {};
                  final items = (data['items'] as List? ?? const [])
                      .map((item) => Map<String, dynamic>.from(item as Map))
                      .toList();
                  return Column(children: [
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: items.length,
                      itemBuilder: (_, index) {
                        final item = items[index];
                        final canOpen = item['status'] == 'generated' &&
                            _supportsPdfActions(item);
                        return ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: Text(
                              '${item['title'] ?? item['type'] ?? 'Document'}'),
                          subtitle: Text([
                            item['studentName'],
                            item['className'],
                            item['matricule'],
                            AppDateUtils.formatNumeric(item['date']?.toString(),
                                fallback: 'Date inconnue'),
                          ]
                              .where((value) =>
                                  value != null && '$value'.trim().isNotEmpty)
                              .join(' · ')),
                          onTap: canOpen
                              ? () => _openDocument(
                                  item, _DocumentAction.preview)
                              : null,
                          trailing: canOpen
                              ? PopupMenuButton<_DocumentAction>(
                                  tooltip: 'Actions du document',
                                  onSelected: (action) =>
                                      _openDocument(item, action),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: _DocumentAction.preview,
                                      child: ListTile(
                                        leading: Icon(Icons.visibility_outlined),
                                        title: Text('Voir'),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: _DocumentAction.download,
                                      child: ListTile(
                                        leading: Icon(Icons.download_outlined),
                                        title: Text('Télécharger'),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: _DocumentAction.send,
                                      child: ListTile(
                                        leading: Icon(Icons.ios_share_outlined),
                                        title: Text('Envoyer'),
                                      ),
                                    ),
                                  ],
                                )
                              : const Text('Archivé'),
                        );
                      },
                    ),
                    Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Text(
                              'Page ${data['page'] ?? _page} / ${data['pageCount'] ?? 1}'),
                          Wrap(children: [
                            TextButton(
                                onPressed: _page <= 1
                                    ? null
                                    : () {
                                        _page--;
                                        _reload();
                                      },
                                child: const Text('Précédente')),
                            TextButton(
                                onPressed:
                                    _page >= (data['pageCount'] as num? ?? 1)
                                        ? null
                                        : () {
                                            _page++;
                                            _reload();
                                          },
                                child: const Text('Suivante')),
                          ])
                        ])
                  ]);
                },
              ),
          ],
        ),
      );

  Widget _bulletinFilters() {
    final store = context.read<StoreService>();
    final years = store.getAcademicYears();
    final cycles =
        store.getSchoolCycles().where((item) => item.isActive).toList();
    final levels = store
        .getSchoolLevels()
        .where((item) =>
            item.status == 'active' &&
            (_cycleId == null || item.cycleId == _cycleId))
        .toList();
    final classes = store
        .getClassesByYear(_yearId)
        .where((item) =>
            (_cycleId == null || item.cycleId == _cycleId) &&
            (_levelId == null ||
                item.levelId == _levelId ||
                item.structuredLevelId == _levelId))
        .toList();
    final monthChoices = <String>[];
    final now = DateTime.now();
    for (var offset = 0; offset < 24; offset++) {
      final value = DateTime(now.year, now.month - offset);
      monthChoices
          .add('${value.year}-${value.month.toString().padLeft(2, '0')}');
    }
    Widget field(Widget child) => SizedBox(width: 220, child: child);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 4,
              children: [
            const Text('Filtrer les bulletins',
                style: TextStyle(fontWeight: FontWeight.w700)),
            TextButton.icon(
                onPressed: _resetFilters,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Réinitialiser les filtres')),
              ]),
          const Text(
              'La direction est appliquée automatiquement selon votre périmètre.'),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            field(DropdownButtonFormField<String>(
              value: _yearId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Année scolaire'),
              items: years
                  .map((item) =>
                      DropdownMenuItem(value: item.id, child: Text(item.name)))
                  .toList(),
              onChanged: (value) {
                _yearId = value;
                _classId = null;
                _filterChanged();
              },
            )),
            field(DropdownButtonFormField<String>(
              value: _cycleId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Cycle'),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text('Tous les cycles')),
                ...cycles.map((item) =>
                    DropdownMenuItem(value: item.id, child: Text(item.name)))
              ],
              onChanged: (value) {
                _cycleId = value;
                _levelId = null;
                _classId = null;
                _filterChanged();
              },
            )),
            field(DropdownButtonFormField<String>(
              value: _levelId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Niveau'),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text('Tous les niveaux')),
                ...levels.map((item) =>
                    DropdownMenuItem(value: item.id, child: Text(item.name)))
              ],
              onChanged: (value) {
                _levelId = value;
                _classId = null;
                _filterChanged();
              },
            )),
            field(DropdownButtonFormField<String>(
              value: _classId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Classe'),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text('Toutes les classes')),
                ...classes.map((item) =>
                    DropdownMenuItem(value: item.id, child: Text(item.name)))
              ],
              onChanged: (value) {
                _classId = value;
                _filterChanged();
              },
            )),
            field(DropdownButtonFormField<String>(
              value: _generatedMonth,
              isExpanded: true,
              decoration:
                  const InputDecoration(labelText: 'Mois de génération'),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text('Tous les mois')),
                ...monthChoices.map((value) => DropdownMenuItem(
                    value: value, child: Text(_monthLabel(value))))
              ],
              onChanged: (value) {
                _generatedMonth = value;
                _filterChanged();
              },
            )),
            field(TextField(
                controller: _lastName,
                onChanged: _textChanged,
                decoration: const InputDecoration(labelText: 'Nom'))),
            field(TextField(
                controller: _firstName,
                onChanged: _textChanged,
                decoration: const InputDecoration(labelText: 'Prénom'))),
            field(TextField(
                controller: _matricule,
                onChanged: _textChanged,
                decoration: const InputDecoration(labelText: 'Matricule'))),
          ]),
        ]),
      ),
    );
  }

  Widget _receiptFilters() {
    final store = context.read<StoreService>();
    final years = store.getAcademicYears();
    final classes = store.getClassesByYear(_yearId);
    final monthChoices = <String>[];
    final now = DateTime.now();
    for (var offset = 0; offset < 24; offset++) {
      final value = DateTime(now.year, now.month - offset);
      monthChoices.add(
          '${value.year}-${value.month.toString().padLeft(2, '0')}');
    }
    const natures = <String, String>{
      'registration': 'Inscription',
      'reenrollment': 'Réinscription',
      'tuition': 'Paiement mensuel',
      'td': 'TD',
      'other': 'Autres frais',
    };
    Widget field(Widget child) => SizedBox(width: 220, child: child);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 4,
              children: [
            const Text('Filtrer les reçus',
                style: TextStyle(fontWeight: FontWeight.w700)),
            TextButton.icon(
                onPressed: _resetFilters,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Réinitialiser les filtres')),
              ]),
          const Text(
              'La direction est appliquée automatiquement selon votre périmètre.'),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            field(DropdownButtonFormField<String>(
              value: _yearId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Année scolaire'),
              items: years
                  .map((item) =>
                      DropdownMenuItem(value: item.id, child: Text(item.name)))
                  .toList(),
              onChanged: (value) {
                _yearId = value;
                _classId = null;
                _filterChanged();
              },
            )),
            field(DropdownButtonFormField<String>(
              value: _classId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Classe'),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text('Toutes les classes')),
                ...classes.map((item) =>
                    DropdownMenuItem(value: item.id, child: Text(item.name))),
              ],
              onChanged: (value) {
                _classId = value;
                _filterChanged();
              },
            )),
            field(DropdownButtonFormField<String>(
              value: _nature,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Nature'),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text('Toutes les natures')),
                ...natures.entries.map((entry) => DropdownMenuItem(
                    value: entry.key, child: Text(entry.value))),
              ],
              onChanged: (value) {
                _nature = value;
                _filterChanged();
              },
            )),
            field(DropdownButtonFormField<String>(
              value: _generatedMonth,
              isExpanded: true,
              decoration:
                  const InputDecoration(labelText: 'Mois de génération'),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text('Tous les mois')),
                ...monthChoices.map((value) => DropdownMenuItem(
                    value: value, child: Text(_monthLabel(value)))),
              ],
              onChanged: (value) {
                _generatedMonth = value;
                _filterChanged();
              },
            )),
            field(TextField(
                controller: _lastName,
                onChanged: _textChanged,
                decoration: const InputDecoration(labelText: 'Nom'))),
            field(TextField(
                controller: _firstName,
                onChanged: _textChanged,
                decoration: const InputDecoration(labelText: 'Prénom'))),
            field(TextField(
                controller: _matricule,
                onChanged: _textChanged,
                decoration: const InputDecoration(labelText: 'Matricule'))),
          ]),
        ]),
      ),
    );
  }
}
